# U07 — The Idris side writes regions: lambdas, delays and region primitives

Mandatory findings: F-clo-6 F-prim-2

## Permitted outcome

1. **Lambdas and delays as regions.** `Term.Lam` and `Term.Suspend`
   carry their bodies with free variables, not a label and a capture
   vector. Emit writes them as `idr.lambda` and `idr.delay` regions that
   use enclosing values directly (C4.1, C4.2). Closure conversion and
   lambda lifting leave the Idris side. Mandatory.
2. **One region node.** `ArrayGen` and `ArrayFold` become the one
   generic `Region` constructor over the generated `IdrRegionPrim`, and
   Emit has one case for it. Mandatory.
3. **`Term.Effect` over `IdrPrim`** (C8.3, review R10). It becomes
   `Effect : Loc -> IdrPrim -> List Ty -> List (Term a) -> DataId -> Term a`,
   and the frontend fills its `List Ty` from the call. Mandatory.
4. **The primitives that became `Op`** (C8.3). `Terms.idr` builds
   `Op NatToBig`, `Op NatFromBig` and `Op StrPack` or `Op StrConcat`
   where it built `NatToBig`, `NatFromBig` and `StrBuild`, which leave
   `Prim` (U17). Mandatory.

## Owner / exclusive writes

- `CS/Term.idr`
- `CS/Ids.idr`
- `CS/Emit/Bodies.idr`
- `CS/Emit/Declarations.idr`
- `CS/Emit/Monad.idr`
- `CS/Frontend/Translate/Terms.idr`
- `CS/Frontend/Translate/Closed.idr`
- `CS/Emit/Attributes.idr`
- `CS/Emit.idr`, `CS/Frontend/Translate/State.idr` and
  `CS/Frontend/Translate/Cases.idr`, for what closure conversion leaves
  there: `Emit.idr`'s lifted functions, `State.idr`'s labels, and
  `Cases.idr`'s `Ord a` constraints and label comment (README S6)

**Excluded:**

- `CS/Types.idr` and `CS/Emit/Operations.idr`, which are U17's: it
  generates `IdrRegionPrim` and `regionArity`, and removes `ArrayLoop`.
- `CS/Dialect/Idr.idr`, which is generated.
- The registry and `CS/Frontend/Translate/Hooks.idr`, which are U18's
  (`Hook.IOCall` carries an `IdrPrim`).
- `foreign/idr/tools/idris-mlir-tblgen.cc`, U17's.

## Read first

- `contracts.md` C4.1, C4.2, C4.3 step 4, C4.4, C8.2, C8.3 and C13.
- `review.md` R10.
- `findings.md` F-clo-6 and F-prim-2.
- `CS/Term.idr`, all of it: `Lam`, `Suspend`, `ArrayGen`, `ArrayFold`,
  `TermF`, `hmap`, `para`, `lam`, `delay`, the printer.
- `CS/Emit/Bodies.idr`: `lifted`, `inFunction`, `epilogue`, and the
  `LamF` and `SuspendF` cases, and the two array-loop cases.
- `CS/Emit/{Declarations,Monad}.idr`, wherever `lifted` is read.
- `CS/Frontend/Translate/{Terms,Closed}.idr`, wherever `lam`, `delay`,
  `Lam`, `Suspend` or the array loops are built.
- `CS/Ids.idr` (`Label`).
- `CS/Emit/Attributes.idr` (`inherited`, `own`, `lifted`).
- `CS/Term.idr`'s `Effect` and `CS/Frontend/Translate/Terms.idr`'s
  `ioCall` and array case.

## Fixed decisions

- **The constructors:**

  ```idris
  Lam : Loc -> Binder -> Term (Under 1 a) -> Term a
  Suspend : Loc -> Term a -> Term a
  Region : {k : Nat} -> Loc -> (prim : IdrRegionPrim) -> (types : List Ty)
        -> List (Term a) -> Term (Under k a) -> DataId -> Term a
  ```

  with `k = regionArity prim`. `types` carries what `ArrayGen` carries
  (the element type) and what `ArrayFold` carries (the element and the
  accumulator), in that order.
- **What Emit writes:**
  - `LamF` writes `idr.lambda : !idr.fn<(A) -> (B)>`, with one block
    argument for the binder. The body's result is yielded with
    `idr.yield`. A body that never returns ends in `ub.unreachable`.
  - `SuspendF` writes `idr.delay : !idr.lazy<T>` the same way, with no
    block argument.
  - The region op's location is the lambda's.
  - Emit no longer creates any function for a lambda or a suspension.
- **Attributes.** What a lifted function got is fixed in C4.3 step 4:
  `idr.break_last` when the enclosing function has it, and `idr.total`
  always. `idr-isolate` (U08) gives them. `Emit/Attributes.idr`'s
  `lifted` and `inherited` go; `own` keeps its meaning with
  `inherited`'s one line inlined.
- **`Effect`'s types.** The `List Ty` holds the type arguments today's
  `IOOp` constructors carry: `[e]` for an array primitive, `[t]` for
  `BufferLoad t` and `BufferStore t`, `[]` otherwise. `Terms.idr` reads
  them from the call, as it does today. No table.
