/// Command line interface for detecting similar functions in D source trees.
/// Supports `--dir`, `--threshold`, `--min-lines`, `--min-tokens` and related
/// flags. See the README for complete usage instructions.
module cli.main;

import std.stdio : writeln;
import std.getopt : getopt, defaultGetoptPrinter, GetoptResult;
import std.file : exists, isDir;
import std.json : parseJSON;

enum packageVersion = parseJSON(import("dub.json"))["version"].str;

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
    __gshared bool lastHelpWanted;
    __gshared bool lastShowVersion;
    __gshared string lastVersionPrinted;
    void printVersion(string s) { lastVersionPrinted = s; }
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
    void printVersion(string s) { writeln(s); }
}
import crossreport : collectMatches, CrossMatch;
import dmd.frontend : initDMD, deinitializeDMD;

int main(string[] args)
{
    double threshold = 0.85;
    size_t minLines = 5;
    size_t minTokens = 20;
    bool noSizePenalty = false;
    bool printResult = false;
    bool crossFile = true;
    bool excludeUnittests = false;
    bool excludeNested = false;
    bool showVersion = false;
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
        "exclude-nested", &excludeNested,
        "version", &showVersion
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
        lastHelpWanted = helpInfo.helpWanted;
        lastShowVersion = showVersion;
    }

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("similarity-d [options]", helpInfo.options);
        return 0;
    }

    if (showVersion)
    {
        printVersion(packageVersion);
        return 0;
    }

    if (!exists(dir) || !isDir(dir))
    {
        writeln("Invalid directory: ", dir);
        return 1;
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
    return 0;
}

unittest
{
    auto dir = ".";
    assert(main(["app", "--help"]) == 0);
    assert(lastHelpWanted == true);
    assert(main(["app", "--version"]) == 0);
    assert(lastShowVersion == true);
    assert(lastVersionPrinted == packageVersion);
    lastIncludeUnittests = true;
    lastExcludeNested = false;
    assert(main(["app", "--dir", dir]) == 0);
    assert(lastIncludeUnittests == true);
    assert(lastExcludeNested == false);
    assert(lastShowVersion == false);
    assert(lastThreshold == 0.85);
    assert(lastMinLines == 5);
    assert(lastMinTokens == 20);
    assert(lastCrossFile == true);
    assert(lastNoSizePenalty == false);
    assert(lastPrintResult == false);

    assert(main(["app", "--dir", dir, "--exclude-unittests",
        "--threshold=0.9", "--min-lines=2", "--min-tokens=10",
        "--cross-file=false", "--no-size-penalty", "--print", "--exclude-nested"]) == 0);
    assert(lastIncludeUnittests == false);
    assert(lastExcludeNested == true);
    assert(lastThreshold == 0.9);
    assert(lastMinLines == 2);
    assert(lastMinTokens == 10);
    assert(lastCrossFile == false);
    assert(lastNoSizePenalty == true);
    assert(lastPrintResult == true);
    assert(lastShowVersion == false);
}

unittest
{
    auto dir = ".";
    lastExcludeNested = false;
    assert(main(["app", "--dir", dir, "--exclude-nested"]) == 0);
    assert(lastExcludeNested == true);
    assert(lastShowVersion == false);
}

unittest
{
    import std.file : deleteme, remove, readText;
    import std.algorithm.searching : canFind;
    import std.stdio : File, stdout;

    auto bogus = "./does-not-exist";
    auto capturePath = deleteme ~ "-cli-main";
    auto captureFile = File(capturePath, "w+");
    auto oldStdout = stdout;
    stdout = captureFile;
    scope(exit)
    {
        stdout.flush();
        stdout = oldStdout;
        captureFile.close();
        remove(capturePath);
    }

    assert(main(["app", "--dir", bogus]) == 1);
    captureFile.rewind();
    auto output = readText(capturePath);
    assert(output.canFind("Invalid directory: " ~ bogus));
    assert(lastShowVersion == false);
}
