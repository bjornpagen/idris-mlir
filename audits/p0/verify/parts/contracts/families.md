<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: the families API (L04, 2026-10-21)

## Specification

In `IdrisMLIR.Spec.Families.Dialect`:
- `erasedBinderInterface : InterfaceDef` is `ErasedBinderOpInterface`,
  with the method `getBoundSorts(Region&) -> ::llvm::ArrayRef<::idr::families::Sort>`.
- `#idr.index_binders<[nat, ...]>` is `::idr::IndexBindersAttr`;
  `getSorts()` returns `ArrayRef<families::Sort>`.
- `#idr.index_args<[3, v0, _]>` is `::idr::IndexArgsAttr`;
  `getTerms()` returns `ArrayRef<families::TermNode>`, and `getCount()`.
- The slots are `indexBinders : AttrKind` and `indexArgs : AttrKind`.
  There is one name: no `indexArgsSlot`.
- ODS classes live in `::idr`, so the attributes are spelled
  `IndexBindersAttr` and `IndexArgsAttr`.

## C++

Headers in `include/idr/IR/Families/*.h`, in namespace `idr::families`
unless said otherwise.

**`Tag`** is defined in `Families/Declaration.h`. `IdrDialect.h` does not
define it. `Grades.h` keeps only the opaque redeclaration
`enum class Tag : std::uint32_t;`.

**`DataType`'s members:**
- `getGroup()`, `getMember()`, `getIndices()`.
- `possibleTags()` returns a `const TagSet &`, not an `ArrayRef`: it has
  `size()`, `front()`, `contains()` and iteration.
- `singleTag()`, `declaredCount()`.
- `ctor(Tag)` returns a `CtorView{StringRef label, binders, equation,
  fields}`.
- `binderSorts(Tag)` returns `ArrayRef<Sort>`.
- `memo()` returns an `optional<MemoView>`:
  - `labels()` gives `ArrayRef<MemoLabelDecl{Mode mode; LabelDecl label}>`;
  - `running()`, `forced()`.
- `closures()` returns an `optional<ClosuresView>`, whose `labels()` gives
  `ArrayRef<LabelDecl{label, fn, binders, equation, fields}>`.
- `listShape()`, `promise()`.
- `layout()` returns the generated enum `Layout`: `Word8` to `Word64`,
  `Natural`, `InPlace`, `Cell`.
- `cls()`, `determinedFields(Tag)`.
- `refined(tags)`, `refinedTo(tag, binders)`, `unrefined()`.

**`ConAttr` and `ConOp`:** `getTag()` is derived from the refined result
type. There is no tag attribute.

**Free functions:**
- `refines(sub, super)`
- `instanceOf(instance, pattern)`
- `levelArgs(ctx, first, count)`, returning `IndexArgsAttr`
- `opaqueArgs(ctx, count)`
- `classesUnder(FunctionType, IndexArgsAttr)`, returning
  `optional<IndexArgsAttr>`
- `substitute(Type, IndexArgsAttr)`, returning `Type`
- `substituteFunction(Operation *fn, IndexArgsAttr)`, returning
  `FailureOr<SmallVector<Sort>>`: the binders kept, which the caller sets
  on its op
- `renumber(Region&, from, count, to)`

**`idr.field`** takes an operand refined to one constructor:
`idr.field %v[i] : !T -> R`, with no tag (D105).
