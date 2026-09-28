# Snapshot: MLton pass sources

- **Upstream:** `MLton/mlton` on GitHub (the project site `mlton.org` is dead: no
  connection, HTTP 000).
- **Revision:** `master` at `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37`.
- **Fetched:** 2026-09-26, from
  `https://raw.githubusercontent.com/MLton/mlton/aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37/<path>`.
- **Paths:** relative to the repository root (so `mlton/ssa/contify.fun`).
- **Files:** 16.
- **Licence:** MLton license (HPND-style) (verify).
- **Threads:** D, G.

**What is here.**
- `mlton/closure-convert/`: `abstract-value.fun`, `closure-convert.fun`,
  `closure-convert.sig`, `globalize.fun`, `lambda-free.fun`.
- `mlton/ssa/`: `contify.fun`, `useless.fun`, `remove-unused.fun`, `inline.fun`,
  `ssa-tree.fun`, `ssa2.fun`.
- `mlton/backend/`: `ssa2-to-rssa.fun`, `rssa.fun`, `packed-representation.fun`,
  `representation.sig`, `machine.fun`.

The manifest asked for the selected pass sources: closure conversion, the SSA passes
contify, useless and remove-unused, and the RSSA representation and layout.

**Correction.** RSSA lives under `mlton/backend/` (`ssa2-to-rssa.fun`, `rssa.fun`,
`packed-representation.fun`), not in a `mlton/rssa/` directory.
