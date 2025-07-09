/// Collects functions from D source code using the DMD front end.
/// Provides utilities to traverse files or directories and return normalized
/// `FunctionInfo` records.
module functioncollector;

import std.file : readText, dirEntries, SpanMode;
import std.string : splitLines, strip;
import std.conv : to;
import std.array : array;
import std.algorithm : joiner;

import dmd.frontend : parseModule;
import dmd.dmodule : Module;
import dmd.dsymbol : Dsymbol, ScopeDsymbol;
import dmd.attrib : AttribDeclaration;
import dmd.func : FuncDeclaration;
import dmd.globals : global;
import dmd.lexer : Lexer;
import dmd.tokens : TOK;
import dmd.statement;

version(unittest) import testutils : DmdInitGuard;

/// Metadata describing a function found in a source file.
public struct FunctionInfo
{
    string file;       /// file path of the function
    uint startLine;    /// first line number of the function
    uint endLine;      /// last line number of the function
    string snippet;    /// raw function text
    string normalized; /// normalized body text

    /// Stores the DMD AST node for this function, enabling further analysis
    /// and tests.
    FuncDeclaration funcDecl;
}

/// RAII helper that toggles `global.params.useUnitTests` for the lifetime of
/// the instance.
private struct UnitTestFlagGuard
{
    @disable this(this);
    this(bool enabled)
    {
        _prev = global.params.useUnitTests;
        global.params.useUnitTests = enabled;
    }
    ~this()
    {
        global.params.useUnitTests = _prev;
    }
    private bool _prev;
}

/// Strip comments and whitespace from a snippet.
private string normalizeCode(string code)
{
    auto buffer = code.dup ~ "\0";
    auto len = buffer.length;
    scope Lexer lex = new Lexer(null, buffer.ptr, 0, len - 1,
        false, false, global.errorSinkNull, &global.compileEnv);
    string[] tokens;
    for (;;)
    {
        const tok = lex.nextToken();
        if (tok == TOK.endOfFile)
            break;
        tokens ~= to!string(lex.token.toString());
    }
    return to!string(tokens.joiner(" ").array.strip);
}

/// Extract the lines between `startLine` and `endLine` from `code`
private string sliceLines(string code, uint startLine, uint endLine)
{
    auto lines = code.splitLines();
    if (startLine == 0 || startLine > lines.length || endLine == 0)
        return "";
    if (endLine > lines.length)
        endLine = cast(uint) lines.length;
    return to!string(lines[startLine - 1 .. endLine].joiner("\n").array);
}

