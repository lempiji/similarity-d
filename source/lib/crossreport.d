module crossreport;

import std.algorithm : sort, max;
import std.range : isOutputRange, put;
import functioncollector : FunctionInfo, collectFunctionsFromSource;
import treediff : treeSimilarity, nodeCount;

/**
 * Detailed information about a detected match between two functions.
 *
 *  Fields prefixed with `A` refer to the first function in the pair and those
 *  with `B` refer to the second.  `priority` is calculated as
 *  `max(linesA, linesB) * similarity` and is used when sorting results.
 */
struct CrossMatch
{
    /// Path to the first function's source file.
    string fileA;
    /// Starting line of the first function.
    size_t startA;
    /// Ending line of the first function.
    size_t endA;
    /// Path to the second function's source file.
    string fileB;
    /// Starting line of the second function.
    size_t startB;
    /// Ending line of the second function.
    size_t endB;
    /// Number of lines in the first function.
    size_t linesA;
    /// Number of lines in the second function.
    size_t linesB;
    /// Calculated similarity score between the two functions.
    double similarity;
    /// Ranking metric used when ordering matches.
    double priority;
    /// Raw source snippet of the first function.
    string snippetA;
    /// Raw source snippet of the second function.
    string snippetB;
}

/// Generate cross matches from collected functions and output each match via `sink`.
void collectMatches(Sink)(FunctionInfo[] funcs, double threshold, size_t minLines,
        size_t minTokens, bool noSizePenalty, bool crossFile, auto ref Sink sink)
    if (isOutputRange!(Sink, CrossMatch))
{
    CrossMatch[] matches;
    size_t[FunctionInfo] nodeCountCache;
    foreach (f; funcs)
    {
        nodeCountCache[f] = nodeCount(f);
    }

    foreach (i, f1; funcs)
    {
        auto len1 = f1.endLine - f1.startLine + 1;
        if (len1 < minLines)
            continue;
        if (nodeCountCache[f1] < minTokens)
        {
            continue;
        }

        foreach (f2; funcs[i + 1 .. $])
        {
            auto len2 = f2.endLine - f2.startLine + 1;
            if (len2 < minLines)
                continue;
            if (nodeCountCache[f2] < minTokens)
                continue;
            if (!crossFile && f1.file != f2.file)
                continue;

            auto sim = treeSimilarity(f1, f2, !noSizePenalty);
            if (sim >= threshold)
            {
                CrossMatch m;
                m.fileA = f1.file;
                m.startA = f1.startLine;
                m.endA = f1.endLine;
                m.fileB = f2.file;
                m.startB = f2.startLine;
                m.endB = f2.endLine;
                m.linesA = len1;
                m.linesB = len2;
                m.similarity = sim;
                m.priority = cast(double)max(len1, len2) * sim;
                m.snippetA = f1.snippet;
                m.snippetB = f2.snippet;
                matches ~= m;
            }
        }
    }

    sort!((a, b) => a.priority > b.priority)(matches);
    foreach (m; matches)
        put(sink, m);
}

unittest
{
    import dmd.frontend : initDMD, deinitializeDMD;
    initDMD();
    scope(exit) deinitializeDMD();

    string codeA = q{
int foo(){ return 1; }
};
    string codeB = q{
int bar(){ return 1; }
};
    auto fA = collectFunctionsFromSource("a.d", codeA);
    auto fB = collectFunctionsFromSource("b.d", codeB);
    auto all = fA ~ fB;

    CrossMatch[] matches;
    // cross-file disabled should yield no matches
    collectMatches(all, 0.8, 1, 1, false, false, (CrossMatch m){ matches ~= m; });
    assert(matches.length == 0);

    // cross-file enabled should find one match
    matches.length = 0;
    collectMatches(all, 0.8, 1, 1, false, true, (CrossMatch m){ matches ~= m; });
    assert(matches.length == 1);
    assert(matches[0].fileA == "a.d" && matches[0].fileB == "b.d");
    assert(matches[0].similarity > 0.98 && matches[0].similarity <= 1.0);
}

unittest
{
    import dmd.frontend : initDMD, deinitializeDMD;
    initDMD();
    scope(exit) deinitializeDMD();

    string code = q{
int a(){ return 0; }
int b(){ return 0 + 1; }
int c(){ return 0; }
};
    auto funcs = collectFunctionsFromSource("s.d", code);
    CrossMatch[] matches;
    collectMatches(funcs, 0.0, 1, 1, false, true, (CrossMatch m){ matches ~= m; });
    assert(matches.length == 3); // three pairs
    foreach(i; 0 .. matches.length - 1)
        assert(matches[i].priority >= matches[i + 1].priority);
}

unittest
{
    import dmd.frontend : initDMD, deinitializeDMD;
    import std.conv : to;
    initDMD();
    scope(exit) deinitializeDMD();

    enum count = 150;
    string code;
    foreach(i; 0 .. count)
        code ~= "int fn" ~ i.to!string() ~ "(){ return " ~ i.to!string() ~ "; }\n";
    auto funcs = collectFunctionsFromSource("big.d", code);
    size_t pairs;
    collectMatches(funcs, 0.0, 1, 1, false, true, (CrossMatch m){ ++pairs; });
    auto expected = funcs.length * (funcs.length - 1) / 2;
    assert(pairs == expected);
}

unittest
{
    import dmd.frontend : initDMD, deinitializeDMD;
    initDMD();
    scope(exit) deinitializeDMD();

    string code = q{
int foo(){
    int x = 0;
    for(int i = 0; i < 10; ++i)
        x += i;
    return x;
}
int bar(){
    int y = 0;
    for(int i = 0; i < 5; ++i)
        y += i * 2;
    return y;
}
};
    auto funcs = collectFunctionsFromSource("m.d", code);
    CrossMatch[] matches;
    collectMatches(funcs, 0.0, 1, 1, false, true,
        (CrossMatch m){ matches ~= m; });
    assert(matches.length == 1);
    assert(matches[0].startA == funcs[0].startLine);
    assert(matches[0].startB == funcs[1].startLine);
    assert(matches[0].similarity > 0.5 && matches[0].similarity < 0.9);
}
