<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Investigation: Is the Idris → `idr` MLIR handoff too low level?

**Status:** answered. Proposal 0001 took up its questions and the cutover
(proposal 0002) decided them: the frontend emits no erased value and no
newtype, names are readable quoted symbols with locations, and the
dialect's functions are `idr.func`. The IR it quotes is the handoff at
25890d32; the brief is kept as the record those proposals cite.

> **Audience:** coding agent working in `github.com/bjornpagen/idris-mlir`
> **Mode:** investigate and report first. Do **not** start refactoring until the report in §9 is written and reviewed.
> **Context:** The textual MLIR the Idris frontend emits (the `idr` dialect in generic form, with mangled `$40$`-style names, `idr.q<zero, plain, none>` erased arguments, `MkCore`/`MkIO` wrappers, etc.) **is the handoff point** between the Idris frontend and the C++ MLIR code. The worry is that this boundary sits too low: the frontend hands C++ an IR that is verbose, under-optimized, and missing semantic information that only the frontend has, which forces the C++ side to rediscover facts the frontend already knew.

---

## 0. The core question

Answer this with evidence:

> **Which transformations currently happen (or are expected to happen) in C++/MLIR that are cheaper, safer, or only possible in the Idris frontend, and what would the handoff IR look like if the frontend did them?**

There's a guiding principle, but test it, don't assume it:

- **The frontend should do what needs Idris semantics.** That covers types, quantities, interface resolution, totality, data-type shape, binder names, source spans, and which arguments are proofs.
- **MLIR should do what is generic over the IR.** That covers inlining heuristics, CSE, DCE, SCCP, control-flow sinking, duplicate function elimination, lowering to `scf`/`cf`/`llvm`/`gpu`, and target-specific work.
- **The handoff IR should be the cleanest representation that still preserves everything later stages need.** In particular, anything the GPU / dependently-typed-workload goals will need (see §7) must survive.

A secondary question: is a **two-level dialect** inside C++ (`idr.hi` → `idr.lo`) the better answer for some items, rather than moving them into the frontend? Compare both options for each item.

---

## 1. Phase 0 — map the pipeline (do this first)

Before judging anything, produce a factual map. For each step, record file paths, function names, and a one-line summary.

### 1.1 Frontend side (Idris)

1. **Which Idris2 compiler IR is the source?** Find where the backend obtains definitions. Possibilities to check:
   - Typed definitions / case trees straight from the context (`Core.Context` `Def`, `CaseTree`, `TT` terms).
   - `CompileData` from `Compiler.Common.getCompileData` and which field: `namedDefs` (`NamedCExp`), `lambdaLifted` (`LiftedDef`), `anf` (`ANFDef`), or `vmcode` (`VMDef`).
   - Some custom traversal.

   **Why it matters:** the dump contains things upstream Idris2 phases normally remove or simplify, such as zero-quantity arguments passed as values, newtype wrappers (`MkCore`, `MkIO`, `MkST`), and interface-dictionary shims. The dump also carries **types**, which `CExp` does not, and it is monomorphized. That strongly suggests the backend consumes a **typed, pre-erasure** representation and reimplements (or skips) passes Idris2 already has.
   - **Verify:** list the Idris2 compiler passes (`Compiler.Opts.*`, `Compiler.CompileExpr`, newtype/erasure handling, inlining, constant folding, CSE, identity-function detection, etc.) and state for each whether idris-mlir runs it, reimplements it, or skips it.
2. **Where is monomorphization/specialization done?** The mangled names carry type arguments, e.g. `Core.Core.pure[(List (Pair Name Bool))]` or `fromBuf[(Pair Name Bool), TTC impl at Core.Binary.Prims:240:1--248:22 ...]`. Find the code that decides what gets specialized and what the specialization key is: an Idris type, a normalized type, or a runtime representation.
3. **Where are names mangled?** Find the `$<ascii>$` escaping code (`$40$` = `(`, `$91$` = `[`, etc.) and which names it applies to: symbols, type names, constructor refs.
4. **Where are `idr` types decided?** In particular `!idr.data` vs `!idr.box`, `!idr.q<mult, plain, T>`, `!idr.world_carrier`, `!idr.lazy`, `!idr.nat`, `!idr.big`, `!idr.str`, and the use of `memref<...>` for `IORef`/`Mut`.
5. **Where are locations produced?** Why is almost every op `loc(unknown)`, and why do library ops get `loc(fused<"library">[unknown])`? Does the frontend have `FC` spans available at that point?
6. **How is the text emitted?** Does the frontend print MLIR text itself, or build it through bindings? Is `"op"() <{...}>` generic syntax chosen deliberately by the frontend, or produced by the C++ printer (see §1.3)?

