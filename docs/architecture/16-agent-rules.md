# 16. Rules for implementation work and agent fan-out

This spec is written so that work can be split across people or agents
without them coordinating anywhere except through the contract. These rules
bind every contributor, human or agent.

## Before starting

- **AG-READ-1.** Read [00](00-index.md), [01](01-goals.md),
  [02](02-profile.md), [03](03-semantics.md) and [08](08-idr-dialect.md), then
  the documents of your work package. `AGENTS.md` summarizes the working
  rules.
- **AG-SCOPE-1.** A work package is a set of rule identifiers. The package is
  done when every rule in it has its check and its test (`TEST-SPEC-1`) and
  every required suite passes.

## Ownership

- **AG-OWN-1.** Each package may change only the paths it owns:

  | Package | Paths |
  | --- | --- |
  | Frontend and middle end (Idris) | `compiler/`, `tests/compiler/`, `tests/profile/` |
  | Dialect and passes (C++) | `foreign/idr/`, `tests/idr/` |
  | Toolchain and build | `tools/dev.py`, `CMakeLists.txt`, `CMakePresets.json`, `toolchain.lock.json`, `PINS.md`, `docs/cpp-profile.md`, `docs/toolchain.md`, `tests/tooling/`, `tests/mlir/` |
  | End to end | `tests/e2e/` |
  | Spec | `docs/architecture/` (lead only) |

  A package that needs a change outside its paths asks the lead. It does not
  make the change itself.
- **AG-OWN-2.** The frontend package and the dialect package depend on each
  other only through [08](08-idr-dialect.md). Each tests against the contract
  alone:
  - the frontend with `FileCheck` on its `.mlir` output, and
    `idr-check-input` once that exists;
  - the dialect with hand-written `.mlir`.

  Neither waits for the other.

## What no one may do

- **AG-NEVER-1.** Change a contract document (02, 03, 08) without the user's
  approval. Change another spec document without being the lead.
- **AG-NEVER-2.** Invent behaviour the spec does not define. A gap or an
  ambiguity is reported to the lead with the rule identifier and a concrete
  question. The implementation meanwhile rejects the construct with
  `unsupported`.
- **AG-NEVER-3.** Implement a construct outside the current profile version,
  even partially or behind a flag.
- **AG-NEVER-4.** Edit `third_party/Idris2`, move its gitlink, add a
  dependency, add a pinned tool, or change a pin, except as a toolchain
  package change that the spec requires.
- **AG-NEVER-5.** Install anything outside `.toolchain/`, or change global
  compiler installations or shell configuration.
- **AG-NEVER-6.** Build or run anything in a research-only task. Research
  produces documents only.
- **AG-NEVER-7.** Weaken, skip, or delete a test to make a suite pass, or
  report a skipped test as passed.

## Checks and commits

- **AG-CHECK-1.** Before handing work back, run `dev.py check` always, plus
  the suites for what changed ([14-testing](14-testing.md#commands)).
  Report every failure and every skip, with the reason.
- **AG-COMMIT-1.** Each commit message names the rule identifiers it
  implements or changes. Commits stay within one package.
- **AG-COMMIT-2.** Only the lead merges and pushes to `main`. Packages are
  developed on their own branches or worktrees.
