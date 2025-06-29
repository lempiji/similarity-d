# Basic Sample

This directory contains two small D modules with nearly identical functions. Only
the function names differ.

Run the similarity tool on this directory:

```bash
$ dub run -- --dir samples/basic
```

With the default options, cross-file comparison is enabled so the functions in
`file_a.d` and `file_b.d` will be compared. A single match should be reported.

You can adjust the similarity threshold or the minimum lines required for a
function using the `--threshold` and `--min-lines` options if needed.