### 1.2 C++ side

1. List every pass, pattern set, and conversion in C++ (ODS files, `*.td`, pass registrations, pipeline construction). For each, note:
   - **Name**
   - **What it does**
   - **Which input facts it relies on**
   - **Whether those facts were known in the frontend**
2. List the `idr` dialect ops and types (ODS), and note for each op:
   - Its traits (`Pure`, `ConstantLike`, side effects, `RegionBranchOpInterface`, `CallOpInterface`, `OpAsmOpInterface`, etc.)
   - Whether it has an `assemblyFormat` or custom printer/parser
   - Whether it has a folder and/or canonicalizer
3. Is there an inliner interface registered for `idr`? Is the func inliner extension registered?
4. What is the current lowering path to LLVM (and to GPU, if any)?

### 1.3 The generic-form question (quick, high value)

`func.func` and `func.call` have custom assembly formats upstream, yet the dump prints them as `"func.func"() <{sym_name = ...}>`. Only two things cause this:

- something sets `printGenericOpForm()` / `--mlir-print-op-generic`, or
- **the module fails verification**. The AsmPrinter verifies first and falls back to generic form, emitting a `// Verification failed, printing generic form` comment.

**Action:**
1. Determine which of the two it is. Check printing flags in code, grep the full dump for that comment, and run with `-debug-only=mlir-asm-printer`.
2. If the module fails verification, record **which op fails and why**.

Do this before anything else, because it decides whether the C++ side can even consume this IR cleanly today.

**Deliverable for Phase 0:** a diagram (ASCII is fine) of the pipeline, from Idris source through the Idris2 phases used, the idris-mlir frontend steps, the emitted `idr` text, each C++ pass, and finally LLVM/GPU, with file references at each arrow.

---

## 2. Phase 1 — quantify the handoff IR

Write a small script (Python is fine) that parses or greps a full emitted module and reports the metrics below. Run it on (a) the self-hosting Idris compiler build that produced the dump and (b) one or two small programs.

| Metric | How to measure | Why |
|---|---|---|
| Total `func.func` count | count ops | baseline |
| Total op count, and count per op name | count ops | where the bulk is |
| `% idr.constant #idr.erased` of all ops | count | cost of not erasing in frontend |
| `% params` typed `!idr.q<zero, ...>` | parse signatures | same |
| Avg/max symbol name length (bytes) | measure `sym_name` | symbol table bloat |
| Total bytes in symbol names vs whole file | ratio | same |
| Specializations per base name | strip `[...]` suffix, then group and count | specialization explosion |
| Functions with **structurally identical bodies** modulo types | normalize: replace all `!idr.box<...>` with `!box`, strip names and locs, then hash | value of representation-keyed specialization |
| Functions whose body is a single `func.call`/`idr.apply` forwarder, or `return lambda { call }` | pattern match | dictionary/eta shim count |
| `idr.match` with exactly one case and no fields (e.g. `@MkUnit`) | pattern match | trivially foldable |
| `idr.match` whose `cases` list is shorter than its region count | compare | implicit default regions |
| `idr.delay` whose body is just `idr.yield %existing_value` | pattern match | useless thunks |
| `idr.lin.enter` / `idr.lin.use` count | count | linearity-cast overhead |
| Ops with `loc(unknown)` | count | lost source info |
| Binder names leaking into type keys, e.g. `{arg:NNNN}` in names | regex `\{arg:\d+\}` (mangled `$123$arg$58$`) | specialization-key bug (§3.6) |
| Unstable counters in names, e.g. `case block 10059` | regex `case\$32\$block\$32\$\d+` | cache/diff instability |

**Deliverable:** a table of these numbers for each input, plus the 20 most-specialized base names and the 20 largest equivalence classes of identical-modulo-box bodies.

---

## 3. Phase 2 — investigate each suspected problem

For **each** item below, report:

