# [mlir] Reading deeply nested attributes from bytecode takes quadratic time

At `llvmorg-23.1.2`, `mlir-opt` reads a module whose attribute is a builtin
array nested n deep from bytecode in time quadratic in n, while it parses
the same module from text in linear time. The bytecode reader defers an
attribute nested more than 5 deep to a worklist so as not to recurse, and
the worklist then resolves one level of deferral per pass over itself.

## Reproduce

`nested.sh N > nested.mlir` writes

```mlir
module attributes {test.nested = [[[[ ... ]]]]} {
}
```

with the array nested N deep. The text parser recurses per level (see
`recursive-attribute-parser`), so the conversion to bytecode needs a large
stack:

```
$ ulimit -s unlimited
$ for n in 8000 16000 32000; do
    sh nested.sh $n > n$n.mlir
    mlir-opt n$n.mlir --emit-bytecode -o n$n.mlirbc
    time mlir-opt n$n.mlirbc --emit-bytecode -o /dev/null
  done
```

| depth | read from bytecode | read from text |
| --- | --- | --- |
| 8,000 | 0.36 s | 0.09 s |
| 16,000 | 1.12 s | 0.14 s |
| 32,000 | 4.55 s | 0.18 s |

Each doubling of the depth takes four times as long from bytecode.
Expected: linear time, as from text.

A compiler that evaluates code at compile time meets such values as a
matter of course: a computed list of 20,000 elements is a constant nested
20,000 deep.

## Cause

`AttrTypeReader::resolveEntry` (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp:1370-1464`).
Reading an entry that is nested more than `maxAttrTypeDepth = 5` deep fails
and records the entry it reached in `deferredWorklist`
(`BytecodeReader.cpp:1100-1107`). The slow path then keeps a deque: it pops
an entry, retries it, and on failure moves it to the back and pushes its
deferred dependencies to the front, but only those not already in the deque
(`addToWorklistFront` skips an entry in `inWorklist`, l. 1411-1414).

For a chain `e0 → e5 → e10 → …` of deferrals, the first pass pushes each
link to the front in turn, so the deque becomes `e_last, e0, e5, e10, …`.
Once `e_last` resolves, `e0` is retried before `e5`, fails on `e5` again,
and goes to the back without moving `e5` forward, because `e5` is already
in the deque. Every later entry does the same, so each pass over the deque
resolves only its last element: n/5 passes of n/5 retries each.

## Proposed fix

When a retried entry fails on a dependency that is already in the
worklist, move that dependency to the front instead of skipping it. A
stack serves: push the failed entry back, then its dependencies on top of
it, so that an entry is retried only once everything it waits on has been
resolved.

## Our workaround

`PINS.md`: `bytecode-deferred-quadratic`. Compile-time evaluation sends its
results to the compiler as bytecode of a flat table of their parts, each
naming the parts it holds by position (`foreign/idr/lib/Eval/Reify.h`), so
no attribute in it is nested more than a few levels deep, whatever the
depth of the value.
