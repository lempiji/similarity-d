/// Command line interface for detecting similar functions in D source trees.
/// Supports `--dir`, `--threshold`, `--min-lines`, `--min-tokens` and related
/// flags. See the README for complete usage instructions.
module cli.main;

import std.stdio : writeln;
import std.getopt : getopt, defaultGetoptPrinter, GetoptResult;

version(unittest)
{
    import functioncollector;
    alias FunctionInfo = functioncollector.FunctionInfo;
    __gshared bool lastIncludeUnittests;
    __gshared double lastThreshold;
    __gshared size_t lastMinLines;
    __gshared size_t lastMinTokens;
    __gshared bool lastCrossFile;
    __gshared bool lastNoSizePenalty;
    __gshared bool lastPrintResult;
    __gshared bool lastExcludeNested;
    FunctionInfo[] collectFunctionsInDir(string dir, bool includeUnittests = true, bool excludeNested = false)
    {
        lastIncludeUnittests = includeUnittests;
        lastExcludeNested = excludeNested;
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
    size_t minTokens = 20;
    bool noSizePenalty = false;
    bool printResult = false;
    bool crossFile = true;
    bool excludeUnittests = false;
    bool excludeNested = false;
    string dir = ".";

    GetoptResult helpInfo = getopt(args,
        "threshold", &threshold,
        "min-lines", &minLines,
        "print", &printResult,
        "no-size-penalty", &noSizePenalty,
        "cross-file", &crossFile,
        "min-tokens", &minTokens,
        "dir", &dir,
        "exclude-unittests", &excludeUnittests,
        "exclude-nested", &excludeNested
    );

    version(unittest)
    {
        lastThreshold = threshold;
        lastMinLines = minLines;
        lastMinTokens = minTokens;
        lastCrossFile = crossFile;
        lastNoSizePenalty = noSizePenalty;
        lastPrintResult = printResult;
        lastExcludeNested = excludeNested;
    }

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("similarity-d [options]", helpInfo.options);
        return;
    }

    initDMD();
    scope(exit) deinitializeDMD();

    auto funcs = collectFunctionsInDir(dir, !excludeUnittests, excludeNested);
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
    lastExcludeNested = false;
    main(["app", "--dir", dir]);
    assert(lastIncludeUnittests == true);
    assert(lastExcludeNested == false);
    assert(lastThreshold == 0.85);
    assert(lastMinLines == 5);
    assert(lastMinTokens == 20);
    assert(lastCrossFile == true);
    assert(lastNoSizePenalty == false);
    assert(lastPrintResult == false);

    main(["app", "--dir", dir, "--exclude-unittests",
        "--threshold=0.9", "--min-lines=2", "--min-tokens=10",
        "--cross-file=false", "--no-size-penalty", "--print", "--exclude-nested"]);
    assert(lastIncludeUnittests == false);
    assert(lastExcludeNested == true);
    assert(lastThreshold == 0.9);
    assert(lastMinLines == 2);
    assert(lastMinTokens == 10);
    assert(lastCrossFile == false);
    assert(lastNoSizePenalty == true);
    assert(lastPrintResult == true);
}

unittest
{
    auto dir = ".";
    lastExcludeNested = false;
    main(["app", "--dir", dir, "--exclude-nested"]);
    assert(lastExcludeNested == true);
}
