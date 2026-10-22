<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: typed effects, and where they live

Written 2026-10-21 at e96bb991, before the owner rules on DP-02 (the world)
and DP-03. The owner: "i see some other language with a typesafe effect
system and i get jealous ... let's investigate before we call this one",
sharpened the same day: "why have an effect system baked into our mlir
tablegen layer and not ... in our types in our compiler? am i nuts?"
Written after D15 ("always idris") and D16 (every `.td` of ours generated
from one typed Idris specification), as the coordinator relayed them. No
code was written; nothing was built or run.

Claims are marked *read* (a path and line at e96bb991, a paper's section, a
URL seen), *recalled*, *conjecture*, or *decision* (a ruling of
`proposals/0000-mlir-native.md` §2: D9, D12 and so on). "effects.md 1.4"
is `audits/p0/design/effects.md` §1.4; "02 §3.7" is
`audits/p0/02-ods-effects.md`; "F DP-02" is
`audits/p0/synthesis/F-decisions.md`. Koka is cited at 198fc3bb
(`/tmp/rc-lane-koka/koka`, read, never run); GHC at 9.14.1 (`/tmp/ghcsrc`;
`sources/code/ghc` holds only the compact-regions files); paper texts were
extracted to `/tmp/effpapers/`. Read-only helpers read the web, Koka and
GHC sources; their citations were spot-checked.

## 0. In plain words

**Not nuts.** The instinct is the classic one, from Lucassen and Gifford's
type-and-effect systems to Koka: what a computation may do is a fact about
the computation. It composes, and a checker can hold it.

**And effects.md already builds it, under another name.** Its atoms are a
monomorphic effect row; `derive` is bottom-up inference over the call
graph's components; V1 and V2 are the checker; the `total` seed is Koka's
`div` inference, done by Idris; the LLVM attributes are what a compiler
does with purity. D16 makes the rest literal: the vocabulary, the rules
and their laws become Idris types in the specification (3.3.4, 3.3.5).

**What is left of "in our types" is one placement question in the IR:**
does a computation's row live on the op (an inherent property of
`idr.func` and `idr.call`), or in an MLIR type (`!idr.fn<(i64) -> i64,
effects<io>>`)? For each of the three things in our IR that compute:
- *A named function:* no difference. MLIR keeps a function's type as an
  attribute of its op, so a row inside it is the same fact in the same
  place. A call keeps its own copy either way, because a function pass may
  not read a sibling function (5.8 B9).
- *A closure:* a row in `!idr.fn` would travel with the value, but
  closures live two passes (`lib/Transforms/Pipeline.cpp:66-71`, read), and
  defunctionalization's sums, one per label set, say more than a row.
- *A region:* MLIR has no region types; `RecursiveMemoryEffects` already
  folds a body's effects into its op.

**The rule the landscape teaches.** An effect belongs in a function's
*type* when it changes how a value of that type is called or returns:
Koka's yield checks, Effekt's capability parameters, Flix's frames for
control effects, Mojo's `Throws` and `Async`. An effect that only orders,
or licenses deletion, belongs on the op and on the function's attributes:
MLIR's `MemoryEffectsOpInterface`, LLVM's `memory`, `willreturn`,
`nounwind`. Koka shows it plainly: its compiler uses effect types to pick
a translation, and its optimizer does not read them (1.2). None of our
atoms changes a calling convention (Idris has no handlers; our IO is
direct style), so none belongs in an MLIR type today.

**For DP-02**, (c) is not a third way to order IO: under A and under (c),
op effects order it. It fills A's one gap: the world is today the only
typed mark of "does IO" on a signature or a closure, and the derived row
replaces it exactly. Under B, the world parameter and the row's `io` atom
would be one fact twice. **For DP-03**, a row is sound only if it covers
every state a caller orders with: eff-Q1 (b) is forced. Verdict and
recommendation: section 5.

## 1. The landscape

### 1.1 At a glance

| system | what the effect types say | what the compiler does with them | cost |
| --- | --- | --- | --- |
| Koka | inferred rows: `total`, `div`, `exn`, `io`, user effects | picks the monadic translation and evidence swaps; optimizer ignores them | a yield check after each effectful call |
| Effekt | required capabilities; second-class blocks | capability parameters; known handlers inlined away | stacks for resumptions |
| Flix | Boolean effect formulas, inferred in bodies | grounded at monomorphization; purity drives DCE, inlining, parallelism, frames | frames only for control effects |
| Frank | ambient abilities, implicit variables | checking only | unoptimized |
| Eff | dirt sets `A ! Δ`, internal | type-directed handler reduction, then erasure | near hand-written OCaml |
| Unison | `A ->{e} B`, inferred unions | none: continuations in an interpreter | interpreter |
| OCaml 5 | none | runtime fibers, one-shot | ~1% when unused |
| F* | `Tot < GTot`, `Tot < Dv`, `ST`, `ML` | erasure and extraction | none for `Tot` |
| Lean 4 | `IO` over opaque `IO.RealWorld` | token erased; ordering guarded by hand | none |
| GHC | `State# RealWorld` token | token erased; per-primop effect classes; state hack | ordering patched by magic |
| GHC libraries | `Eff es a`, mtl classes, free monads | fast only when specialized and inlined | breaks across modules |
| Mojo, Swift | `Throws`, `Async`; `throws`, `async` | the calling convention | the convention |
| Idris 1 `Effects` | resource-dependent effect lists | nothing: a library and its interpreter | the interpreter |
| `Control.App` | `Has [Console] e`, `Path`, linear `App1` | nothing: interfaces over world passing | an `Either` per action unless inlined |

