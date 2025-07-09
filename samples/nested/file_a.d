module file_a;

/// Outer function used in nested samples.
void outerA()
{
    int addOne(int x)
    {
        return x + 1;
    }

    auto y = addOne(3);
    import std.stdio : writeln;
    writeln(y);
}

