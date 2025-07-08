#!/usr/bin/env rdmd
// Verify that each generated `source-*.lst` coverage file reports at least
// a 70% pass rate. The coverage summary is found within the last two lines
// of each file, so both lines are inspected. Typically run with
// `rdmd scripts/check_coverage.d`.
import std.stdio;
import std.file : dirEntries, SpanMode, readText;
import std.array : array;
import std.string : splitLines, strip;
import std.regex : regex, match;
import std.conv : to;

int main()
{
    auto files = dirEntries(".", "source-*.lst", SpanMode.shallow).array;
    if (files.length == 0)
    {
        writeln("No coverage files found.");
        return 1;
    }

    bool fail = false;
    foreach (f; files)
    {
        auto lines = readText(f.name).splitLines();
        if (lines.length == 0)
        {
            stderr.writeln("Could not parse coverage percentage from ", f.name);
            fail = true;
            continue;
        }
        string[] tail = lines.length >= 2 ? lines[$-2 .. $] : lines[$-1 .. $];
        int perc = -1;
        foreach (line; tail)
        {
            auto m = match(line.strip, regex(r"([0-9]+)%"));
            if (!m.empty)
            {
                perc = to!int(m.captures[1]);
                break;
            }
        }
        if (perc == -1)
        {
            stderr.writeln("Could not parse coverage percentage from ", f.name);
            fail = true;
        }
        else if (perc < 70)
        {
            stderr.writefln("Coverage for %s is below 70%%: %s%%", f.name, perc);
            fail = true;
        }
    }

    if (fail)
    {
        stderr.writeln("Coverage check failed.");
        return 1;
    }

    writeln("All coverage files meet the threshold.");
    return 0;
}
