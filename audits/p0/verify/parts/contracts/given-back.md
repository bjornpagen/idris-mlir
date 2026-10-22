<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: what a function gives back (C18; L10, 2026-10-21)

- **Name:** `given_back`, an optional inherent attribute on `idr.func`,
  `#idr.given_back<[...]>`, C++ `GivenBackAttr`. It is absent when no
  result is given back.
- **Shape:** a list of entries `{result : Path, argument : Path}`, sorted
  by result path.
  - `Path = {index : uint32, fields : ArrayRef<uint32>}`.
  - The fields are positions through constructors laid out inline: each
    step is a field of a type whose constructor its type fixes.
  - Printed `given_back = [0 <- 2, 1.0 <- 0.1]`.
- **Meaning:** on every path that returns, that component of the result
  is that component of the argument: the same value (identity, not
  equality).
- **Who writes it:** only the pass that proves it, the optimizer's decide
  step (L18). It is never copied onto calls. L14's identity rule reads it
  through `CalleeFacts`.
- **The tail rule** (L10's, checked by L02 in `idr.call`'s
  `verifySymbolUses`, which resolves the callee): a `tail` call's callee
  gives back exactly the result paths its caller gives back. Tail-joined
  functions return one type, so a result dropped in one is dropped in
  every one (P0 §8's idr-returned-arguments bug).
- **Deleted:** the lowering-time Returned solve and
  idr-returned-arguments (`Transforms/Tail/Returned.cpp`,
  `ReturnedArguments.cpp`).
