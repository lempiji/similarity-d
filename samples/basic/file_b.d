module file_b;

long total(long[] arr)
{
    long sum = 0;
    foreach (v; arr)
        sum += v;
    return sum;
}

class Creature
{
    string name;

    this(string name)
    {
        this.name = name;
    }

    void scream()
    {
        import std.stdio : writeln;

        writeln(name, " screams!");
        writeln("The sound echoes through the forest.");
    }
}