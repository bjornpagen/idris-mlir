Approach changed: the old patch swapped the deque for a stack with no duplicate check, which fixed the order but grew forever on a cycle; now the pending entries are a path where each waits on the one above and appears at most once, so a chain takes O(n) parses and a cycle is an error.

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
At `llvmorg-23.1.2`, `mlir-opt` reads a module whose attribute is a builtin array nested n deep from bytecode in time quadratic in n. Parsing the same module from text is linear in n. A nested constant of this depth is an ordinary value: a computed list of 20,000 elements is one constant, nested 20,000 deep.

## Reproduce

`nested.sh`:

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

The text parser recurses once per level, so writing the bytecode needs a large stack:

```
$ ulimit -s unlimited
$ for n in 500 1000 2000 4000 8000 16000 32000 64000; do
    sh nested.sh $n > n$n.mlir
    mlir-opt n$n.mlir --emit-bytecode -o n$n.mlirbc
    time mlir-opt n$n.mlirbc --emit-bytecode -o /dev/null
  done
```

Best of three runs, x86_64 Linux; the text column runs the same command on `n$n.mlir`.

| depth | from text | from bytecode |
| --- | --- | --- |
| 500 | 0.020 s | 0.017 s |
| 1,000 | 0.020 s | 0.023 s |
| 2,000 | 0.019 s | 0.032 s |
| 4,000 | 0.021 s | 0.071 s |
| 8,000 | 0.025 s | 0.243 s |
| 16,000 | 0.037 s | 1.042 s |
| 32,000 | 0.064 s | 3.831 s |
| 64,000 | 0.118 s | 15.908 s |

From 8,000 on, each doubling of the depth takes four times as long from bytecode. Expected: linear time, as from text.

## Cause

`AttrTypeReader::resolveEntry` (`mlir/lib/Bytecode/Reader/BytecodeReader.cpp`, lines 1371-1459 at `llvmorg-23.1.2`). A parse nested more than `maxAttrTypeDepth = 5` deep records the entry it reaches with `addDeferredParsing` and fails (lines 1100-1107 and 1130-1137). The slow path keeps a deque: it pops an entry, parses it again, and on failure moves it to the back and pushes the entry it deferred to the front, unless that entry is already in the deque (`addToWorklistFront`, lines 1411-1414).

For a chain `e0 -> e5 -> e10 -> ...` of deferrals, the first pass pushes each link to the front in turn, leaving `e_last, e0, e5, e10, ...`. Once `e_last` resolves, `e0` is retried before `e5`, fails on `e5` again, and goes to the back without moving `e5` forward, because `e5` is already in the deque. Every later entry does the same, so each pass over the deque resolves only its last element: n/5 passes of n/5 parses each.

The same loop never ends when entries refer to each other in a cycle, which a malformed file can do: `mlir-opt` hangs on it instead of reporting an error. A pull request with a fix and a test file for both follows.
````

## PR title

```
[mlir][bytecode] Resolve deferred attributes and types in linear time
```

## PR body

````
Reading an attribute nested n deep from bytecode takes time quadratic in
n: 3.8 s for a builtin array nested 32,000 deep and 15.9 s at 64,000,
against 0.06 s and 0.12 s from text. A parse that reaches
maxAttrTypeDepth stops at the entry it would recurse into, and
AttrTypeReader::resolveEntry resolves that entry before parsing the
first one again. The slow path kept the pending entries in a deque: a
failed entry went to the back, and the entry it deferred to the front
unless it was already queued. For a chain e0 -> e5 -> e10 -> ... the
first pass leaves e_last, e0, e5, ...; from then on each entry is
retried before the one it waits on, fails on it again and goes to the
back, so each pass over the deque resolves one entry. Entries that refer
to each other in a cycle never leave the deque, and the reader hangs on
such a file.

A parse returns at the first entry it defers, so a failed entry waits on
exactly one other. The slow path now keeps those waits as a path, a
chain of entries each waiting on the one above it: the entry the top
parse stopped at goes on top, and once it resolves the entry below it is
parsed again. An entry joins the path at most once, so a chain of n
deferred entries takes O(n) parses, and an entry that waits on one
already on the path is a cycle, reported as an error. The deferred
worklist becomes the one deferred entry a failed parse can record.

| depth  | text   | bytecode, before | bytecode, after |
| ------ | ------ | ---------------- | --------------- |
| 500    | 0.02 s | 0.02 s           | 0.02 s          |
| 4,000  | 0.02 s | 0.07 s           | 0.02 s          |
| 32,000 | 0.06 s | 3.83 s           | 0.05 s          |
| 64,000 | 0.12 s | 15.91 s          | 0.07 s          |

op_with_properties_deeply_nested_attr.mlir round-trips a chain of
attributes then types 80 deep, and invalid_attr_type_section.mlir reads
a file whose arrays refer to each other in a cycle.
````

## Patch file

`llvm.patch`

That file is the one commit. Use its diff as-is; it adds a small binary test file (`invalid-attr_type_section-cycle.mlirbc`), so apply it with `git apply` or `git am`, not `patch`. The commit subject is the PR title above; drop the `Subject: [PATCH]` framing on the first line of the file. Base the commit on current llvm-project `main`. The diff was made against `llvmorg-23.1.2`; if it does not apply, rebase that same commit. Pull request #229910 (custom encodings for mutable types), open at the time of writing, rewrites the same slow path; if it lands first, rebase onto it. Do not add a second commit.