/// Traverse a statement tree and collect nested functions.
private void collectNestedFromStmt(Statement s, string source,
    ref FunctionInfo[] results, bool includeUnittests, bool excludeNested)
{
    if (s is null)
        return;
    if (auto ex = s.isExpStatement())
    {
        if (auto de = ex.exp.isDeclarationExp())
        {
            if (auto fd = de.declaration.isFuncDeclaration())
                collectFrom(fd, source, results, includeUnittests, excludeNested);
        }
    }
    if (auto cs = s.isCompoundStatement())
    {
        if (cs.statements)
            foreach (st; *cs.statements)
                collectNestedFromStmt(st, source, results,
                    includeUnittests, excludeNested);
        return;
    }
    if (auto sc = s.isScopeStatement())
    {
        collectNestedFromStmt(sc.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto conds = s.isConditionalStatement())
    {
        collectNestedFromStmt(conds.ifbody, source, results,
            includeUnittests, excludeNested);
        collectNestedFromStmt(conds.elsebody, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto ifs = s.isIfStatement())
    {
        collectNestedFromStmt(ifs.ifbody, source, results,
            includeUnittests, excludeNested);
        collectNestedFromStmt(ifs.elsebody, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto ws = s.isWhileStatement())
    {
        collectNestedFromStmt(ws._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto fs = s.isForStatement())
    {
        collectNestedFromStmt(fs._init, source, results,
            includeUnittests, excludeNested);
        collectNestedFromStmt(fs._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto fes = s.isForeachStatement())
    {
        collectNestedFromStmt(fes._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto fr = s.isForeachRangeStatement())
    {
        collectNestedFromStmt(fr._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto sw = s.isSwitchStatement())
    {
        collectNestedFromStmt(sw._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto csw = s.isCaseStatement())
    {
        collectNestedFromStmt(csw.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto cr = s.isCaseRangeStatement())
    {
        collectNestedFromStmt(cr.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto def = s.isDefaultStatement())
    {
        collectNestedFromStmt(def.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto sync = s.isSynchronizedStatement())
    {
        collectNestedFromStmt(sync._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto w = s.isWithStatement())
    {
        collectNestedFromStmt(w._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto tc = s.isTryCatchStatement())
    {
        collectNestedFromStmt(tc._body, source, results,
            includeUnittests, excludeNested);
        if (tc.catches)
            foreach (c; *tc.catches)
                collectNestedFromStmt(c.handler, source, results,
                    includeUnittests, excludeNested);
        return;
    }
    if (auto tf = s.isTryFinallyStatement())
    {
        collectNestedFromStmt(tf._body, source, results,
            includeUnittests, excludeNested);
        collectNestedFromStmt(tf.finalbody, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto dbg = s.isDebugStatement())
    {
        collectNestedFromStmt(dbg.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto sg = s.isScopeGuardStatement())
    {
        collectNestedFromStmt(sg.statement, source, results,
            includeUnittests, excludeNested);
        return;
    }
    if (auto ur = s.isUnrolledLoopStatement())
    {
        if (ur.statements)
            foreach (st; *ur.statements)
                collectNestedFromStmt(st, source, results,
                    includeUnittests, excludeNested);
        return;
    }
    if (auto cd = s.isCompoundDeclarationStatement())
    {
        if (cd.statements)
            foreach (st; *cd.statements)
                collectNestedFromStmt(st, source, results,
                    includeUnittests, excludeNested);
        return;
    }
    if (auto ca = s.isCompoundAsmStatement())
    {
        if (ca.statements)
            foreach (st; *ca.statements)
                collectNestedFromStmt(st, source, results,
                    includeUnittests, excludeNested);
        return;
    }
    if (auto pr = s.isPragmaStatement())
    {
        collectNestedFromStmt(pr._body, source, results,
            includeUnittests, excludeNested);
        return;
    }
}

/// Recursively traverse a symbol tree and collect all function declarations.
///
/// Params:
///   s = symbol to start traversal from
///   source = full source text the symbols originate from
///   results = array receiving discovered `FunctionInfo`
///   includeUnittests = whether to include `unittest` functions

private void collectFrom(Dsymbol s, string source, ref FunctionInfo[] results,
    bool includeUnittests, bool excludeNested)
{
    if (auto fd = s.isFuncDeclaration())
    {
        if (!includeUnittests && fd.isUnitTestDeclaration())
        {
            // skip unit test blocks when flag is disabled
        }
        else if (fd.fbody !is null && fd.loc.isValid)
        {
            auto snippet = sliceLines(source, fd.loc.linnum, fd.endloc.linnum);
            results ~= FunctionInfo(fd.loc.filename.to!string,
                fd.loc.linnum, fd.endloc.linnum,
                snippet, normalizeCode(snippet), fd);
            if (!excludeNested)
                collectNestedFromStmt(fd.fbody, source, results,
                    includeUnittests, excludeNested);
        }
    }
    if (auto ad = s.isAttribDeclaration())
    {
        if (ad.decl)
            foreach (d; *ad.decl)
                collectFrom(d, source, results, includeUnittests, excludeNested);
    }
    if (auto sd = s.isScopeDsymbol())
    {
        if (sd.members)
            foreach (d; *sd.members)
                collectFrom(d, source, results, includeUnittests, excludeNested);
    }
}

/// Traverse the AST of `mod` and collect all functions.
private FunctionInfo[] collectFunctions(Module mod, string code, bool includeUnittests, bool excludeNested)
{
    FunctionInfo[] result;
    if (mod !is null && mod.members)
        foreach (s; *mod.members)
            collectFrom(s, code, result, includeUnittests, excludeNested);
    return result;
}

/// Parse `code` and collect all functions it contains
public FunctionInfo[] collectFunctionsFromSource(string filename, string code,
    bool includeUnittests = true, bool excludeNested = false)
{
    scope const(UnitTestFlagGuard) _ = UnitTestFlagGuard(includeUnittests);

    auto t = parseModule(filename, code);
    return collectFunctions(t.module_, code, includeUnittests, excludeNested);
}

/// Parse a D source file and collect its functions
public FunctionInfo[] collectFunctionsInFile(string path, bool includeUnittests = true, bool excludeNested = false)
{
    scope const(UnitTestFlagGuard) _ = UnitTestFlagGuard(includeUnittests);

    const t = parseModule(path);
    auto mod = cast(Module) t.module_;
    auto code = readText(path);
    return collectFunctions(mod, code, includeUnittests, excludeNested);
}

/// Collect functions from all `.d` files under `dir`
public FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true, bool excludeNested = false)
{
    FunctionInfo[] results;
    scope const(UnitTestFlagGuard) _ = UnitTestFlagGuard(includeUnittests);

    foreach (entry; dirEntries(dir, "*.d", SpanMode.depth))
    {
        if (entry.isFile)
            results ~= collectFunctionsInFile(entry.name, includeUnittests, excludeNested);
    }
    return results;
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
int foo() { // comment
    return 1;
}
int bar(int x)
{
    return x; /*block*/
}
};
    auto funcs = collectFunctionsFromSource("test.d", code);
    assert(funcs.length == 2);
    assert(funcs[1].startLine > funcs[0].startLine);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
struct S
{
    int foo(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("struct.d", code);
    assert(funcs.length == 1);
    const expected = normalizeCode("int foo(){ return 1; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
class C
{
    void bar(){ }
}
};
    auto funcs = collectFunctionsFromSource("class.d", code);
    assert(funcs.length == 1);
    const expected = normalizeCode("void bar(){ }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
mixin template Temp()
{
    int tfoo(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("templ.d", code);
    assert(funcs.length == 1);
    const expected = normalizeCode("int tfoo(){ return 1; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
void outer()
{
    int inner(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("nested01.d", code);
    assert(funcs.length == 2);
    const expected = normalizeCode("void outer(){ int inner(){ return 1; } }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 2 && funcs[0].endLine == 5);

    const withoutNested = collectFunctionsFromSource("nested02.d", code, true, true);
    assert(withoutNested.length == 1);
    assert(withoutNested[0].funcDecl.ident.toString() == "outer");
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
struct Multi
{
    int a(){ return 1; }
    int b(){ return 2; }
}
};
    auto funcs = collectFunctionsFromSource("multi.d", code);
    assert(funcs.length == 2);
    assert(funcs[0].startLine == 4);
    assert(funcs[1].startLine == 5);
    const expected = normalizeCode("int a(){ return 1; }");
    assert(funcs[0].normalized == expected || funcs[1].normalized == expected);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
struct Gen(T)
{
    T get(T v){ return v; }
}
};
    auto funcs = collectFunctionsFromSource("genstruct.d", code);
    assert(funcs.length == 1);
    const expected = normalizeCode("T get(T v){ return v; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
class Many
{
    static int s(){ return 1; }
    int n(){ return 2; }
}
};
    auto funcs = collectFunctionsFromSource("many.d", code);
    assert(funcs.length == 2);
    const expected = normalizeCode("static int s(){ return 1; }");
    bool found;
    foreach(f; funcs)
        if(f.normalized == expected)
        {
            assert(f.startLine == 4 && f.endLine == 4);
            found = true;
        }
    assert(found);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
void outerMost()
{
    void a(){}
    void b(){}
}
};
    auto funcs = collectFunctionsFromSource("nested03.d", code);
    assert(funcs.length == 3);
    const expected = normalizeCode("void outerMost(){ void a(){} void b(){} }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 2 && funcs[0].endLine == 6);

    const withoutNested = collectFunctionsFromSource("nested04.d", code, true, true);
    assert(withoutNested.length == 1);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
unittest { assert(foo()); }
};
    auto funcs = collectFunctionsFromSource("ut.d", code);
    assert(funcs.length == 2);
    assert(funcs[0].startLine == 2);
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
unittest { assert(foo()); }
};
    const funcs = collectFunctionsFromSource("ut.d", code, false);
    assert(funcs.length == 1);
}

unittest
{
    // validate line slicing helper
    string code = "a\nb\nc\nd";
    assert(sliceLines(code, 2, 3) == "b\nc");
    // boundary conditions
    assert(sliceLines(code, 0, 2).length == 0);
    assert(sliceLines(code, 1, 0).length == 0);
    assert(sliceLines(code, 5, 6).length == 0);
    assert(sliceLines(code, 3, 10) == "c\nd");
}

unittest
{
    import std.file : tempDir, mkdir, rmdirRecurse, write;
    import std.path : buildPath;
    import std.datetime.systime : Clock;
    import std.conv : to;

    auto dir = buildPath(tempDir(), "fcdirtest-" ~ to!string(Clock.currTime().toUnixTime()));
    mkdir(dir);
    scope(exit) rmdirRecurse(dir);

    write(buildPath(dir, "a.d"), "int foo(){ return 1; }");
    write(buildPath(dir, "b.d"), "int bar(){ return 2; }\nunittest { assert(bar() == 2); }");

    FunctionInfo[] withUT;
    {
        scope const(DmdInitGuard) _ = DmdInitGuard.make();
        withUT = collectFunctionsInDir(dir);
    }
    assert(withUT.length == 3);
    size_t utCount;
    foreach(f; withUT)
        if(f.funcDecl.isUnitTestDeclaration())
            ++utCount;
    assert(utCount == 1);

    FunctionInfo[] withoutUT;
    {
        scope const(DmdInitGuard) _ = DmdInitGuard.make();
        withoutUT = collectFunctionsInDir(dir, false);
    }
    assert(withoutUT.length == 2);
    foreach(f; withoutUT)
        assert(!f.funcDecl.isUnitTestDeclaration());
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
void outer()
{
    if(true)
    {
        int inIf(){ return 1; }
    }
    foreach(i; 0 .. 1)
    {
        int inForeach(){ return i; }
    }
}
};

    auto t = parseModule("whitebox.d", code);
    auto outer = (*t.module_.members)[0].isFuncDeclaration();
    FunctionInfo[] nested;
    collectNestedFromStmt(outer.fbody, code, nested, true, false);
    assert(nested.length == 2);
    import std.algorithm.searching : canFind;
    import std.conv : to;
    string[] names;
    foreach(n; nested)
        names ~= to!string(n.funcDecl.ident.toString());
    assert(names.canFind("inIf"));
    assert(names.canFind("inForeach"));
    foreach(n; nested)
        if(n.funcDecl.ident.toString() == "inIf")
            assert(n.normalized == normalizeCode("int inIf(){ return 1; }"));
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
void outerAll(int x)
{
    version(unittest)
    {
        int inVersion(){ return 0; }
    }
    else
    {
        int inVersionElse(){ return 0; }
    }
    while(x > 0)
    {
        int inWhile(){ return x; }
        --x;
    }
    for(int i=0; i<1; ++i)
    {
        int inFor(){ return i; }
    }
    foreach(i; 0..1)
    {
        int inForeach(){ return i; }
    }
    foreach(i; 0 .. 1)
    {
        int inForeachRange(){ return i; }
    }
    switch(x)
    {
        case 0:
            int inCase(){ return 0; }
            break;
        case 1: .. case 2:
            int inCaseRange(){ return 0; }
            break;
        default:
            int inDefault(){ return 0; }
    }
    synchronized
    {
        int inSync(){ return 0; }
    }
    with(new Object())
    {
        int inWith(){ return 0; }
    }
    try
    {
        int inTry(){ return 0; }
    }
    catch(Exception e)
    {
        int inCatch(){ return 0; }
    }
    try
    {
        int inTryFinally(){ return 0; }
    }
    finally
    {
        int inFinally(){ return 0; }
    }
    debug
    {
        int inDebug(){ return 0; }
    }
    scope(exit)
    {
        void inScope(){ }
    }
    int a, b;
    asm { nop; }
    pragma(inline, false)
    {
        int inPragma(){ return 0; }
    }
}
};

    auto t = parseModule("whitebox2.d", code);
    auto outer = (*t.module_.members)[0].isFuncDeclaration();
    FunctionInfo[] nested;
    collectNestedFromStmt(outer.fbody, code, nested, true, false);
    import std.algorithm.searching : canFind;
    import std.conv : to;
    string[] names;
    foreach(n; nested)
        names ~= to!string(n.funcDecl.ident.toString());
    assert(names.canFind("inVersion"));
    assert(names.canFind("inVersionElse"));
    assert(names.canFind("inWhile"));
    assert(names.canFind("inFor"));
    assert(names.canFind("inForeach"));
    assert(names.canFind("inForeachRange"));
    assert(names.canFind("inCase"));
    assert(names.canFind("inCaseRange"));
    assert(names.canFind("inDefault"));
    assert(names.canFind("inSync"));
    assert(names.canFind("inWith"));
    assert(names.canFind("inTry"));
    assert(names.canFind("inCatch"));
    assert(names.canFind("inTryFinally"));
    assert(names.canFind("inFinally"));
    assert(names.canFind("inDebug"));
    assert(names.canFind("inScope"));
    assert(names.canFind("inPragma"));
}

unittest
{
    scope const(DmdInitGuard) _ = DmdInitGuard.make();

    string code = q{
deprecated {
    int attrFunc(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("attr.d", code);
    assert(funcs.length == 1);
    assert(funcs[0].funcDecl.ident.toString() == "attrFunc");
}

unittest
{
    import std.file : tempDir, mkdir, rmdirRecurse, write;
    import std.path : buildPath;
    import std.datetime.systime : Clock;
    import std.conv : to;
    import std.algorithm.searching : canFind;

    auto dir = buildPath(tempDir(), "fcnested-" ~ to!string(Clock.currTime().toUnixTime()));
    mkdir(dir);
    scope(exit) rmdirRecurse(dir);

    write(buildPath(dir, "a.d"), q{
void outer1()
{
    int inner1(){ return 1; }
}
});
    write(buildPath(dir, "b.d"), q{
void outer2()
{
    void inner2(){}
}
});

    FunctionInfo[] funcs;
    {
        scope const(DmdInitGuard) _ = DmdInitGuard.make();
        funcs = collectFunctionsInDir(dir, true, true);
    }

    assert(funcs.length == 2);
    string[] names;
    foreach(f; funcs)
        names ~= to!string(f.funcDecl.ident.toString());
    assert(names.canFind("outer1"));
    assert(names.canFind("outer2"));
}

unittest
{
    import std.file : tempDir, mkdir, rmdirRecurse, write;
    import std.path : buildPath;
    import std.datetime.systime : Clock;
    import std.conv : to;
    import std.algorithm.searching : canFind;

    auto base = buildPath(tempDir(), "fcnested2-" ~ to!string(Clock.currTime().toUnixTime()));
    mkdir(base);
    scope(exit) rmdirRecurse(base);

    mkdir(buildPath(base, "sub"));
    write(buildPath(base, "top.d"), q{
void top(){ }
});
    write(buildPath(base, "sub", "sub.d"), q{
void subfn(){ }
});

    FunctionInfo[] funcs;
    {
        scope const(DmdInitGuard) _ = DmdInitGuard.make();
        funcs = collectFunctionsInDir(base, true, true);
    }

    assert(funcs.length == 2);
    string[] names;
    foreach(f; funcs)
        names ~= to!string(f.funcDecl.ident.toString());
    assert(names.canFind("top"));
    assert(names.canFind("subfn"));
}
