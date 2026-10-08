# U19 — Flat constants: #idr.con runs

Mandatory findings: F-const-1

## Permitted outcome

`#idr.con` stores a run of `n >= 2` cells of one constructor, linked
through one spine field, as one flat attribute, behind the unchanged
`getCtor()` and `getFields()` (C7). Mandatory:

- the canonical form;
- `getRun`, `isRun` and `getRunLength`;
- the flat print and parse;
- the sub-element walk and replace.

## Owner / exclusive writes

- `IDR/Dialect/Attrs`

**Excluded:**

- `INC/IdrOps.td`, where the coordinator writes `ConAttr`'s parameters
  and declarations (C1.1 item 6).
- `IDR/Eval/Reify.cppm` (U14 calls `getRun`).
- `IDR/Fold` (U04 calls `getRun`).
- `IDR/Lower/StaticData.cppm` (U12 lowers runs).
- Every other reader of `ConAttr`, which keeps using `getCtor` and
  `getFields` unchanged.

## Read first

- `contracts.md` C7 (all), C1.1 item 6 and C13.
- `findings.md` F-const-1.
- `PINS.md` `mlir-recursion` and `bytecode-deferred-quadratic`.
- `IDR/Dialect/Attrs/ConAttr.cc`.
- `INC/IdrOps.td:208-235` (`Idr_Attr`, `Idr_ConAttr`).
- The pinned `mlir/include/mlir/IR/AttributeSupport.h` and
  `StorageUniquer.h` (custom storage), and `mlir/IR/SubElementInterfaces`
  / `AttrTypeSubElements.h` (`walkImmediateSubElements`,
  `replaceImmediateSubElements`).

## Fixed decisions

- **The stored parameters** are `(ctor, stored, tail, spine)` (C1.1
  item 6).
  - **Plain:** `stored` is the fields, `tail` is null, and `spine` is
    unused.
  - **Run:** `stored` is an `ArrayAttr` of `n` `ArrayAttr`s, each one
    cell's fields without the spine field. `tail` is the attribute after
    the last cell, and `spine` is the spine field's index.
- **`getFields()` of a run** returns the first cell's fields with, at
  `spine`, the same run from its second cell. That is a run of `n - 1`
  cells, or a plain con when one is left, or `tail` when none is left.
  Each call builds that attribute, which is uniqued, so equality still
  holds.
- **Canonical form.** `get(ctx, ctor, fields)` checks whether exactly
  one field is a `ConAttr` of the same `ctor` symbol. If so, it returns
  the run with this cell prepended, which copies the stored cells; else
  the plain con. `getRun(ctx, ctor, spine, cells, tail)` builds the run
  directly in O(n). If `tail` is itself a con of `ctor` at `spine`, its
  cells are merged in, so one value has one attribute.
- **The printed forms:**

  ```
  #idr.con<@C, [fields]>
  #idr.con<@C, run <spine> [[cell0], [cell1], ...] tail <attr>>
  ```

  The parser accepts both. A plain con whose recursive field is a con of
  the same constructor, written in text, is canonicalized on parse.
- **Sub-elements.** `walkImmediateSubElements` visits every cell's
  fields and the tail, never a nested run. `replaceImmediateSubElements`
  rebuilds with `getRun`.

## Inputs

- The `ConAttr` ODS declaration and parameters (C1.1 item 6).

## Outputs

- `ConAttr::get`, `getRun`, `isRun`, `getRunLength`, `getCtor`,
  `getFields`, the custom parse and print, the sub-element hooks, and
  the verifier.

## Implement

- Per the fixed decisions, in `IDR/Dialect/Attrs/ConAttr.cc`, plus new
  units in `IDR/Dialect/Attrs/` if the 400-line limit requires it. Name
  any new unit in your handoff for the coordinator's
  `IDR/Dialect/CMakeLists.txt`.

## Delete

- Nothing else. The old `get` keeps its signature.

## NOT TO DO

- Do not change any `ConAttr` reader.
- Do not add a second attribute kind.
- Do not change `#idr.closure` or `#idr.big`.
- Do not add a bytecode interface unless the dialect already has one.
  If it has none, attributes go through text, which is now flat.

## Acceptance

- A 10^4-cell list run prints in one line of nesting depth 1, parses
  back to the same attribute, and round-trips through bytecode with
  `idris-mlir-opt --emit-bytecode` and back.
- `getFields` walks it cell by cell to the tail.
- U22 writes `T/idr/constants/run`.
- `ConAttr::get` of a cons onto a run equals `getRun` of the longer
  run: pointer-equal attributes.
- **Tempting partial:** a new `#idr.list` attribute that readers must
  learn. Rejected: thirty readers would each need a second case, and
  one value would have two spellings.

## Escalate if

- An `Idr_Attr` cannot carry a custom storage class with the ODS shape
  of C1.1 item 6. Report the ODS text that works, for the coordinator.

## Stop and return

You are done when `ConAttr` stores runs flat behind its unchanged API.
Return the changed paths, any new unit names,
`Verification: NotRun (swarm policy)`, and seams.
