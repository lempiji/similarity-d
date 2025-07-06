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

version(unittest) import testutils : DmdInitGuard;

/// Metadata describing a function found in a source file.
public struct FunctionInfo
{
    string file;       /// file path of the function
    uint startLine;    /// first line number of the function
    uint endLine;      /// last line number of the function
    string snippet;    /// raw function text
    string normalized; /// normalized body text

    FuncDeclaration funcDecl;
}

/// RAII helper that toggles `global.params.useUnitTests` for the lifetime of
/// the instance.
private struct UnitTestFlagGuard
{
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
    scope Lexer lex = new Lexer(null, buffer.ptr, 0, buffer.length - 1,
        false, false, global.errorSinkNull, &global.compileEnv);
    string[] tokens;
    for (;;)
    {
        auto tok = lex.nextToken();
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

/// Recursively traverse a symbol tree and collect all function declarations.
///
/// Params:
///   s = symbol to start traversal from
///   source = full source text the symbols originate from
///   results = array receiving discovered `FunctionInfo`
///   includeUnittests = whether to include `unittest` functions

private void collectFrom(Dsymbol s, string source, ref FunctionInfo[] results, bool includeUnittests)
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
        }
    }
    if (auto ad = s.isAttribDeclaration())
    {
        if (ad.decl)
            foreach (d; *ad.decl)
                collectFrom(d, source, results, includeUnittests);
    }
    if (auto sd = s.isScopeDsymbol())
    {
        if (sd.members)
            foreach (d; *sd.members)
                collectFrom(d, source, results, includeUnittests);
    }
}

/// Traverse the AST of `mod` and collect all functions.
private FunctionInfo[] collectFunctions(Module mod, string code, bool includeUnittests)
{
    FunctionInfo[] result;
    if (mod !is null && mod.members)
        foreach (s; *mod.members)
            collectFrom(s, code, result, includeUnittests);
    return result;
}

/// Parse `code` and collect all functions it contains
public FunctionInfo[] collectFunctionsFromSource(string filename, string code, bool includeUnittests = true)
{
    scope UnitTestFlagGuard guard = UnitTestFlagGuard(includeUnittests);

    auto t = parseModule(filename, code);
    return collectFunctions(t.module_, code, includeUnittests);
}

/// Parse a D source file and collect its functions
public FunctionInfo[] collectFunctionsInFile(string path, bool includeUnittests = true)
{
    scope UnitTestFlagGuard guard = UnitTestFlagGuard(includeUnittests);

    auto t = parseModule(path);
    auto mod = t.module_;
    auto code = readText(path);
    return collectFunctions(mod, code, includeUnittests);
}

/// Collect functions from all `.d` files under `dir`
public FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true)
{
    FunctionInfo[] results;
    scope UnitTestFlagGuard guard = UnitTestFlagGuard(includeUnittests);

    foreach (entry; dirEntries(dir, "*.d", SpanMode.depth))
    {
        if (entry.isFile)
            results ~= collectFunctionsInFile(entry.name, includeUnittests);
    }
    return results;
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

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
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
struct S
{
    int foo(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("struct.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("int foo(){ return 1; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
class C
{
    void bar(){ }
}
};
    auto funcs = collectFunctionsFromSource("class.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("void bar(){ }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
mixin template Temp()
{
    int tfoo(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("templ.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("int tfoo(){ return 1; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
void outer()
{
    int inner(){ return 1; }
}
};
    auto funcs = collectFunctionsFromSource("nested.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("void outer(){ int inner(){ return 1; } }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 2 && funcs[0].endLine == 5);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

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
    auto expected = normalizeCode("int a(){ return 1; }");
    assert(funcs[0].normalized == expected || funcs[1].normalized == expected);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
struct Gen(T)
{
    T get(T v){ return v; }
}
};
    auto funcs = collectFunctionsFromSource("genstruct.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("T get(T v){ return v; }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 4 && funcs[0].endLine == 4);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
class Many
{
    static int s(){ return 1; }
    int n(){ return 2; }
}
};
    auto funcs = collectFunctionsFromSource("many.d", code);
    assert(funcs.length == 2);
    auto expected = normalizeCode("static int s(){ return 1; }");
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
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
void outerMost()
{
    void a(){}
    void b(){}
}
};
    auto funcs = collectFunctionsFromSource("nested2.d", code);
    assert(funcs.length == 1);
    auto expected = normalizeCode("void outerMost(){ void a(){} void b(){} }");
    assert(funcs[0].normalized == expected);
    assert(funcs[0].startLine == 2 && funcs[0].endLine == 6);
}

unittest
{
    scope DmdInitGuard guard = DmdInitGuard.make();

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
    scope DmdInitGuard guard = DmdInitGuard.make();

    string code = q{
int foo(){ return 1; }
unittest { assert(foo()); }
};
    auto funcs = collectFunctionsFromSource("ut.d", code, false);
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
        scope DmdInitGuard guard = DmdInitGuard.make();
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
        scope DmdInitGuard guard = DmdInitGuard.make();
        withoutUT = collectFunctionsInDir(dir, false);
    }
    assert(withoutUT.length == 2);
    foreach(f; withoutUT)
        assert(!f.funcDecl.isUnitTestDeclaration());
}