- **Emit's effect case.** `Emit/Bodies.idr`'s `EffectF` case calls U17's
  `effect : Index -> Loc -> IdrPrim -> List Ty -> List Val -> DataId -> E (Maybe Val)`
  (C8.3) and nothing else.
- **The generic region case.**
  - Operands are emitted as the two array-loop cases emit them
    today.
  - The region has `regionArity prim` block arguments, typed as the old
    cases type them.
  - The op is built with the generated
    `regionOp prim operands region resultTypes`.
  - The `IORes` instance is built from the results, as today.

## Inputs

- `IdrRegionPrim`, `regionArity` and `regionOp` (generated, C8.2).
- `IdrPrim` (generated) and `effect` from `Emit/Operations.idr` (U17,
  C8.3).
- `Prim`'s `Op IdrPrim` (U17), and U18's `Hook.Builds`, which carries
  the `IdrPrim` of the string it builds (C8.3).
- `Idr.lambdaOp` and `Idr.delayOp` from the generated mirror (C1.1
  item 4).

## Outputs

- The new `Term` and `TermF`, and Emit writing regions.

## Implement

- **`Term.idr`.** Change the constructors, `TermF`, `hmap`, `para`,
  `Functor`, `Foldable`, `Traversable` (derived) and the printer. A
  lambda's body now mentions `a` again, so renaming enters it; the
  derived instances do that.
- **`Frontend/Translate/{Terms,Closed}.idr`.** Build `Lam l b body` and
  `Suspend l body` directly. Build `Region` where the array loops were
  built.
- **`Emit/Bodies.idr`.** Write the two region cases and the generic
  `RegionF` case.
- **`Emit/Monad.idr` and `Emit/Declarations.idr`.** Remove the `lifted`
  state and its readers.
- **`Ids.idr`.** Remove `Label` if nothing else reads it; check with
  `grep -rn Label compiler/src`.
- **`Emit/Attributes.idr`.** Remove `lifted` and `inherited`.
- **`Effect`.** Change the constructor, `EffectF`, and their cases in
  `Term.idr`. `Terms.idr` builds `Effect l p tys args d` from the hook's
  `IdrPrim` (U18) and the call's type arguments.
- **`Op` for what left `Prim`.** In `Terms.idr`'s `natOperation`
  (`:285-303`), `NatToBig` and `NatFromBig` become `Op NatToBig` and
  `Op NatFromBig`. `builderCall` (`:373-379`) takes the hook's `IdrPrim`
  (`Builds p`, from `builderOf`, U18) in place of a `Builder`, and builds
  `PrimApp loc (Op p) lowered`. It still checks that the one parameter
  is a list, and no longer passes the list's `DataId`: a pure `Op p`
  takes its operand at the operand's own type (U17).

## Delete

- `lam`, `delay` and the closure-conversion comment block in
  `Term.idr`, and `freeVars` if nothing else uses it.
- `lifted` and the `lifted` state field, with its readers.
- `ArrayGen`, `ArrayFold`, `ArrayGenF` and `ArrayFoldF`, and their
  cases.
- `Label`, if it has no other reader.
- `Emit/Attributes.idr`'s `lifted` and `inherited`.
- `Effect`'s `IOOp` payload, and every `IOOp` pattern in your files.
- Every use in your files of the `Prim` constructors `NatToBig`,
  `NatFromBig` and `StrBuild`, and of `Builder`. The generated `IdrPrim`
  constructors `NatToBig`, `NatFromBig`, `StrPack` and `StrConcat`, under
  `Op`, replace them.

## NOT TO DO

- Do not outline anything on the Idris side.
- Do not change how applications (`App`, `Idr.applyOp`) or forces
  (`Resume`, `Idr.forceOp`) are emitted.
- Do not change `Types.idr` or `Emit/Operations.idr` (U17), or the
  registry and `Hooks.idr` (U18).
- Do not add a region form for anything but lambdas, delays and the two
  region primitives.

## Acceptance

- For `\x => x + y`, Emit writes one `idr.lambda` whose body uses `%y`
  from above, and no `func.func` for it.
- For `Delay (f n)`, Emit writes one `idr.delay`.
- `T/programs/` produce the same output once `idr-isolate` runs first
  (the coordinator runs them).
- The size of `CS/` in lines falls. Record before and after in your
  handoff.
- `grep -rn 'lifted\|ArrayGen\|ArrayFold' compiler/src/IdrisMLIR --include=*.idr`
  finds nothing outside the generated `Dialect/`.
- **Tempting partial:** keeping `lam` and `delay` and emitting a region
  whose captures are block arguments. Rejected: that is closure
  conversion on the Idris side, which this lane deletes.

## Escalate if

- An Idris function that is not `Lam`, `Suspend` or an array loop
  depends on `Label` or `lifted`. Report it.

## Stop and return

You are done when the constructors and Emit's cases are as above and
the Delete list is empty of survivors. Return the changed paths,
`Verification: NotRun (swarm policy)`, and seams.
