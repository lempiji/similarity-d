# Threshold Example

This folder contains `a.d` with two similar functions of different lengths.

Run the tool with default options:

```bash
$ dub run -- --dir samples/threshold
```

No matches will be printed because the similarity between the functions is below the default threshold of `0.85`.

Re-run with a lower threshold and cross-file comparison disabled:

```bash
$ dub run -- --dir samples/threshold --threshold=0.3 --min-lines=3 --cross-file=false
```

This command reports a match between `shortFunc` and `biggerFunc`. Reducing the threshold accepts partial similarity while `--cross-file=false` limits comparisons to functions inside each file, which avoids unrelated matches when scanning a larger directory.
