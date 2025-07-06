# similarity-d
[![CI](https://github.com/lempiji/similarity-d/actions/workflows/ci.yml/badge.svg)](https://github.com/lempiji/similarity-d/actions/workflows/ci.yml)

similarity-d is a command-line tool written in D for finding similar functions in a project.
It uses a Tree Edit Distance (TED) algorithm to compare normalized abstract syntax trees.

## Prerequisites

The tool requires **DMD** 2.111.0 or newer and relies on `dub` being available in your `PATH`.
If the compiler is not installed, use the official `install.sh` script or Windows installer provided by the D language project.
After installation, run `dub --version` to confirm the tool chain is accessible.

## Usage

```
dub fetch similarity-d
dub run similarity-d -- [options]
```

### Options

- `--dir` &lt;path&gt;  Directory to search for `.d` source files (defaults to current directory).
- `--threshold` &lt;float&gt;  Similarity threshold used to decide matches.
- `--min-lines` &lt;integer&gt;  Minimum number of lines in a function to be considered.
- `--min-tokens` &lt;integer&gt;  Minimum number of normalized AST nodes (default 20).
- `--no-size-penalty`  Disable length penalty when computing similarity.
- `--print`  Print the snippet of each function when reporting results.
- `--cross-file`[=true|false]  Allow comparison across different files (default `true`). Use `--cross-file=false` to limit comparisons within each file.
- `--exclude-unittests`  Skip `unittest` blocks when collecting functions.
- `--exclude-nested`  Ignore nested functions and only collect top-level declarations.

The CLI compares all functions it finds in the specified directory and prints any matches whose similarity score exceeds the threshold.
Each result lists the two locations and the calculated similarity.
The TSED algorithm normalizes identifiers and literals before calculating an edit-distance based score.

When computing similarity a length penalty is applied so that short functions do not dominate the results. This behaviour can be disabled with `--no-size-penalty` if you want the raw tree edit distance score.

Example:

```bash
$ similarity-d --threshold=0.8 --min-lines=3 --dir=source --exclude-nested
# disable cross-file comparisons
$ similarity-d --threshold=0.8 --cross-file=false
```

## Remarks

This project adapts the ideas from
[mizchi/similarity](https://github.com/mizchi/similarity), a multi-language
code duplication detector written in Rust and TypeScript. While the original
repository focuses on various languages, **similarity-d** implements the same
tree edit distance approach specifically for D source code.

## Sample Usage

Several small examples are available under the `samples/` folder. Each folder
contains a couple of `.d` files and a short README describing the scenario.

### `samples/basic`

This directory has two almost identical functions. Lower the token filter to
see the match:

```bash
$ dub run -- --dir samples/basic --min-tokens=0
samples/basic\file_a.d:3-9 <-> samples/basic\file_b.d:3-9 score=1 priority=7
samples/basic\file_a.d:20-26 <-> samples/basic\file_b.d:20-26 score=1 priority=7
```

Cross-file comparison is enabled by default, so functions from `file_a.d` and `file_b.d` match. Restrict the tool to compare only within each file:

```bash
$ dub run -- --dir samples/basic --min-tokens=0 --cross-file=false
No similar functions found.
```

Running without `--min-tokens=0` prints nothing because the default value of 20
filters out these tiny functions.

### `samples/threshold`

Two functions with different lengths live in `a.d`. The default threshold of
`0.85` hides the pair:

```bash
$ dub run -- --dir samples/threshold
No similar functions found.
```

Lowering the threshold reveals a partial match:

```bash
$ dub run -- --dir samples/threshold --threshold=0.3 --min-tokens=0 --cross-file=false
samples/threshold\a.d:1-7 <-> samples/threshold\a.d:9-17 score=0.346939 priority=3.12245
```

## Development

Run the full test suite before sending a pull request.  The project expects
coverage information to be generated and kept above 70% for each module.

```bash
dub test --coverage --coverage-ctfe
```

After running tests, inspect the `source-*.lst` files and confirm the final two
lines show coverage of at least 70%.
You can automate this check by running `scripts/check-coverage.sh` which will
exit with an error if any coverage file is below the threshold.

To verify the command line interface still works, invoke it with a minimal
configuration:

```bash
dub run -- --dir source/lib --exclude-unittests --threshold=0.9 --min-lines=3
```


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow and guidelines.
