# How to write a lane's part

A part is one file, `parts/U??-<name>.md`, the body of the lane's
dispatch. `assemble.sh` appends the common obligations and the six
binding rules; the part itself holds none of that text. `validate.sh`
checks the sections below by their exact headings, the first lines, the
owned paths, and that no retired mechanism (README "Retired
mechanisms") is named outside `## Delete`. A part never says that the
lane waits for, is blocked on, or runs after another lane or the
coordinator: every lane writes against `contracts.md` from the first
minute.

The worker who receives the dispatch is a capable but literal
implementer with no other context. The part must let it build the
lane's outcome without inventing architecture: every decision is in
`contracts.md` or in `## Fixed decisions`; every path it may write is in
`## Owner / exclusive writes`; every file it must read first is in
`## Read first`, with the line ranges that matter.

```markdown
# Uxx — <outcome-oriented title>

Mandatory findings: F-a-1 F-b-2        (exactly ownership.json's list; "none" when empty)

## Permitted outcome
Numbered, finite, externally observable. Mark each Mandatory or
Optional. Name the consumer adaptations the lane makes.

## Owner / exclusive writes
The paths of ownership.json, each named; what is new, what is deleted.
**Excluded:** the tempting neighbours, by path, and who owns them.

## Read first
contracts.md sections; findings.md ids; the lane's source files with
the line ranges that matter; the MLIR headers or docs under sources/
the lane leans on, by path.

## Fixed decisions
Selected representations, class names, file names, transitions,
invariants. No open alternatives.

## Inputs
The contract declarations the lane consumes (never a sibling's body).

## Outputs
The declarations, files and consumers the lane supplies, by name.

## Implement
At the level of files, classes and callers: what each new unit holds,
which old unit's logic it takes, what changes in the logic, the
failure paths. Where the lane's area becomes several .cpp files, list
them with one line each.

## Delete
Every old path, class, helper, mode and flag that goes, by name. The
only section where a retired mechanism may be named.

## NOT TO DO
Lane-specific: adjacent features, mechanisms, files and shortcuts the
lane must not touch or add, with the owner of each.

## Stop and return
What completes the lane; what to report as a seam without stopping.

## Acceptance
Concrete: input or fixture -> observable property. Source and deletion
conditions compilation does not establish. Which U21/U22 fixtures state
each property.

## Escalate if
Named contract or ownership conflicts with the live source, with the
evidence to report.
```

Voice: the repository's. Short sentences, no em-dashes, no rhetorical
questions. Claims about the code cite `path:line` at 25890d32.