### 1.2 Koka (read)

- **Types.** "The absence of any effect is denoted as `total`"; `exn` for
  raising, `div` "if a function may not terminate"; `exn` and `div`
  together are `pure` (`doc/spec/tour.kk.md:452-462`). All inferred; mutual
  recursion is "assume[d] ... divergent for now"
  (`src/Core/Divergent.hs:26-27`; `src/Type/Infer.hs:183-188`).
- **What the compiler does: it picks a translation.** Only a function
  whose row has an open tail or a handled, non-`linear` effect gets the
  monadic (yielding) translation (`isMonEffect`, `src/Core/Core.hs:856-861`;
  `src/Core/Monadic.hs:79, 132`). Built-in effects never do: "no cost for
  effect handlers for any code that does not use them" (Leijen, POPL 2017,
  §5.1.1). Full CPS "turned out to slow down the code significantly" (§5);
  closing rows cut CPS-translated functions "by over 80%" (§5.1.1).
  Handlers are reached through one evidence vector, so representations stay
  "stable under type instantiation" (Xie et al., ICFP 2020, §4);
  tail-resumptive operations run in place, and "almost all important
  effects are tail-resumptive" (§6.2). In C, each effectful call is
  followed by `if (ctx->is_yielding) { yield_extend(...); return 0; }`
  (Xie and Leijen, ICFP 2021, §2.8).
- **What it does not do: optimize by purity.** The simplifier inlines or
  drops only *syntactically* total code ("does not consider the effect
  type", `src/Core/Core.hs:797-799`; a known `total` callee counts as not
  total, `:832`); the C backend never reads an effect type
  (`src/Backend/C/FromCore.hs:1246`).
- **Cost.** Without the tail-resumptive path a counter is "10× slower";
  Ev.Eff in Haskell ran "4× faster" as GHC inlined it fully (ICFP 2021, §5).

### 1.3 The others (read, unless marked)

