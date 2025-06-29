module file_a;

int accumulate(int[] arr)
{
    int sum = 0;
    foreach (v; arr)
        sum += v;
    return sum;
}

class Animal
{
    string name;

    this(string name)
    {
        this.name = name;
    }

    void speak()
    {
        import std.stdio : writeln;

        writeln(name, " says hello!");
        writeln("Wow, ", name, " is happy to see you.");
    }
}