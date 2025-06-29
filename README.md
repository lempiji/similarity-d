# similarity-d

similarity-d is a command-line tool written in D for finding similar functions in a project.
It uses a Tree Edit Distance (TED) algorithm to compare normalized abstract syntax trees.

## Usage

```
dub fetch similarity-d
dub run similarity-d -- [options]
```

### Options

- `--dir` &lt;path&gt;  Directory to search for `.d` source files (defaults to current directory).
- `--threshold` &lt;float&gt;  Similarity threshold used to decide matches.
- `--min-lines` &lt;integer&gt;  Minimum number of lines in a function to be considered.
- `--min-tokens` &lt;integer&gt;  Minimum number of normalized tokens (default 30).
- `--no-size-penalty`  Disable length penalty when computing similarity.
- `--print`  Print the snippet of each function when reporting results.
- `--cross-file`[=true|false]  Allow comparison across different files (default `true`). Use `--cross-file=false` to limit comparisons within each file.
- `--exclude-unittests`  Skip `unittest` blocks when collecting functions.

The CLI compares all functions it finds in the specified directory and prints any matches whose similarity score exceeds the threshold.
Each result lists the two locations and the calculated similarity.
The TSED algorithm normalizes identifiers and literals before calculating an edit-distance based score.

Example:

```bash
$ similarity-d --threshold=0.8 --min-lines=3 --dir=source
# disable cross-file comparisons
$ similarity-d --threshold=0.8 --cross-file=false
```

## Remarks

https://github.com/mizchi/similarity

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