- **Effekt.** `def div(n: Double, m: Double): Double / { exc }`: effects
  in return position are capabilities the caller provides
  (effekt-lang.org/docs/concepts/effect-safety); first-class functions are
  boxed with what they capture (effekt-lang.org/tour/captures). The
  compiler turns effect types into capability parameters
  (`effekt/shared/.../Compiler.scala`, "Uses annotated effects to translate
  to explicit capability passing"); a known handler then disappears by
  general inlining, static `reset`/`shift` reduction and dead code removal
  (`core/optimizer/{Normalizer,StaticResumptions}.scala`).
- **Flix.** `def map(f: a -> b \ ef, l: List[a]): List[b] \ ef`, Boolean
  formulas with principal types (Madsen and van de Pol, OOPSLA 2020). "A
  whole-program optimizing compiler that uses monomorphization and inlining
  (like Rust and MLton)" (flix.dev/faq). Monomorphization grounds every
  effect, a free variable defaulting to `Pure`
  (`language/phase/monomorph/Specialization.scala`). Then `Pure < Impure <
  ControlImpure` (`language/ast/Purity.scala`) drives the inliner and DCE
  (a dead pure binder goes, a dead impure one stays,
  `phase/optimizer/Inliner.scala`), the JVM code (only control-impure
  functions get resumption frames, `phase/jvm/GenFunAndClosureClasses.scala`),
  and purity reflection, resolved at compile time, so `Set.count` runs in
  parallel when its predicate is pure (doc.flix.dev/purity-reflection.html;
  ECOOP 2023). The closest model to us.
- **Frank and Unison.** Frank's ambient ability is implicit and "there is
  no effect inference"; types only check, and the elaboration "is not at
  all optimised for efficiency" (POPL 2017, arXiv:1611.09259, §2.4, §4.1).
  Unison infers `A ->{e} B` as unions and runs abilities on delimited
  continuations in an interpreter (unison-lang.org, abilities reference;
  blog/jit-announce).
- **Eff.** Dirt sets internal to the compiler (JFP 2020, arXiv:2005.13814).
  The OOPSLA 2021 compiler uses "the explicit type and effect information
  ... to aggressively reduce handler applications", then erases it; pure
  code is elaborated without monads (JFP §2.5); polymorphic code is
  "conservatively assum[ed] ... impure" (§2.6).
- **OCaml 5.** No effect types ("do not provide effect safety", manual 5.3,
  §24.5); one-shot fibers, "mean 1% overhead" when unused (PLDI 2021,
  arXiv:2104.00250, §6.1). Modal effect types (OOPSLA 2025,
  arXiv:2407.11816) and OxCaml's yielding mode only check.
- **F\*** (fstar-lang.org tutorial, part 4). `Tot < GTot`, `Tot < Dv`;
  "Ghost computations are guaranteed to be erased"; state is extracted to
  OCaml's own (POPL 2017, arXiv:1608.06499, §2.7).
- **Lean 4** (`src/Init/System/IO.lean`; v4.26 notes). An opaque
  `IO.RealWorld` keeps IO in order; v4.26 erases it ("zero cost `BaseIO`",
  PR #10625); `unsafeBaseIO` is `@[noinline]` with closed-term extraction
  off, and "the compiler may re-order, duplicate, or delete calls".

### 1.4 Haskell: the same world as Idris's (read)

- **The token.** `newtype IO a = IO (State# RealWorld -> (# State#
  RealWorld, a #))` (`libraries/ghc-internal/src/GHC/Internal/Types.hs:553`),
  "represented by nothing at all" (`compiler/GHC/Builtin/Types/Prim.hs:1145-1165`):
  Idris's `PrimIO a = (1 x : %World) -> IORes a`
  (`third_party/Idris2/libs/prelude/PrimIO.idr:13-14`).
- **Data dependence was not enough.** Every primop has an effect class
  (`primops.txt.pp:139`), because "the state token threading expresses
  ordering, but duplicating even a read-only effect would defeat this"
  (`compiler/GHC/Builtin/PrimOps.hs:369-449`; the table of what each class
  allows, `:451-561`).
- **The token needs magic.** The state hack "claims that every function
  over realWorldStatePrimTy is a one-shot function ... sometimes it's
  false" (`compiler/GHC/Core/Opt/Arity.hs:254-275, 544-560`); `runRW#` is
  inlined "extremely late", or a `newArray#` floats out and "All calls to f
  will share a single array!" (`compiler/GHC/CoreToStg/Prep.hs:1273-1300`);
  `unsafePerformIO` needs `noDuplicate#`, `lazy`, NOINLINE and `-fno-cse`
  (`GHC/Internal/IO/Unsafe.hs:30-145`).
- **The libraries** (each project's README). effectful, an evidence vector
  in all but name, is fast because "the `Eff` monad is concrete";
  polysemy's optimizations "don't work in bigger, multi-module programs";
  eff: "GHC compiles most effect-polymorphic code via dictionary passing,
  not specialization". GHC specializes an imported function only with an
  INLINABLE pragma (`compiler/GHC/Core/Opt/Specialise.hs:703-735`).
  Whole-program monomorphization guarantees what they hope for.

### 1.5 Mojo and Swift: effects in function types are conventions

Mojo's function type holds `FnEffects {Throws, Async, Capturing, RefResult,
CABI}` (`KGENEnums.td:266-285`, read via 5.8 A4,
`audits/p0/wave1/5.8-dialect-design.md:129-141`); each changes how the
function is called or returns. Its memory effects are not in the type
(5.8 G5, `:590-596`). Swift's `throws` and `async` are in its function
types for the same reason, and `@_effects(readonly)` is a declaration
attribute (*recalled*); LLVM's `memory`, `willreturn` and `nounwind` are
attributes, not types (effects.md 1.9).

### 1.6 Idris's own

- **Idris 1 `Effects`** (`sources/docs/idris-effects/Effects.idr`, read).
  An effect is indexed by a resource its result may change (`Effect = (x :
  Type) -> Type -> (x -> Type) -> Type`, `:20-21`); a program is a tree,
  `EffM`, whose `EBind` hides its intermediate type (`:229-237`), run by an
  interpreter over a heterogeneous `Env m xs` (`:142-144, 348-358`).
- **Idris 2 `Control.App`** (`libs/base/Control/App.idr`, read). World
  passing that returns an `Either`: `MkApp : (1 prog : (1 w : %World) ->
  AppRes (execTy l e t)) -> App {l} e t`, `execTy p es ty = Either (OneOf
  es p) ty` (`:53-54, 102`). Capabilities are interfaces (`Has`, `:26-28`;
  `Console`, `App/Console.idr:8-12`; `PrimIO`, `App.idr:354-359`); state is
  an `IORef` (`:232-234`); `Path = MayThrow | NoThrow` (`:20`) keeps linear
  resources safe (`OneOf es NoThrow` is uninhabited, `:49-51`).

### 1.7 What compilers do with effect types

Three uses, and only three:
1. **Choose a calling convention or translation:** Koka, Effekt, Flix's
   frames, Eff, F*'s erasure, Mojo, Swift. It needs the effect in the
   type: a function value must be called right without knowing which
   function it is.
2. **License deletion, motion, parallelism:** Flix's inliner, DCE and
   purity reflection, GHC's primop classes, LLVM's attributes. It needs
   the fact where the optimizer asks, and MLIR asks ops:
   `MemoryEffectsOpInterface` and `ConditionallySpeculatable` are
   `OpInterface`s; no type interface for effects exists
   (`mlir/include/mlir/Interfaces/SideEffectInterfaceBase.td:52`,
   `SideEffectInterfaces.td:26, 119`, read).
3. **Check the programmer:** every typed system above. It needs source
   syntax, which Idris lacks (3.1).

We need none of the first, want all of the second, may not do the third.

## 2. What our compiler already has

### 2.1 Today's `effects` property

`idr.func` and `idr.call` hold `effects`, a bit set over {io, crash,
diverge}, inherent, by default "everything"
(`foreign/idr/include/idr/IR/IdrOps.td:143-163, 219-220`;
`IdrAttrs.td:186-209`; read). A call's set must contain its callee's
(`lib/IR/Func/Call.cpp:52-57`), and the call answers MLIR's effect queries
from it (`:65-72`). The solve runs over call-graph components, callees
first (`lib/Analysis/Effects.cpp:36-47`; `lib/IR/Func/Func.cpp:207-230`).
The seed is Idris's proof: no `total`, then `diverge` (`Func.cpp:190`).

How close to an inferred, monomorphic effect row? **Very close in shape,
wrong in source.** It is inferred, monomorphic, bottom-up, checked at every
call and read by upstream passes. But `bodyEffect` reads four side facts,
not the body's ops (a world parameter, `MayCrashOpInterface`, `world.new`,
a label runner; `Func.cpp:189-202`), so an op none of them sees is lost at
the boundary: `handle.string`'s read, `exit`'s end of the run, every memo
or memory write (02 §3.7). As a type, it is unsound.

### 2.2 effects.md fixes the source

Atoms on one resource tree (effects.md 1.2, 1.4), a summary derived from
the ops (3.6), V1 and V2 (4.1), the seed `total` (1.8), LLVM attributes
(1.9). In type-system words: a finite row lattice, principal rows by
inference, subsumption (V1), a checker after every pass, erasure.

### 2.3 The world

`!idr.world` is linear by its type and has no runtime form
(`include/idr/IR/IdrTypes.td:255-261`); 79 ops take and give one and
`world.new` forges one (02 §2.2 F1). In the frontend's Core it is a value:
the last operand of every `Effect`, a binder of `TabulateIO`, forged by
`NewWorld` (`compiler/src/IdrisMLIR/Term.idr:167-169, 197-219`, read). Two
jobs, not equally needed:
- *Ordering:* redundant already. Every IO op reads and writes `IOResource`
  (02 §6); two forged chains are ordered "by the effects where no world
  does" (`tests/effects-io/effects-io.mlir`, read).
- *Typing:* a world in a signature is today's only typed mark of "does
  IO". `bodyEffect` reads it (`Func.cpp:191`), and so do
  `Analysis/Identities.cpp:30`, `Specialize/Consumer.cpp:46-49` and
  `Specialize/Keys.cpp:201` (read), each asking "does it do IO?" as "does
  it take a world?". An IO action's closure is `!idr.fn<(!idr.world) ->
  (!idr.world)>` (8 fixtures, by grep).

## 3. The three possibilities

### 3.1 (a) A limitation of the language

Idris 2's types say two things about effects: whether a result is in `IO`
(world passing, `PrimIO.idr:13-19`), and, on a definition but never in a
type, whether Idris proved it `total`. Linear and indexed types encode
resource protocols, as libraries (1.6). What cannot be had, because the
language has no syntax or rule for it and D12 forbids inventing one:
- user effects and handlers as constructs (Koka's `effect`, Unison's
  abilities);
- effect polymorphism in function types; Idris says it only through
  classes over monads (`HasIO io =>`), which monomorphization removes;
- distinctions the programmer can see: "may crash" or not, "only reads"
  or "writes", a *total callback* (Idris checks totality per definition,
  through what it calls; no type asks for it);
- first-class delimited continuations (GHC needed four primops for them,
  proposal 0313).

The language does not stop what a compiler does with rows: inferred after
defunctionalization, where every call is known, they beat annotations.

### 3.2 (b) Userspace

**The evidence style compiles away.** A tail-resumptive handler is a
record of functions passed down (1.2): an interface dictionary, which is
what `Control.App`'s `Console e =>`, `State tag t e =>` and `PrimIO e =>`
are. Our frontend resolves every dictionary at compile time
(`tests/interface-state-monad`, a user monad over a user interface,
expected to compile and run) and refuses one that grows without bound
(`tests/polymorphism-growth-dictionary`, expected `unsupported
(polymorphism)`). The specialization GHC's libraries miss across modules
(1.4) is guaranteed here, as in Flix. With `bindApp` (`App.idr:109-117`)
and `primIO` (`:362-366`) inlined, a `putStr` through `Console e` is a
`put_str`, an `AppRes` and a `Right` matched at once, which known-case
folding removes (`lib/IR/Canon/MatchPatterns.cpp:3-5`; *conjecture* for
this program).

**What it still costs:**
- *Exceptions are values.* Under `MayThrow` an action not inlined returns
  an `Either`, one constructor per call: the essential cost of exceptions
  without unwinding (effects.md 1.9: `no_unwind`). Koka pays a yield check.
- *`NoThrow` needs a fact.* `OneOf es NoThrow` has no constructor, so
  `Either Void t` could be `t`. Whether the frontend knows an indexed
  family's instance is empty is unknown (*conjecture*); if not, it is a
  representation fact worth adding.
- *State is memory.* An `IORef` is a 0-d memref
  (`Registry/Primitives.idr:425-433`, read): a load and a store unless
  promoted.
- *Upstream's `Control.App` may trip the thread refusal.* `PrimIO e` has a
  method `fork` calling `Prelude.fork` (`App.idr:359, 373`). The registry
  rules `Prelude.IO.fork` out (`Registry/Recognized.idr:221-227`), and
  reachability follows every name a reached definition's type and case
  tree mention (`Frontend/Profile.idr`, `refsOf`). A program using
  `primIO` reaches the dictionary, which names `fork`'s implementation.
  *Conjecture* that it is refused; no test uses `Control.App`. If so, a
  program over base is refused, against AGENTS.md:144-148. Fixes for the
  owner: reachability by the methods used, or a fork-free `App` in
  `libs/`. Apart from DP-02.

**Out of reach:**
- *Free monads.* `EBind` hides its intermediate type, and `Env`'s type
  depends on a run-time value (`Effects.idr:193-197, 233-234, 348`). A
  field whose representation depends on an erased value is refused
  (`unsupported (dependent field)`, `tests/dependent-field-type-field`),
  and a uniform boxed form is forbidden (AGENTS.md:149-155). *Conjecture*
  that every freer-monad design hits the same rule.
- *Resumable handlers* (generators, backtracking, async) need CPS.
  Defunctionalization makes continuations data, so they compile, with an
  allocation per captured frame: Koka's bubbling by hand.
- *Threads and `%foreign`:* outside the language (AGENTS.md:192-200).

**The same code as hand-written IO?** For tail-resumptive effects in
`Control.App`'s style, yes, after specialization, inlining and known-case
folding (*conjecture* until the tests of section 5 exist). Exceptions
across calls: a constructor per call. Resumptions: continuation data.

### 3.3 (c) A typed effect system inside the compiler

#### 3.3.1 Two kinds of effect fact

- **Per op: what an op of this kind does to which state.** A fact of the op
  kind, fixed when the compiler is built (D10). It goes where MLIR asks, on
  the op: CSE (`lib/Transforms/Utils/CSE.cpp:222-228, 264`), DCE
  (`wouldOpBeTriviallyDead`), known-case inlining
  (`lib/Interfaces/ControlFlowInterfaces.cpp:1224-1228`) all ask ops
  (effects.md 7.1). These are the axioms.
- **Per computation: what a run of a function, closure or region may do.**
  It composes from the axioms and from what it runs: the row. The
  coordinator is right that it is a type, in type theory. The question is
  where MLIR can hold it.

The same split already governs linearity: a fact of a *value* lives in its
type (`!idr.lin<T>`, AGENTS.md), a fact of an *op kind* on the op, a fact
of a *function* on the function's op.

#### 3.3.2 The three carriers

**Named functions.** `idr.func`'s type is a `TypeAttrOf<FunctionType>`, an
attribute of the op (`IdrOps.td:158`). A row inside a custom function type
or beside it as a property is the same fact on the same op in the same
storage. The call cannot read either from its callee ("must not inspect
the state of operations that are siblings", `docs/PassManagement.md:29-31`,
via 5.8 B9), so it keeps a copy, V2's verified cache. MLIR does not fight a
custom function type (`llvm.func` has one), but every reader that compares
or hashes function types would see rows (*conjecture* how many). The gain,
V2 folded into the type check of `Call.cpp:34-51`, is small. **Verdict:
keep the property; the difference is spelling.**

**Closures.** A type carries what a property cannot: the row would travel
through block arguments, region results and data fields, and `idr.apply`
could answer MLIR from its callee's type instead of "everything"
(`Idr_RunsUnknown`, effects.md 1.7). Three facts decide against it:
1. Closures exist for two passes, deduplication and defunctionalization
   (`Pipeline.cpp:66-71`); after them every apply or force is a call of a
   dispatch function.
2. The sums are keyed by label set, one per flow set (`Defunctionalize.h:54-65`,
   via `audits/p0/06-defunc.md:381-382, 504`). A sum's row is the join of
   its labels' rows, which the dispatch's derived summary already is; a row
   on the sum is a second copy (AGENTS.md: "Generate the second copy from
   the first, or delete it").
3. Idris's closure types do not say `diverge` or `crash`, so a row on
   `!idr.fn` would come from the label solve, which then deletes closures;
   and refining an immutable type retypes every value of it, data-type
   bodies included (5.8 DS3): the rewrite defunctionalization already does.

**Verdict: no row in `!idr.fn` or `!idr.lazy`;** the label sum is the typed
form of what a closure can do.

**Regions.** No region types; `RecursiveMemoryEffects` folds a body into
its op (effects.md 7.1). A row adds only a lowering's query (3.3.6).

#### 3.3.3 The coordinator's framing, claim by claim

| claim | finding |
| --- | --- |
| per-op effects belong in ODS, as upstream queries ops | **confirmed** (3.3.1); after D16 the ODS is generated from the Idris specification |
| per-computation effects compose and are naturally types | **confirmed** in type theory; in MLIR a function's type is an attribute of its op, so the property *is* the typed form |
| rows in function, closure and region types | **corrected**: function rows stay on the op; closure rows are fixed by the label sums; regions have no types (3.3.2) |
| inferred over the call graph from op axioms, verifier-checked | **confirmed**: effects.md's `derive`, V1, V2 |
| rows travel through closures and defunctionalization's sums, where a property must be re-derived | **corrected**: closures die at pass 2; then only labels travel, and a dispatch's row is derived like any function's |
| "a pure-typed value holding an IO closure" made unrepresentable | **corrected**: AGENTS.md allows it in trusted code (a forged world in a lazy value, AGENTS.md:160-163); the invariant is "never hidden": every IO is in the row of every computation that may run it (V1, V2) |
| possibly replacing the world as IO's carrier | **confirmed for typing, not needed for ordering** (2.3; section 4) |
| the call's `MemoryEffectsOpInterface` generated from the callee's type | **corrected**: the call holds a copy (B9), and effects.md generates its effects from it (`Idr_Summarized`, effects.md 1.6) |
| one vocabulary of compile-time constants (D9) | **confirmed**; under D16 it is an Idris type, the constants generated |
| Idris's types give a coarse row to hand over | **half**: `total` is exact for `diverge` and is handed over (effects.md 1.8); `IO` is an upper bound broken by trusted forging, and says nothing of `crash` (totality does not exclude a crashing primitive, such as D13's zero divisor) or of heap, count and memo; nothing reads a row before the first derivation, so the bound buys only a cross-check (3.3.7) |

#### 3.3.4 The specification, in Idris (D15, D16)

The effect system's one source becomes a module of the dialect's Idris
specification. The generator emits from it every op's ODS effects, the
resource classes and constant tables (effects.md 2.1-2.4), the row's enum,
the projection table, the verifier's rules and the LLVM columns. The
frontend imports the module instead of a generated mirror (today
`compiler/src/IdrisMLIR/Dialect/Idr.idr` is generated from the `.td`,
effects.md 2.6). A sketch in the two-host subset (`%default total`, proofs
and indices at quantity 0); not compiled:

```idris
module IdrisMLIR.Spec.Effects      -- a sketch
%default total

data Addr = Addressable | Opaque

||| A child may be addressable only under an addressable parent.
data Under : (parent, child : Addr) -> Type where
  Same   : Under a a
  Hidden : Under Addressable Opaque

||| A state, built from its parent: one root, no cycle, and an
||| addressability that is legal by its index.
data Node : Addr -> Type where
  Root  : Node Addressable                     -- upstream's DefaultResource
  Child : NodeName -> Node p -> (0 _ : Under p c) -> Node c

heap : Node Addressable
heap = Child Heap Root Same
io, halt : Node Opaque
io   = Child IO Root Hidden
halt = Child Halt io Same                      -- [DP-03 ods-Q3]
-- `Child Fresh io Same : Node Addressable` does not type-check.

data Kind = Read | Write | Allocate | Free     -- upstream's four, no new kind

||| An effect of an op whose groups are `gs`: on a state, or on one group's
||| values, which only an addressable state admits.
data Effect : (gs : List Group) -> Type where
  OnOp    : Kind -> Node a -> Effect gs
  OnGroup : Kind -> Node Addressable -> Elem g gs -> Effect gs

||| One form of declaration per family, never two, never none.
data Declared : List Group -> Type where
  NoEffect  : Declared gs
  Static    : List1 (Effect gs) -> Declared gs
  Typed     : List1 (Rule gs) -> Declared gs      -- effects.md 1.6
  Recursive : List (Effect gs) -> Declared gs     -- its own, and its bodies'

||| What a caller must order a run with [DP-03 eff-Q1 (b); D14's exit].
data Atom = AIO | AExit | ACrash | ADiverge | AReads | AWrites | ACount | AMemo

||| A terminator with no successor ends the run on an atom that stops
||| returning, and its effects touch that atom's state (D14). A family is
||| its groups, a `Declared` and an `Ending` of it.
data Ending : Declared gs -> Type where
  Continues : Ending d
  Ends      : (a : Atom) -> (0 _ : StopsReturn a) -> (0 _ : Touches d (nodeOf a)) -> Ending d

||| The atoms a run may perform; no variable, since monomorphization and
||| defunctionalization leave no effect-polymorphic call. `Sub r s`: every
||| atom of `r` is in `s` (a declared row may say more, never less: V1).
Row : Type
Row = Vect 8 Bool

-- The derivation and its laws, over a small model of a program (each body
-- a list of family ops, calls and regions).

||| effects.md 3.6's `derive`: a body's row from its ops' projected axioms
||| and its callees' declared rows.
derive : (Fn -> Row) -> List Op -> Row

Checked : Program -> Type                       -- V1, for every function
Checked p = (f : Fn) -> Sub (derive p.declared (p.body f)) (p.declared f)

||| What the verifier rests on: if every function passes V1 (V2 is built into
||| the model), a function's row covers every op effect any run of it reaches.
sound : Checked p -> Reaches p f op -> Sub (project op) (p.declared f)

||| A call holding an atom declares effects that project back to it.
roundTrip : (a : Atom) -> projectAll (callEffects a) = single a
roundTrip AIO = Refl                            -- one `Refl` per atom
```

`sound` is an induction on `Reaches` (an op in the body, or reached
through a call), with `derive` monotone in its callees' rows. *Conjecture*:
a few hundred lines of Idris with the model.

#### 3.3.5 What an Idris specification proves that TableGen cannot

TableGen has records, folds over `!instances` and `assert` on values
(`llvm/lib/TableGen/TGLexer.cpp:447, 683`, read). It checks finite
properties of the records it has. It cannot make a record ill-typed, and
it cannot state anything about programs it has never seen.

| property | today, or effects.md | Idris specification |
| --- | --- | --- |
| a tree; no addressable node under an opaque one | upstream checks the second only under `EXPENSIVE_CHECKS` (`SideEffectInterfaces.h:164-173`); effects.md 1.10 (d) | unrepresentable: `Node`, `Under` |
| a value effect only on an addressable state | upstream aborts at run time (`:339-343`); 1.10 (d) | unrepresentable: `OnGroup` |
| exactly one form of declaration per op | 1.10 (b), (c), generator errors | unrepresentable: `Declared` |
| a rule names a group its op has | 1.10 (g) | unrepresentable: `Elem g gs` |
| a no-successor terminator stops the run (D14) | 1.10 (e) | unrepresentable: `Ending` |
| every family declares its effects | 1.10 (b), over open records | a closed family list, covered by a total function |
| projection round trip; never less | `static_assert` on generated tables (effects.md 2.4) | proved on the source; tables computed from the proved function |
| V1 and V2 mean no reader sees too little | prose (effects.md 4.1) | `sound`, over every program of the model |
| inlining keeps V1 when rows join (`absorb`) | not stated | a lemma beside `sound` |
| a row never refuses a program | not stated | `Row` has no error case |

The trust point: the proofs are about the specification's model; the
generator and the C++ walker that derives rows on real IR are trusted to
implement it, and V1 and V2, run on the real IR after every pass, close
the gap per program. Proofs are erased: free on both hosts.

#### 3.3.6 IR sketches (under DP-02 A; names illustrative)

```mlir
// Idris: greet : String -> IO ()
idr.func effects<io> @greet(%s: !idr.str) {
  idr.io.put_str %s                  // axiom from the specification: Read+Write on IO
  idr.return
}
idr.call @greet(%s) effects<io> : (!idr.str) -> ()      // its copy (B9), equal (V2)

// a closure, pass 1: nothing between the frontend and defunctionalization asks for a row
%c = idr.closure @log(%h) : (i64) -> !idr.fn<(!idr.str) -> ()>
idr.apply %c(%s) : !idr.fn<(!idr.str) -> ()>           // runs unknown
// pass 2 on: the label set is the type; the row is the dispatch's, derived
%c = idr.con @Log(%h) : !idr.data<"Fn$str#1">          // labels {@log, @ignore}
idr.call @dispatch$str$1(%c, %s) effects<io> : (!idr.data<"Fn$str#1">, !idr.str) -> ()
```

A trusted `unsafePerformIO` (AGENTS.md:160-163) is a region whose IO is in
the row of the function that demands the value, whatever Idris's type says
(effects.md 6.2 A). And a region's row read by a lowering is Flix's purity
reflection, internal and unannotated, once `tabulate_io` merges into
`tabulate` (effects.md 6.2 A):

```mlir
// Idris: counter : Int, in a trusted library
idr.func effects<io> @counter() -> i64 {
  %n = idr.io.unsafe_run -> i64 {    // RecursiveMemoryEffects
    %v = idr.array.get %ref[] : memref<i64>
    idr.yield %v : i64
  }
  idr.return %n : i64
}

%a = idr.tabulate %n -> memref<?xi64> {
^bb0(%i: index):
  %v = idr.call @f(%i) effects<none> : (index) -> i64   // empty row: any order
  idr.yield %v : i64
}
// effects<io> in the body: row-major order, as Term.idr:211-219 states
```

An IO op in a function whose row lacks `io` fails V1 after the pass that
made it, which is all the strength a type has in MLIR too.

#### 3.3.7 What (c) adds to effects.md, and what it rejects

effects.md *is* (c)'s machinery. This investigation adds: (1) the frame
and the proofs, 3.3.5's properties proved in the Idris specification
(D16) instead of checked by a generator or argued in prose; (2) V1 as
subsumption, the standard typing rule, not a weakening of "equals"
(equality holds at every write, effects.md 4.1, 6.8); (3) rows read by
lowerings: the merged `tabulate`, memo's `by_name` (F DP-50) and 2.3's
readers ask rows, not worlds; (4) "never hidden" as the IO invariant.

Rejected: rows in `!idr.fn` and `!idr.lazy` (3.3.2); a custom function type
for `idr.func` (spelling, at a cost); an Idris-declared IO bound beside the
derived row (it differs only by trusted regions, so it needs an exception,
and nothing reads it before the first derivation).

**D12 and the programmer.** No upstream concept changes: `IO`, `total`,
`covering` and `%default` mean what they mean upstream; the row is internal
and derived; no program is accepted or refused because of it; the
programmer writes nothing. **What MLIR fights:** the sibling rule (calls
keep a copy) and immutable types (rows in value types cost a whole-program
retyping); a row's uniquing is free (8 to 16 bits). **When a row would
belong in a type:** when an effect changes a calling convention, as
Mojo's `Throws` and `Async` do. Proposal 0020's Rust calls (fallible or
async) are the likely first case. Not now.

## 4. What this means for DP-02, DP-03 and effects.md

**DP-02.** The world does two jobs (2.3); (c) shows each is better done
otherwise:
- *Ordering* is op effects under every option. GHC and Lean, which order
  by a token, still need per-op effect classes and hand guards against
  floating, duplication and deletion (1.3, 1.4). Our IO ops already
  conflict through `IOResource` (02 §6).
- *Typing* ("does this computation do IO?") is the row's `io`, derived and
  checked. It is exact where the world is an upper bound (an `IO ()` that
  does nothing still takes a world), and it covers trusted forging, which
  the world needs `world.new` to say.

So (c) is option A with its typed carrier named, not a third ordering
mechanism; under B the world parameter and the row's `io` are one fact
twice. A requires only what effects.md has: a row covering every state
(DP-03), `io.unsafe_run` (6.2 A), the IO primitives' `idrisIO` for Idris's
sequencing (2.6), and 2.3's readers asking "row holds `io`". A's costs
stand (F DP-02: MoveOut's next-IO search, the ten world-threaded memory
ops, rank-0 `tabulate_io`, 391 frontend lines), and nothing anything reads
is lost: nothing reads a row before the first derivation (effects.md 4.1,
V0), and closures die at pass 2.

**DP-03.** A row is a sound type only if a caller can order with all it
summarizes: eff-Q1 (b) is forced (`reads`, `writes`, `count`, `memo`;
effects.md 6.4 found the same). ods-Q3 and eff-Q4 shape the tree, the op
axioms, untouched by where rows live.

**effects.md.** Unchanged in machinery; changed in four places: its source
is the Idris specification (D16), not `IdrEffects.td`; 1.10's generator
checks become types (3.3.5); 4.1 states V1 as subsumption and cites
`sound`; 6.2's option B records the duplication above.

## 5. The verdict, and a recommendation

- **A limitation of the language:** effects the programmer writes, sees,
  abstracts over and handles. Worth being jealous of; out of reach by D12.
- **Userspace:** capabilities as interfaces compile to hand-written IO,
  more reliably than in GHC; exceptions cost a constructor per throwing
  call; free monads are refused; resumptions are continuation data;
  upstream's `Control.App` may be refused through `fork` (3.2).
- **Inside the compiler:** everything a compiler does with effect types but
  choose calling conventions, which our language never needs: inferred
  monomorphic rows from op axioms, checked after every pass, lowered to
  LLVM, used to delete, move, merge and parallelize, as Flix does on the
  JVM. That is effects.md, specified and proved in Idris.
- **Not nuts:** after D16 the effect system lives in our types, the Idris
  specification's. In the IR a row lives on the op that is the computation,
  where MLIR keeps a function's type and every optimizer asks. TableGen is
  one of the outputs.

**Recommendation.**
1. DP-02 **A**, with the derived row as IO's typed carrier.
2. DP-03 eff-Q1 **(b)**, forced for a sound row.
3. effects.md as the type-and-effect system, its source the Idris
   specification's effects module (D16), with `roundTrip`, never-less and
   `sound` proved there. No rows in MLIR value types.
4. Tests of `Control.App`: a `Console`, a `MayThrow` and a `NoThrow`
   program, each against its expected output and against the same program
   in plain `IO`. File the `fork` refusal if it reproduces.

**What it costs in P0** (*conjecture*, nothing measured): beyond effects.md
and D16's own cutover, the effects module (vocabulary and family
declarations, needed anyway), the finite proofs (a `Refl` per case) and
the model with `sound`, perhaps a few hundred lines of Idris. DP-02 A's
cost is DP-02's, unchanged by (c). The `Control.App` tests are about a day.

## 6. Sources

**In full:** the representation-first skill; `AGENTS.md` (working tree);
`proposals/0000-mlir-native.md` §0-§5.1; `audits/p0/design/effects.md`; F
DP-01 to DP-04, DP-50; `audits/p0/synthesis/A-dialect.md` §2.2, §5.1-5.5,
§5.9; `Control/App.idr`, `App/Console.idr`, `PrimIO.idr:1-120`. **In
part:** 5.8 (A4, B9, B11, G5, T6, EF1-EF5, DS2); 5.10 (Perceus only, no
effect material); 02 §2.2-2.6, §3.5, §3.7, §6; 15 and 06 (by grep);
`Effects.idr`; our code, tests and upstream at the paths cited. **Koka,
GHC:** the files cited in 1.2, 1.4. **Papers** (text in `/tmp/effpapers/`):
Leijen, POPL 2017 (`sources/papers/leijen-2017-koka-effects`), quotes
checked at `algeff.txt:1112, 1206, 1237`; Xie, Brachthäuser, Hillerström,
Schuster, Leijen, *Effect Handlers, Evidently*, ICFP 2020; Xie and Leijen,
*Generalized Evidence Passing for Effect Handlers*, ICFP 2021, checked at
`multip.txt:551, 580-600`. **Web:** the URLs of 1.3, 1.4. **Not read:**
Brady's TFP 2014 paper (no PDF reader; the author's copy answered 403),
so none of its claims is used; the bodies of the OOPSLA 2021 Eff and ICFP
2025 Effekt papers (abstracts only).
