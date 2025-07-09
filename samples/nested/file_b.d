module file_b;

/// Another outer function for nested sample.
void outerB()
{
    int addOne(int x)
    {
        return x + 1;
    }

    import std.stdio : writeln;
    foreach(i; 0 .. 2)
        writeln(addOne(i));
}

