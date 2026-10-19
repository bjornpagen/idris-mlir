<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## F — a function's facts are checked against its body; owned values fill their slots; the reducer reduces inside regions on the reserved stack
Findings: F02, F06, F07, F22
Owner / exclusive writes: `foreign/idr/include/idr/IR/**`, `foreign/idr/lib/IR/**`, `foreign/idr/tools/idris-mlir-reduce.cpp`, `foreign/idr/lib/Analysis/Effects.cpp`, `foreign/idr/include/idr/Analysis/Effects.h`; excludes `foreign/idr/include/idr/IR/IdrStringOps.td`, `foreign/idr/include/idr/IR/CMakeLists.txt`, `foreign/idr/lib/IR/OpsStrings.cpp`, `foreign/idr/lib/IR/Fold/Strings.cpp`, `foreign/idr/lib/IR/CMakeLists.txt`. Read-only for you: `foreign/idr/include/idr/Support/Stack.h`, `PINS.md`, and every test.
Read first:
- **Packet:** README §3 F02, F06, F07; §4.3 (but see the corrections under Fixed decisions); §5 (reduction row).
- **F02, the facts and the verifier:**
  - `foreign/idr/include/idr/IR/IdrOps.td:91-149`: the comment on the facts, then `Idr_FuncOp`. `total` and `no_inline` are `UnitAttr`s; `effects` is `DefaultValuedOptionalAttr<Idr_EffectAttr, "::idr::anyEffect">`; `absorb` is at line 134.
  - `foreign/idr/include/idr/IR/IdrAttrs.td:205-224`: the `Effect` bit enum (`none`, `io`, `crash`, `diverge`), with operators `| & ~` and `bitEnumContainsAll`.
  - `include/idr/IR/IdrDialect.h:49`: `anyEffect`.
  - `foreign/idr/lib/IR/Func/Func.cpp:104-115`: `FuncOp::verify`, which only rejects the default stored explicitly.
  - `foreign/idr/lib/IR/Verify/Program.cpp:222-275`: `verify::program`, which the program's `verifySymbolUses` runs once per module verification, on one thread, after every op is verified (`Func.cpp:53-60`).
  - `foreign/idr/lib/Analysis/Effects.cpp:41-58`: `bodyOf`, the solver's rule for what a body does of itself. Its own part: `diverge` unless `getTotal()`; `io` if any argument type `holdsWorld`; `crash` for a `MayCrashOpInterface` op with a `getCrashCause()`; `io` for `WorldNewOp`; then the callees of its `idr.call`s. `include/idr/Analysis/Effects.h:46-56` states it.
- **The writers of `total` and `no_inline`:**
  - `compiler/src/IdrisMLIR/Emit/Declarations.idr:53-58`: `total' = f.facts.terminating`, and `noInline` for a lazy constant of arity 0.
  - `compiler/src/IdrisMLIR/Emit/Closures.idr:89-93`: lambda and delay functions are always `total`: "it has no loop of its own".
  - `foreign/idr/lib/Transforms/Defunctionalize/Forces.cpp:39-46`: force functions are given `total`.
  - `Inline/Inline.cpp:63` and `Optimize/Contify.cpp:97`: `absorb`.
  - `Tail/Loop.cpp:122-124` and `Tail/WhileDo.cpp:283-285`: `idr.may_loop` only where `!getTotal()`.
- **F06, the grades:**
  - `foreign/idr/include/idr/IR/Grades.h:60-68`: `owned`, `view`, `atQuantity`.
  - `foreign/idr/lib/IR/Grades.cpp:82-94`: `view` now gives `borrow` for a type of ours; bfdcac70 changed it from plain.
  - The four sites that compare a value against a slot declared plain through `view`:
    - `lib/IR/OpsCon.cpp:135-153` (`ConOp::verify`, loop at 146-150);
    - `lib/IR/OpsArrays.cpp:32-39` (`verifyElement`, called at :54, :126, :132, :138);
    - `lib/IR/OpsGenerating.cpp:54-71` (`verifyEnd`, line 67);
    - `lib/IR/OpsOwnership.cpp:32-37` (`DupOp::verify`, whose operand is `Idr_ViewType`: plain or borrow, `IdrOwnershipOps.td:50`).
  - `OpsOwnership.cpp:27` (`movesAs`) compares `view` with `view` and is correct.
