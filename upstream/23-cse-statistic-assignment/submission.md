<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Submission texts

One pull request to llvm/llvm-project. Its diff is `llvm.patch`.

## Pull request title

[mlir] Accumulate CSE pass statistics over nested runs

## Pull request body

`CSE::runOnOperation` assigned each run's CSE/DCE counts to its pass
statistics instead of accumulating them. For a nested CSE, pass
statistics merge the per-clone values by summing, so the report was
the count of the last operation each clone ran on — under
`-mlir-disable-threading`, simply the last function's count:

```
$ mlir-opt cse.mlir -pass-pipeline='builtin.module(func.func(cse))' \
    -mlir-pass-statistics -mlir-pass-statistics-display=list
  CSEPass
    (S) 3 num-cse'd
$ mlir-opt cse.mlir ... -mlir-disable-threading
  CSEPass
    (S) 0 num-cse'd
```

for a module where 3 operations are CSE'd in both runs (the new
`cse-statistics.mlir` test). Accumulate with `+=` instead.

`ControlFlowSink::runOnOperation` assigns `numSunk` the same way, once
per region-branch operation it walks; left alone here, happy to fold
it in or split it out as reviewers prefer.
