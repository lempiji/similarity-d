---
title: Nested Function Collection
date: 2025-07-06
status: Approved
---

*A Japanese translation is available [here](0001-nested-function-collection.ja.md).* 

# Proposal: Nested Function Collection

## Motivation
Some projects rely heavily on nested functions for organization. The
current collector only records top level functions which makes it
impossible to analyse nested routines individually.

## Goals
- Collect nested functions by default to avoid missing matches.
- Allow opting out when only top level functions are desired.

## Non-Goals
- Refactoring how normalized ASTs are generated.
- Detecting nested functions across different modules.

## Solution Sketch
Extend the collector to traverse `FuncDeclaration` nodes found inside
statements. A new `excludeNested` flag is added to the public API and
CLI. Nested functions are gathered by default; when this flag is set each
nested declaration is ignored.

## Alternatives
- Parse source using a custom visitor rather than the existing AST
  helpers. This was rejected for simplicity.

## Impact & Risks
Collecting nested functions by default may increase memory usage for
large code bases, but it can be mitigated by using `--exclude-nested`.

## Next Steps
- Update documentation and unit tests.
