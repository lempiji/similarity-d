---
title: Default Collect Nested Functions
date: 2025-07-06
status: Accepted
---

*A Japanese translation is available [here](0001-default-collect-nested.ja.md).* 

# ADR 0001: Default Collect Nested Functions

Originating Proposal: docs/design/proposals/0001-nested-function-collection.md

## Context
Proposal 0001 describes adding an `excludeNested` option so users can
opt out of collecting nested functions. The goal is to make the tool
more helpful by inspecting all functions that might be duplicated,
including those declared inside other functions.

## Decision
Nested functions will be collected by default. The collector and CLI
expose an `excludeNested` flag to skip nested declarations when the
user does not need them.

## Consequences
- Improves similarity detection for projects that rely heavily on
  nested functions.
- Slightly increases memory use and processing time for large code
  bases, which can be mitigated by `--exclude-nested`.
