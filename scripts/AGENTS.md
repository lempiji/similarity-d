# Scripting Guidelines

Scripts in this directory must be cross‑platform and written in the D programming language. Use `rdmd` to run them so they work on both Windows and Linux.

```
#!/usr/bin/env rdmd
```

Typical invocation:

```
rdmd path/to/script.d
```

Avoid platform‑specific shell commands inside the scripts.
