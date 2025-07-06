module testutils;

version(unittest) {
import dmd.frontend : initDMD, deinitializeDMD;

/// RAII helper to manage DMD initialization for unit tests.
public struct DmdInitGuard
{
    @disable this(this);

    /// Since structs cannot define user default constructors, calling a
    /// constructor would require a dummy parameter.  Instead provide a static
    /// factory that performs initialization and relies on NRVO so the
    /// destructor is not triggered before the caller's scope exits.
    static DmdInitGuard make()
    {
        initDMD();
        // using `DmdInitGuard()` here avoids the dummy argument and allows
        // the compiler to apply NRVO
        return DmdInitGuard();
    }

    ~this()
    {
        deinitializeDMD();
    }
}
}
