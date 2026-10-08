# [mlir] Reading deeply nested attributes from bytecode takes quadratic time

At `llvmorg-23.1.2`, `mlir-opt` reads a module whose attribute is a builtin
array nested n deep from bytecode in time quadratic in n, while it parses
the same module from text in linear time. The bytecode reader stops a
parse that is nested more than 5 deep at the entry it would recurse into,
and resolves that entry before parsing again; the queue it keeps those
entries in retries each one before the entry it waits on. The same queue
never empties when entries refer to each other in a cycle: the reader
hangs on such a file.

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
$ for n in 500 1000 2000 4000 8000 16000 32000 64000; do
    sh nested.sh $n > n$n.mlir
    mlir-opt n$n.mlir --emit-bytecode -o n$n.mlirbc
    time mlir-opt n$n.mlirbc --emit-bytecode -o /dev/null
  done
```

Best of three runs on a shared 4-core x86_64 Linux machine. Both
`mlir-opt` builds link the pinned toolchain's static libraries with
`BytecodeReader.cpp` compiled the same way (clang 18, `-O2`), once as
pinned and once with `llvm.patch`; "text" is the pinned build reading
`n$n.mlir` with the same flags.

| depth | text | bytecode, pinned | bytecode, patched |
| --- | --- | --- | --- |
| 500 | 0.020 s | 0.017 s | 0.015 s |
| 1,000 | 0.020 s | 0.023 s | 0.015 s |
| 2,000 | 0.019 s | 0.032 s | 0.015 s |
| 4,000 | 0.021 s | 0.071 s | 0.017 s |
| 8,000 | 0.025 s | 0.243 s | 0.020 s |
| 16,000 | 0.037 s | 1.042 s | 0.032 s |
| 32,000 | 0.064 s | 3.831 s | 0.045 s |
| 64,000 | 0.118 s | 15.908 s | 0.066 s |

From 8,000 deep on, each doubling of the depth takes four times as long
from the pinned reader. The patched reader prints the 32,000-deep module
back exactly as the text parser does.

A compiler that evaluates code at compile time meets such values as a
matter of course: a computed list of 20,000 elements is a constant nested
20,000 deep.

The cycle: in the bytecode of `sh nested.sh 10 | mlir-opt - --emit-bytecode`,
the attribute section holds arrays `1 3 <2i+1>`, each of the one entry
`i`, from `1 3 7` to `1 3 23`, then the empty `1 1`. Changing that `23` to
`7` makes entry 10 hold entry 3 instead of entry 11. The pinned `mlir-opt` never returns; the patched one
fails with `cyclic reference to attribute index: 8`. The patch carries
this file as `invalid-attr_type_section-cycle.mlirbc`.

## Cause

`AttrTypeReader::resolveEntry` (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp:1371-1459`).
`DialectReader::readAttribute` and `readType`, nested more than
`maxAttrTypeDepth = 5` deep, record the entry they reach with
`addDeferredParsing` and fail (l. 1100-1107, 1130-1137); every parser
returns at its first failure, so a failed parse records one entry. The
slow path then keeps a deque: it pops an entry, parses it again, and on
failure moves it to the back and pushes the entry it deferred to the
front, unless that one is already in the deque (`addToWorklistFront`,
l. 1411-1414).

For a chain `e0 → e5 → e10 → …` of deferrals, the first pass pushes each
link to the front in turn, so the deque becomes `e_last, e0, e5, e10, …`.
Once `e_last` resolves, `e0` is retried before `e5`, fails on `e5` again,
and goes to the back without moving `e5` forward, because `e5` is already
in the deque. Every later entry does the same, so each pass over the deque
resolves only its last element: n/5 passes of n/5 parses each. For a
cycle, no entry ever resolves, and the deque turns forever.

## Proposed fix

