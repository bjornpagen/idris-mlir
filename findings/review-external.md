# An independent review of the dialect and its lowering

A second reviewer read the pipeline from `lib/Registration.cc` down to LLVM.
Its verdict: this does not read as novice work, and it has two real problems,
a stale attribute that nothing validates and bit packing that nothing checks.

## Confirmed bugs (checked against the code)

- **Dead `quantities` attribute on constructors.** `idr.ctor ... {quantities
  = ["w", "w"]}` still appears in `tests/idr/rc/loops.mlir:16-17` and
  `tests/idr/stack/expect.mlir:16-17`. Quantities live in the field types
  now (`!idr.erased`, `!idr.lin<T>`, plain T), and nothing reads the
  attribute. It parses because `idr.ctor`'s `attr-dict` accepts any
  discardable attribute. Fix: delete it, and have the ctor verifier reject
  unknown attributes, so a dropped representation cannot linger as
  accepted junk.
- **Unchecked packing of the cell header's info word.**
  `foreign/idr/lib/Lower/Layout.h:21-22` computes `tag | objs << 16 | kind <<
  24` with no range check, and `Layout.cc:159` counts `++cell.objs` with no
  bound.
  - 256 or more counted components in one cell overwrite the kind bits.
    Unboxed sums flatten into box fields, so a fat record gets there sooner
    than it looks.
  - A closure tag is a module-wide label id: more than 65535 labels (which
    specialization clones make easier) bleed into objs.
  - Either corrupts frees at runtime instead of failing the compile. It
    needs an `unsupported` error in Layouts, or a representation with room
    (see below).
- **A test hole.** The `CHECK-NOT`s of the rc tail-loop test only cover the
  region after the `scf.while`. `idr-expect holds=counts-nothing=@sumAcc`
  states the property for the whole function.

## Design smells (debatable)

- **One dialect, two semantics, switched by `idr.stage = "owned"`.** The
  same ops follow different rules depending on a module attribute:
  `inc`/`dec`/`reset`/`reuse` exist in the pure stage but are illegal there.
  Lean splits a pure IR from an RC IR, so legality comes out of which
  dialect is loaded. Today every pass has to know its stage.
- **Untyped constant attributes, with a `NoneType` self-type hack** (the td
  comment admits it works around the parser). `#idr.con<@L::@N, []>` doesn't
  know its type, so every holder supplies it from context. Typed attributes
  would simplify `materializeConstant` and folding.
- **Nominal types via symbol refs (`!idr.box<@L>`).** Standard (LLVM named
  structs do the same), but every analysis does symbol lookups. Hot passes
  must cache them, as Layouts does.
- **`idr.*` attributes stripped by string prefix before translation.** An
  LLVM translation interface that ignores them would be cleaner. Low
  priority.

## Judged fine as is

World-token threading; func.func/func.call instead of our own function ops;
`idr.borrowed`/`idr.total` as verified discardable attributes; the two-phase
lowering (eager match rewrite, then conversion); the 1:n conversion for
unboxed sums; signless ints with `signed` on the ops.

## Coordinator's note

Both bugs are representation problems in the sense of the project's
principle. A junk attribute that verifies means the ctor's representation
admits states that mean nothing. A header whose fields can overflow into
each other means the packed word admits values the runtime misreads. The
fixes are to make them unrepresentable (reject unknown attributes; give the
fields widths the compiler checks, or a layout type that cannot be built
out of range), not to add a guard at one use.
