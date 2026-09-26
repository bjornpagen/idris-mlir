# Idris 2 interfaces for a compiler that preserves static information

> Research snapshot from before the scaffold. See [the architecture spec](../architecture/00-index.md) and [repository README](../../README.md) for implemented scope.

Source audit: Idris commit `1c630e67c386629a0fbbc6b78a59176fde7f0a76`.
The compiler API package declares version `0.8.0`.

## Conclusion

**We can use Idris's existing frontend without consuming its erased backend
IR.** The documented external-codegen entry point receives both a Core entry
term and the compiler's definition context. Calling `getCompileData` is a
convenience used by existing backends, not a requirement of that interface.

The best first investigation is an external compiler registered through
`Idris.Driver.mainWithCodegens` that reads checked Core definitions and
exports a small, explicitly versioned representation of its own. Preserve
types, multiplicities, and index relationships there; perform specialization,
representation selection, and erasure deliberately before lowering to MLIR.

This path does not initially require a frontend fork. It does require handling
the differences between fresh definitions and definitions loaded from cache.
The existing `incCompileFile` callback offers a particularly useful second
entry: it runs after successful module processing and before TTC serialization.
Test it as a typed-sidecar producer before considering a new frontend hook.

## Terminology: TT, CExp, and Core

**TT** is the elaborated core language: terms and their environments retain
types, multiplicities, and dependent relationships. **CExp** is the expression
representation prepared for runtime compilation, after relevance-based erasure
and pattern compilation. Its primitive operations still identify things such
as integer addition, but it does not carry the original dependent typing
context. TT and CExp are different representations.

**Core** is not a third IR alongside them. It can refer informally to the TT
language, to the compiler's `Core.*` subsystem, or specifically to the `Core a`
computation type. In [Core.Core](../../third_party/Idris2/src/Core/Core.idr), that last meaning is
a wrapper around `IO (Either Error a)`: how compiler functions do work and
report errors. The `Core.CompileExpr` module name does not make CExp typed TT.

## What “stable” means here

There is real evidence of compatibility intent:

- [CONTRIBUTING.md](../../third_party/Idris2/CONTRIBUTING.md), under “Things That Should Be
  Discussed via the Issue Tracker First,” says changes to TT and CExp should
  be discussed because they “have been fairly stable for a while” and external
  tools depend on them.
- The same section explicitly calls for coordination around elaborator-script
  compatibility.
- [The custom backend guide](../../third_party/Idris2/docs/source/backends/custom.rst) documents using
  the compiler as a library, with `mainWithCodegens` and `Codegen`.
- [idris2api.ipkg](../../third_party/Idris2/idris2api.ipkg) exports much of the frontend and Core,
  not just backend modules.

These are supported extension surfaces and comparatively stable structures,
not a promise of an immutable ABI or compatibility across arbitrary revisions.
An `export` or `public export` declaration establishes accessibility, not a
versioning guarantee. Pin our adapter to a compiler revision and test upgrades.

## Interface inventory

| Surface | Compatibility evidence | What it gives us | Suitability |
| --- | --- | --- | --- |
| `Idris.Driver.mainWithCodegens` and `Compiler.Common.Codegen` | Documented external extension route | CLI/build integration; Core entry term; `Defs` and `SyntaxInfo`; compilation, execution, and optional incremental callbacks | Recommended integration shell, even when bypassing backend IR |
| `Core.TT.Term`, `Binder`, `Env` | Explicit compatibility consideration for TT; shipped in API | Elaborated terms, binder types, multiplicities, applications, dependent types, and typed laziness | Recommended semantic input |
| `Core.Context.GlobalDef`, `Def.PMDef`, `CaseTree` | Public API structures; tied to compiler implementation | Global types; checked clauses with environments; compile-time and runtime case trees; constructor and analysis information | Needed alongside `Term`; isolate behind our adapter |
| `getCompileData`, CExp, Lifted, ANF, VMCode | Documented backend route; explicit compatibility consideration for CExp | Erased executable program with progressively lower-level structure | Useful reference implementation and fallback; insufficient alone for all type-driven optimization |
| `Language.Reflection` / `Elaboration` | Language feature with explicit ecosystem compatibility concern | Quoting, checking, type/constructor queries, generating declarations and files | Good for a staged DSL or explicit kernel API; not a general whole-program Core-body export |
| Parser, desugaring, `TTImp` elaboration, module-build functions | Exported through compiler API | A custom frontend driver with control over processing | Possible, but more orchestration and coupling than the codegen callback |
| `Core.Binary.readFromTTC`, `Core.TTC` | Explicitly version-checked internal format | Cached checked definitions and compiled expressions | Use through the pinned Idris API; not a durable external interchange format |
| IDE protocol and IR dumps | Documented tooling/debug facilities | Editor queries and human-readable compiler output | Neither is a typed whole-program compiler boundary |
| `%foreign`, `%spec`, `%transform`, `%builtin` | Documented language mechanisms | External calls, selected specialization, rewrites, compiler-recognized operations | Useful supporting tools, not substitutes for a typed compiler interface |

