# Nested Functions

This folder demonstrates how the `--exclude-nested` option affects the results.
Two files define identical nested functions named `addOne`. Without excluding
nested functions a match is reported. When nested functions are ignored, no match
is found because the outer functions differ.

Run the tool with default options and a low token filter:

```bash
$ dub run -- --dir samples/nested --min-tokens=0
```

This prints a match between the nested `addOne` functions. Now exclude nested
functions:

```bash
$ dub run -- --dir samples/nested --min-tokens=0 --exclude-nested
```

No matches should appear.