1. **Evidence**, with a short IR excerpt from the dump.
2. **Root cause**, with code location.
3. **Where it should be fixed**: frontend, C++ `idr.hi`→`idr.lo`, or a generic upstream pass. Include the reasoning and what information each location has.
4. **Estimated impact**, from the Phase 1 metrics.
5. **Risk**: correctness, and loss of info needed later (§7).

### 3.1 Zero-quantity (erased) arguments and fields still exist as values

**Evidence:** every function takes `!idr.q<zero, plain, none>` params, and every call site materializes them:
```mlir
%4 = "idr.constant"() <{value = #idr.erased}> : () -> (!idr.q<zero, plain, none>)
%5 = "func.call"(%4, ...) ...
```
Constructors also carry erased fields: `idr.con(%erased, %l, %k, %r) {ctor = @Branch2}`.

**Hypothesis:** the frontend knows quantities exactly and should drop them entirely from signatures, calls, constructor layouts, and pattern bindings.

**Questions:**
- Is there any consumer in C++ that needs zero-quantity values today? Grep for uses of the erased type or attribute.
- If dependent indices matter for GPU shapes (§7), they should travel as **compile-time attributes or types**, not as runtime SSA values of an "erased" type.

### 3.2 Newtype / single-constructor wrappers are not erased

**Evidence:** `Core` (`MkCore`), `IO` (`MkIO`), `ST` (`MkST`), `Namespace` (`MkNS`), and `SizeOf` (`MkSizeOf`, whose second field is erased) appear as real constructors, matches, and projections. Patterns like `idr.con @MkCore(%f)` are immediately followed by `idr.match %x {@MkCore(...)}` across functions.

**Hypothesis:** Idris2 has newtype handling. Data types with one constructor and one non-erased field should be represented as that field. This is a frontend/data-layout decision.

**Questions:**
- Does the backend bypass Idris2's newtype optimization? Why?
- After erasure, `Core a` = `World ->1 IORes (Either Error a)`. Should the handoff IR even mention `Core`?

### 3.3 Interface dictionaries and method shims are not resolved

**Evidence:** functions like these just return a curried lambda that forwards to the concrete implementation:
- `Prelude.Interfaces.map[..., Functor implementation at ...]`
- `Prelude.Interfaces.(>>=)[..., Monad implementation at Prelude.Types:234:1--237:23]`
- `Prelude.Interfaces.pure[...]`
- `Prelude.Interfaces.(<$>)[...]`
- `Prelude.EqOrd.(==)[OriginDesc, Eq implementation ...]`

Callers then `idr.apply` twice. In `Prelude.Show.primNumShow[...]`, the `>=` on `Prec` goes through `Prelude.EqOrd.(>=)[Prec, Ord implementation ...]` and `fromChar` is applied to a constant `45`.