- **F07, the reducer:**
  - `foreign/idr/tools/idris-mlir-reduce.cpp:1-38` and `foreign/idr/tools/idris-mlir-opt.cpp:37-114` (the reserved-stack runner pattern).
  - `foreign/idr/include/idr/Support/Stack.h`; `runtime/idris_rt.h:405-421` (`idris_rt_run_on_stack`); `PINS.md:274-293` (`mlir-recursion`: "idris-mlir-reduce does not have it").
  - `.toolchain/llvm-project/mlir/include/mlir/Reducer/{ReductionPatternInterface.h,DialectReductionPatternInterface.td}`.
  - `.toolchain/llvm-project/mlir/lib/Reducer/ReductionTreePass.cpp`: lines 36-73 (`applyPatterns`); 186-205 (phase 2 erases ops and drops their uses; phase 3 applies the dialects' patterns to ops it keeps); 214-226 (the patterns are gathered from every loaded dialect's interface).
  - `lib/Reducer/Tester.cpp` (a candidate that fails to verify is uninteresting).
  - `lib/Tools/mlir-reduce/MlirReduceMain.cpp:66` (it constructs its own `llvm::InitLLVM`).
  - `mlir/lib/Dialect/Func/Extensions/InlinerExtension.cpp:89` (`dialect->addInterfaces<...>()` from a registry extension).
  - `tests/reduce-regions/reduce-regions.mlir` (the counterexample).
Permitted outcome:
- **Mandatory (F02):**
  - The program verifier refuses an `idr.func` whose declared `effects` do not cover its body, as an internal error naming the function, its declared set and the uncovered bits.
  - The body's own part is one function in `lib/IR` that the solver also calls; you make that edit in `lib/Analysis/Effects.cpp`, which you own.
  - `Idr_FuncOp` gets an ODS `description` stating where `total`, `no_inline`, `effects` and `instance` come from, as the source has them.
- **Mandatory (F06):** one Grades.h rule, `atPermission`, used at the four sites.
- **Mandatory (F07):** a `DialectReductionPatternInterface` for idr, registered by idris-mlir-reduce, and idris-mlir-reduce running on the reserved stack.
- **Named consumer adaptations, all outside your writes and so returned as text:**
  - PINS.md;
  - the fixtures listed under Handoff.
- **Optional:** none.
- **Later:** a verifier rule relating `total` to callees, if the owner wants one under some other meaning of `total` (see the contradiction below).
Fixed decisions:
- **`bodyEffect`.** Declare `idr::Effect idr::bodyEffect(idr::FuncOp fn);` in `include/idr/IR/Func.h` and define it in `lib/IR/Func/Func.cpp`. It is exactly `bodyOf`'s own part. The comment: "What `fn`'s body does of itself, its calls aside: not return unless Idris proved it total; perform IO where a parameter may hold a world or the body forges one; crash where an op may crash. The one rule: idr-effects' solve and the program's verifier both read it."
- **The effects rule (§4.3).**
  - Required set of a function: `bodyEffect(fn)`, plus `callee.getEffects()` for each `idr::CallOp` in its body (a callee without `effects` reads as `anyEffect` through its accessor; a callee the table does not find counts as `anyEffect`), plus `anyEffect` for each `idr::ApplyOp` and `idr::ForceOp`, whose callee is a value.
  - Checked only on a function whose `getEffectsAttr()` is non-null; a function with no attribute declares everything.
  - Violation: `!bitEnumContainsAll(fn.getEffects(), required)`, reported as `fn.emitOpError("declares the effects ") << stringifyEffect(declared) << ", which do not cover what its body may do: " << stringifyEffect(required & ~declared)`. This is an internal error, never `refuse`.
