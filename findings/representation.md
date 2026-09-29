# Representation: what Idris proves, what idris-mlir may choose, and how the IR states it

Stream "representation". Experiments are in
`representation-experiments.md` (programs, IR excerpts, the crash). Paths
are relative to the repository. "Proved" means read in the code or
reproduced. "Conjecture" means not measured or not implemented anywhere.

## The questions

1. Which runtime representations can idris-mlir choose because of what
   Idris's types prove (quantities, indices, constructor signatures,
   totality and size-change, the closed world after monomorphisation)?
2. For each one, where does the decision belong, and how is it recorded
   in IR types so that it carries load, can be verified, and cannot be
   dropped?
3. Why does AGENTS.md say "erased does not mean constant" and "indexed
   vectors do not imply contiguous storage", and what extra proof would
   license contiguous storage?
4. How should the representation layer be structured as data rather
   than as special cases in Emit and Lower?

## Short answer

- **Two layouts today, both chosen by structure, not by fact.**
  - Today there are two layouts:
    - an unboxed sum (`Sop`);
    - a box, used exactly when an instance lies on a containment cycle.
  - Every Nat-like type, `Fin` included, is `!idr.big`. That drops
    non-negativity, the bound, and the Nat operations.
- **The Nat operations (proved).** Idris's own backends carry the Nat
  operations with the representation (the "Nat hack"). idris-mlir does
  not. As a result:
  - `plus`, `natToInteger` and `integerToNat` are O(n) non-tail
    recursions over bigs;
  - `printLn (tri 500)`, where `tri` sums Nats, segfaults from stack
    overflow (104,736 `natToInteger` frames). Under Chez it prints
    125250 in 0.09 s.
- **The main opportunities.** They fall into four groups:
  - numbers: Nat, Fin and Integer as words;
  - boxes: constructor packing, pointer tagging, niches, and boxing only
    where a cycle needs it;
  - closed indices: `Vect 3 Double` as three doubles;
  - the closed world: useless fields, unused constructors, and the shapes
    of closure sums.
- **Where the decisions go.** Every one of them should be:
  - a fact in a type, written by the frontend (`!idr.nat`,
    `!idr.fin<N>`, closed-index instances, a known-constructor type);
  - plus a decision in a typed layout attribute on `idr.data`, written by
    one dialect pass;
  - plus a verifier that checks the decision against the facts. The
    checks are: no confusion between constructors' heads, header fields
    in range, and no read of an absent field.

  Lowering only reads the decisions.
- **Contiguous `Vect` needs three proofs.** It needs:
  - the length available at runtime at every allocation;
  - no persistent sharing of a tail across two different conses
    (uniqueness, not QTT linearity);
  - every consumer supported by the array at no worse complexity.

  None of these follows from the type `Vect n a`.

## What idris-mlir decides today (evidence)

**Two layouts, chosen by cycles.**
- `Term.Repr = Sop | Box`, and a data instance is a box exactly when it
  lies on a cycle of the "a field contains" graph
  (`compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr:82-92`).
- `Graph.cyclic` marks *every* node of a strongly connected component
  (`compiler/src/IdrisMLIR/Graph.idr:46-53`).
- So `data Rose = Node Int (List Rose)` makes both `Rose` and
  `List Rose` boxes (experiment `rose`). Each node costs two cells and
  48 bytes, where one box on the cycle would do.

**Unboxed sums** (`foreign/idr/lib/Lower/Layout.cc:56-97`).
- The tag is i8, i16 or i32 by constructor count.
- Slots are shared between constructors only when their types are equal
  (i64 and f64 never share a slot).
- A counted slot holds null in constructors that do not use it.
- A sum is inlined into any cell that holds it, which is why the review
  found that "a fat record" can overflow `objs`.
- `idr.inc` of a sum increments every counted slot
  (`foreign/idr/include/idr/IdrOps.td:884-892`). An unboxed sum with k
  pointers costs k increments where a box costs one.

**Boxes.**
- A box is a cell: an 8-byte header `{count, info}`, then the object
  slots, then the scalars (`Layout.cc:131-171`).
- `info = tag | objs << 16 | kind << 24` is packed with no range check
  (`Layout.h:17-23`, `Layout.cc:159`, `runtime/idris_rt.h:40-77`).
- A nullary constructor of a box, such as `Nil`, is a static cell
  (`Lower/Runtime.cc:329-340`).
- Every match on a box loads the tag from the header
  (`Lower/Patterns.cc` `LowerTag`, `Runtime::loadTag`,
  `Lower/Runtime.cc:142`).

**Closures.**
- `idr-defunctionalize` turns closures of known label sets into ordinary
  sums `@fn$n`, one constructor per label, boxed only on a cycle
  (`Passes/Defunctionalize.cc:14-32`).
- "Only idr-eval lowers closures" (`Lower/Closures.cc:1-4`). So the
  module-wide label ids packed into the 16-bit tag
  (`Layout.cc:36-52`) matter only in the JIT, but there they can still
  overflow.

**Nat, Integer and Fin.**
- Every Nat-like type (Idris's `ZERO`/`SUCC` flags, read by
  `natLike`, `Frontend/Translate/Types.idr:228-235,264-265`) is `BigT`,
  and `Integer` is too (`:250`). `Fin` is Nat-like: Idris counts only
  runtime arguments (the comment at `:207-210`).
- `!idr.big` is one word: an odd word holds a signed 63-bit value,
  otherwise a pointer to a GMP cell (`runtime/big.cc:24-31`,
  `idris_rt.h:88-92`).
  - Nat and Integer share the signed small range
    [-2^62, 2^62-1], so Nat uses half of it.
  - The type's summary ("an Integer, or a Nat-like value
    (non-negative)", `IdrOps.td:79-81`) admits that the type does not
    say which one it is.