## The important distinction: registration versus representation

[Compiler.Common](../../third_party/Idris2/src/Compiler/Common.idr) defines the callback as:

```idris
compileExpr : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
              (tmpDir : String) -> (outputDir : String) ->
              ClosedTerm -> (outfile : String) -> Core (Maybe String)
```

It does not take CExp or ANF. Our implementation can inspect `Defs` and the
`ClosedTerm` directly. `mainWithCodegens` supplies the standard driver around
that callback. This is a stronger starting point than parsing Idris ourselves
or adding a new backend inside the upstream compiler.

The callback runs after normal frontend processing; using it does not stop
Idris from also generating its usual compiled expressions. The useful property
is that much of the checked information remains available alongside them.

The optional module callback is also worth using directly:

```idris
incCompileFile : Maybe (Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                        (sourcefile : String) ->
                        Core (Maybe (String, List String)))
```

`Idris.ProcessIdr.process` calls it after successful `processMod`, records its
returned incremental data, and then calls `writeToTTC`. It is therefore an
existing **pre-serialization** hook, though not a pre-erasure pass. It can
inspect fresh retained TT and write our own typed sidecar as its intermediate
artifact. Match the callback's path/extension and incremental-data conventions;
the consumer/linker would be ours.

`toIR defs` supplies the documented current-module definition set; follow the
additional type/constructor references needed by our export. Do not call
`getIncCompileData` if the intent is to inspect typed definitions directly.

An unchanged cached module may skip the callback. Furthermore,
`Core.Context.addImportedInc` can disable incremental mode for the selected
codegen when an import lacks its incremental data. Start without Prelude, then
explicitly test rebuilding dependencies, missing sidecars, cache invalidation,
and fallback. See [the test plan](starting-point-and-tests.md).

`getCompileDataWith`, by contrast, deliberately takes a runtime view. It follows
runtime references, temporarily decodes minimal definitions, merges lambdas,
fixes arities, performs CSE, and optionally produces lifted/ANF/VM forms.
Its minimal decoder supplies an erased placeholder for a global type. It
restores cached entries afterward. Do not mistake that temporary context for
a complete typed export, or mistake the runtime call graph for all dependencies
needed to interpret types and proofs.

## What checked Core actually retains

The relevant source structures are:

- [Term](../../third_party/Idris2/src/Core/TT/Term.idr): elaborated applications and bindings,
  references, metavariables, type universes, and typed delay/force constructs.
- [Binder](../../third_party/Idris2/src/Core/TT/Binder.idr): lambda, let, pi, and pattern binders
  carry their types and `RigCount` multiplicities.
- [GlobalDef and PMDef](../../third_party/Idris2/src/Core/Context/Context.idr): a global type,
  erasure/specialization argument sets, totality information, flags, compiled
  expressions, and the underlying definition. A `PMDef` contains `treeCT`,
  `treeRT`, and original checked clauses `pats`.
- Each checked clause retains an `Env Term`, a left-hand side, and a right-hand
  side. The source explicitly describes these as full, non-erased terms used
  for specialization, among other purposes.
- [CaseTree](../../third_party/Idris2/src/Core/Case/CaseTree.idr): scrutinee types, constructor
  alternatives, term leaves, unmatched cases, and impossible cases.

