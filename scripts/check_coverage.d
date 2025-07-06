#!/usr/bin/env -S rdmd
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
        auto lastLine = lines[$-1].strip;
        auto m = match(lastLine, regex(r"([0-9]+)%"));
        if (!m.empty)
        {
            int perc = to!int(m.captures[1]);
            if (perc < 70)
            {
                stderr.writefln("Coverage for %s is below 70%%: %s%%", f.name, perc);
                fail = true;
            }
        }
        else
        {
            stderr.writeln("Could not parse coverage percentage from ", f.name);
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
