module file_a;

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
