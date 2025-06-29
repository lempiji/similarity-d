# AGENTS.md

This repository contains `similarity-d`, a CLI tool and library for detecting similar D functions. It relies on the DMD front-end to parse source files and a custom tree edit distance implementation.

## Setup

- Use `dmd` **2.111.0** or newer and ensure `dub` is on your `PATH`.
- If the compiler is missing, run the installer script located at `/workspace/dlang/install.sh`.
- After installation run `dub --version` to verify the tool chain is accessible.

## Testing

The project includes extensive unit tests. Always run them before committing:

```bash
dub test --coverage --coverage-ctfe
```

- The command generates `source-*.lst` coverage files. Check the final two lines of each file to confirm the percentage is **70% or higher**.
- If overall coverage drops below the threshold, add tests to raise it before merging.
- Old coverage files can be removed with `dub clean` when necessary.

After tests pass, ensure the CLI still functions with a minimal invocation:

```bash
dub run -- --dir source/lib --exclude-unittests --threshold=0.9 --min-lines=3
```

## Design Documents

- Architectural decisions and feature proposals live in `docs/design/`.
- Follow the workflow defined in `docs/design/AGENTS.md` for creating **Proposals** and **ADRs**.
- Do not start coding until a Proposal is **Approved** and any related ADR is **Accepted**.

## Code Overview

```
source/cli        entry point and command-line options
source/lib        core library modules
  ├─ functioncollector.d  – parse files and extract functions
  ├─ treediff.d           – normalize ASTs and compute similarity
  ├─ treedistance.d       – basic tree edit distance algorithm
  └─ crossreport.d        – high level matching and reporting utilities
```

The CLI (`source/cli/main.d`) wires these pieces together. Tests for each module reside at the bottom of the corresponding `.d` file.

## Contribution Workflow

1. Create or update design docs under `docs/design/` when planning new features.
2. Open a PR referencing the Proposal/ADR IDs once they are approved.
3. Run tests and verify coverage before pushing.
4. Keep README and documentation up to date when behavior changes.
5. Use clear commit messages explaining *why* a change is made.

Following these guidelines keeps the codebase maintainable and ensures design decisions remain traceable.
