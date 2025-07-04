module cli.main;

import std.stdio : writeln;
import std.getopt : getopt, defaultGetoptPrinter, GetoptResult;

version(unittest)
{
    import functioncollector;
    alias FunctionInfo = functioncollector.FunctionInfo;
    __gshared bool lastIncludeUnittests;
    FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true)
    {
        lastIncludeUnittests = includeUnittests;
        return [];
    }
}
else
{
    import functioncollector : collectFunctionsInDir;
}
import crossreport : collectMatches, CrossMatch;
import dmd.frontend : initDMD, deinitializeDMD;

void main(string[] args)
{
    double threshold = 0.85;
    size_t minLines = 5;
    size_t minNodes = 20;
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
        "min-nodes", &minNodes,
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
    collectMatches(funcs, threshold, minLines, minNodes,
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
