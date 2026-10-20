<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Audits

Findings collected before anything is fixed: what is wrong with the test
suite and its machinery, measured against the owner's two guidelines,
`.claude/skills/testing-by-search` (the contract, the oracle, the search)
and `.claude/skills/representation-first` (the data, not the control
flow). The audit only collects; the decisions come after, from the whole
picture, and bad tests are not spared: the owner prefers deleting a test
that does not work to maintaining it.

## The 2026-10-18 test-suite audit

Taken on the representation wave's first build (arm64 macOS), when
`make test` passed 193 of 542 and `make test-idr` 218 of 368: much of the
suite had never run on the code it describes.

One file per lane, each a verdict for every test directory or fixture in
its scope (keep, rewrite as a property, merge, delete) and the findings
behind it, each citing the guideline section it rests on:

| lane | scope |
| --- | --- |
| `idr-a.md` | `tests/idr/` actions to defunc |
| `idr-b.md` | `tests/idr/` e2e to lower |
| `idr-c.md` | `tests/idr/` names to world |
| `programs.md` | `tests/programs/` |
| `accept-reject.md` | `tests/accept`, `reject`, `compiler`, `registry`, `two-levels` |
| `repo-tests.md` | `tests/spec`, `toolchain`, `upstream`, `determinism`, `bench` |
| `machinery.md` | the runner, `testutils.sh`, `tests/lib`, templates, the acceptance process, the Makefile's test targets |
| `search.md` | the search and its oracles: `Gen`, `Fuzz`, `Sem`, `Prims`, `TwoLevels`, `tests/fuzz`, the googletest boxes, the runtime property programs, `idr-expect` and the pass contracts |
| `gaps.md` | the contracts the compiler promises (AGENTS.md, the passes, the primitives, the refusal rules) that no test states, and the properties and generators that would |

`SUMMARY.md` is the synthesis: the categories across lanes, the full
delete list, the rewrite list, the code bugs the audit found, and the
shape of the suite rebuilt on these principles.

## The 2026-10-19 leak audit

`leaks.md`: the leak classes on 6f774119, each with its reproducer, its
status and its root cause, why the owned stage's verifier let each
through, and the ownership representation proposed to make them
unrepresentable; the reproducers and fixtures it names are in `leaks/`.

## The 2026-10-19 rederivation sweep

`rederived.md`: every place a fact the compiler knew (a source location, a
type, a parent, an analysis) is thrown away and derived again or guessed,
from five read-only sweeps over the fork, the frontend, the dialect, the
passes and the runtime and harness, each with its fix and its lane.
