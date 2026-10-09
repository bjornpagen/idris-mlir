# Handoff (2026-10-09)

Two independent agents, each started locally in Claude Code in a clone of
bjornpagen/idris-mlir at `main`. Paste the prompt under each heading as
the agent's first message. They touch disjoint things: the first works
in a separate clone of llvm-project and only updates `upstream/` status
here; the second owns this repository's toolchain and code.

State when written: `main` is clean and pushed. The eight LLVM
submissions (`upstream/01-*` to `08-*`) are final and tested on llvm
main at 7208ba24 (`upstream/README.md`). This repository's pinned
toolchain is stale: `upstream/*/llvm.patch` changed after
`.toolchain/llvm-musl` was built, so `tools/verify-pins.sh llvm` fails and
`make build` refuses until `tools/bootstrap.sh llvm` rebuilds it. A
rebuild was started in the cloud and stopped in stage 2; nothing of it is
needed locally. The pin moves to llvm main 7208ba24 first
(`proposals/0003-llvm-trunk.md`), so the 23.1.2 toolchain is never
rebuilt. Proposal 0002 (`proposals/0002-representation-cutover/`)
is validated (`validate.sh`: 23 dispatches, 0 failures) and not launched.

## Agent 1: upstreaming

```
Read upstream/README.md in this repository, all of it, and do what it
says. You are the sending agent it describes. Start with the first row
of its status table marked "send next". Its rules are absolute: I (Bjorn)
approve every post one command at a time, everything ends with
"Assisted-by: Claude Code", you push only to my fork, one submission at
a time, trunk only, check-mlir green on current llvm main first. Before
anything else, confirm `gh auth status` and git's user.name/user.email,
and tell me what you found. Do not touch this repository's toolchain or
code; the only files you change here are upstream/README.md's status
table, upstream/NN-*/README.md's "Upstreaming plan" and PINS.md entries,
as its "After a pull request lands" and step 9 say, committed and pushed
to main.
```

## Agent 2: LLVM trunk cutover, then proposal 0002

```
You work in this repository (bjornpagen/idris-mlir). Read AGENTS.md
first; it binds you. Two phases, in order. Commit and push main after
each green step, and force the session branch to main if there is one.

Phase 1: the LLVM trunk cutover. Read proposals/0003-llvm-trunk.md; it
is decided, and its "The cutover, in order" is your task list, all of
it, as a hard cutover: the pin moves from llvmorg-23.1.2 to llvm main
7208ba24ca2894729cd394475a00d2a7b605e642, every patch, pin and
workaround that exists only because 23.1.2 lacked something on main
goes in the same change, and the trunk mechanisms that replace ours are
adopted (composite-fixed-point-pass with on-convergence-failure for
idr-simplify's fixpoint loop first). Rules:
- tools/bootstrap.sh learns an untagged pin (it clones by tag today);
  `tools/bootstrap.sh llvm` takes hours and about 13 GB under .toolchain,
  and resumes in its build directory if interrupted.
- The upstream/NN-*/ patches are being sent to LLVM by another agent
  (upstream/README.md). Their trunk diffs are already tested on
  7208ba24; make each llvm.patch the trunk diff as 0003 says, but do not
  change what a patch does. If one breaks our build or tests, report it
  to me with the evidence instead of editing it.
- fast_float 8.3.1 and snmalloc 0.7.6 are already pinned; the runtime is
  rebuilt with them here.
- Done when `make build`, `make check`, `make test`, `make test-idr` and
  `make test-mlir-tools` all pass on the new pin, PINS.md and
  upstream/README.md say what was retired and why, and findings/ lists
  the trunk mechanisms you checked and what was adopted. A failure is a
  real failure: find its cause.
- When phase 1 is green and pushed, hand the two queued clang bugs,
  upstream/11-clang-module-layout-forward-declaration and
  upstream/12-clang-module-predeclared-new, to the bug-filing agent.
  First run their tests/upstream/<bug>/ checks on the new pin. If a bug
  is fixed on trunk, retire it as 0003 says and say so. If it still
  reproduces, record the result in its README's "Upstreaming plan".
  Then find the local Claude Code session named "Bug filing assistance"
  with ListAgents and send it one message with SendMessage, standing on
  its own: the commit you pushed, which of 11 and 12 still reproduce on
  llvm main 7208ba24 and with what error, the exact commands to
  reproduce each from a clean clone of this repository, and the task:
  reduce each (cvise or by hand, against llvm main as the README plans),
  then prepare it for filing under upstream/README.md's rules, with
  Bjorn approving every post. Do not wait for its answer; go on to
  phase 2.

Phase 2: proposal 0002, the representation cutover, on the new base.
You are its coordinator: proposals/0002-representation-cutover/
orchestrator.md is your prompt; follow it exactly, starting with its
reading list. I say "launch" now. HEAD is past ee4ce8e and the pin has
moved, so do orchestrator step 1 in full (diff every owned path, re-read
the cited anchors, fix the packet through contracts.md for anything
phase 1 changed or retired, rerun validate.sh) before dispatching.
Notes that postdate the packet:
- upstream/ directories are numbered (upstream/NN-<bug>/);
  tests/upstream/<bug>/ keep the bug name without the number.
  upstream/README.md is the procedure for anything under upstream/; its
  rules about sending to LLVM are not yours: nothing is sent.
- U01 touches upstream/06, 11 and 12, and phase 1 may already have
  retired 11 or 12. 06 is a pending LLVM submission: if U01 changes its
  llvm.patch in substance, record that in 06's README and tell me.
- U01's toolchain rebuild is the packet's integration tail, as
  work-units.md says, on the trunk pin.
- Dispatch all 23 lanes at once as Agent subagents, each with the full
  text of its dispatch/U??-*.md. If you cannot run 23 at once, say how
  many you can and stop for my answer; do not serialize quietly.
Report at the end per orchestrator step 8, with every NotRun named.
Commit only at integration, per the packet's commit policy, and push
main.
```
