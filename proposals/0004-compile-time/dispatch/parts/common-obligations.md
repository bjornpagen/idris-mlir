## Common obligations

These bind every lane, the same text in every dispatch.

**The engagement.** One checkout, `/Users/bjorn/Documents/idris-mlir`, on
`main`. No branches, no worktrees, no stash, and no git command that writes:
you never run `git add`, `commit`, `checkout`, `restore`, `reset`, `stash`
or `push`; the coordinator commits. Eighteen other lanes edit their own
files in the same tree at the same time. Never edit, revert, reformat or
"fix" a file outside your exclusive writes, even if it looks broken: report
it. Compatibility is owed to nothing the packet replaces (a hard cutover);
real user data does not exist here.

**What decides.** AGENTS.md binds you. `proposals/0004-compile-time/README.md`
(the design, decisions D1 to D48) and `proposals/0003-typed-apl/README.md`
(the array design) are the architecture; `contracts.md` in this folder
fixes every declaration lanes share, by name and shape. Where your lane
body and a contract disagree, the contract wins and you report the
disagreement. You implement against the contract text, never against a
sibling's file: a sibling may not have written it yet, and that is no
reason to wait.

**Two project rules that override convenience.**
- Acceptance is a property of the program, never of the optimizer
  (AGENTS.md). No pass you write refuses a program because of a count, a
  round, a fixpoint or a budget; a budget only stops optimizing. The only
  refusals are the frontend's, naming an unbounded construct, and a broken
  invariant is an internal error.
- Representation first (the owner's guideline, appended below). A new case
  changes the data, the types and the invariants until it is no longer
  special or no longer expressible. You never answer it with a flag, an
  option, a toggle, a fallback, a second code path, a guard that validates
  and discards, a fact in a discardable attribute, or a name made from a
  counter.

**Numbers.** Every number you write (a size, a bound, a budget, a bin) cites
the packet or 0004/0003 decision that fixes it, or a measurement. A number
with no authority is not written; report it as a missing decision.

**Verification on this machine.** This machine is typecheck-only and you
never build LLVM, MLIR or the compiler: never run `make build`, `make
test*`, `make bootstrap`, `make typecheck`, `make check`, `ninja`, `cmake`,
or `tools/bootstrap.sh`. The coordinator runs `make typecheck` and `make
check` at integration. You may run, as often as useful:
- C++: `python3 proposals/0004-compile-time/check-units.py <your .cpp
  files>` (syntax-only, the dev warnings as errors, safe concurrently). A
  failure caused by another lane's header or ODS that does not exist yet is
  expected; check against the contract and report it, do not work around
  it. A new .cpp file is not in the build until the coordinator adds it;
  the script says so.
- Idris: typecheck with a private build directory so lanes never share
  one: `cd compiler && IDRIS2_PREFIX="$PWD/../.toolchain/idris2"
  IDRIS2_PACKAGE_PATH="$(IDRIS2_PREFIX="$PWD/../build/idris2-host"
  ../.toolchain/idris2/bin/idris2 --libdir)"
  ../.toolchain/idris2/bin/idris2 --build-dir /tmp/<your lane id>-build
  --typecheck idris-mlir.ipkg` (the lane that owns `libs/` uses the same
  form on its packages).
- Reading anything, anywhere, including `.toolchain/build/llvm-project` and
  `sources/`.

**Tests.** Tests check behaviour, never op sequences, SSA names, clone
numbers or function order (AGENTS.md). Nothing here can run a test. A test
or fixture you change or write states the property it checks; where its
expected transcript cannot be known without running, write
`NEEDS-ACCEPTANCE: <what to check>` as the first line of the file your
lane's handoff lists instead of inventing output, and list it in your
handoff for the owner's machine.

**Voice.** The repository's: short sentences, no em-dashes; comments say
why the code is as it is now and never cite documents, decisions, lanes or
rule numbers.

**Handoff.** When your permitted outcome is done, return exactly: changed
paths, each mapped to an obligation; the contract declarations you
supplied; the consumer adaptations you made; checks actually run, with
their output's last lines, or NotRun; every `NEEDS-ACCEPTANCE` file; every
unresolved seam (file, what is missing, which contract). Then stop.

**Escalation.** If a contract or an ownership boundary conflicts with the
live source, report the exact evidence (path, line, what the contract
says, what the code needs) and the contract change you propose, and keep
working on everything else. Never add a shim, weaken an invariant, widen
your writes or choose another architecture.
