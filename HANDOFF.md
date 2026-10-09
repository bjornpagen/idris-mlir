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
needed locally. Proposal 0002 (`proposals/0002-representation-cutover/`)
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

## Agent 2: toolchain, then proposal 0002

```
You work in this repository (bjornpagen/idris-mlir). Read AGENTS.md
first; it binds you. Two phases, in order.

Phase 1: the toolchain. The pinned LLVM in .toolchain is stale because
upstream/*/llvm.patch changed. Run `tools/bootstrap.sh llvm` (hours; it
needs about 13 GB free under .toolchain and resumes in its build
directory if interrupted). Then `make build`, `make check`, `make test`,
`make test-idr`, `make test-mlir-tools`. Every one must pass. A failure
is a real failure: find the cause. If it comes from a changed
upstream/*/llvm.patch (the forward-dataflow one changes DataFlowSolver's
layout; the remove-dead-values one changes what idr-dead-values sees;
the inline one changes which dialect allowSingleBlockOptimization asks),
fix our code, or report the patch's problem to me; do not edit a patch
on your own, since the same change is being sent to LLVM
(upstream/README.md). Commit what you change and push main.

Phase 2: proposal 0002, the representation cutover. You are its
coordinator: proposals/0002-representation-cutover/orchestrator.md is
your prompt; follow it exactly, starting with its reading list. I say
"launch" now. HEAD is past ee4ce8e, so do orchestrator step 1 in full
(diff every owned path, re-read the cited anchors, fix the packet
through contracts.md, rerun validate.sh) before dispatching. Notes that
postdate the packet:
- upstream/ directories are numbered now (upstream/NN-<bug>/); the
  packet's paths were updated. tests/upstream/<bug>/ keep the bug name
  without the number. upstream/README.md is the procedure for anything
  under upstream/, and its rules about sending to LLVM are not yours:
  U01 may change patches and READMEs here, but nothing is sent.
- U01 touches upstream/06, 11 and 12. 06 is also a pending LLVM
  submission; if U01 changes 06's llvm.patch in substance, record it in
  06's README so the sending agent sees it, and tell me.
- Dispatch all 23 lanes at once as Agent subagents, each with the full
  text of its dispatch/U??-*.md. If you cannot run 23 at once, say how
  many you can and stop for my answer; do not serialize quietly.
- Phase 1's toolchain is the one the packet's integration needs; the
  packet's own toolchain rebuild (U01's patches) is its integration
  tail, as work-units.md says.
Report at the end per orchestrator step 8, with every NotRun named.
Commit only at integration, per the packet's commit policy, and push
main.
```
