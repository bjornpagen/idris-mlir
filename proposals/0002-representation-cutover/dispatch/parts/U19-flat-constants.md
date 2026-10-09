# U19 — Flat constants: #idr.con runs

Mandatory findings: F-const-1

## Permitted outcome

1. **Runs.** `#idr.con` stores a run of `n >= 2` cells of one
   constructor, linked through one spine field, as one flat attribute
   (C7). Mandatory:
   - the canonical form of C7.1, so that one value has one attribute;
   - the part of the C7.2 API that is yours: `get` (and the `getChecked`
     ODS declares beside it), `getRun`, `getField` and `getFields`. ODS
     generates `getCtor`, `getCells`, `getTail` and `getSpine`, and the
     hub defines `isRun`, `getRunLength` and `getRunCells` inline;
   - the flat print and parse;
   - the verifier, which rejects a non-canonical run;
   - the round trip of a 10^4-cell run through the printer, the parser
     and bytecode, over the sub-element walk and replace ODS generates.
2. **`IDR/Sharing/Aliases.cppm`** follows the walk rule (C7.2).
   Mandatory.

## Owner / exclusive writes

- `IDR/Dialect/Attrs`
- `IDR/Sharing`

**Excluded:**

- `INC/IdrOps.td`, where the coordinator writes `ConAttr`'s parameters,
  `skipDefaultBuilders`, declarations and the inline `isRun`,
  `getRunLength` and `getRunCells` (C1.1 item 6).
- Every other walker and builder of C7.2's tables: each lane adapts its
  own (U03, U04, U09, U10, U12, U13, U14, U21).

## Read first

- `contracts.md` C7 (all), C1.1 item 6 and C13.
- `findings.md` F-const-1.
- `review.md` R3.
- `PINS.md` `mlir-recursion` and `bytecode-deferred-quadratic`.
- `IDR/Dialect/Attrs/ConAttr.cc`.
- `IDR/Sharing/Aliases.cppm`.
- `INC/IdrOps.td:204-264` (`Idr_Attr`, `Idr_ConAttr`, as the hub
  applied them), and the `ConAttr` class and `ConAttrStorage` that
  `mlir-tblgen -gen-attrdef-decls` and `-gen-attrdef-defs` make of them.
- The pinned `mlir/include/mlir/IR/StorageUniquerSupport.h` (`Base::get`,
  which asserts the verifier) and `mlir/IR/AttrTypeSubElements.h`
  (`walkImmediateSubElements`, `replaceImmediateSubElements`, and
  `constructSubElementReplacement`, which rebuilds through `Base::get`
  when the attribute has no `get` of exactly its parameters).

## Fixed decisions

- **The stored parameters** are `(ctor, cells, tail, spine)` and the
  self type, `NoneType` (C1.1 item 6). ODS generates the storage, which
  `Initialize.cc` completes through `IdrAttrs.cc.inc`; you write none.
  - **Plain:** `cells` is one `ArrayAttr`, the fields; `tail` is null;
    `spine` is 0.
  - **Run:** `cells` is `n >= 2` `ArrayAttr`s, each one cell's fields
    without the spine field. `tail` is the attribute after the last
    cell, and `spine` is the spine field's index.
- **The builders** reach the storage through
  `Base::get(ctx, ctor, cells, tail, spine, NoneType::get(ctx))`, on
  canonical parameters only. `get` hides `Base::get` by name, so call it
  as `Base::get`.
- **The canonical form** is C7.1's, exactly:
  - a run has at least two cells, all of constructor `C` and spine `s`;
  - `get(ctx, ctor, fields)` builds a run exactly when one field `i` is
    a `#idr.con` of `ctor` and that field is either a run with spine
    `i` (this cell is prepended) or a plain con of `ctor` none of whose
    fields is a con of `ctor` (it becomes the second cell, its field
    `i` the tail). Otherwise it builds a plain con: a zig-zag or a tree
    cell with two such fields stays plain;
  - `getRun(ctx, ctor, spine, cells, tail)` gives what repeated `get`
    would give, in O(n): one cell gives a plain con; a tail that is a
    run of the same constructor and spine is merged; a tail that is a
    plain con of `ctor` with no same-constructor field becomes the last
    cell.
