module file_b;

/// Returns the sum of all elements in `arr`.
long total(long[] arr)
{
    long sum = 0;
    foreach (v; arr)
        sum += v;
    return sum;
}

/// Simple creature used by the examples.
class Creature
{
    /// Name of the creature.
    string name;

    /// Create a `Creature` with the given name.
    this(string name)
    {
        this.name = name;
    }

    /// Emit an excited scream.
    void scream()
    {
        import std.stdio : writeln;

        writeln(name, " screams!");
        writeln("The sound echoes through the forest.");
    }}
