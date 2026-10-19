<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] A nested operation's print writes every type inline at each use

On llvm main at 7208ba24 (the pin), `Operation::print` collects and
prints aliases only for a top-level operation at module scope
(`mlir/lib/IR/AsmPrinter.cpp`, `Operation::print(raw_ostream &, AsmState &)`).
The IR printer prints every nested operation with local scope
(`mlir/lib/Pass/IRPrinting.cpp`, `printIR`), so each dump of
`-mlir-print-ir-after-all`, and each file of `-mlir-print-ir-tree-dir`,
writes every attribute and type inline at every use.

Our data types are nominal and print their bodies, which hold other data
types, so a dump's size is the type DAG unfolded into a tree at every
use. The harness compiles every program with its dumps
(`harness/lib/mlir.sh`, `dump_options`): tests/directory-listing's
47-line program dumps 1.9 GB, 84% of it the text of data types, and its
compile takes 43 s of CPU against 7 s without dumps, so under the
harness it crosses the 60 s step. sortedmap's dumps were 9 GB.

## Reproduce

`print-local-aliases.mlir`, upstream's own dialects: two ops of one
function hold one affine map. After `canonicalize` in a `func.func` nest
the IR printer writes the map inline twice; with
`-mlir-print-local-aliases` it writes `#map = ...` once, before the
function, and `#map` at each use.

## Patch

`llvm.patch`, against 7208ba24: `OpPrintingFlags::printLocalAliases`
and the option `-mlir-print-local-aliases` (off by default), under which
`Operation::print` initializes the aliases of the operation it prints and
prints it as it prints a top-level one, its aliases first. The flag's bit
is the last of the flags' bit-fields, so the class keeps its size. Its
test, `mlir/test/IR/print-local-aliases.mlir`, is the reproducer.

Measured with the patched printer linked into idris-mlir (arm64 macOS,
Debug): directory-listing's dumps 1.9 GB -> 65 MB, its compile with
dumps 43 -> 11 s of CPU; every program-level dump still parses as a
module. tests/upstream-print-local-aliases checks the pinned mlir-opt.

Once the toolchain carries it, `dump_options` (`harness/lib/mlir.sh`)
adds `--mlir-print-local-aliases`.

## Upstreaming plan

Status: not sent. Send as one pull request to llvm/llvm-project,
`[mlir] Print an operation's aliases with local scope on request`, with
`llvm.patch`'s diff and its message; no issue is needed. Reviewers may
prefer the IR printer to print aliases by default for the files of
`-mlir-print-ir-tree-dir`, which are documents of their own; follow them.
The patch goes when the pin carries the option.