- **The accessors** (C7.2). The hub's and ODS's:
  - `getRunCells()`: a run's cells' non-spine fields; empty for a plain
    con (a thin alias of the generated `getCells()`);
  - `getTail()`: a run's tail; null for a plain con;
  - `getSpine()`: a run's spine index; 0 for a plain con.

  Yours:
  - `getField(i)`: O(1) for `i != spine`; for `i == spine`, the run from
    the second cell;
  - `getFields()`: correct for both forms, O(n) on a run, which builds
    its suffix.
- **The printed forms:**

  ```
  #idr.con<@C, [fields]>
  #idr.con<@C, run <spine> [[cell0], [cell1], ...] tail <attr>>
  ```

  The parser accepts both and canonicalizes.
- **Sub-elements.** ODS generates `walkImmediateSubElements` and
  `replaceImmediateSubElements` over the parameters: each cell as an
  `ArrayAttr`, the tail directly, never a nested run. You write neither.
  A replace rebuilds through `Base::get` without canonicalizing, so it
  can produce a non-canonical run, which your verifier rejects (C7.2).
- **`Aliases.cppm`** walks a list constant's spine with `getRunCells()`
  and `getTail()` in a loop, never by `getFields()[s]`.

## Inputs

- The `ConAttr` ODS declaration and parameters (C1.1 item 6).

## Outputs

- `ConAttr`'s C7.2 builders and field accessors, its custom parse and
  print, and the verifier, which every other lane's walker uses.

## Implement

- Per the fixed decisions, in `IDR/Dialect/Attrs/ConAttr.cc`, plus new
  units in `IDR/Dialect/Attrs/` if the 400-line limit requires it. Name
  any new unit in your handoff for the coordinator's
  `IDR/Dialect/CMakeLists.txt`.
- `IDR/Sharing/Aliases.cppm` per the walk rule.

## Delete

- `ConAttr::verify`'s old signature, `(ctor, ArrayAttr, Type)`: the
  generated declaration takes `(ctor, cells, tail, spine, type)`.
  Nothing else. The old `get` keeps its signature.

## NOT TO DO

- Do not change a `ConAttr` reader outside your files: each lane adapts
  its own.
- Do not add a second attribute kind.
- Do not change `#idr.closure` or `#idr.big`.
- Do not add a bytecode interface unless the dialect already has one.
  If it has none, attributes go through text, which is now flat.

## Acceptance

- A 10^4-cell list run prints in one line of nesting depth 1, parses
  back to the same attribute, and round-trips through bytecode with
  `idris-mlir-opt --emit-bytecode` and back.
- A list built cell by cell with `get` and the same list built with
  `getRun` are pointer-equal attributes. So are a zig-zag tree written
  in text and the same tree built by `get`.
- `getField(i)` for a non-spine field does not build the suffix.
- A plain con has one cell, a null tail and spine 0, and the verifier
  rejects a run that `Base::get` built non-canonical.
- U22 writes `T/idr/constants/run`.
- **Tempting partial:** a new `#idr.list` attribute that readers must
  learn. Rejected: thirty readers would each need a second case, and
  one value would have two spellings.
- **Tempting partial:** keeping `getFields()[s]` as the walk and calling
  it "uniqued, so cheap". Rejected by R3: each step builds the suffix,
  about 5·10^9 pointers for the 10^5-element test.

## Escalate if

- The generated storage, walk or replace cannot hold C7.1's form with
  the parameters of C1.1 item 6. Report the ODS text that works, for
  the coordinator.

## Stop and return

You are done when `ConAttr` stores runs flat in canonical form behind
the C7.2 API, and `Aliases.cppm` follows the walk rule. Return the
changed paths, any new unit names, `Verification: NotRun (swarm policy)`,
and seams.
