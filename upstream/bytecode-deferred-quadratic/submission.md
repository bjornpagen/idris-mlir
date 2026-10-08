# Submission

Paste into GitHub on https://github.com/llvm/llvm-project. File a new issue, then a pull request. LLVM's Bugzilla is the wrong tracker.

Author: Bjorn, as an individual, outside any employer.

The pull request is one commit. Its diff is `llvm.patch` in this directory. On squash-and-merge, the commit subject is the PR title and the commit message is the PR body. Do not add an Assisted-by trailer. Do not @mention anyone.

Copy each fenced block below without its surrounding fence. After the issue exists, append `Fixes #<number>` as the last line of the PR body, with that issue's number.

## Issue title

```
[mlir] Reading deeply nested attributes from bytecode takes quadratic time
```

## Issue body

````
At `llvmorg-23.1.2`, `mlir-opt` reads a module whose attribute is a builtin array nested n deep from bytecode in time quadratic in n. Parsing the same module from text is linear in n. The bytecode reader defers an attribute nested more than 5 deep onto a worklist so that it does not recurse, and that worklist then resolves one level of deferral per pass over itself.

The reader must be linear in the nesting depth. A nested constant of this depth is an ordinary value: a computed list of 20,000 elements is one constant, nested 20,000 deep, and the text parser already reads it in linear time.

## Reproduce

Save this as `nested.sh`:

```sh
#!/bin/sh
# nested.sh DEPTH: a module whose one attribute is an array nested DEPTH
# deep, on standard output.
depth=${1:?usage: nested.sh DEPTH}
awk -v n="$depth" 'BEGIN {
  printf "module attributes {test.nested = "
  for (i = 0; i < n; i++) printf "["
  for (i = 0; i < n; i++) printf "]"
  printf "} {\n}\n"
}'
```

`sh nested.sh N > nested.mlir` writes

```mlir
module attributes {test.nested = [[[[ ... ]]]]} {
}
```

with the array nested N deep. The text parser recurses once per level, so converting that module to bytecode needs a large stack.

```
$ ulimit -s unlimited
$ for n in 8000 16000 32000; do
    sh nested.sh $n > n$n.mlir
    mlir-opt n$n.mlir --emit-bytecode -o n$n.mlirbc
    time mlir-opt n$n.mlirbc --emit-bytecode -o /dev/null
  done
```

The text column is `mlir-opt` reading `n$n.mlir`. The bytecode column is the timed command above.

| depth | read from bytecode | read from text |
| --- | --- | --- |
| 8,000 | 0.36 s | 0.09 s |
| 16,000 | 1.12 s | 0.14 s |
| 32,000 | 4.55 s | 0.18 s |

Each doubling of the depth takes four times as long from bytecode. Expected: linear time, as from text.

## Cause

`AttrTypeReader::resolveEntry` (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp`, lines 1370-1464 at `llvmorg-23.1.2`). Reading an entry nested more than `maxAttrTypeDepth = 5` deep fails and records the entry it reached in `deferredWorklist` (lines 1100-1107). The slow path then keeps a deque: it pops an entry, retries it, and on failure moves it to the back and pushes its deferred dependencies to the front, but only those not already in the deque (`addToWorklistFront` skips an entry already in `inWorklist`, lines 1411-1414).

For a chain `e0 → e5 → e10 → …` of deferrals, the first pass pushes each link to the front in turn, so the deque becomes `e_last, e0, e5, e10, …`. Once `e_last` resolves, `e0` is retried before `e5`, fails on `e5` again, and goes to the back without moving `e5` forward, because `e5` is already in the deque. Every later entry does the same, so each pass over the deque resolves only its last element: n/5 passes of n/5 retries each.

## Proposed fix

When a retried entry fails on a dependency that is already in the worklist, move that dependency to the front. A stack does this: the failed entry stays where it is, and the entries it deferred are pushed on top of it, so an entry is retried only once everything it waits on has been resolved. A chain of n deferrals then resolves in one pass down and one back up.

A pull request follows, with a round-trip of an attribute nested 300 deep (`mlir/test/Bytecode/deeply_nested_chain.mlir`).

Filed by Bjorn as an individual, outside any employer.
````

## PR title

```
[mlir][bytecode] Resolve deferred attribute entries in linear time
```

## PR body

````
Reading an attribute nested n deep from bytecode takes time quadratic in
n (4.5 s for a builtin array 32,000 deep, against 0.18 s from text). The
reader must be linear in that depth: parsing the same module from text
already is, and a nested constant of this size is an ordinary value, a
computed list of tens of thousands of elements. Retrying each deferred
entry before the dependency it failed on takes a pass over the chain per
deferred entry, which is the wrong bound.

An entry nested more than maxAttrTypeDepth deep is deferred, and
AttrTypeReader::resolveEntry's slow path resolved deferrals from a deque:
a failed entry went to the back and its dependencies to the front, unless
already in the deque. For a chain e0 -> e5 -> e10 -> ... of deferrals the
first pass leaves the deque as e_last, e0, e5, e10, ...; once e_last
resolves, e0 is retried before e5, fails on e5 again and goes to the back
without moving e5 forward, and so does every later entry: each pass over
the deque resolves only its last element, n/5 passes of n/5 retries.

The slow path is now a stack. A failed entry stays where it is, with the
entries it deferred pushed on top of it, so it is retried only once
everything it waits on has been resolved, and each retry reaches past
them. A chain of n deferrals takes one pass down and one back up. An
entry pushed again after it was resolved reads at once.

Test: deeply_nested_chain.mlir round-trips an attribute nested 300 deep.
````

## Patch file

`llvm.patch`

That file is the one commit. Use its diff as-is. The commit subject is the PR title above; drop the `Subject: [PATCH]` framing on the first line of the file. Base the commit on current llvm-project `main`. The diff was made against `llvmorg-23.1.2`; if it does not apply, rebase that same commit. Do not add a second commit.
