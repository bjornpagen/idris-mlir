# idris-mlir architecture specification

Status: **draft 2, awaiting review.** Once the user approves it, it governs p0
and v0 (see [roadmap](15-roadmap.md)). Until then nothing in it may be
implemented.

This directory is the normative specification of idris-mlir: a whole-program
compiler for a versioned, strict subset of Idris 2 (the *profile*). It lowers
checked TT through an MLIR dialect of our own (`idr`, C++) and upstream MLIR
dialects to native code. It replaces the former `docs/architecture.md`, which
described the "no C++" state.

## How to read this spec

| Doc | Subject | Contract? |
| --- | --- | --- |
| [01-goals](01-goals.md) | goals, non-goals, principles, settled decisions | |
| [02-profile](02-profile.md) | the Idris subset, per version | **yes** |
| [03-semantics](03-semantics.md) | reference semantics of profile programs | **yes** |
| [04-frontend](04-frontend.md) | what the compiler reads from Idris and how | |
| [05-middle-ir](05-middle-ir.md) | the Idris-side IR (`Core`) and its pass order | |
| [06-elimination](06-elimination.md) | erasure, monomorphisation, the guaranteed eliminations (lambdas, monads, strings) | |
| [07-proved-rewrites](07-proved-rewrites.md) | reserved: rewriting with user-proved equalities | |
| [08-idr-dialect](08-idr-dialect.md) | the `idr` dialect: the Idris ↔ C++ boundary | **yes** |
| [09-optimization](09-optimization.md) | which optimization runs where, and why | |
| [10-lowering](10-lowering.md) | `idr` → upstream dialects → LLVM → object code | |
| [11-toolchain](11-toolchain.md) | pinned toolchains, cpp-starter adoption, layout | |
| [12-driver](12-driver.md) | executables, command lines, artifacts | |
| [13-diagnostics](13-diagnostics.md) | errors, codes, source locations | |
| [14-testing](14-testing.md) | oracles, suites, conformance | |
| [15-roadmap](15-roadmap.md) | p0, v0–v4: scope and exit criteria | |
| [16-agent-rules](16-agent-rules.md) | how implementation work is divided and constrained | |

Read 01, 02, 03 and 08 before any other document. They define what is
compiled, what it means, and the one interface between the two
implementation languages.

## Normative language

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY, and OPTIONAL are to be interpreted as described in BCP 14
(RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

Text marked *Note* or *Rationale* is informative.

## Rule identifiers

Every normative rule has a stable identifier `<DOC>-<AREA>-<n>`, for example
`PROF-TYPE-1`. The prefixes are:

| Prefix | Doc |
| --- | --- |
| `GOAL` | 01 |
| `PROF` | 02 |
| `SEM` | 03 |
| `FE` | 04 |
| `CORE` | 05 |
| `ELIM` | 06 |
| `RW` | 07 |
| `IDR` | 08 |
| `OPT` | 09 |
| `LOW` | 10 |
| `TC` | 11 |
| `DRV` | 12 |
| `DIAG` | 13 |
| `TEST` | 14 |
| `RM` | 15 |
| `AG` | 16 |

Identifiers are never reused or renumbered. A withdrawn rule keeps its
identifier, marked *withdrawn*, with the reason.

Each rule states the first profile version it applies to, as `(v0)`, and how it
is enforced:
- **Check**: the code that enforces it (a function, verifier, or pass).
- **Test**: the tests that show the check works.

A rule whose check or test does not exist yet is marked *planned* with the
version that delivers it. Every `MUST` rule MUST have a check and a test by
the end of that version (`TEST-SPEC-1` enforces this mechanically). No rule may
exist only on paper.

## Precedence and conflicts

- This spec takes precedence over code, tests, and other documentation.
- `AGENTS.md` summarizes working rules and points here. If it disagrees with
  this spec, the spec wins, and the disagreement is a bug in `AGENTS.md`.
- If code disagrees with the spec, either is wrong. Do not resolve it silently:
  fix the code, or propose a spec change.
- `third_party/Idris2` at its pinned gitlink defines the Idris language. This
  spec only selects a subset of it and fixes its meaning where Idris leaves it
  to backends (see [03-semantics](03-semantics.md)).

## Change process

- **Contract documents (02, 03, 08)** change only with the user's explicit
  approval, in a commit whose message names the changed rule identifiers.
- **Other documents** may change in the same commit as the code they
  describe, if no contract rule changes and the commit names the changed
  rule identifiers. Adding a rule to a contract document is a contract
  change.
- A new profile version is a contract change to 02 (and usually 03 and 08).
  It is released only when its exit criteria in [15-roadmap](15-roadmap.md)
  are met.

## Glossary

- **Profile.** The strict, versioned subset of Idris 2 that this compiler
  accepts ([02-profile](02-profile.md)). A program is *in profile vN* if it
  satisfies every rule of vN.
- **Reference semantics.** The meaning of a profile program, defined in
  [03-semantics](03-semantics.md) by reference to the pinned Idris 2.
- **Checked TT.** Idris 2's core terms after elaboration and type checking,
  with the definition context (`Defs`). This is the compiler's only input.
- **Runtime position.** A binder, argument, or constructor field whose
  quantity is not 0.
- **Runtime type.** A type that a value in a runtime position may have in the
  current profile version (`PROF-TYPE-*`).
- **Erased.** Absent at runtime because its quantity is 0. Erased does not
  mean constant, and erased values can still carry facts the compiler uses.
- **Root.** The definition compilation starts from: `main` in the root module.
- **Fact.** A statically known property from checked TT (a quantity,
  constructor set, coverage, totality, or type equality) that an optimization
  may use.
- **Contract.** The `idr` dialect as specified in
  [08-idr-dialect](08-idr-dialect.md). It is the only interface between the
  Idris code and the C++ code.
- **Frontend.** The Idris code that reads checked TT (`IdrisMLIR.Frontend.*`).
- **Middle end.** The Idris code that transforms `Core`.

## Open questions

Settled in draft 2:
- **Multiple modules.** `main : IO ()` programs compile through Idris's
  whole-program callback (`-o`), which handles imports.
- **IO surface.** Stock `Builtin` and `PrimIO` plus our own small module,
  `IdrisMLIR.IO`, which is the only place `%foreign` is allowed.
- **Prelude.** Deferred like GC. The Prelude's dependency modules come first,
  one layer at a time, each fully tested
  ([15-roadmap](15-roadmap.md)).

Still open, and blocking nothing before it is needed:
1. **Later:** the surface syntax of proved rewrites
   ([07-proved-rewrites](07-proved-rewrites.md)).
