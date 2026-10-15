# How to write a lane's part

A part is one file, `parts/U??-<name>.md`, the body of the lane's
dispatch. `assemble.sh` appends the common obligations, the owner's
representation-first guideline and the six binding rules; the part holds
none of that text. `validate.sh` checks the sections below by their exact
headings, the owned paths, and that no retired mechanism (swarm.md,
"Retired mechanisms") is named outside `## Delete`. A part never says that
the lane waits for, is blocked on, or runs after another lane or the
coordinator: every lane writes against `contracts.md` from the first
minute.

The worker is a capable but literal implementer with no other context.
The part must let it build the outcome without inventing architecture:
every decision is in `contracts.md` or `## Fixed decisions`; every path it
may write is in `## Owner / exclusive writes`; every file it must read is
in `## Read first`, with the line ranges that matter.

```markdown
# Uxx — <outcome-oriented title>

## Permitted outcome
Numbered, finite, externally observable. Mark each Mandatory or Optional.
Name the consumer adaptations the lane makes.

## Owner / exclusive writes
Every path of ownership.json, each named; what is new, what is deleted.
**Excluded:** the tempting neighbours, by path, and who owns them.

## Read first
contracts.md sections; 0004/0003 sections; the lane's source files with
the line ranges that matter; upstream headers under
.toolchain/build/llvm-project and snapshots under sources/, by path.

## Fixed decisions
Selected representations, class and file names, transitions, invariants.
No open alternatives.

## Inputs
The contract declarations the lane consumes (never a sibling's body).

## Outputs
The declarations, files and consumers the lane supplies, by name.

## Implement
At the level of files, classes and callers: what each unit holds, which
old unit's logic it takes, what changes, the failure paths.

## Delete
Every old path, class, helper, mode and flag that goes, by name. The only
section where a retired mechanism may be named.

## NOT TO DO
Lane-specific: adjacent features, mechanisms, files and shortcuts the lane
must not touch or add, each with its owner.

## Tempting partial solutions
Each with the acceptance case that rejects it.

## Acceptance
Exact conditions: input, then observable outcome; source and deletion
review conditions; what check-units.py or the Idris typecheck shows.

## Stop and return
The deliverable and checks that end the assignment; the missing operands
or ownership conflicts to report without stopping other work.
```
