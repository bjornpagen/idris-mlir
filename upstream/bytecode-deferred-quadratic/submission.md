Approach changed: the old patch swapped the deque for a stack with no duplicate check, which fixed the order but grew forever on a cycle; now the pending entries are a path where each waits on the one above and appears at most once, so a chain takes O(n) parses and a cycle is an error.

# Submission

Paste into GitHub on https://github.com/llvm/llvm-project: file the
issue, then open the pull request. Author: Bjorn, as an individual, no
employer. No @mentions. Add `Assisted-by: <tool>` as the last line of the pull request body
(llvm/docs/AIToolPolicy.md).

The pull request is one commit, `llvm.patch` in this directory. The same
file applies to llvm-project main at 7208ba24 (2026-10-08) and to
llvmorg-23.1.2, whose `BytecodeReader.cpp` and test files are identical
to main's, so there is no separate trunk diff. It adds a 154-byte binary
test file: apply it with `git am` or `git apply`, not `patch`. On
squash-and-merge the PR title is the commit subject and the PR body the
commit message. After filing the issue, put its number in the last line of
the PR body.

## Issue title

```
[mlir][bytecode] Reader quadratic in nesting depth, hangs on a cycle
```

## Issue body

````
Reading bytecode, `mlir-opt` takes time quadratic in the nesting depth of
an attribute, and never returns on a file whose attributes refer to each
other in a cycle. Seen with llvmorg-23.1.2; `BytecodeReader.cpp` on main
at 7208ba24 is the same file.

**Deep nesting.** `nested.sh`:

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

```
$ ulimit -s unlimited   # the text parser recurses once per level
$ for n in 8000 16000 32000 64000; do
    sh nested.sh $n > n$n.mlir
    mlir-opt n$n.mlir --emit-bytecode -o n$n.mlirbc
    time mlir-opt n$n.mlirbc --emit-bytecode -o /dev/null
  done
```

Best of three, x86_64 Linux; "text" is the same command on `n$n.mlir`:

| depth  | text    | bytecode |
| ------ | ------- | -------- |
| 8,000  | 0.025 s | 0.243 s  |
| 16,000 | 0.037 s | 1.042 s  |
| 32,000 | 0.064 s | 3.831 s  |
| 64,000 | 0.118 s | 15.908 s |

Expected: linear in the depth, as from text.

**Cycle.** `cycle.mlirbc` is the bytecode of `sh nested.sh 10` with one
index changed, so that the ninth array holds the second instead of the
tenth:

```
$ base64 -d > cycle.mlirbc <<'END'
TUzvUg1NTElSMjMuMS4yAAENAwEDAQMHAyUdAQEdEwsPDw8PDw8PDw8LEwsCUwMDAwUFBQEDBwED
CQEDCwEDDQEDDwEDEQEDEwEDFQEDBwEBFxsDAwUHBBkFAVEZAQEHBAcDAQEGAwEFAQBRCREZDxFi
dWlsdGluAG1vZHVsZQB0ZXN0Lm5lc3RlZAA8c3RkaW4+AAgJAwUBAQ==
END
$ mlir-opt cycle.mlirbc -allow-unregistered-dialect
```

Actual: `mlir-opt` never returns. Expected: an error.

Both come from the deferred worklist in `AttrTypeReader::resolveEntry`.
````

## PR title

```
[mlir][bytecode] Resolve deferred attributes and types in linear time
```

## PR body

````
Reading an attribute nested n deep from bytecode takes time quadratic in
n, and a file whose attributes refer to each other in a cycle makes the
reader loop forever.

A parse that reaches maxAttrTypeDepth stops at the entry it would recurse
into, and AttrTypeReader::resolveEntry resolves that entry before parsing
the first one again. The slow path kept the pending entries in a deque:
a failed entry went to the back, and the entry it deferred to went to the
front unless it was already queued. For a chain e0 -> e5 -> e10 -> ...
the first pass leaves e_last, e0, e5, ...; from then on each entry is
retried before the one it waits on, fails on it again and goes to the
back, so each pass over the deque resolves one entry. In a cycle no entry
ever resolves.

A parse returns at the first entry it defers, so a failed entry waits on
exactly one other. Keep those waits as a path, each entry waiting on the
one above it: the entry the top parse stopped at goes on top, and once it
resolves, the entry below it is parsed again. An entry joins the path at
most once, so a chain of n deferred entries takes O(n) parses. An entry
that waits on one already on the path closes a cycle, and the reader now
fails with "cyclic reference to attribute index: N" (or type) instead of
hanging. deferredWorklist becomes deferredEntry, the one entry a failed
parse can record.

Reading a builtin array nested 32,000 deep goes from 3.8 s to 0.05 s, and
64,000 deep from 15.9 s to 0.07 s; from text it takes 0.06 s and 0.12 s.
Measured on x86_64 Linux at llvmorg-23.1.2, whose BytecodeReader.cpp is
the same as main's, with the file built by clang 18 at -O2, best of three.

op_with_properties_deeply_nested_attr.mlir round-trips a chain of
attributes then types 80 deep. invalid_attr_type_section.mlir reads a
file whose arrays refer to each other in a cycle; like the other files in
invalid/, it is checked-in bytecode, since the writer cannot produce a
cycle: it is a 10-deep array with one index changed.

Fixes #<issue>
````

## Pull request #229910

Pull request #229910 (`[mlir][bytecode] Allow custom encodings for
mutable types`, open and unreviewed on 2026-10-08) rewrites the same slow
path: it wraps the deque loop in a lambda and drains it again for entries
that were answered only with a partial type. It does not change the order
in which entries are retried, so the quadratic and the hang are still
there with it, and this patch is not a review comment on it: send this
pull request against main now. Whichever lands second rebases, and the
rebase is mechanical: the path loop becomes a lambda that resolves the
path from a root, called for the entry being resolved and then for each
partial entry not yet parsed, with `allowPartial=false` on type reads as
#229910 has them.

Once both are in, a self-reference deeper than `maxAttrTypeDepth` (a
mutable type whose body reaches itself through six nested types) defers
to the entry being parsed, because the depth-limited branch of
`DialectReader::readType` looks only at resolved entries, not at
partials. #229910 alone then retries that entry forever; with this patch
it is reported as a cycle. Either way the fix belongs in #229910: the
depth-limited branch should return the partial before deferring. This is
from reading the code, not from a run (`!test.test_rec_alias` needs the
test dialect). If Bjorn wants to raise it there, a review comment:

````
A self-reference deeper than maxAttrTypeDepth seems to bypass the
partial: past the depth limit, DialectReader::readType returns only a
resolved entry (getTypeOrSentinel) and otherwise defers, so for
!test.test_rec_alias<s, tuple<tuple<tuple<tuple<tuple<tuple<!test.test_rec_alias<s>>>>>>>>
the read of s defers to s itself, and the worklist retries s forever.
Should that branch return getPartialType(index) first?
````