- **The `total` contradiction.** §4.3's "the verifier refuses `total` on a function whose body calls one that is not" contradicts the source. In this compiler `total` means "every loop of this body's own ends": `Effects.cpp:47` adds `diverge` for a missing `total`, and takes callees' divergence from their effects. The frontend gives every lambda and delay function `total` while their bodies may call partial functions (`Closures.idr:89-93`). idr-defunctionalize gives force functions `total` while they call labels that need not be total (`Forces.cpp:39-46`). A total specialization calls a partial lambda once applies are dispatched. So the rule would refuse valid frontend output at the first verification. **Do not implement it.** State the meaning in the description instead.
- **The provenance contradictions.** §4.3's "`total` comes only from the frontend; no other pass sets either" and "`no_inline` from idr-optimize's capped callees" also contradict the source. idr-defunctionalize sets `total` on force functions; nothing in `lib/Transforms/Optimize/` sets `no_inline` (its "capped" is only a count). The description states the source's provenance.
- **The ODS description.** It replaces the `//` block at `IdrOps.td:91-106` (moved into `let description = [{ ... }]` on `Idr_FuncOp`, not duplicated) and adds:
  - **`total`:** written by the frontend where Idris proved every loop of the body terminating, and on a lambda's or delay's function, which has no loop of its own; written by idr-defunctionalize on each force function, whose body is a match and calls. A copy keeps it, and `absorb` clears it when a body takes in a callee without it (inlining, contification). No other pass writes it. A call of a function without it is no loop of the caller's own.
  - **`no_inline`:** written only by the frontend, on a function of no parameters whose result is lazy, whose cell every use shares.
  - **`effects`:** by default everything, whose one form is absence. A solve (idr-effects, idr-optimize's ready set) writes it, and a stale value says too much, never too little. The program's verifier holds that it covers the body's own part, its callees' effects, and (before idr-defunctionalize) everything for an apply or a force.
  - **`instance`:** as the frontend wrote it.
- **`atPermission`.** Declare `mlir::Type idr::atPermission(mlir::Type type, Permission permission);` in `Grades.h` right after `atQuantity`. Define it in `Grades.cpp` as `graded({gradeOf(type).quantity, permission}, unrestricted(type))`. It keeps the quantity, which is Idris's, and sets the permission. Extend the Grades.h comment at 60-64 to say so.
- **The four uses.**
  - **ConOp:** a field value is accepted iff `value == expected`, or `isOwned(value)` and `value == atPermission(expected, gradeOf(value).permission)`. A borrow never fills a field: what a cell holds, it owns.
  - **verifyElement:** `type == atPermission(elem, gradeOf(type).permission)`, which is any permission, as its comment and that of `verifyUpdate` (`OpsArrays.cpp:42-44`) say.
  - **verifyEnd:** for a graded position, `value == atPermission(type, gradeOf(value).permission)`.
  - **DupOp:** `getValue().getType() == atPermission(getType(), gradeOf(getValue().getType()).permission)`, which accepts plain static data as well as a borrow; `Idr_ViewType` already bounds the permission.
- **F06 is a real defect, wider than reported.** At HEAD, `view(plain !idr.str)` is `!idr.q<many, borrow, !idr.str>`. So `verifyElement` refuses every plain element of a type of ours, in every stage: an `idr.array.get` of a `memref<?x!idr.str, #idr.world>` fails. `ConOp` refuses every owned field (README counterexample). `DupOp` refuses a plain static operand.
- **The reducer's interface.** Implement it in `tools/idris-mlir-reduce.cpp`, in an anonymous namespace; a new file under `lib/IR` would need a coordinator CMake edit and could not be typechecked here. It is registered by a registry extension, so no other tool carries the Reducer headers.
  - **Pattern `PoisonResults`:** a `RewritePattern(MatchAnyOpTypeTag(), /*benefit=*/1, ctx)` that matches an op with at least one result, no regions, that is not `ub::PoisonOp`, and that has an `idr::FuncOp` ancestor. It replaces each result with `ub::PoisonOp::create(rewriter, op->getLoc(), type)` through `rewriter.replaceOp`. The UB dialect loads with idr (`IdrBase.td:66-67`).
  - **Interface `IdrReductionPatterns`:** derives from `mlir::DialectReductionPatternInterface`, has an explicit public constructor `IdrReductionPatterns(mlir::Dialect *dialect) : DialectReductionPatternInterface(dialect) {}`, and its `populateReductionPatterns` adds `PoisonResults`.
- **The reserved stack.** idris-mlir-reduce runs on the reserved stack exactly as idris-mlir-opt does: an `Invocation{argc, argv, status = 1}`; `reduceMain(void *)` does today's registrations plus the extension, makes the context and sets the status from `mlirReduceMain`; `main` calls `idris_rt_gmp_init()` then `idris_rt_run_on_stack(reduceMain, &invocation, idr::support::toolStack, idr::support::toolStackGuard, exhausted)`. Add no `llvm::InitLLVM`: `mlirReduceMain` makes one. Messages: `idris-mlir-reduce: the stack is exhausted` (with `_exit(1)` from the handler) and `idris-mlir-reduce: no stack could be reserved` (return 1). The header comment gains `PIN(mlir-recursion)`.
Inputs: §4.3, as corrected above. Nothing from a sibling's body.
Outputs:
- `idr::bodyEffect(FuncOp)` in `Func.h`, consumed by your verifier and by `lib/Analysis/Effects.cpp` (yours).
- `idr::atPermission(Type, Permission)` in `Grades.h`, consumed by your four sites.
- The ODS description on `idr.func`.
- An idr reduction interface, seen by `mlir-reduce`'s `ReductionTreePass` in idris-mlir-reduce.
Implement:
- F22 (one small range): `foreign/idr/include/idr/IR/Ranges.h:23-24` defines the small integer range a second time; `runtime/Big/Big.h:22-23` holds the runtime's. Lane R3 adds `IDRIS_RT_SMALL_MIN` and `IDRIS_RT_SMALL_MAX` to `runtime/idris_rt.h` (packet §3 F22, fixed now, so write against those names). Make `Ranges.h` take its bounds from them (it may include `idris_rt.h`, which `foreign/idr` already reads for the runtime ABI) and delete its own two constants.
1. **`Func.h` and `Func.cpp`.** Add `bodyEffect` as fixed above. `Func.cpp` already includes `Grades.h` (`holdsWorld`) and `IdrDialect.h` (`MayCrashOpInterface`, `WorldNewOp`). Walk with `fn.getBody().walk`, as `bodyOf` does.
2. **`Verify/Program.cpp`.** Include `idr/IR/Func.h`. Add a static `LogicalResult effectsCovered(ProgramOp program)`: build one `SymbolTable symbols(program.getOperation())`, and for each `FuncOp fn : program.getOps<FuncOp>()` with a declared `effects`, compute the required set and report as fixed. In `idr::verify::program`, call it right after `rootType(root)` succeeds, and return failure if it fails. It runs at every stage that has an `idr.func`: higher, first and owned. Extend the file's header comment and `include/idr/IR/Verify.h`'s comment on `program` with one sentence each: the declared effects cover the body.
3. **`IdrOps.td`.** Move the facts comment into `let description` and add the provenance as fixed. Run `make typecheck-tblgen` and `make typecheck-dialects` to confirm ODS still generates.
4. **`Grades.h` and `Grades.cpp`.** Add `atPermission` and the comment line.
5. **The four sites.** Rewrite each as fixed. The error text of each stays as it is.
6. **`tools/idris-mlir-reduce.cpp`.** Rewrite it as fixed. It also includes:
   - `idr/Support/Stack.h`;
   - `mlir/Reducer/ReductionPatternInterface.h`;
   - `mlir/Dialect/UB/IR/UBOps.h`;
   - `mlir/IR/PatternMatch.h`;
   - `<unistd.h>`.
   
   The extension is `registry.addExtension(+[](mlir::MLIRContext *, idr::IdrDialect *dialect) { dialect->addInterfaces<IdrReductionPatterns>(); });`. idris_rt is already linked through IdrIR.
7. **Check.** `python3 tools/check-units.py foreign/idr/lib/IR/Verify/Program.cpp foreign/idr/lib/IR/Func/Func.cpp foreign/idr/lib/IR/Grades.cpp foreign/idr/lib/IR/OpsCon.cpp foreign/idr/lib/IR/OpsArrays.cpp foreign/idr/lib/IR/OpsGenerating.cpp foreign/idr/lib/IR/OpsOwnership.cpp foreign/idr/tools/idris-mlir-reduce.cpp`, then `make typecheck-tblgen` and `make typecheck-dialects`.
Delete:
- The `view(...) == expected` and `view(...) != ...` comparisons at the four sites.
- The `//` comment block at `IdrOps.td:91-106`, which moves into the description.
- `idris-mlir-reduce`'s direct run on the process stack.
- The solver's inline copy of the own part in `lib/Analysis/Effects.cpp` (`bodyOf`'s own part), replaced by a call to `bodyEffect`, so that it is the one rule.
NOT TO DO:
- No verifier rule about `total` and callees, and none about `no_inline`.
- No change to `lib/Transforms/**`, the frontend or any test file; their changes are handoff text. (`lib/Analysis/Effects.cpp` and its header are yours.)
- No reduction pattern beyond `PoisonResults` (no match-to-region rewrite, no type simplification).
- No reducer for the LLVM half: that is `llvm-reduce`.
- No change to `idris-mlir-opt.cpp` (K1's) or `Stack.h`.
- Do not "fix" `movesAs`.
- Do not touch `IdrStringOps.td`, `OpsStrings.cpp` or `Fold/Strings.cpp` (P's).
Stop and return: Return when steps 1-6 are in and step 7's checks pass, with every hub text written out. If `make typecheck-dialects` shows that an Idris-side file is generated from the op description (and so changes), return that as a seam rather than editing `compiler/`.
Acceptance:
- F22: no definition of the small range's bounds remains under `foreign/idr`; `grep -rn` for the old constants' names in `foreign/idr` finds only uses of `IDRIS_RT_SMALL_MIN`/`IDRIS_RT_SMALL_MAX`; your units pass `tools/check-units.py`.
- **F02:**
  - Input: the module from F02's counterexample, `idr.func @f() attributes {total, effects = #idr.effects<none>}` whose body has an `idr.io.put_str` on a world parameter. Outcome: `idris-mlir-opt` exits 1 with `'idr.func' op declares the effects none, which do not cover what its body may do: io`. At HEAD it verifies.
  - Input: a function declaring `crash` that calls one declaring `io`. Outcome: refused, naming `io`.
  - Input: a function that declares no `effects`. Outcome: never refused by this rule.
  - Input: a module after `--idr-effects` (the solver). Outcome: always accepted, since the required set equals `bodyOf`'s by construction once the solver calls `bodyEffect`.
- **F06:**
  - Input: `idr.con !idr.own<!P> @P(%s : !idr.own<!idr.str>)` in an owned program. Outcome: verifies (at HEAD it fails with `field has type ... expected !idr.str`).
  - Input: `idr.con` with a `!idr.q<many, borrow, !idr.str>` field. Outcome: still refused.
  - Input: an `idr.array.get` of `memref<?x!idr.str, #idr.world>` giving `!idr.str` at the first stage. Outcome: verifies (at HEAD it fails).
- **F07:** running `tests/reduce-regions/reduce-regions.mlir`'s command leaves no `arith.addi`, `arith.subi` or `arith.constant` inside the matches' regions; they become `ub.poison`. At HEAD every op stays. A module nested deeper than the process stack allows runs the reducer, not a SIGSEGV.
- **This machine:** check-units on the eight units, plus `make typecheck-tblgen` and `make typecheck-dialects`.
- **Only the owner's build:** every fixture's behaviour, including the consumer fixtures under Handoff, which will fail until the coordinator or X1 adapts them.
Tempting partial solution:
- **F06 at one site.** Fixing `ConOp::verify` alone, by replacing `view(x) == expected` with `unrestricted(x) == expected`. That drops the quantity: it would let a `many` value fill a linear field. It also leaves arrays and dups broken. Acceptance requires one rule that keeps the quantity, at all four sites.
- **F02 by op resources.** Checking effects through the IO, crash and divergence resources of `ownEffects`. That refuses the solver's own output: a crash also writes the IO resource (`IdrDialect.h:154-170`), and `idr.handle.string` reads IO with no world (`IdrPlatformOps.td:346-353`). Only `bodyOf`'s rule, held once, agrees with idr-effects.
Escalate if:
- `lib/Analysis/Effects.cpp`'s solver cannot call `bodyEffect` without changing what it computes: report the exact difference, and do not keep two copies of the rule.
- The owner insists on §4.3's `total` rule as written.
- A fifth site compares against a plain slot through `view`.
- `addInterfaces` from an extension does not reach `ReductionTreePass`'s collection.
Handoff:
- **Shape (per parts/common.md):** changed paths, each mapped to an obligation; contracts supplied; consumer adaptations made; hub text the coordinator must apply; checks actually run with their results, or NotRun; unresolved seams, each with its evidence.
- **Hub requests:**
  1. Your own edit, not a hub request, in `foreign/idr/lib/Analysis/Effects.cpp`: add `#include "idr/IR/Func.h"`. In `bodyOf`, replace the `!fn.getTotal()` and `holdsWorld` lines and the `MayCrashOpInterface` and `WorldNewOp` branches of the walk with `body.own = idr::bodyEffect(fn);`, keeping only the `idr::CallOp` branch in the walk. Point the comment above `bodyOf` at `bodyEffect`.
  2. `PINS.md`, `mlir-recursion`: in the workaround, say "idris-mlir runs the whole compilation, and idris-mlir-opt and idris-mlir-reduce their runs, on the runtime's reserved-stack runner", and delete "idris-mlir-reduce does not have it".
- **Consumer fixtures (X1's; the coordinator routes them).** Each new fixture carries a first-line `NEEDS-ACCEPTANCE`. Give the full text for:
  - a new `tests/verify-effects/verify-effects.mlir` (`-split-input-file -verify-diagnostics`), with four chunks: IO under `none`; a crash callee under `none`; a non-total function declaring `none`; and a covered pair that verifies. Take op syntax from `tests/effects-io/effects-io.mlir` and `idr-effects.mlir`.
  - a new `tests/verify-con-owned-field/verify-con-owned-field.mlir`: an owned field verifies; a borrow field is refused with `field has type`.
  - `tests/reduce-regions/reduce-regions.mlir`: `// CHECK-NOT: arith.` and its comment rewritten.
- **Breakage to report:**
  - `tests/dedup-keep-apart/dedup-keep-apart.mlir:18,22`: `@A.eff` and `@B.eff` declare no `diverge` without `total`, and need `total`.
  - `tests/canon-facts/canon-facts.mlir:36`: `@applies` declares `crash, diverge` over an `idr.apply`, and needs `io` too, or no attribute.
  - `tests/idr/ownership/consumed-effects.mlir:20-24`: `@plain` stores a borrow into a con field, which every version of the rule refuses, so the fixture fails at parse.
