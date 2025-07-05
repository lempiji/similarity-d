module functioncollector;

import std.file : readText, dirEntries, SpanMode;
import std.string : splitLines, strip;
import std.conv : to;
import std.array : array;
import std.algorithm : joiner;

import dmd.frontend : parseModule, initDMD, deinitializeDMD;
import dmd.dsymbol : Dsymbol, ScopeDsymbol;
import dmd.attrib : AttribDeclaration;
import dmd.func : FuncDeclaration;
import dmd.globals : global;
import dmd.lexer : Lexer;
import dmd.tokens : TOK;

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

/// Parse `code` and collect all functions it contains
public FunctionInfo[] collectFunctionsFromSource(string filename, string code, bool includeUnittests = true)
{
    auto prev = global.params.useUnitTests;
    scope(exit) global.params.useUnitTests = prev;
    global.params.useUnitTests = includeUnittests;
    auto t = parseModule(filename, code);
    auto mod = t.module_;
    FunctionInfo[] result;
    if (mod.members)
        foreach (s; *mod.members)
            collectFrom(s, code, result, includeUnittests);
    return result;
}

/// Parse a D source file and collect its functions
public FunctionInfo[] collectFunctionsInFile(string path, bool includeUnittests = true)
{
    auto prev = global.params.useUnitTests;
    scope(exit) global.params.useUnitTests = prev;
    global.params.useUnitTests = includeUnittests;
    auto t = parseModule(path);
    auto mod = t.module_;
    auto code = readText(path);
    FunctionInfo[] result;
    if (mod.members)
        foreach (s; *mod.members)
            collectFrom(s, code, result, includeUnittests);
    return result;
}

/// Collect functions from all `.d` files under `dir`
public FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true)
{
    FunctionInfo[] results;
    auto prev = global.params.useUnitTests;
    scope(exit) global.params.useUnitTests = prev;
    global.params.useUnitTests = includeUnittests;

    foreach (entry; dirEntries(dir, "*.d", SpanMode.depth))
    {
        if (entry.isFile)
            results ~= collectFunctionsInFile(entry.name, includeUnittests);
    }
    return results;
}

unittest
{
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    initDMD();
    scope(exit) deinitializeDMD();

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
    import dmd.frontend : initDMD, deinitializeDMD;
    import std.file : tempDir, mkdir, rmdirRecurse, write;
    import std.path : buildPath;
    import std.datetime.systime : Clock;
    import std.conv : to;

    auto dir = buildPath(tempDir(), "fcdirtest-" ~ to!string(Clock.currTime().toUnixTime()));
    mkdir(dir);
    scope(exit) rmdirRecurse(dir);

    write(buildPath(dir, "a.d"), "int foo(){ return 1; }");
    write(buildPath(dir, "b.d"), "int bar(){ return 2; }\nunittest { assert(bar() == 2); }");

    initDMD();
    auto withUT = collectFunctionsInDir(dir);
    deinitializeDMD();
    assert(withUT.length == 3);
    size_t utCount;
    foreach(f; withUT)
        if(f.funcDecl.isUnitTestDeclaration())
            ++utCount;
    assert(utCount == 1);

    initDMD();
    auto withoutUT = collectFunctionsInDir(dir, false);
    deinitializeDMD();
    assert(withoutUT.length == 2);
    foreach(f; withoutUT)
        assert(!f.funcDecl.isUnitTestDeclaration());
}

