module cli.main;

import std.stdio : writeln;
import std.getopt : getopt, defaultGetoptPrinter, GetoptResult;
import std.array : join;
import std.algorithm.searching : canFind;

version(unittest)
{
    import functioncollector;
    alias FunctionInfo = functioncollector.FunctionInfo;
    __gshared bool lastIncludeUnittests;
    __gshared string[] capturedOutput;

    // Replace writeln so output can be inspected by tests
    void writeln(T...)(T args)
    {
        import std.conv : text;
        capturedOutput ~= text(args);
    }

    // Provide stub implementations for CLI dependencies
    FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true)
    {
        lastIncludeUnittests = includeUnittests;
        return [];
    }

    import crossreport : CrossMatch;

    void collectMatches(FunctionInfo[] funcs, double threshold, size_t minLines,
            size_t minTokens, bool noSizePenalty, bool crossFile,
            scope void delegate(CrossMatch) sink)
    {
        CrossMatch m;
        m.fileA = "a.d";
        m.startA = 1;
        m.endA = 1;
        m.fileB = "b.d";
        m.startB = 1;
        m.endB = 1;
        m.similarity = 1.0;
        m.priority = 1.0;
        m.snippetA = "int foo(){ return 1; }";
        m.snippetB = "int bar(){ return 1; }";
        sink(m);
    }
}
else
{
    import functioncollector : collectFunctionsInDir;
    import crossreport : collectMatches, CrossMatch;
}
import dmd.frontend : initDMD, deinitializeDMD;

void main(string[] args)
{
    double threshold = 0.85;
    size_t minLines = 5;
    size_t minTokens = 20;
    bool noSizePenalty = false;
    bool printResult = false;
    bool crossFile = true;
    bool excludeUnittests = false;
    string dir = ".";

    GetoptResult helpInfo = getopt(args,
        "threshold", &threshold,
        "min-lines", &minLines,
        "print", &printResult,
        "no-size-penalty", &noSizePenalty,
        "cross-file", &crossFile,
        "min-tokens", &minTokens,
        "dir", &dir,
        "exclude-unittests", &excludeUnittests
    );

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("similarity-d [options]", helpInfo.options);
        return;
    }

    initDMD();
    scope(exit) deinitializeDMD();

    auto funcs = collectFunctionsInDir(dir, !excludeUnittests);
    bool found = false;
    collectMatches(funcs, threshold, minLines, minTokens,
            noSizePenalty, crossFile, (CrossMatch m)
    {
        found = true;
        writeln(m.fileA, ":", m.startA, "-", m.endA,
            " <-> ", m.fileB, ":", m.startB, "-", m.endB,
            " score=", m.similarity, " priority=", m.priority);
        // snippetA/snippetB now contain raw function text
        if (printResult)
        {
            writeln("\n---\n", m.snippetA, "\n---\n", m.snippetB, "\n---");
        }
    });

    if (!found)
    {
        writeln("No similar functions found.");
    }
}

unittest
{
    auto dir = ".";
    lastIncludeUnittests = true;
    main(["app", "--dir", dir]);
    assert(lastIncludeUnittests == true);
    main(["app", "--dir", dir, "--exclude-unittests"]);
    assert(lastIncludeUnittests == false);
}

unittest
{
    // verify --print outputs function snippets
    capturedOutput.length = 0;
    main(["app", "--print"]);
    auto joined = capturedOutput.join();
    assert(joined.canFind("int foo()") || joined.canFind("int bar()"));
}