`Term` is intrinsically scoped, not intrinsically indexed by its object-language
type. Binder/global environments and functions such as
[`Core.GetType.getType`](../../third_party/Idris2/src/Core/GetType.idr) supply the typing context.
An arbitrary constructed `Term` is not itself proof that elaboration succeeded.

Use [`lookupCtxtExact`](../../third_party/Idris2/src/Core/Context.idr) to obtain decoded global
definitions and the existing name-resolution/normalization utilities. Export
stable names of our own; `Resolved Int` identities belong to a compiler session.

**Candidate inputs:** checked clauses are attractive when we need original
binder environments and dependencies; `treeCT` supplies already compiled
pattern decisions. Neither should simply be treated as executable CExp.
Compile-time case trees serve normalization and can contain distinctions that
must disappear during runtime erasure. Our lowering must explicitly respect
Idris's relevance, case-compilation, evaluation, and effect semantics.

## Cache limitations that affect the architecture

The serialization code gives concrete constraints:

1. [`TTC Def`](../../third_party/Idris2/src/Core/TTC.idr), for `PMDef`, saves `args`, `treeCT`, and
   `pats`, but **not `treeRT`**. On load it substitutes `Unmatched ""` for the
   runtime tree. A frontend-derived compiler cannot rely on imported runtime
   trees being available just because fresh ones are.
2. `TTC GlobalDef` saves the compiled expression, references, multiplicity,
   name, and definition. It saves the global type and additional metadata only
   when `isUserName` holds. Other names load with an erased type placeholder
   and default metadata. In this revision, `isUserName` excludes `MN` and `PV`
   names (including through namespace/display wrappers); it is not simply a
   test for whether a programmer literally wrote the name.
3. [`Core.Binary`](../../third_party/Idris2/src/Core/Binary.idr) requires an exact TTC-format
   version match. Its current value is `2025_08_16_00`, independent of the
   package's `0.8.0` version. Matching the format is necessary, not a guarantee
   that our adapter is compatible with every compiler sharing that number.

Therefore “the full context is accessible” does **not** mean “every cached
helper has every original annotation.” The first prototype must compare fresh
source and cached imports, especially generated helpers and local functions.
Recover missing information only when justified by retained clauses and their
environments. Otherwise report an unsupported case, use an explicit fallback,
or arrange to export richer information while compiling that dependency.

## Where an earlier hook could go

The current path is approximately:

```text
Idris syntax -> TTImp -> checked Core definitions/clauses
                           |
                           +-> retained types, treeCT, checked pats
                           |
                           +-> runtime preparation:
                               transforms / selected specialization / erasure
                               -> treeRT -> CExp -> lower backend forms
```

[`TTImp.ProcessDef.mkRunTime`](../../third_party/Idris2/src/TTImp/ProcessDef.idr) reads retained
clauses, applies transforms and specialization, and calls `linearCheck` with
erasure enabled before producing a runtime case tree. Its `toErased` helper is
the concrete place to study when designing an information-preserving export.

[`Idris.ProcessIdr`](../../third_party/Idris2/src/Idris/ProcessIdr.idr) runs declaration processing,
collects totality errors, and then calls `compileAndInlineAll` if there are no
errors. A module export after successful checking can snapshot retained Core;
it is not literally before every runtime transformation, because declaration
processing has already prepared runtime definitions.

There is no general, documented “register any pre-erasure pass” callback in the
interfaces inspected. The existing incremental callback is sufficient to try
an export before persistence; it does not insert a new phase into erasure.
For an actual new phase, we would need a small frontend patch or a custom
driver built from the exposed frontend modules. A hook inside
runtime preparation must not mistake incomplete intermediate state for a fully
checked module; finalize exports only after the relevant checks succeed.

## Options if we do not target backend IR

### A. External codegen registration, typed Core input — recommended first

Reuse the normal driver; inspect retained checked definitions in our callback;
translate into our own typed IR and then MLIR. Keep compiler-version coupling
inside a small adapter. This preserves the frontend investment without assuming
a new upstream extension mechanism exists.

First prove information availability and semantics on a small set of programs.
Do not commit to arbitrary Idris compilation until cache and generated-helper
coverage has been measured.

### B. Existing incremental callback and typed sidecars

