# Contributing

Thank you for wanting to contribute to **similarity-d**. This document summarizes the project workflow described in `AGENTS.md`.

## Prerequisites

- Install **DMD** 2.111.0 or newer using the provided install script or the official Windows installer.
- Ensure `dub` is on your `PATH` and verify with:

```bash
dub --version
```

## Design Documents

Proposals and Architectural Decision Records (ADRs) live under `docs/design/`. The complete process is defined in [`docs/design/AGENTS.md`](docs/design/AGENTS.md).

1. Draft a Proposal in `docs/design/proposals/`.
2. Iterate until its status is **Approved**.
3. If architectural decisions are required, create an ADR in `docs/design/adr/` and obtain **Accepted** status.
4. Do not start implementing code until the relevant Proposal is Approved and any ADR is Accepted.
5. Reference the document IDs in pull requests.

## Tests and CLI Check

Run the full test suite and confirm coverage before committing:

```bash
dub test --coverage --coverage-ctfe
```

Each generated `source-*.lst` file must end with a coverage percentage of **70% or higher**. If coverage drops below the threshold, add tests. Remove old coverage files with `dub clean` if needed.

After tests pass, verify the command-line interface with a minimal invocation:

```bash
dub run -- --dir source/lib --exclude-unittests --threshold=0.9 --min-lines=3
```

Only commit changes after these checks succeed.