- Only `big.pred` knows a value is a Nat (`IdrOps.td:714-724`).
- Nat functions are compiled as written: `plus`, `natToInteger` and
  `integerToNat` are recursions over bigs (experiments `fin`, `nat`).
  The pinned Prelude comments out its `%builtin` pragmas
  (`third_party/Idris2/libs/prelude/Prelude/Types.idr:41,103`). Idris's
  own backends rewrite these functions by name
  (`third_party/Idris2/src/Compiler/Opts/Constructor.idr:80-94`).

**Vect.**
- Instance names erase every index, "so that `Vect 3 Double` and
  `Vect n Double` name one instance"
  (`Frontend/Translate/Types.idr:181-195,278-281`). So a literal length
  is dropped before any pass could use it.
- In `tests/e2e/v3/vect`, `dot v v` on a `Vect 3 Double` builds:
  - three `idr.stack` cons cells for each vector;
  - three more cells in `zipWith`;
  - a `foldl` loop over them (experiment `vect`).

**Strings** (`runtime/strings.cc:75-83`).
- A string is one cell: the header, the byte count, the scalar count,
  then the bytes.
- `str.tail` and `str.substr` copy (`slice`).

**Constants** (`IdrOps.td:107-115`).
- The constant attributes are untyped: a `NoneType` self type, and the
  holder supplies the type.

**Erased values are all one constant.**
- `idr.constant #idr.erased` is `ConstantLike`.
- In the `vect` dump a single `%12` fills the erased length field of
  every cons of every vector.

## What the sources say, as it bears on representation

**Brady 2021 (QTT)** (`erasure.tex:12-16,99-240`, `linearity.tex:1-12`).
- Quantity 0 means "not used at run time", but the value still exists
  in the semantics: `length : Vect n a -> Nat` must recompute `n`.
  Keeping `n` requires writing `{n : Nat}`, "which has a storage cost".
- Quantity 1 "promises that it will not share the argument in the
  future; there is no requirement that it has not been shared in the
  past".
- Idris "optimises Nat to a binary representation at run time"
  (`idris2.tex:284-286`).

**Idris 2's backends** (`src/TTImp/ProcessData.idr:235-388`,
`Compiler/Opts/Constructor.idr`).
- `ConInfo` is computed by shape, not by name: `NIL`/`CONS` for
  list-shaped types, `NOTHING`/`JUST`, `ENUM n`, `RECORD`, `UNIT`,
  `ZERO`/`SUCC` (Nat-like), and newtypes (one constructor with one
  relevant argument, `findNewtype`, `:235-247`).
- The Nat hack changes the representation *and* maps the operations to
  it:
  - `plus` to add, `mult` to multiply, `minus` to a truncating subtract;
  - `natToInteger` to the identity;
  - `integerToNat` to a clamp;
  - `equalNat` and `compareNat` to comparisons.

  Enums become `Bits8`/`16`/`32`.
- A change of representation that leaves the operations behind is only
  half a change.

**Chataing, Dolan, Scherer, Yallop 2024** (§1.3, §3.3-3.6, §5.3, §8.2).
- A constructor may be unboxed (represented as its argument) exactly
  when the *head shapes* of all constructors stay disjoint: "no
  confusion".
- The check is a multiset computation over a small syntax of head
  shapes: (immediates) × (block tags). Pattern matching then tests the
  head.
- Rust's niche filling is the special case where every constructor is
  unboxed. "Unboxing by transformation" (§5.3) remaps immediates to
  make room.
- Zarith's small-integer unboxing gives 20% (§2.3); ropes give 30%
  (§2.4).
- MLton unboxes single-constructor types, but its "representation of sum
  types with several (inhabited) constructors remains uniform" (§8.1).
  I read `packed-representation.fun` as saying MLton does pack small
  variants into tagged words (below), so that sentence undersells
  MLton.

**MLton** (`sources/code/mlton/mlton/backend/packed-representation.fun`,
`docs/mlton/doc/guide/src/{RSSA,Useless,RemoveUnused,Flatten,DeepFlatten}.adoc`).
- Representation is a family of datatypes, computed once:
  - `Rep = {NonObjptr | Objptr{endsIn00}, ty}` (`:116-130`);
  - `TupleRep = Direct | Indirect ObjptrRep` (`:1023-1037`);
  - `ConRep = ShiftAndTag | Tag | Tuple` (`:1352-1359`);
  - a TyconRep chosen among `One`, `Objptrs`, `Small`, `SmallAndBox`,
    `SmallAndObjptr`, `SmallAndObjptrs` and `Unit` (`:1780-1786`).
- Small variants are shifted and tagged into one word. When a pointer
  can also appear, only 3/4 of the tag values are usable, because tags
  ending in 00 are pointers (`:1798-1812`). As few variants as possible
  are boxed, so that the tags fit (`:1930-2000`).
- The header of a pointer variant holds its object-type index, and a
  case switches on that index directly (`:1510-1550`).
- RSSA is "an IL that makes representation decisions explicit", with
  singleton types and subtyping (`RSSA.adoc`).
- `Useless`: "a value of ground type is useful if it is an arg to a
  primitive... a conapp is useful if it contains a useful component or
  is used in a case". A useless component becomes `unit`.
- `RemoveUnused` removes unused datatypes, constructors, constructor
  arguments, function arguments and returns.