**Hypothesis:** when the specializer has already fixed the implementation (it's in the mangled name!), the frontend should emit a **direct, saturated call** to the method implementation (e.g. `Prelude.Types.(>>={>>=_Monad_Maybe})`). It should not route through a curried shim.

**Questions:**
- Where are interface method calls lowered? Does the specializer know the concrete implementation at that point (evidence says yes)?
- How many shim functions exist (Phase 1 metric)?
- Can upstream `-inline` + a beta-reduction pattern clean these up instead? If so, is it worth keeping them at the handoff? Note that shims bloat the handoff and slow C++.

### 3.4 Currying and eta-expansion at the boundary

**Evidence:** functions return `idr.lambda` of `idr.lambda`, e.g. `fn<(A) -> fn<(B) -> C>>`, and callers immediately apply them. `fromBuf` builds a lambda and applies it to its own argument right away.

**Hypothesis:** the frontend knows the syntactic arity of each definition. Emit functions at their **full arity**, emit saturated calls directly, and only build closures for genuine partial application. This is classic arity analysis / uncurrying.

**Question:** does Idris2's lambda-lifted IR (`LiftedDef`, with `LApp`/`LUnderApp`/`LAppName`) already give this for free?

### 3.5 Specialization keyed on source types instead of representation

**Evidence:**
- `PrimIO.case block 949/928 in io_bind[...]` is instantiated for many payload types: `Either Error (List Doc)`, `Either Error Name`, `STRef (List (List SGR))`, `IORef String`, and more. The bodies are identical apart from types, and all the payloads are `!idr.box` pointers.
- `primNumShow` is emitted for Int8/Int16/Int32/Int64/Bits8/Bits16/Bits32/Bits64/Double. Int32 and Bits32 share `i32`, and so on.
- `WithBounds.bounds[...]`, `WithBounds.(.bounds)[...]`, `const[...]`, `map[...]`, and `treeInsert'` case blocks all repeat per type.

**Hypothesis:** specialization should be keyed on **runtime representation** (pointer vs `i8`/`i16`/`i32`/`i64`/`f64`/unboxed struct layout), not on Idris types. Specializing on types only pays when it changes representation, inlines a dictionary, or enables a fold.

**Questions:**
- What is the specialization key today? (Code location.)
- From Phase 1: how many functions collapse if boxed types are normalized?
- Does the GPU goal need type-specific specialization that a representation key would lose? See §7.
- Fallback option: keep type keys in the frontend, but have C++ run `-duplicate-function-elimination` after lowering `!idr.box<@X>` to a uniform pointer type. Note this pass is **`func.func`-only**.

### 3.6 Pi-binder names leak into specialization keys (likely bug)

**Evidence:** names like
`WithBounds[({arg:3640} : List Body) -> List1 Body]`
(mangled `$123$arg$58$3640$125$`) and
`Maybe[({arg:16547} : (Pair Name GlobalDef)) -> Core Bool]`.

**Hypothesis:** the key includes an auto-generated binder name. Two alpha-equivalent types therefore produce different keys, and so duplicate specializations and duplicate type definitions.

**Action:** confirm with a test, two functions whose types differ only in binder names. Fix by alpha-normalizing or erasing binder names in keys.

### 3.7 Laziness and `ifThenElse` not simplified

**Evidence:**
- `idr.delay() ({ idr.yield %15 })` wraps an already-computed value.
- `Prelude.Basics.ifThenElse[...]` is called with two `idr.delay` thunks.
- `(&&)` / `(||)` are called with lazy second args.
- `idr.force` sits inside lambdas that are created just to be applied (`(>>)` in `Maybe`).

**Hypothesis:**
- The frontend should inline `ifThenElse`, `&&`, and `||` into direct `match` on `Bool`.
- It should never emit `delay` around a value that is already evaluated.
- A `Lazy` argument to a function that is inlined should disappear.

**Question:** what does Idris2 itself do here (`%inline` on these Prelude functions)? Are those inline hints honored by idris-mlir?

### 3.8 Case-of-known-constructor and trivial matches

**Evidence:**
- `idr.match %10 {cases=[@MkUnit]}` (a match on `Unit`).
- `Data.So.choose` and `Core.TT.Var.locateIsVar` build `Left Oh` / `Right Oh` / `MkErased` proofs only to be matched or discarded.
- Matches on freshly built constructors appear after shims are inlined.

**Hypothesis:** proof-only data (`So`, `Erased`, equality proofs) should be erased in the frontend (to `Bool`/unit/nothing). Simple case-of-known-constructor should be done wherever the constructor is syntactically visible, which is often in the frontend.

### 3.9 Implicit default regions in `idr.match`

**Evidence:** `Libraries.Text.Parser.Core.mergeWith` has `cases = [@Res]` but two regions. `Libraries.Text.Bounded.mergeBounds` has `cases = [@True]` with two regions.

**Question:** is the second region an implicit default/fallthrough? Make it explicit in the op definition (a `default` region, with a verifier that regions = cases + optional default). Could this be what fails verification (§1.3)?

### 3.10 Linearity encoded as wrapper types → cast noise

**Evidence:** `idr.lin.enter` / `idr.lin.use` appear at nearly every IO boundary to convert between `T` and `!idr.q<one, plain, T>`.

**Options to compare:**
- **(a)** Keep the wrapper type, add canonicalizations for `enter(use(x))` → `x` and `use(enter(x))` → `x`.
- **(b)** Make linearity a property of uses: argument attributes plus a single-use verifier pass, with no wrapper type.
- **(c)** Have the frontend check linearity (it already typechecked it) and emit only what later passes need. For example, keep the world token as `!idr.world` and drop `q<one,...>` elsewhere.

**Question:** what does C++ actually do with linearity today, e.g. in-place update or uniqueness optimizations? That decides how much must survive the handoff.

### 3.11 Names: mangling, stability, length

**Evidence:**
- `$40$`-escaped symbols embedding full type arguments and full interface-implementation source locations, e.g. `TTC implementation at Core.Binary.Prims:240:1--248:22`.
- Unstable counters like `case block 10059`.

**Hypothesis:**
- MLIR accepts quoted symbol names (`@"Core.Core.pure[List (Name, Bool)]"`). Escaping is only needed when emitting object-file symbols.
- Specialization info belongs in attributes, not in symbol names.
- Symbols for generated case blocks should derive from a stable source (content hash or source span), not a global counter.

### 3.12 Stringly-typed types

**Evidence:** `!idr.data<@Prelude.Types.Either$91$Core.Core.Error$44$$32$Int$93$>`. The type arguments live **inside a symbol name**, so no pass can inspect them structurally.

**Hypothesis:** make the data type a parametric MLIR type, `!idr.data<@Either, [!Err, i64]>`. The type structure then becomes real. Aliases come from `OpAsmTypeInterface::getAlias` / `genMnemonicAlias`. Any pass that needs the payload type of `Either` stops parsing strings.

**Question:** does any C++ code currently parse these strings? Grep for it.

### 3.13 Locations

**Evidence:** nearly everything is `loc(unknown)`. The only real info is a function-level `loc("Core.Core.seqCore")` plus `fused<"library">[...]`.

**Hypothesis:** the frontend has `FC` spans and binder names. Emit:
- `FileLineColRange` (or `FileLineColLoc`) locations from `FC`.
- `NameLoc("x"(<file loc>))` on values that come from Idris binders. With `--mlir-use-nameloc-as-prefix`, the printer then names SSA values after Idris variables.
- A typed attribute for origin (library vs user) instead of a fused string.

### 3.14 `memref<T>` as the IORef representation

**Evidence:** `Data.IORef.Mut` shows up as `memref<!idr.str>` / `memref<!idr.box<...>>`.

**Questions:**
- Is a full memref descriptor (pointer, offset, sizes, strides) the intended representation for a single mutable cell?
- Does the element type implement the memref element-type interface?
- Would `!idr.ref<T>` or the upstream `ptr` dialect fit better?
- Is this a deliberate GPU-interop choice? If so, document it.

---

## 4. Phase 3 — C++ dialect hygiene (relevant regardless of where the boundary ends up)

Check and report each item. These decide how much "for free" cleanup upstream MLIR can do after the handoff.

- [ ] Ops that are side-effect free are marked `Pure`: `idr.constant`, `idr.con`, `idr.lambda`, `idr.match` without effectful bodies, projections.
- [ ] `idr.constant` is `ConstantLike` with a `fold`, so canonicalize dedupes and hoists constants.
- [ ] `idr.match`, `idr.lambda`, and `idr.delay` implement `RegionBranchOpInterface` where meaningful. This enables `-sccp`, `-control-flow-sink`, and `-remove-dead-values` (which removes dead function arguments and dead region args/results).
- [ ] An inliner interface exists for `idr` ops (`DialectInlinerInterface`), and the func inliner extension is registered.
- [ ] Every op has an `assemblyFormat` or custom printer/parser (no generic form in normal output).
- [ ] `OpAsmOpInterface` is implemented:
  - `getAsmResultNames`: `%nil`, `%just`, `%erased`, `%clo`
  - `getAsmBlockArgumentNames`: match regions named after constructor fields
  - `getAsmBlockNames`: `^Left` / `^Right`
- [ ] `OpAsmTypeInterface::getAsmName` on `!idr.world_carrier` returns `w`. `getAlias` (or `genMnemonicAlias`) is implemented on `idr` types.
- [ ] `DefaultValuedParameter` is used to elide default type params (e.g. `plain` in `!idr.q`).
- [ ] Canonicalization patterns exist for:
  - beta reduction: `apply(lambda)`
  - case-of-known-constructor
  - single-case/no-field match
  - `force(delay(x))` → `x`
  - `delay` of an evaluated value
  - `enter(use(x))` → `x`
- [ ] The pipeline uses upstream passes where applicable: `-inline`, `-canonicalize` (with `cse-between-iterations`), `-cse`, `-sccp`, `-remove-dead-values`, `-control-flow-sink`, `-symbol-dce`, `-duplicate-function-elimination` (func-only), with `-composite-fixed-point-pass` for the simplify loop.
- [ ] A decision is recorded on `func.func` vs a custom `idr.func`. A custom op enables `getDefaultDialect() = "idr"` (dropping the `idr.` prefix inside bodies), but loses `-duplicate-function-elimination` and the func inliner extension unless they're ported.

---

## 5. Phase 4 — propose the target handoff format

Write a short spec (one page) for what the frontend **should** emit. Then hand-write the target IR for **these exact functions from the current dump**, so before/after is concrete:

1. `Core.Core.pure[List (Pair Name Bool)]`
2. `Core.Core.(>>=)[...]` together with its `seqCore` / `case block 10059` / `io_bind` helpers. These should collapse into one function or disappear into callers.
3. `Libraries.Data.NameMap` `treeInsert'` split case blocks
4. `Prelude.Show.primNumShow[Int64]`
5. `Libraries.Text.Bounded.mergeBounds[Unit, Unit]`
6. `Libraries.Text.Parser.Core.mergeWith[...]`
7. `Data.So.choose` and its caller `Core.TT.Var.locateIsVar`'s case block

A starting sketch for the target style, to refine or reject with reasons:

```mlir
// Types are parametric and aliased; no data in symbol names.
!Err    = !idr.box<@Core.Core.Error>
!Name   = !idr.box<@Core.Name.Name>
!NB     = !idr.data<@Builtin.Pair, [!Name, i1]>
!NBList = !idr.box<@Prelude.Basics.List, [!NB]>

// Core a erased to World ->1 IORes (Either Error a) — no MkCore.
// No zero-quantity params. Quoted readable symbols. Real locations.
// SSA names from Idris binders via NameLoc.
idr.func private @"Core.Core.pure[List (Name, Bool)]"(%xs: !NBList)
    -> !idr.fn<(!idr.world) -> !idr.iores<!idr.either<!Err, !NBList>>>
    attributes {idr.total, idr.spec = {base = @Core.Core.pure, args = [!NBList]}} {
  %k = lambda (%w: !idr.world) {
    %r   = con @Right(%xs) : !idr.either<!Err, !NBList>
    %res = con @MkIORes(%r, %w)
    yield %res
  }
  return %k
} loc("src/Core/Core.idr":712:1 to 712:40)

// Interface methods resolved to direct saturated calls; Bool as i1;
// ifThenElse / && inlined into match; no curried shims.
idr.func private @"Prelude.Show.primNumShow[i64]"(
    %show: !idr.fn<(i64) -> !idr.str>, %d: !Prec, %x: i64) -> !idr.str {
  %s   = apply %show(%x)
  %ge  = call @"Prelude.Show.Ord_Prec.>="(%d, %prefixMinus) : (!Prec, !Prec) -> i1
  %neg = match %ge : i1 {
    ^True  { %c = call @"Prelude.Show.firstCharIs"(%isMinus, %s) : (...) -> i1
             yield %c }
    ^False { %f = arith.constant false
             yield %f }
  }
  %out = call @Prelude.Show.showParens(%neg, %s) : (i1, !idr.str) -> !idr.str
  return %out
}
```

The spec must state, for each property, whether it's guaranteed by the frontend (an invariant the C++ verifier can check) or best-effort:

- [ ] No zero-quantity values anywhere.
- [ ] No newtype constructors.
- [ ] No unresolved interface shims when the implementation is statically known.
- [ ] Functions at full arity; closures only for real partial application.
- [ ] Specialization keyed on representation, or on type where justified; keys alpha-normalized.
- [ ] Data types parametric, not stringly typed.
- [ ] Symbols readable and stable; specialization metadata in attributes.
- [ ] Locations and binder names present.
- [ ] `match` regions explicit, including default.
- [ ] Linearity representation decided (§3.10).
- [ ] Laziness only where semantically required.

---

## 6. Phase 5 — frontend vs C++ decision matrix

Fill in this table. "Info available" means the facts needed to do it correctly and cheaply.

| Transformation | Info available in frontend? | Info available in C++? | Upstream MLIR pass exists? | Recommended home | Reason |
|---|---|---|---|---|---|
| Erase zero-quantity args/fields | | | | | |
| Newtype erasure | | | | | |
| Resolve interface method shims | | | partial (`-inline`) | | |
| Arity / uncurrying | | | no | | |
| Representation-keyed specialization | | | partial (`-duplicate-function-elimination`) | | |
| Alpha-normalize specialization keys | | | no | | |
| Inline `ifThenElse`/`&&`/`\|\|`, drop trivial `delay` | | | partial | | |
| Proof-type erasure (`So`, `Erased`, `=`) | | | no | | |
| Case-of-known-constructor | | | canonicalize pattern | | |
| Dead argument removal | | | `-remove-dead-values` | | |
| Constant dedupe/hoist | | | canonicalize (`ConstantLike`) | | |
| Duplicate function elimination | | | `-duplicate-function-elimination` | | |
| Unreachable symbol removal | | | `-symbol-dce` | | |
| Linearity checking | | | no | | |
| Source locations / binder names | | | n/a | | |
| Readable / stable symbol names | | | n/a | | |
| Lowering to `scf`/`cf`/`llvm`/`gpu` | | | yes | C++ | |

Default heuristic, to override with evidence: **if it needs Idris types, quantities, interface resolution, or source info, it goes in the frontend. If it's a generic graph/dataflow optimization that upstream MLIR already implements, it goes in C++ and you implement the interfaces.**

---

## 7. Constraints from the project's goals: don't erase what the GPU path needs

The project aims at **dependently typed, GPU-shaped workloads**. Before moving erasure or representation decisions into the frontend, check which "erased" information later stages may need:

- **Static sizes/indices** (e.g. `Vect n a` lengths, `Fin n` bounds, matrix dims). These are zero-quantity at runtime but valuable for shape inference, bufferization, tiling, and bounds-check elimination. Candidate representation: types or attributes on values (`!idr.vect<?, T>` with an index attribute, or a shape attribute), **not** runtime SSA values.
- **Totality** (`idr.total`). Useful for speculation, hoisting, and GPU kernels that must terminate. Keep it as an attribute.
- **Linearity / uniqueness.** Enables in-place updates and buffer reuse, which matters a lot for GPU. Decide how it survives (§3.10).
- **Purity / effects.** Needed to know what can be outlined into a kernel.
- **Data layout** of unboxed records. Needed for structs of arrays vs arrays of structs.

**Deliverable:** a list of facts that must cross the handoff boundary even after the cleanup, with a proposed representation for each.

---

## 8. Experiments to run (cheap, informative)

1. **Upstream-only baseline.** Without changing the frontend, add the interface/trait work from §4 (traits, folder, inliner interface) and run `inline, canonicalize, cse, sccp, remove-dead-values, symbol-dce, duplicate-function-elimination` on the current handoff IR. Re-run the Phase 1 metrics. This shows how much C++ alone can recover.
2. **Frontend erasure prototype.** Make the frontend drop zero-quantity params/args/fields and newtype wrappers, behind a flag. Re-run the metrics.
3. **Representation-keyed specialization prototype.** Behind a flag, normalize boxed types in the specialization key. Count functions before and after.
4. **Alpha-normalization test.** Construct two alpha-equivalent types and confirm they currently produce two specializations (§3.6).
5. **Compile time.** Measure C++ pipeline time on the full module before and after experiments 2 and 3. Smaller handoff IR should speed up every later pass.

For each experiment, record function count, op count, file size, C++ pipeline time, and whether the result verifies.

---

## 9. Report template (write this before changing code)

```markdown
# Handoff Investigation Report

## Summary (5 bullets max)

## Pipeline map
<diagram + file references>

## Generic-form root cause
<flags vs verification failure; failing op if any>

## Metrics
<Phase 1 table for each input; top-20 lists>

## Findings
### 3.1 Erased args — evidence / root cause / recommended home / impact / risk
### 3.2 ...
...

## Experiments
<results table>

## Decision matrix
<filled §6 table>

## Facts that must cross the boundary (GPU path)
<§7 list>

## Proposed handoff spec
<one page + hand-written target IR for the 7 functions in §5>

## Recommended plan
<ordered steps, each with: change, location, expected metric delta, risk, test>

## Open questions for the author
```

---

## 10. Ground rules

- Cite file paths and line ranges for every claim about the code.
- Quote short IR excerpts as evidence. Never paraphrase IR from memory.
- Separate **observed** facts from **hypotheses**, and label them.
- If something in this brief turns out to be wrong about the codebase, say so plainly and correct it. This brief was written from one IR dump without access to the code.
- Prefer flags or prototypes over in-place rewrites until the report is reviewed.
