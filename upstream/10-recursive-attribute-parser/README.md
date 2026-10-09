# [mlir] The textual parser and printer recurse once per level of attribute nesting, and overflow the stack

At `llvmorg-23.1.2`, `mlir-opt` crashes with SIGSEGV on a module whose
attribute is a builtin array nested a few thousand deep: the parser calls
itself for every level, and the stack runs out. The printer recurses the
same way. Nothing checks the depth, so the crash is a bare segmentation
fault, with no diagnostic.

## Reproduce

`nested.sh 10000 > nested.mlir` writes:

```mlir
module attributes {test.nested = [[[[ ... ]]]]} {
}
```

with the array nested 10,000 deep (20 KB of text).

```
$ ulimit -s 8192
$ mlir-opt nested.mlir
Stack dump:
0.	Program arguments: mlir-opt nested.mlir
1.	MLIR Parser: custom op parser 'builtin.module'
Segmentation fault
```

`mlir-opt` exits with status 139. On an 8 MiB stack, 4,000 levels parse
and print, and 6,000 crash. Expected: the module parses and prints back, or
the parser reports that the nesting is too deep.

Values nested this deep are ordinary for a compiler that evaluates code at
compile time: a list of 10,000 elements that a program computes becomes
a constant nested 10,000 deep.

## Cause

`Parser::parseAttribute` (`mlir/lib/AsmParser/AttributeParser.cpp:74-85`)
parses an array's elements through `parseCommaSeparatedListUntil` with a
callback that calls `parseAttribute` again, so every level costs several
frames. `AsmPrinter::Impl::printAttributeImpl`
(`mlir/lib/IR/AsmPrinter.cpp:2485-2489`) prints the elements by calling
`printAttribute` for each, and the alias collection before it
(`AsmPrinter.cpp:949-951`) walks them recursively too. The bytecode reader
has no such limit: it reads attributes from a worklist.

## Proposed fix

Parse and print nested attributes from an explicit worklist, as the
bytecode reader does; or, failing that, bound the depth and report
"attribute nested too deeply" as a parse error, so that the failure is a
diagnostic rather than a crash.

## Our workaround

`PINS.md`: `mlir-recursion`. `idris-mlir-cc` runs the whole compilation,
and compile-time evaluation's child runs its calls, on a stack reserved as
large as the address space allows (the runtime's `idris_rt_run_on_stack`),
so the depth is bounded by memory, not by the default 8 MiB stack.
`idris-mlir-opt` runs on the same stack; `idris-mlir-reduce` does not.

## Why there is no patch

Neither proposed fix lets the workaround go. A depth bound turns the
crash into a diagnostic but refuses the values compile-time evaluation
makes, which the reserved stack lets the compiler handle today; it would
be a regression for us. A worklist parser and printer for builtin
attributes would make the reproducer pass, but the recursion is also in
the alias collection, in `AttrTypeWalker` and `AttrTypeReplacer`, and in
every dialect's attribute parser that calls `parseAttribute` for its
parameters (the idr dialect's constants among them), so the compiler
would still need its large stack. The fix is a change of design across
the parser, the printer and the sub-element walks, which needs upstream's
agreement before code.

## Upstreaming plan

Status: not ready. Still reproduces on the pin, llvm main at 7208ba24:
on arm64 macOS, with `.toolchain/llvm-macos` built at that commit
(2026-10-09), `tests/upstream/recursive-attribute-parser` printed
`nested: still reproduces`: on an 8 MiB stack the array nested 1,000
deep parses, and the one nested 100,000 deep ends `mlir-opt` with a
signal. `Parser::parseAttribute` still parses an array's elements by
calling itself (`AttributeParser.cpp:74-85` at 7208ba24, as at
23.1.2). Not rerun on x86_64 Linux at the pin.

- Where: an RFC on LLVM Discourse (MLIR) first, for iterative parsing,
  printing and sub-element walking of nested attributes, citing the
  bytecode reader's worklist. Until upstream agrees on the design, the
  workaround stays and this directory carries no patch.
- Upstream test: `nested.sh 10000` round-tripping through `mlir-opt` on
  an 8 MiB stack.
