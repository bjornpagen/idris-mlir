# Handoff (2026-10-09)

Two independent agents, each started locally in Claude Code in a clone of
bjornpagen/idris-mlir at `main`. Paste the prompt under each heading as
the agent's first message. They touch disjoint things: the first works
in a separate clone of llvm-project and only updates `upstream/` status
here; the second owns this repository's toolchain and code.

State, updated 2026-10-09 after agent 2's work landed: the LLVM pin is
llvm main 7208ba24 (`proposals/0003-llvm-trunk.md`), proposal 0002 is
integrated (accepted in part; its qualification is open), and the
toolchain is one recipe for both targets (`tools/bootstrap.sh`, into
`.toolchain/llvm`). No toolchain is built yet with the patches the tree
carries (`upstream/README.md`, "This repository's toolchain"), so
`make build` refuses on either target until `make bootstrap` runs there.
The LLVM submissions are in `upstream/`; their status table says which is
next.

## Agent 1: upstreaming

```
Read upstream/README.md in this repository, all of it, and do what it
says. You are the sending agent it describes. Start with the first row
of its status table marked "send next". Its rules are absolute: I (Bjorn)
approve every post one command at a time, everything ends with
"Assisted-by: Claude Code", you push only to my fork, one submission at
a time, trunk only, the diff applying to current llvm main and
clang-format clean, check-mlir left to LLVM's pre-merge CI. Before
anything else, confirm `gh auth status` and git's user.name/user.email,
and tell me what you found. Do not touch this repository's toolchain or
code; the only files you change here are upstream/README.md's status
table, upstream/NN-*/README.md's "Upstreaming plan" and PINS.md entries,
as its "After a pull request lands" and step 9 say, committed and pushed
to main.
```

## Agent 2: done

Its two phases landed: the trunk cutover (20fcfadb, 1677b8cb) and proposal
0002 (93f5d9c9, 327c2e30, 0451b1b8). What it left open is now the
repository's own: the bootstrap and the suites on both targets at the pin
(proposal 0003, step 5), and 0002's qualification (its README).
