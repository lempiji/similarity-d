module file_a;

/// Returns the sum of all elements in `arr`.
int accumulate(int[] arr)
{
    int sum = 0;
    foreach (v; arr)
        sum += v;
    return sum;
}

/// Simple animal type used by the examples.
class Animal
{
    /// Name of the animal.
    string name;

    /// Create an `Animal` with the given name.
    this(string name)
    {
        this.name = name;
    }

    /// Print a friendly greeting.
    void speak()
    {
        import std.stdio : writeln;

        writeln(name, " says hello!");
        writeln("Wow, ", name, " is happy to see you.");
    }}