Keep what the failed parses wait on as what it is: a chain. Each failed
entry waits on exactly one entry, so the pending entries form a path,
each waiting on the one above it. The entry a parse stopped at goes on
top; when the top resolves, it leaves and the entry below it is parsed
again. An entry is parsed again only once what it waits on is resolved,
and joins the path at most once, so a chain takes a number of parses
linear in its length; an entry that would join the path twice is a cycle,
and an error.

## Our workaround

`PINS.md`: `bytecode-deferred-quadratic`. The pinned reader carries the
patch below; nothing in our code stands in for it. Compile-time evaluation
still sends a call's results as a flat table of their parts
(`foreign/idr/lib/Eval/Encoding.cppm`). That table is not this bug's
workaround: bytecode writes an `idr.con` by its assembly, which repeats a
shared part at every use, so the table is what keeps a shared value the
size of its distinct parts. A chain, which shares nothing, is linear in
the patched reader without the table.

## Patch

`llvm.patch` implements the proposed fix. `resolveEntry`'s slow path keeps
a `SetVector` path of entries, each waiting on the one above it, and
reports an entry already on the path as `cyclic reference to attribute
index: N` (or type). `deferredWorklist`, a vector, becomes
`deferredEntry`, an optional pair: a failed parse records one entry, and
the type now says so; the attribute and type callbacks that fall through
restore it as they restored the vector's size. Tests, in the upstream
files for each: `op_with_properties_deeply_nested_attr.mlir` round-trips
a chain of arrays then tuple types 80 deep, and
`invalid/invalid_attr_type_section.mlir` reads the cyclic file above.

The same file is the pull request: `BytecodeReader.cpp` and both test
files are identical on llvm-project main at 7208ba24 (2026-10-08), and
the patch applies there and to the pin.

Checked here: the patch applies to the pinned tree and to main; the
patched file compiles against main's headers and is clang-format clean on
the changed lines; with the patched reader linked into the pinned
toolchain (assertions on), both lit cases and the file's existing
`INDEX` and `TRAILING_DATA` cases pass (the round trip with
`--allow-unregistered-dialect`, as this build has no test dialect), the
cycle case times out with the pinned reader, and the pinned and patched
readers print the same module for random nested attribute and type
modules. `tests/upstream/bytecode-deferred-quadratic` checks the scaling.

Not changed by the patch: an attribute whose many elements are each
nested deeper than 5 (an array of k elements nested 10 deep) still reads
in time quadratic in k, 2.5 s at k = 16,000 before and after. Each
element defers once, and each deferral restarts the parse of the array
from its first element; a parse that resumes where it stopped would need
`DialectBytecodeReader` parsers that can be suspended, a different
change.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (each directory's `pull-request.diff`, else its
`llvm.patch`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

Then, with this patch's `BytecodeReader.cpp` change alone reverted:
`Bytecode/invalid/invalid_attr_type_section.mlir` does not finish (the
`CYCLE` case loops; the run was stopped by hand), and with the change
back it passes. `op_with_properties_deeply_nested_attr.mlir` passes both
ways: its 80-deep chain checks that the new path reads such input
correctly, and is too small to show the time; the time is what the
issue's `nested.sh` table measures.

## Upstreaming plan

Status: file upstream. Not fixed on main at 7208ba24, and no issue or
pull request reports it.

- Where: a GitHub issue and a pull request to llvm/llvm-project (MLIR
  bytecode). The paste is `submission.md` in this directory: the issue
  holds the timing table and the cycle file, and the pull request is one
  commit, `llvm.patch`, titled
  `[mlir][bytecode] Resolve deferred attributes and types in linear time`.
- Upstream test: the `deeply_nested_chain` case of
  `op_with_properties_deeply_nested_attr.mlir` and the `CYCLE` case of
  `invalid/invalid_attr_type_section.mlir`; the time itself is measured
  by `nested.sh`, quoted in the issue.
- Open upstream: pull request #229910 (custom encodings for mutable
  types) rewrites the same loop without changing its order, so it fixes
  neither symptom; this goes to main on its own, and whichever lands
  second rebases (`submission.md` says how, and what #229910 should do
  for a self-reference past the depth limit).
