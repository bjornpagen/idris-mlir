# Lane L01 (effects-ops): the effect tree and its one source

**Exclusive write:** `compiler/spec/IdrisMLIR/Spec/Effects/`,
`foreign/idr/include/idr/IR/Effects/`, `foreign/idr/lib/IR/Effects.cpp`.

**Read deeply:** P0 §5.1 whole; in §2 the rulings D9, D13, D14, D20 to
D23, D27 to D29, D92, D102, D103; in §3 C2 (as amended by D92), C3, C72,
C73, C151, C152. Your verification report `audits/p0/verify/L01-effects-ops.md`
in full (its op table is the declaration every op lane copies). The
audits: 02 whole; 03 (effects parts); `design/effects.md` §1, §2;
`design/effect-vocabulary.md` whole; `design/typed-effects.md`;
`design/egraph-full/effects.md`; wave1 §5.2; synthesis A (effects).
Code: every `Idr*Ops.td`, `IdrInterfaces.td`, `IdrBase.td`'s traits,
`lib/IR/Effects.cpp`, the runtime function each IO and runtime op calls
(`runtime/Io/`, `runtime/Rc/`, `runtime/Strings/`, `runtime/Big/`);
upstream `mlir/include/mlir/Interfaces/SideEffectInterfaces.{h,td}`.

**Contract:** P0 §5.1 is canonical: the tree (D27; AGENTS.md's resource
tree), the declaration forms, the typed rules, the names (D28) and atoms
(D29), "building a value acquires nothing before counting" (C3), and the
one query API every reader asks.

**End state:** `Spec.Effects` declares the resource tree, the declaration
forms (static, typed rules, recursive, runs unknown code, definition),
the typed rules by which effects follow from types and consumption, the
atoms of a function's summary, and what LLVM is told for each atom. The
C++ under `include/idr/IR/Effects/` is the `consteval` effect set per op
class and the one query API, implementing MLIR's
`MemoryEffectOpInterface` from the generated tables. Nothing else names a
resource or reads effects its own way.

**Recipe:**
- Write `Spec.Effects` in the subset both hosts compile, with the tree's
  shape and every rule's invariants in its types.
- Write the C++ query API and the concepts over it; replace
  `lib/IR/Effects.cpp`'s hand logic with it.
- Encode consumption: a quantity-1 operand consumed is `Read` with
  `Free` on its count; an exclusive drop reads no count; `Allocate` on
  `identity` for a linear or owned result; `Allocate` on `heap` only at
  the cell's allocation (C3).
- Encode C152: before counting an element read is `Read` on contents
  only. Encode D21: the heap is a sibling of the crash; crash, `exit` and
  output are ordered among themselves.
- Each op lane declares its own ops' effects through your forms, copying
  your report's table; you write the forms, never their ops.

**Delete:** `PerformsIO`, `ObservableIO`, `MayCrashOpInterface`,
`ReferenceResource`, `NoReturn`, `TakesReference`, `BuildsValue`, the
double IO writes of crashes and `may_loop`, the root resource on 51 ops,
the world (D20); every C++ reader of them in your files.

**QTT:** consumption effects follow from a quantity-1 operand's type,
never from a flag; an exclusive value's drop reads no count (D10).

**NOT TO DO:** rows, their derivation, their verifier (L02); LLVM
attributes (L21); another lane's op declarations; a resource beyond the
tree.

**Acceptance:** INT finds every op's effects coming from the one source,
`tests/runtime-effects` (L19) passing, and the program suite unchanged
except where a ruling changes what a run shows.

**Stop and return:** when `Spec.Effects`, the query API and the deletions
are written and your handoff is sent.

## Common obligations (every lane)