- `DeepFlatten` flattens tuples into mutable objects and vectors, with
  no significant impact on MLton's own benchmarks (`DeepFlatten.adoc`).

**GHC** (`sources/docs/ghc/commentary-compiler-demand.md`).
- The worker/wrapper split turns strictness and absence into a
  calling convention: fields passed unboxed, absent fields dropped.
- `-funbox-small-strict-fields` unboxes only what is small
  (`users_guide/using-optimisation.html`).
- Idris is strict, so strictness is given. The analysis that is left is
  about absence and escape.

**Lean 4.**
- Verified in `.toolchain/lean/include/lean/lean.h`:
  - the header is `m_rc`, `m_cs_sz:16`, `m_other:8` (the number of
    object fields) and `m_tag:8` (at most 243) (`:92-107,149-156`);
  - the limits are only an `assert` in `lean_alloc_ctor` (`:796-801`),
    the same class of risk the review found here;
  - object fields come first and scalars after (`:791-794,841-844`);
  - nullary and scalar values are odd immediates (`lean_box`), and
    reference counting skips them (`:334-335,698-700`);
  - the small Nat range is `SIZE_MAX >> 1`, unsigned (`:1500`).
- From memory of Lean's sources, which are not in `sources/`:
  - LCNF/IR types separate scalars (`uint8..64`, `usize`, `float`)
    from `object`/`tobject`, and `irrelevant` from both;
  - enum-like inductives are `uint8`/`16`/`32`;
  - a structure with one relevant field is that field;
  - `@[unbox]` asks the compiler to return values of a structure type
    unboxed.

  These are conjecture as far as this repository can show.

**Kovács 2022** (`paper.tex:686-720`).
- "Memory representation polymorphism": `Rep` is a *meta-level* type,
  runtime types are indexed by representations, and "we have type
  dependency, but we do not have dependency in memory representations".
- The comment at `:713-720` says length-prefixed flat arrays
  `(n : Nat) × Vec n A` are "dependent memory layouts" and "highly
  challenging".
- This is the right frame for idris-mlir: Idris types (facts) and a
  representation that is computed from them at compile time.

**Kovács 2024** (§2.2, §3, pp. 4-5, 14).
- Value types (first-order data) are separate from computation types
  (functions, which are never stored).
- A function's result that is a finite sum can return into per-constructor
  *join points* ("fused returns", SOP): the caller's case is fused away
  and no constructor is built.

**Huang and Yallop 2023, Danvy and Nielsen 2001, Hovgaard, Henriksen and Elsman 2018.**
- Defunctionalization makes closures into a first-order data type, so
  every data representation choice applies to closures.
- Danvy p. 19: a defunctionalized continuation with one nullary and one
  self-recursive constructor "implements Peano numbers", and replacing
  it with machine integers gives the counter.
- Hovgaard (§1-2): when the form of the function at each application is
  known statically, a closure is just its environment record, with no
  tag and no apply dispatch. The `orderZero` judgment is the type-level
  fact that guarantees this.

**Maranget 2008** (§2).
- Decision trees are compiled over complete *signatures*.
- Idris's coverage gives more than a signature: it proves which
  constructors are impossible at a given index.

**Sørensen, Glück, Jones 1996 and Mitchell 2010.**
- Positive information: inside `case x of C ys`, `x = C ys`.
- Mitchell §3 (p. 9) and §4 (p. 10): supercompilation leaves unboxing to
  GHC. Once the intermediate structures are gone, "all the numbers have
  been unboxed". The exp3_8 gain was eliminating `Nat` intermediates.

**Rondon, Kawaguchi, Jhala 2008** (§5, p. 10).
- Bounds checks are removed with qualifiers relating an index to `0`,
  to another variable, and to `len ⋆`.
- These are *relational* facts, between two runtime values. MLIR's
  `ValueBoundsOpInterface` expresses exactly that shape of fact
  (`.toolchain/llvm-project/mlir/include/mlir/Interfaces/ValueBoundsOpInterface.td`).

**Henriksen et al. 2017** (§2-3).
- Arrays carry exact shapes: sizes are bound to runtime values.
- Arrays must be regular, and in-place updates need uniqueness types.
- Arrays of tuples become tuples of arrays early (footnote 2).
- The size is always a *runtime value* when an array exists.

## Why "erased does not mean constant", and why `Vect` is not contiguous

**Erased does not mean constant.**
- A quantity-0 binder has no runtime representation, but it has a
  *value* on each call, and the values differ between calls. For
  example, `n` in `length : Vect n a -> Nat` is 3 on one call and 7 on
  the next.
- What the compiler may do with it:
  - it may use the erased value's *facts*, as symbolic equalities and
    inequalities, for instance that this `Fin n` is below this vector's
    length;
  - it may not fold it, share it, or specialize on it as if it were one
    value.
- The IR is safe today only because no fact mentions an erased value.
  All erased values are the one `ConstantLike` `idr.constant
  #idr.erased`, which CSE merges (the `vect` dump). Once a fact relates
  a runtime value to an erased index, merging two erased values moves
  that fact from one `n` to another, which is unsound.
- Specialization already does the right thing: an erased parameter is a
  key hole (`{idr.hole = 0}` in the `vect` dump), not a constant.
- *Closed* indices are the other case. `Vect 3 Double`'s `3` is a normal
  form and is constant. Erasing it from the instance key
  (`Types.idr:181-195`) is a lost fact, not a safety rule.