Use `incCompileFile` to export retained typed module data before ordinary TTC
serialization omits annotations. This is the next option if the final callback
cannot recover all needed information from cached definitions. It uses the
existing registration API, but requires building dependencies with our exporter
and designing artifact invalidation/loading carefully.

The current starting recommendation is to test A and B together: observe a
module in the incremental callback, then observe it after cache reload. This
separates the sufficiency of the checked representation from the sufficiency
of Idris's existing persistent format.

### C. A new frontend export hook — only if existing callbacks are too late

Export typed module data while it is available, including generated-helper
types and the facts required by our transformations. Persist a sidecar with its
own schema version, compiler revision, dependency hashes, and target-independent
semantics. Avoid changing TT/CExp themselves merely to transport our data.

This adds a patch to maintain and a dependency-rebuild requirement. It can be
the better long-term boundary if the callback cannot reliably recover the
required information from ordinary caches.

### D. Elaborator reflection and a typed kernel library

Use a deliberately designed Idris DSL or collection API to expose static
parameters, layouts, and operations, then generate/export a constrained IR.
Reflection exposes type queries, checking, quoting, and declaration generation,
but no general arbitrary-function-body getter in the inspected `Elab` API.
An explicitly represented DSL program is therefore much easier than recovering
all ordinary Idris programs through reflection.

This is viable for proving performance ideas quickly. It tests a library/DSL
contract rather than establishing an optimizing compiler for general Idris.

### E. Reuse frontend API with our own driver

`Idris.ModTree`, `Idris.ProcessIdr`, and `TTImp` processing/elaboration modules
are exposed by `idris2api.ipkg`. They allow more control, but bring initialization,
imports, caches, primitive definitions, errors, and compiler-state orchestration
into our maintenance scope. Use this only for concrete control that A cannot
provide.

### F. Translate surface syntax directly

Possible, but it gives up Idris's elaborated implicit arguments, resolved names,
dictionary construction, and checked dependencies unless we reconstruct them.
It is the weakest choice for reusing Idris's guarantees. Parsing a `.ttc` file
independently or scraping pretty-printed Core is similarly unattractive.

## The boundary we should own

Define a small versioned **typed export**, not a copy of every compiler data
structure. Its initial contract should include:

- Stable symbols; function and constructor signatures; explicit binder scopes.
- Types and multiplicities; checked bodies/case decisions; source locations.
- Constructor field/index relationships and explicit erasure decisions.
- Separate categories for known constants, symbolic index relationships, and
  dynamic runtime values. Erased does not mean compile-time constant.
- Evaluation/effect and laziness information needed to preserve behavior.
- Explicit unsupported/unknown cases, including unresolved holes and missing
  metadata. A type's presence is not permission to invent representation facts.

MLIR lowering then consumes our contract, not arbitrary Idris context records.
Ownership/alias facts require separate justification: multiplicity 1 alone
does not mean every reachable heap object is uniquely owned. Similarly, a
dependent length does not choose a contiguous layout or make that length a
constant. Preserve these distinctions in the IR rather than adding optimistic
flags to LLVM operations.

## First experiment and decision gates

Build a Core inspector/exporter through `mainWithCodegens`, including the
incremental callback, before building the native backend. Cover scalar
arithmetic, an erased proof argument, an indexed
datatype, a higher-order function, an interface dictionary, a local helper, and
a lazy/effectful example. Run each both fresh and through cached imports.

The experiment should answer: can we obtain each required type and body,
identify unavailable metadata, preserve name identity across modules, and
separate runtime dependencies from type-only dependencies? Those results decide
whether the final callback is enough, typed sidecars are needed, or a genuinely
earlier hook is warranted. Concrete existing fixtures and acceptance criteria
are in [starting-point-and-tests.md](starting-point-and-tests.md).

Then lower a small scalar/indexed subset, checking behavior against existing
backends and inspecting allocation counts and generated code. Performance claims
need measurements, including a hand-written low-level baseline.

This document records source inspection, not a working exporter or benchmark.
No `idris2`, `mlir-opt`, or `mlir-translate` executable was found on the current
PATH, and no compiler build or performance experiment was run for this audit.
See [MLIR and Mojo notes](mlir-and-mojo.md) for the associated design research.