**What this swarm is.** The P0 cutover itself: the implementation of
`proposals/0000-mlir-native.md`, written whole by twenty-one owned lanes
at once and an integration lane, in place, on `main`.
It is one change (D56: "we will only build when this entire cutover is
fully done"): no lane builds, typechecks or runs its part; the
integration lane (INT) builds, runs and qualifies the whole on the four
targets and routes every failure back to the lane that owns it. It is a
hard cutover (D6, AGENTS.md): the new form replaces the old in the same
change, with no shim, alias, re-export, dual path, fallback, flag or
"remove later", and the dead code, tests and comments it leaves are
deleted.

**Read first, in full, before any edit:**
1. `.claude/skills/representation-first/SKILL.md` (the lens every change
   is judged by), and `.claude/skills/testing-by-search/SKILL.md` before
   touching a test.
2. `AGENTS.md` (the rules; the owner's dated rulings are quoted there).
3. `proposals/0000-mlir-native.md`, the whole document: §2 holds the
   owner's rulings D1 to D109, which bind you; §3 the coordinator's
   decisions C1 to C157, which bind you unless you show the coordinator a
   contradiction; §5 the target by area, the canonical contract every
   lane writes against; §6 what goes; §7 the order.
4. Your verification report, `audits/p0/verify/LNN-*.md` (named in your
   lane): its §2 (boundaries, provenance, seams) and §5 (work units) are
   the drafted recipe for your area, written before the rulings after
   it; where a later ruling or decision differs, the later one governs.
5. The design documents your lane names, then the code you own and the
   code that consumes it.

**The engagement contract.**
- Checkout `/Users/bjorn/Documents/idris-mlir`, branch `main` (the owner, 2026-10-21: "we should do everything on main").
  Record `git rev-parse --short HEAD` when you start and when you finish.
- Write only inside your **exclusive write** paths (`ownership.json`); a
  new file goes only inside a directory you own. Every other path is
  another writer's: the other lanes, INT, and the coordinator
  (`proposals/`, `AGENTS.md`, `audits/`, `.claude/`). Never edit
  `third_party/` or `sources/`.
- No build, no typecheck, no test run, no generator run, no `make` target
  of any kind, and never `make bootstrap`, `tools/bootstrap.sh`,
  `make build`, `make test*`, `make self` or `make compile` (D56; this
  machine does not build LLVM). Reading, `grep`, `find`, `wc`, `git log`,
  `git show` and `git diff` are fine. No git write: the coordinator
  commits.
- Four first-class targets (AGENTS.md): nothing per-target outside the
  target's entry.

**Shared contracts.** P0 §5 fixes every shared declaration by name and
shape: the specification's ops, types and attributes, the grade
(`!idr.graded<uses, hold, T>`, D88 to D90), the lifetime
(`!idr.lifetime<view | room | cursor | home k>` and its openers, D93),
families (`!idr.data<#Family[...]>`, D48), the effect tree and its one
query API (D9, D27 to D29), the solver layer's shared types (C114), the
tail fact on `idr.call` (D30, C139), the runtime's one ending table
(D37, D64, D81) and the pipeline as one generated list (C28). Write
against those names and shapes as P0 states them, whoever owns the file
that declares them; never declare your own copy, and never wait for the
owner's file to land. Where you need a declaration P0 does not fix,
report the exact seam to the coordinator and continue with everything
else.

**Hub files.** Every `CMakeLists.txt` outside a directory you own, the root `Makefile` and
`CMakeLists.txt`, and the generated outputs (`include/idr/IR/Generated/`,
`generated.manifest`) are INT's. Do not edit them: list in your handoff
each file you added, moved or deleted, per directory, and INT wires
them.

**How the code is written.**
- C++: concept-constrained templates, monomorphized; dispatch over ops
  only through MLIR (an interface, a trait, a rooted pattern), never an
  `isa<A, B>` ladder or a concept that lists ops; a choice is a type or
  an enum case, never a `bool`; no `assert` (D91): an invariant is a
  type, a verifier rule, or nothing; no pointer-keyed map holding
  per-node state; nothing static built per function.
- Idris: in the subset both hosts compile, type-driven (indices, views,
  erased proofs, evidence over `Bool`, C154: evidence at quantity 0 in
  bodies the stock host runs). On the stock host, avoid until fixed:
  constructors named `Nil`, `::` or `#` matched inside pattern lambdas,
  nested linear `LPair`s (`audits/p0/design/idris-linear-check.md`), and
  an effectful `let` whose value the body ignores
  (`audits/p0/design/idris-identity-bug.md`).
- Comments explain why the code is the way it is; they cite no document
  or rule number. Names are churned until correct (D90's vocabulary).

**Verification you may do.** Read-only checks only: every symbol you
delete has no remaining reference inside your paths (`grep`), and each
reference outside them is listed in your handoff as a seam for its
owner. INT runs the checks AGENTS.md names (`make check`, `make build`,
`make test`, `make test-idr`, `make test-unit`, `make test-mlir-tools`)
on the whole.

**Handoff.** When your obligations are done, reply in under 400 words:
the paths you changed, per obligation; per obligation, the state made
unrepresentable, the check moved to a boundary or the branch deleted,
or why the case is essential (AGENTS.md); the files added, moved or
deleted per directory, for INT; every unresolved seam, with its owner;
HEAD at start and at finish.

**The owner's word over the coordinator's.** The owner, 2026-10-21: "my
human word always takes precedence over automated decisions." The
rulings bind you; a coordinator decision that the evidence shows wrong
is reported to the coordinator, never changed by you. Escalate
conflicting evidence with the contract change you propose, and keep
working on every obligation it does not block.

## The six binding rules (verbatim)

1. Do exactly the assigned obligations and the necessary consumer adaptations within the exclusive write set. Every changed hunk, new file, dependency or abstraction must map to a named obligation. If the contract cannot be completed within those writes, report the exact missing seam; do not silently widen scope.
2. Add no unsolicited features, frameworks, generic helpers, configuration knobs, retries, telemetry, documentation, dependencies, formatting sweeps or neighboring cleanup. Elegance means completing the selected representation and deleting its named predecessor, not opening another project.
3. Do not be afraid to duplicate reading, investigation, reasoning or small, packet-local, non-authoritative glue. Do not wait for a sibling just to avoid that duplication, and do not introduce a shared helper that creates a false dependency. Reuse repairs that have already landed; duplicated investigation does not mean rebuilding working mechanisms.
4. Authoritative schemas, vocabularies, identities and business facts still have exactly one owner. Never duplicate them, create competing implementations or write concurrently to another owner's file. Duplicate effort is allowed; duplicate authority and overlapping writes are not.
5. Finish the bounded deliverable, report changed paths against obligations, the checks actually run and any unresolved seams, then return control. Do not roam into another packet, manufacture work to keep up the headcount, or build a reporting or coordination platform.
6. User steering goes through the coordinator, into the affected packet only. The coordinator corrects an architectural contradiction in the canonical contract and re-dispatches the affected lane. No lane stops for it.