**Indexed vectors do not imply contiguous storage.**
- `Vect n a` is an inductive family, and its type says nothing about how
  values are produced or consumed. Contiguous storage fails in three
  ways:
  1. The length is erased (quantity 0). An allocation needs a size, and
     the type does not make one available at runtime.
  2. `x :: v` shares `v` in O(1). With an array, cons copies in O(n)
     unless the tail is dead afterwards. A program that keeps both `v`
     and `x :: v` (persistent sharing) would change complexity class,
     from O(n) building to O(n²). A representation must never make a
     program asymptotically slower without saying so.
  3. Pattern matching on `(x :: xs)` needs `xs` as a value. With an
     array that means a slice (buffer, offset, length) that keeps the
     buffer alive, which is a different representation with its own
     costs.

**The proof that would license contiguous storage** is the conjunction
of the following, each checkable:
1. **Length at runtime.** At every construction site the final length is
   a runtime value. Idris proves this when the index in the result type
   is built from relevant (quantity ω) variables, as in
   `build : (n : Nat) -> Vect n Int` or `replicate : (len : Nat) -> ...`,
   or when it is the length of another array (as for `map` and
   `zipWith`). Construction then fills a preallocated buffer in
   destination-passing style: `build (S k) = x :: build k` is tail
   recursion modulo cons, writing slots 0, 1 and so on.
