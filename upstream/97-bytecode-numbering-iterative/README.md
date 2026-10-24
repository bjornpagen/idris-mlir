<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bytecode] The bytecode writer numbers attributes and types by recursion on their nesting depth

On llvm main at 416f328b (the pin), the bytecode writer numbers every
attribute and type before it writes them, and `IRNumberingState::number`
(`mlir/lib/Bytecode/Writer/IRNumbering.cpp:327` for an attribute, `:502`
for a type) numbers a value's nested components by a dummy writing
through the dialect's bytecode interface, whose `writeAttribute` and
`writeType` call `number` again (`NumberingDialectWriter`, `:32`, `:37`;
*read*). Several native frames per level (`number`, the interface's
`writeAttribute`, the generated writer of the value, `writeList`, the
dummy writer): writing a value nested N deep needs a native stack that
grows with N. Operation properties are numbered the same way (`:474`).
The rest of the writer is iterative: operations and regions are numbered
from a worklist, and an entry is written with its nested values as
indices.

What reached it in this repository was the toolchain's `mlir-opt`
writing bytecode: `tests/upstream-bytecode-deferred-quadratic` converted
an array nested 32,000 deep to bytecode before it timed reading it back,
and with `upstream/10-recursive-attribute-parser` carried, the writer's
numbering was the one recursion on the depth left on that path when the
test wrote on the tools' small stack. The compiler itself writes no MLIR
bytecode: the frontend writes it, and the driver reads it. A value nested
this deep is ordinary input for an MLIR tool: a list of 20,000 elements is
a constant nested 20,000 deep, and a chain of call-site locations is as
deep as the inlining that built it.

## Reproduce

`nested.sh DEPTH` writes a module whose one attribute is a builtin array
nested DEPTH deep. `mlir-opt nested.mlir --emit-bytecode -o
nested.mlirbc` under a small stack (`ulimit -s 256`) overflows at the pin
from a few thousand levels on, and finishes with the patch (*conjecture*
on the depth: no overflowing depth is measured). Its text parses from an
explicit stack only with `upstream/10-recursive-attribute-parser`, which
applies before this patch; on main, the parser overflows first.

## The fix

`pull-request.diff`: the dummy writer records the components it reaches, in
the order it reaches them (each nested attribute and type, the dialect
resources a value references, the group name a writer callback chooses),
and `numberNested` numbers them from an explicit stack, one group of
components per value whose writing reached them, with the index of the
next one. The components of a newly numbered value are numbered before
the rest of its group, which is the order the recursion took, so every
value is first numbered, every dialect first met and every resource first
referenced at the same point as before: the `orderedAttrs`,
`orderedTypes`, dialect and resource orders are unchanged, and with them
the bytecode written, byte for byte. What a failed writer callback
reached is still numbered, and a callback's group name is still applied
after the components its writing reached. Not built.

## Why there is no patch

It was carried so that the toolchain's `mlir-opt` could write the input
of `upstream/03-bytecode-deferred-quadratic`'s check on the tools' small
stack. No tool of ours writes bytecode through MLIR's writer, so nothing
in the tree reaches the recursion, and that check writes its input on
the shell's stack and reads it on the small one. The report stays as a
submission, its pull request as `pull-request.diff`, which the bootstrap
does not apply.

## Upstreaming plan

Status: not carried since 2026-10-23 (no tool of ours writes bytecode
through MLIR's writer); not filed.

- Where: one pull request, `[mlir][bytecode]`, after the RFC on
  Discourse for the family of MLIR's recursions on input size
  (upstream/10-recursive-attribute-parser's plan), each family its own
  pull request.
- Upstream test: a lit test in `mlir/test/Bytecode/` round-tripping an
  attribute and a type nested a few thousand deep through
  `-emit-bytecode`, with the output compared to the text round trip; and
  the existing bytecode tests, whose output does not change.
- The report goes when the pin numbers nested attributes and types
  without recursion on their depth.
