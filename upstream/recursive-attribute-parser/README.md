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
`idris-mlir-opt` and `idris-mlir-reduce` do not have it.