2. **No persistent sharing of tails.**
   - Every `::` whose tail is an existing array is applied to a
     *unique* tail, one proved unshared by the whole-program ownership
     analysis. QTT quantity 1 is not enough (Brady: "no requirement that
     it has not been shared in the past").
   - Or the vector is built only by length-preserving producers
     (`replicate`, `map`, `zipWith`, `tabulate`).
3. **Consumers supported by the array.** Every consumer is
   `index`, `head`, `tail`, `foldl`, `foldr`, `map`, `zipWith`, `length`,
   or a match that takes the tail as a slice. Each is O(1) or O(n) on an
   array, as on a list.
4. **Words for the length.** The element type is monomorphic (it is,
   after monomorphisation), and the length fits a word (it does, since
   the array is in memory).

When all four hold, `index : Fin n -> Vect n a -> a` becomes a load with
no bounds check. The Fin's bound and the array's length are the same
symbolic `n`, and that relation must be kept (R11). Futhark's arrays
satisfy (1) and (4) by construction, and (2) through uniqueness types.

## Ranked catalog of representation opportunities

The ranking puts first what fixes a divergence from the reference
semantics, then weighs payoff × generality against cost. Each entry gives:
- **Fact**: the Idris fact it relies on;
- **Representation**: the representation;
- **Decided by**: where the decision belongs;
- **IR**: how it is recorded in IR types;
- **Payoff**: what it buys, with a concrete program;
- **Sound when**: the soundness conditions.

### R1. Nat with its operations, and non-negativity in the type

- **Fact.**
  - The `ZERO`/`SUCC` ConInfo flags prove the type is Peano-shaped, so
    its values correspond to ℕ (`ProcessData.idr:345-363`).
  - `plus`, `mult`, `minus`, `natToInteger`, `integerToNat`, `equalNat`
    and `compareNat` of the Prelude compute the arithmetic functions,
    and their types are checked by shape.
  - Every value is ≥ 0.
- **Representation.**
  - The same tagged word as today, but with an unsigned small range
    [0, 2^63-1], as Lean does.
  - The operations above become `add`, `mul`, a truncating subtract,
    the identity, a clamp and comparisons.
- **Decided by** the frontend.
  - The operation mapping is an entry of the privileged-knowledge table
    (`Registry/Recognized.idr:1-5`: "each entry makes its definition
    faster or stricter, never different"). That is exactly the Nat
    hack's contract.
  - The type comes from `coreType` (`Types.idr:264`): a Nat-like type
    becomes `NatT`, not `BigT`.
- **IR.**
  - A new `!idr.nat`, distinct from `!idr.big`.
  - `big.pred`, `nat.sub` (truncating) and `nat.from_big` (clamp) accept
    or produce only `!idr.nat`; `nat.to_big` is a free retyping.
  - Non-negativity holds by construction: no op makes an `!idr.nat`
    from an unchecked `!idr.big`.
- **Payoff (proved).**
  - `printLn (tri 500)`, with `tri (S k) = S k + tri k`, segfaults
    today from stack overflow in `natToInteger` (called by `show`),
    104,736 frames deep. It is also O(n²) through `plus`. Under Chez it
    prints 125250 in 0.09 s.
  - `build (S k) = cast (S k) :: build k` is O(n²).
  - This is the largest gap between idris-mlir and the reference found
    here, and no test covers it.
- **Sound when.**
  - The recognized definitions are the Prelude's; the registry's shape
    check confirms it.
  - `minus` truncates, and `integerToNat` of a negative number is 0.
  - Compile-time evaluation calls the same runtime, so it agrees.

### R2. A cell header whose fields cannot overflow, by construction

- **Fact.** None from Idris. The fact is the closed world: the number of
  constructors per type, the counted fields per constructor and the
  labels are all known at compile time.
- **Representation.** There are two steps.
  - (a) Now: the widths become part of the layout's type. Tags are
    unsigned 16-bit, objs unsigned 8-bit, and a type or constructor that
    does not fit is rejected with an `unsupported` error that names the
    limit.
  - (b) Structural: the header's info word becomes a *layout id* into a
    static per-program table (`{objs, size, kind}`). This is MLton's
    object-type index (`packed-representation.fun:1510-1550`).
    - Ids are allocated contiguously per type, so the constructor tag is
      `id - base(T)`, and a match is a switch on the id.
    - `objs` lives in the table, as 32-bit data. The only bound left is
      the number of layouts in the program, checked once.
    - Closure sums use their own dense constructor tags, not the
      module-wide label ids. Only the JIT's closure cells keep label
      ids, and those are checked too.
- **Decided by** the layout pass (see "structured as data").
  `Layouts` reads the result.
- **IR.** `idr.data` carries a typed layout attribute whose parameters
  have bounded C++ types (for example `uint16_t`) and a
  `genVerifyDecl` verifier. An out-of-range value can then be neither
  parsed nor built (`getChecked` reports the error). The DataOp verifier
  checks that the layout agrees with the constructors.
- **Payoff.**
  - Frees can no longer be corrupted silently.
  - With (b), a free does one table load instead of shifts and masks.
  - The low bits of pointers become free for R3.
- **Sound when.** The JIT and the program read the same table. They
  already share `Layouts` ("idr-lower and idr-eval compute the same
  numbers from the same module", `Layout.h:98-103`), and an attribute in
  the module makes that sharing explicit.

### R3. Constructor packing and pointer tagging for boxes

- **Fact.**
  - After monomorphisation, a box type's full constructor signature is
    known.
  - Every `!idr.box<@T>` value is built by one of T's constructors:
    escape hatches such as `believe_me` are rejected
    (`Recognized.idr:31-52`).
  - Cells are 8-byte aligned.
- **Representation** (following Chataing's head shapes).
  - **Nullary constructors as immediates.** One nullary constructor
    becomes `NULL` (the niche). Several become odd words `2k+1`, as in
    Lean's `lean_box`. The runtime's counting already accepts `NULL`
    and odd words (`idris_rt.h:136-139`), so this needs no runtime
    change.
  - **Non-nullary constructors** are pointers. The tag is either:
    - in the header (or the layout id, R2);
    - or, for at most 3 pointer constructors, in pointer bits 1-2, with
      bit 0 kept for immediates (MLton's 3/4 rule).
  - **Constructor unboxing** (Chataing §3): a one-field constructor
    whose argument's heads are disjoint from every other constructor's
    is the identity.
- **Decided by** a dialect pass. The choice needs the whole program:
  which constructors are built and their sizes.
- **IR.**
  - The layout attribute gives each constructor a `ConRep`: an
    immediate (`null` or `odd k`), a cell with its tag in the header,
    or a cell with its tag in the pointer's low bits.
  - The verifier computes each constructor's head shape and rejects any
    overlap. This is Chataing §3.5 as a verifier rule: "accept iff the
    head shape has no duplicates".
  - `idr.tag` and `idr.match` lower to the decision tree the layout
    implies.
- **Payoff.**
  - A list traversal today loads a header on every `idr.match`
    (`Runtime.cc:142`). With `Nil = NULL`, the test is a register
    compare, and the static Nil cell and its count checks disappear.
  - `Maybe (List Int)` (a Sop) loses its tag byte: null is Nothing.
  - Unmeasured here. Chataing measures 20-30% for the analogous cases.
- **Sound when.**
  - The heads are disjoint (verified).
  - Counting treats immediates as uncounted (it already does).
  - `idr.reset`/`idr.reuse` never take a token from an immediate: there
    is no cell to reuse.
  - Stack cells (bit 31 of the header) are unaffected.
  - The JIT reifies with the same layout.
  - The alignment of static and stack cells is checked, not assumed.

### R4. Where boxes go: minimal boxing on cycles, size-bounded unboxing, niches in sums

- **Fact.** The containment graph of monomorphic instances, the field
  types, and linearity.
- **Representation.**
  - (a) Box only a feedback vertex set of each cycle, preferring
    multi-constructor types. A single-constructor record on a cycle is
    inlined into the box that holds it. For `Rose`, the cons cell holds
    `{Int, children, tail}`: 32 bytes and one cell per node, where
    today it is 48 bytes and two cells (experiment `rose`).
  - (b) Above a size threshold, an unboxed sum becomes a box. This is
    GHC's "small strict fields": an unboxed sum with k pointers costs k
    increments per `inc` and k words per copy, and fattens every cell
    that holds it (the review's `objs` path).
  - (c) Niches inside unboxed sums:
    - scalars of the same width share a slot (i64 and f64, through a
      bitcast);
    - the tag is dropped when a counted slot is non-null exactly in one
      constructor (`Maybe` of a box);
    - `Maybe Char` uses Char's invalid code points above 0x10FFFF, so
      it needs no tag.
- **Decided by** the same dialect pass. Today the choice is made in the
  frontend (`Programs.idr:82-92`), which should state only the facts.
- **IR.** One nominal sum type, with the representation read from the
  declaration's layout attribute, or `!idr.data`/`!idr.box` rewritten by
  the pass through a `TypeConverter` (open question 1). The verifier
  checks that every cycle passes through a box, and that box-only ops
  (`reset`, `reuse`, `take`'s token) apply only to boxed constructors.
- **Payoff.**
  - Trees whose children are in a list (ASTs, rose trees, JSON-like
    data) allocate half as many cells.
  - Wide records stop multiplying RC traffic.
- **Sound when.** Every cycle is broken. Inlining a record changes only
  copying (all values are immutable), never meaning.

### R5. Fin and bounded Nat as machine words; bounds checks from relational facts

- **Fact.**
  - `FZ : Fin (S k)` and `FS : Fin k -> Fin (S k)`, so every value is
    below its index. This follows by induction from the constructors'
    return indices, and a shape rule (like `calcNaty`) derives it with
    no names.
  - Idris's size-change graphs, which the frontend already reads
    (`Frontend/Translate/Recursion.idr:1-7,112-116`), prove which Nat
    arguments only decrease. Such arguments stay below their initial
    value.
  - A length of an in-memory structure fits a word.
- **Representation.**
  - A closed bound `Fin 5` becomes `iK` with K = bits(N-1).
  - A Nat proved in range becomes i64, with `nuw`/`nsw` on its
    arithmetic (`Arith_IntegerOverflowFlags`).
  - A symbolic bound gives a word plus a relation to `n`.
- **Decided by:**
  - the frontend for the types, since it sees the normalised `Fin 5`;
  - a dialect pass (`idr-narrow`) for Nat→word narrowing. It needs
    whole-program ranges: `IntegerRangeAnalysis`, plus the size-change
    facts kept as function facts.
- **IR.**
  - A static bound is a type: `!idr.fin<N>` (N a parameter). The
    verifier checks constants < N. `FS` maps `fin<N>` to `fin<N+1>`. A
    match gives 0 or `pred`.
  - A symbolic bound cannot be a type: MLIR types cannot mention SSA
    values. It is an op, `%j = idr.fin.enter %i, %n : !idr.fin`, on a
    resource of its own, as `idr.lin.enter` is. Its documentation says
    why (`IdrOps.td:1025-1044`): it is never merged, and it is removed
    when unused. It implements `ValueBoundsOpInterface` (`j < n`).
  - It is never a discardable attribute.
- **Payoff.**
  - `Main.count` in experiment `fin` is a loop that, on every iteration:
    - compares a tagged big to 0;
    - calls `big.pred`;
    - runs `idr.dec` on the big.

    As a word it is `i != 0; i - 1`, and LLVM can recognize it as an
    induction variable.
  - With R12, `index i v` is a load with no bounds check.
- **Sound when.**
  - A type carries only a closed N.
  - A symbolic relation mentions a ghost `n` that no pass may merge with
    another (R11).
  - Narrowing is backed by a proof, not a likelihood. Otherwise the
    value stays `!idr.nat`, whose small path already checks for
    overflow.

### R6. Closed indices in instance keys: `Vect 3 Double` as three doubles

- **Fact.**
  - The index is a closed normal form, a constant, unlike an erased
    variable.
  - Idris's coverage proves which constructors are possible at that
    index: `Nil : Vect Z a` is impossible at `Vect 3`.
- **Representation.**
  - `Vect[3,Double]` has one constructor `::` with fields `f64` and
    `Vect[2,Double]`. The chain has no cycle, so every instance is a
    Sop, and a single constructor needs no tag: three SSA doubles, no
    cells.
  - `mat : Vect 3 (Vect 3 Double)` is nine doubles.
- **Decided by** the frontend, in instance naming
  (`Types.idr:181-195,278-281`):
  - keep closed Nat indices below a threshold in the key;
  - drop the constructors whose return index does not unify with the
    instance's;
  - specialize functions per closed index, as for type parameters,
    under the existing instance budget (`Instances.idr:31`).
- **IR.** No new type. A one-constructor `!idr.data<@Vect[3,Double]>`,
  and the fact is in which instance it is. Constructor tags must become
  layout-local: the DataOp verifier demands 0..n-1 in declaration order
  (`Dialect/Ops.cc:164-176`), which a dropped constructor breaks.
- **Payoff.**
  - In `tests/e2e/v3/vect`, `dot v v`, `mulV mat v` and `norm2` become
    straight-line floating-point code.
  - Today they cost three cells per vector, three per `zipWith` call,
    and a loop (the `vect` dump).
- **Sound when.**
  - Only closed indices are used; a symbolic one stays erased.
  - Past the budget, the program falls back to the erased-index
    instance, with an explicit conversion at the boundary.
  - Code size is bounded by the budget.

### R7. Useless fields and unused constructors

- **Fact.** The closed world after specialization: every reader and
  every builder of each field and constructor is known.
- **Representation.**
  - A field that no one reads becomes *absent* (MLton's `Useless`).
  - A field with the same constant value at every construction becomes
    absent, and a read of it becomes the constant.
  - A constructor that is never built is dropped from the layout
    (`RemoveUnused`). Its tag space shrinks: an enum of 7 constructors
    may become a Bool.
- **Decided by** a dialect pass after the simplify loop.
  `remove-dead-values` removes only function arguments and results
  (`Passes/Prune.cc`). Nothing removes constructor fields.
- **IR.**
  - The layout marks the field absent, and the verifier checks that no
    `idr.field` reads it and that no match region uses its block
    argument.
  - Do not retype the field to `!idr.erased`: that type is Idris's
    quantity-0 fact. "Unused" is the compiler's fact, and the two should
    stay distinguishable.
- **Payoff.**
  - `Prelude.Show.Prec` (7 constructors, one with a `!idr.big`) appears
    in every program that shows a value. Conjecture: only a few of its
    constructors are ever built.
  - Records whose fields only some code reads get smaller cells.
- **Sound when.** An absent linear field is still consumed. The value is
  dropped where it would have been stored, so counting still balances.

### R8. Closures after defunctionalization

- **Fact.**
  - Whole-program label sets.
  - After `idr-defunctionalize`, closures of known labels are ordinary
    sums (`@fn$n ... closures`).
  - Kovács: stored functions are exactly what needs a representation.
- **Representation.** R3, R4 and R7 apply unchanged. In addition:
  - zero-capture labels are immediates or an enum;
  - a singleton label set is its captures, with no tag (Hovgaard);
  - a closure sum shaped like Nat (one nullary label, one label that
    captures only its own key) is a counter (Danvy p. 19);
  - a sum shaped like a list (nullary, plus self and payload) that is
    consumed LIFO is a stack.
- **Decided by** the same representation pass. `idr-defunctionalize`
  keeps making sums (`Defunctionalize.cc:14-32`).
- **IR.** The closure sum is an `idr.data` with a layout like any other.
  Labels become per-sum constructor tags.
- **Payoff.**
  - In the `vect` dump, `@fn$0` (`lam55 () | lam80(!idr.box<@fn$0>,
    !idr.data<@fn$1>)`, with `@fn$1` a single label capturing one f64)
    is exactly `List Double`. It is foldr's chain of continuations: a
    24-byte cell per element and a static Nil cell.
  - With R3 its Nil is `NULL`.
  - The stack (array) representation is conjecture. Continuations are
    used LIFO (Danvy §3.2), but that must be proved per program by the
    ownership analysis.
- **Sound when.** The label sets are exact; an unknown set stays
  `!idr.fn`. The meaning of apply is untouched, since only the data
  changes representation.

### R9. Known constructors, CPR and SOP returns (worker/wrapper)

- **Fact.**
  - Indices prove constructors: `Vect (S k) a` is always `::`.
  - A dominating match gives positive information (Sørensen).
  - Idris is strict, so GHC's strictness analysis is free.
- **Representation.**
  - A *known-constructor* type is the constructor's fields as an
    unboxed product.
  - Functions take and return it: CPR, "constructed product result",
    for boxes whose callers take them apart.
  - A result that callers match at once returns into join points, one
    per constructor (Kovács 2024 §3), so no tag and no cell is built.
- **Decided by:**
  - the frontend, which states index-refined signatures (the impossible
    constructors);
  - a dialect pass, which does the worker/wrapper split.
- **IR.**
  - `!idr.con<@T::@C>`, a subtype of the sum, as in RSSA's singleton
    types (`RSSA.adoc`).
  - `idr.con` makes the sum from it; an `idr.match` on it has one case.
  - The verifier checks the fields.
- **Payoff.**
  - `head`, `last` and `zipWith` on `Vect (S k)` test no tag per step.
  - A builder whose caller immediately matches its result allocates no
    cell.
- **Sound when.**
  - The known constructor is proved (by an index or a dominating match),
    never guessed.
  - It is boxed wherever it escapes into a sum slot.

### R10. Strings

- **Fact.** Immutability. Literal contents are known at compile time. A
  linear string is not a unique one, so uniqueness still has to be
  proved.
- **Representation.**
  - Slices (buffer, offset, length): `str.tail` and `str.substr` become
    O(1). Today they copy (`strings.cc:75-83`), so a walk by `strTail` is
    O(n²).
  - In-place append on a string proved unique, with spare capacity.
  - `!idr.str<ascii>`: index and length in O(1) with no flag test.
  - Strings of at most 7 bytes as odd immediates. Counting already skips
    odd words.
- **Decided by** the runtime and a dialect pass. The ascii fact comes
  from literals (frontend or folding) and is propagated through ops.
- **IR.** A parameter on `!idr.str`. Result types of ops are inferred
  (ascii ++ ascii = ascii). The verifier checks ascii literals.
- **Payoff.** A lexer written with `strHead`/`strTail` goes from O(n²)
  to O(n).
- **Sound when.** A slice keeps its buffer alive. An in-place append
  needs proved uniqueness.

### R11. Erased indices: free at runtime already; keep them as ghost facts

- **Fact.** Quantity 0.
- **Representation.** Absent. This is done: `components` of
  `!idr.erased` is empty (`Layout.cc:99-104`). Erased fields keep their
  positions in constructor field lists at no runtime cost.
- **What is missing: identity.**
  - Where a fact mentions an index (R5 symbolic bounds, R12 lengths),
    the index must be a *ghost* SSA value.
  - A ghost is produced by a non-CSE op on its own resource, or has a
    `!idr.ghost<!idr.nat>` type. It has no bits, and it is never merged
    with another erased value.
  - The shared `ConstantLike #idr.erased` stays for everything else.
- **Decided by** the frontend, which knows which indices facts relate.
- **IR.** As above.
- **Payoff.** It enables R5 and R12 soundly.
- **Sound when.** This is exactly the AGENTS rule.

### R12. Contiguous `Vect`

See the proof obligations above.
- **Representation.** A counted buffer cell holding the length and the
  elements, plus slices for tails. Tuple elements are laid out as
  structure of arrays (Futhark).
- **Decided by** a dialect pass, once R5, R9 and R11 exist and uniqueness
  is proved.
- **IR.** A layout choice on the `Vect` instance, plus a verified
  `ValueBounds` relation between the length and the `Fin` indices.
- **Payoff.** Indexing becomes O(1), a numeric loop can be vectorized,
  and there are n times fewer cells.
- **Sound when.** Conditions 1-4 above. This entry is conjecture as to
  how often real programs meet them.

### R13. Integer as a word by range

- **Fact.** Integer is unbounded. Ranges come from:
  - `cast` from `Int`;
  - literals;
  - guards;
  - decreasing recursion.
- **Representation.** i64 (or i128) where the range fits, else the
  tagged big.
- **Decided by** `idr-narrow`, as in R5. MLIR's integer ranges have a
  fixed width, so a 128-bit domain over-approximates.
- **IR.** A narrowed value is a builtin integer with overflow flags on
  its ops.
- **Payoff.** Loops over Integer, and Prelude ranges over Integer, lose
  the tag, the calls and the counting.
- **Sound when.** The range is proved.

## The representation layer as data

**Three layers, each in its own place.**
1. **Facts are types, written by the frontend.** "Idris does types."
   - `!idr.nat` versus `!idr.big`;
   - `!idr.fin<N>`;
   - `!idr.lin<T>` and `!idr.erased` (already);
   - `!idr.con<@T::@C>`;
   - closed-index instances;
   - ghost indices;
   - the containment graph, implicit in the field types.

   The frontend stops deciding `box`: that is a representation, and
   Programs.idr is not where representations belong.
2. **Decisions are one table, written by one pass.**
   - `idr-represent` runs after specialization and defunctionalization,
     before `idr-stack` and `idr-rc`. Counting has to know which slots
     are counted, and immediates are not.
   - It writes a typed layout attribute on every `idr.data`, and narrows
     numeric types.
   - A candidate grammar, after MLton's datatypes and Chataing's heads:

     ```
     Rep     ::= Absent | Word(bits, range) | Float | Big(signed|unsigned)
               | Ptr(CellLayout) | Imm(null | odd k)
               | Sum(tag: Word | Niche | None, alts) | Product(Rep*)
     ConRep  ::= Inline(Product) | Cell(CellLayout, Header k | PtrBits k) | Imm
     TypeRep ::= { conRep: Ctor -> ConRep, head: decision tree, cycleBox: Bool }
     ```

   - The order runs from more precise to less:
     `Absent ⊑ Word(narrow) ⊑ Word(64) ⊑ Big` and `Imm ⊑ Ptr`. The pass
     computes the least representation the facts justify, a fixpoint
     over the containment graph, as `packed-representation.fun:2692-2694`
     establishes dependences.
   - The table:

     | Idris fact | default representation | refined by |
     | --- | --- | --- |
     | quantity 0 | Absent | ghost identity if a fact mentions it |
     | `Int*`, `Bits*`, `Char` | Word | niche (Char > 0x10FFFF) |
     | Nat-like | Big unsigned | Word + `nuw` (range proof) |
     | `Fin N`, N closed | Word(bits N) | none needed |
     | `Fin n`, n symbolic | Nat + relation to ghost n | index with no check |
     | `Integer` | Big signed | Word (range proof) |
     | enum | Word tag | i1 for two constructors |
     | one constructor, no cycle | Product | box above the size threshold |
     | sum, no cycle | Sum(tag, slots) | niche, slot sharing |
     | on a cycle (feedback set) | Ptr cells + Imm nullary | pointer bits |
     | closed-index family | Product chain | clone budget |
     | `Vect n`, n symbolic | list cells | array (R12's four proofs) |
     | closure sum | as sums | counter, stack |
     | `String` | Ptr | slice, SSO, ascii, unique append |
3. **Mechanics only read.**
   - `Lower/Layout.cc` becomes a reader of the attribute.
   - A `RepresentationTypeInterface` on the idr types replaces the
     `components`/`counted` type switches (`Layout.cc:99-129`). Its
     methods: components, counted, head shape, and size through MLIR's
     `DataLayoutTypeInterface`.
   - The original architecture spec said lowering is "representation
     (dialect conversion), not a place where decisions are made" (commit
     `e65bbd3`). This restores that.
   - The JIT reads the same attributes, so compile-time evaluation and
     the program cannot disagree.
   - Typed constant attributes (`#idr.con<...> : !idr.data<@T>`,
     replacing the `NoneType` self type, `IdrOps.td:107-115`) are the
     representation-independent form in which evaluation results come
     back (`Eval/Reify.cc`). They also let a refinement verify its
     constants: `#idr.fin` 7 at `!idr.fin<5>` is rejected.

**What makes it load-bearing.** Every entry is read by lowering, and
checked by a verifier that runs after every pass:
- constructors' heads are disjoint;
- header fields are within their widths;
- every cycle passes through a box;
- absent fields are never read;
- constants are within the bounds of their types;
- box-only ops apply only to cells;
- the counted slots agree with the counting ops.

A decision that is not in the table cannot be expressed. A decision that
contradicts the facts does not verify.

**Precedent for this structure:**
- MLton's `TyconRep`/`ConRep` computed once, and RSSA;
- Chataing's head shapes (and their suggestion to target a layout IR
  such as Ribbit, §8.3);
- Kovács's meta-level `Rep`;
- Rust's per-type layouts with niches.

## Open questions

1. **One sum type or two.** Should `!idr.data`/`!idr.box` be one nominal
   `!idr.sum<@T>` whose layout lives only in the declaration? That is
   one source of truth, but ops such as `reset` would lose their type
   constraint to a verifier rule. The alternative keeps two types that
   the representation pass rewrites with a `TypeConverter`.
2. **Tokens with immediates (R3).** How do `idr-rc`'s reuse tokens
   interact with immediates? A `Nil` that has no cell gives no token,
   and `Nil → Cons` reuse today relies on the static cell.
3. **Clone budget (R6).** What budget keeps closed-index instances from
   exploding? An existing instance budget exists; is it the right knob?
4. **Size-change facts (R5, R13).** Which of Idris's size-change facts
   survive to MLIR, and in what form? They should be function facts
   next to `idr.total`, not discardable attributes.
5. **Measurement.** Is there a benchmark that exercises the heap? None
   does (`bench/README.md`, "Caveats"). R1-R4 need a Nat benchmark, a
   list and tree benchmark, and a `Vect` benchmark before their payoffs
   can be stated as numbers.
6. **Guarantees in types.** Should the compiler *guarantee* some
   representations, in the README's sense of "guaranteed costs"?
   Examples:
   - `Fin N` indexing a contiguous `Vect` is check-free, or the program
     is rejected;
   - Nat is a word under a stated condition.

   Chataing §4.2 argues that silently ignoring a representation request
   is a bug.
