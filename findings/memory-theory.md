# Memory theory: from Idris's quantities to uniqueness

Stream "memory-theory". This note asks exactly what idris-mlir may soundly
assume from Idris 2's quantities, and how it gets from linearity to
*uniqueness*. Uniqueness is what licenses in-place update, static reuse with
no count test, and no reference counting at all.

It builds on:
- review-external-2.md ("Where QTT stands", "What the dream takes");
- mlir-ownership-types.md, the owned stage as types, with a foldable
  indicator.

It corrects both in places:
- deep versus shallow uniqueness (§6.2);
- borrowed parameters that escape (§7.9);
- the rejecting promise (§6.11);
- idr-specialize does not specialize on lone scalars (§6.5).

The user's direction shapes it: push as much as possible onto MLIR's own
implementations. So the primary design reuses:
- bufferization's ownership-based deallocation;
- One-Shot Bufferize's in-place analysis;
- MLIR's DataFlow framework.

Only a residue that MLIR provably cannot cover is ours, and it is kept
minimal.

Experiments ran against the pinned Chez backend (`.toolchain/idris2/bin/idris2`)
and the built idris-mlir, in the stream's scratch directory. Every program
is short and quoted in full, so each one can be rerun.

## The questions

1. What is linearity, what is uniqueness, and how do they combine?
2. What exactly does Idris 2 check for `(1 x : a)`, and so what may the
   compiler assume?
3. Why does a linear binder not imply unique heap ownership?
4. Which Idris idioms *do* give uniqueness, and why are they sound?
5. What does idris-mlir do today?
6. What design puts uniqueness into the representation, with every piece
   load-bearing, and on MLIR's own machinery?
7. Which pitfalls break soundness?
8. Which tests pin the design down?

## The global maximum

The answer in one picture. The sections after this one give the evidence
and the details.

**The theory in one line.** In-place update of `x` at `p` is sound when
`exclusive(x at p) ∧ dead(x after p)`.
- Idris's quantity 1, or the IR's own use count, gives the second conjunct.
- Nothing in Idris's types gives the first. QTT has dereliction: any value
  may fill a 1 binder (§2, §3).
- Exclusivity is *freshness plus linearity of every edge the value crossed
  since it was made* (Marshall et al. 2022, Theorem 5). A compiler must
  establish it, and must never read it off a binder.

**MLIR already solves this problem for one shape of data: flat buffers.**
- *Tensors* are values.
- One-Shot Bufferize decides statically which writes may happen in place.
  A read-after-write conflict is exactly a missing exclusivity: the
  written value is still read later.
- Ownership-based buffer deallocation places the frees, carrying ownership
  as an `i1` SSA value that folds when static.
- The global maximum is therefore: **every piece of Idris data that has
  that shape takes MLIR's path whole, and the rest (heap graphs of cells)
  reuses MLIR's mechanisms (the DataFlow framework, the foldable `i1`,
  canonicalization) with a minimal residue of our own.**

| concern | MLIR does it | our residue, and why MLIR provably cannot |
|---|---|---|
| arrays and other flat buffers (future Idris arrays; `Vect` of scalars when the representation stream chooses contiguous storage) | all of it: `tensor` values, then `one-shot-bufferize` (function boundaries), then `ownership-based-buffer-deallocation`, canonicalize, `buffer-deallocation-simplification`, `lower-deallocations`, `promote-buffers-to-stack`; `linalg`/`vector`/`affine` for the loops; conflicts reported by `print-conflicts` | none, beyond emitting tensor/linalg ops for the array primitives |
| boxes (recursive, sum-typed cell graphs): *is this cell exclusive?* | the DataFlow framework: `AbstractSparseForwardDataFlowAnalysis` with `DeadCodeAnalysis`, interprocedural over the call graph (SparseAnalysis.cpp:263-290), optimistic like SCCP | the lattice and its transfer functions (§6.3-6.5). One-Shot's alias sets express only *may-alias* among SSA values. "The child of an exclusive parent is exclusive" is a *must*-fact about heap reachability, which it has no word for |
| boxes: using exclusivity | bufferization's mechanism: an `i1` SSA indicator, folded by upstream canonicalization (`scf.if` on a constant) and `sccp`; parameters that folded dropped by `remove-dead-values` | the indicator operand on `take`/`reset`/`drop` and the `idr.exclusive` query with its provenance folder (§6.3) |
| boxes: when they die | bufferization's *shape*: insert conservatively, then simplify with patterns (dup+drop cancels; drop of fresh becomes free; drop of exclusive becomes free of the tree) | the count itself: `dup`/`drop` and the runtime test for heap-stored references. Ownership-based deallocation handles only `BaseMemRefType` values (OwnershipBasedBufferDeallocation.cpp:49, `isMemref`); `bufferization.dealloc` frees "the given memrefs", not what they point to; its alias checks compare SSA-visible base pointers. A cell's children are reached through *stored* pointers, and how many there are is a runtime fact (`replicate n xs` stores one list n times) |
| boxes: copies at a conflict | not applicable: One-Shot copies *eagerly and shallowly* (`memCpyFn`, one buffer) | Perceus's *lazy* per-cell copy on the dynamic path. A shallow copy is unsound for a cell graph: the callee would write the shared children. A deep eager copy is asymptotically wrong for persistent data: a tree insert copies a path, not a tree |
| recursion | One-Shot Module Bufferize analyzes the *boundaries* of non-recursive functions only ("We currently skip all function argument analyses for functions that call each other circularly", OneShotModuleBufferize.cpp:518-523) | none. The DataFlow framework is a fixpoint solver and handles cycles, and Idris data code is almost all recursion (`bump`, `map`, `insert`) |
| the stage | a type conversion with `ConversionTarget` legality (mlir-ownership-types.md) | `LinearUses` (exists) tightened to exact counts: MLIR has no linear-type verifier |
| function ABI | `func.call`'s type check verifies whatever the types say (FuncOps.cpp:80) | the types `!idr.own<T>`, `T` (borrowed), `!idr.uniq<T>`: an ABI inferred and typed, Lean-style, where bufferization's is fixed |

**So for boxes the target is four pieces**, each an MLIR mechanism with a
small core of our own:
1. **A linear owned stage** in types: `!idr.own<T>` used exactly once, `T`
   borrowed, and explicit `idr.dup`/`idr.drop`/`idr.borrow`
   (mlir-ownership-types.md).
   - It is the *linear base* that Marshall's entente needs (§6.1): an SSA
     owned value has never been duplicated, by construction.
   - That is what makes exclusivity a local, provenance fact.
2. **Exclusivity as an `i1` that folds.**
   - `idr.take`, `idr.reset` and `idr.drop` take an exclusivity operand.
   - `idr.exclusive %v` supplies it. It folds `true` for a fresh
     constructor tree, a field taken from a statically exclusive parent, or
     a `!idr.uniq` parameter or result. It folds `false` for a constant, a
     stack cell or a `dup` result.
   - Otherwise it lowers to today's runtime count test.
   - Upstream canonicalization deletes the dead branch.
   - Static reuse is the constant case of the dynamic path, as a constant
     ownership indicator folds `bufferization.dealloc` away.
3. **The interprocedural exclusivity lattice** in the DataFlow framework,
   committed into signatures as `!idr.uniq<T>`, with mixed call sites
   cloned. `func.call`'s verifier then checks the caller half of the
   entente, and `LinearUses` the callee half.
4. **Diagnostics in One-Shot's form.** Each take that did not fold is
   reported as a (definition, reuse, reason) conflict, as `print-conflicts`
   reports a RaW triple. That triple is also the named reason when the user
   demands in-place and the compiler rejects (§6.11).

**What this licenses.**
- Test-free reuse and in-place update wherever the indicator folds.
- No `inc`/`dec` for exclusive values: a drop is a free of the tree.
- Loop-carried exclusivity. From the second iteration on the value is
  fresh or reused, so peeling one iteration gives a test-free steady state.
- Count-free types.
- Stack slots reused in place (`promote-buffers-to-stack`'s cousin,
  idr-stack).
- `fip` as a checkable property (FP²).
- For arrays, everything One-Shot and `linalg`/`vector` give, including
  SIMD.
- Idris's quantity 1 becomes the user's *demand*: a failed fold on a demanded
  site is a named rejection, not a silent runtime test.

**Where a single upstream component could replace the residue.**
- *If* boxes of a type are exclusive everywhere (count-free, §6.6) *and*
  live in one arena per structure, then the arena is a flat buffer and
  ownership-based deallocation frees it: the residue vanishes for that
  type.
- That is a representation choice: arenas for exclusive trees. It is
  conjecture, and it belongs with the representation stream.

## The path to it

Each step reuses the most upstream machinery available at that point, and is
verified before the next.

0. **Now, cheap.**
   - Add a regression test that `assert_linear` is rejected. Only
     `believe_me` has one, and exclusivity depends on both (§7.1).
   - Record that borrowed parameters may escape through an inc (§7.9), so
     that nobody builds "borrowed calls preserve exclusivity" on Borrow.cc
     as it stands.
1. **Arrays on the tensor path, from their first line.** There are none
   yet, so there is nothing to migrate.
   - Array primitives are emitted as `tensor`/`linalg` ops.
   - The pipeline gains One-Shot plus the deallocation pipeline for
     functions that have tensors.
   - This is the step with the largest upstream share and the largest
     payoff (review-external-2 step 5).
2. **Owned-stage types** (mlir-ownership-types.md).
   - `!idr.own`, plain `T` for borrowed, `dup`/`drop`/`borrow`.
   - Function types replace `idr.borrowed`; the verifier becomes
     `LinearUses` plus borrow liveness; `idr.stage` goes.
   - Borrow inference moves onto `AbstractSparseBackwardDataFlowAnalysis`
     (mlir-idioms.md §2).
   - Counting becomes conservative insertion plus canonicalization
     patterns.
3. **The exclusivity operand and the query, intraprocedural.**
   - `take`/`reset`/`drop` lower to `excl ∨ idris_rt_is_unique`.
   - `idr.exclusive` folds by provenance, deep when static (§6.2).
   - Upstream canonicalization removes the dead `scf.if` branches.
   - Payoff: static reuse inside functions and inlined callers.
4. **Interprocedural.**
   - The exclusivity lattice as a sparse forward analysis.
   - One idr-specialize key for "all owned box arguments exclusive":
     today it skips lone scalars (Specialize/Pattern.h:83-85).
   - The commit into `!idr.uniq<T>`.
   - Payoff: static reuse across calls, checked by `func.call`.
5. **Properties, remarks and demand.**
   - `idr-expect in-place=@f` and `fip=@f`.
   - Conflict remarks, and the demand option (§6.11).
6. **Stack, loops and counts.**
   - Reuse-equivalence edges in the escape summaries (One-Shot's
     `BufferRelation::Equivalent`).
   - Loop peeling for loop-carried exclusivity.
   - A census of never-shared types for count-free representations, and
     arenas as the bridge to ownership-based deallocation.
## 1. The semantics

**Linearity is a property of the consumer, and it constrains the future.**
`f : (1 x : a) -> b` promises that "if `f x` is evaluated exactly once, `x` is
evaluated exactly once" (brady-2021-idris2-qtt, linearity.tex §Linearity).
The promise restricts what the body does with its binder. It says nothing
about where the argument came from.

**Uniqueness is a property of the value, and it is a guarantee about the
past.** No duplication has happened since the value was created, so exactly
one reference to its cells exists. Marshall et al. (2022, p.353, §2.2) say
it this way: linearity restricts *outgoing* substitutions, uniqueness
guarantees *incoming* ones.
- Takeaway (§2.2): the two behave "dually with respect to composition, but
  identically with respect to structural rules".
- The conversions run in opposite directions:
  - unique to shared is free (their `&` borrow, `*A → !A`);
  - shared to unique needs a copy (`copy`/`clone`);
  - unrestricted to linear is free (dereliction, `!A → A`);
  - linear to unrestricted is impossible.

**The entente cordiale (LCU, Marshall 2022 §3).** The calculus has a
*linear* base, with `!` for non-linearity and `*` for uniqueness.
- Necessitation (`∅ ⊢ t : A` gives `[Γ] ⊢ t : *A`): a closed, fresh term is
  unique.
- Borrow and copy mediate between `*` and `!`.
- Theorem 5 (Uniqueness): references unique in the incoming heap, and fresh
  ones, stay unique in the value that reduction produces.

The two notions agree when nothing is unrestricted: "in a setting where all
values must be linear, we can also guarantee that every value is unique"
(p.349; Wadler's *steadfast* types, p.350). They come apart through exactly
one rule, dereliction: "any linear value could have previously been a
non-linear one that was duplicated any number of times before being
specialised (via dereliction) to a linear type" (p.351).

**Combined, for a compiler.** An in-place update of `x` at a point `p` is
sound when two facts hold:

  unique(x at p)  ∧  dead(x after p)

- *dead after p* is linearity, the consumer's half. Idris's `1`, or the IR's
  own use count, provides it.
- *unique at p* is the history half: a fact about every caller, back to
  where the value was created.

Uniqueness is therefore *freshness plus linearity of every edge the value
has crossed since it was created*. The rest of this note makes that
equation operational.

**The same split in the other sources.**
- bernardy-2018-linear-haskell, hlt.tex:2878-2886: "a linear type is a
  contract that a function uses its argument exactly once even if the
  call's context can share a linear argument as many times as it pleases …
  uniqueness typing is a *non-aliasing analysis* while linear typing
  provides a *cardinality analysis*."
- lorenzen-2023-fp2, §1.4: the `fip` check is a check of the *callee*.
  Whether a call can be run destructively "requires further information
  about how arguments are shared at call sites". Koka decides that at
  runtime.
- FP² Theorem 1 states the precondition exactly: the store of owned values
  must be *linear*, meaning every variable is referred to at most once
  (Definition 1). That is deep uniqueness.

## 2. What Idris 2 checks, and what the compiler may assume

Read from the pinned `src/Core/LinearCheck.idr` and its helpers:

- **Variables** (LinearCheck.idr:161-176). `rigSafe l r` fails only when
  `l < r`, where `l` is the binder's quantity and `r` the context's. The
  preorder (Algebra/ZeroOneOmega.idr:14-17) has `_ <= RigW`, so an
  **ω binder may be used in a 1 context**. That is dereliction. Usage is
  counted only when the context is linear (`used`).
- **Application** (171, 284-289). The argument is checked at
  `rigf |*| rig`: an argument in a 1 position of a linear context counts
  once, and an ω position turns a linear variable into an error.
- **Lambda** (225-272). The scope of a non-Pi binder is checked at
  `linear`. When the enclosing context is ω, `eraseLinear env` makes linear
  variables unusable inside the lambda. So **a closure that captures a
  linear variable can only be used linearly.** Experiments: a `where`
  function capturing `1 x` is "not accessible"; `let h = p xs in (h 1, h 2)`
  gives "Trying to use linear name h in non-linear context".
- **Binder discharge** (274-276). A linear binder must be used exactly once.
  In case blocks the LHS locals are *affine* (473-486, `isLocArg`): they may
  be unused because they are used outside.
- **Pattern variables** (TTImp/ProcessDef.idr:216-220). A pattern variable's
  quantity is `rigMult c rig`, the constructor field's quantity times the
  argument's. **Matching a `1` scrutinee whose constructor fields are ω
  binds ω variables.** libs/linear defines a separate `LList` with
  `a -@ LList a -@ LList a` precisely to get linear fields.
- **Pi types are invariant in their quantity** (Core/Unify.idr:1059,
  `if cx /= cy then err`). A function value's type states its argument's
  quantity exactly.
- **Erased uses do not count** (qtt linearity.tex, "Remark": uses in
  `Ordered xs` do not count).

**What idris-mlir may soundly assume.** This holds in the accepted subset:
the frontend already rejects `believe_me`, `assert_linear` (which *is*
`believe_me id`, Builtin.idr:198-199), user `assert_total`, holes,
`unsafePerformIO` except as the program root, and unregistered `%extern`
(Frontend/Profile.idr:195-205, Registry/Recognized.idr:43-53). I checked
that `assert_linear (\z => (z, z)) xs` is rejected as `unsupported (escape
hatch)`. It also assumes Idris's checker has no bugs.

- **A1.** A quantity-0 binder is never needed at runtime (`!idr.erased`).
- **A2.** A quantity-1 binder is consumed at most once on every path, and
  exactly once on paths that return normally. In IR terms, `LinearUses`
  (Dialect.cc:328) counts the worst path, which is the right check.
- **A3.** A quantity-1 constructor field is consumed once when the
  constructor value is consumed once (`MkIORes`'s world; `LList`).
- **A4.** A closure or partial application that captures a quantity-1
  binder is applied at most once.
- **A5.** `!idr.fn<(!idr.lin<A>) -> B>` means every closure of that type
  consumes its argument at most once (A5 follows from Pi invariance).
- **A6.** The world is threaded linearly, and only the root creates it.

**What it may NOT assume.**

- **N1.** That the argument of a `1` parameter is unique. Dereliction
  forbids it (§3).
- **N2.** That the fields of a matched `1` scrutinee are linear or unique
  (ProcessDef `rigMult`; `twoTails` in §3).
- **N3.** Anything about results. "In QTT, multiplicities are associated
  with *binders*, not with return values or types" (qtt protocols.tex:15-18).
- **N4.** That a value created through a linear continuation stays linear.
  It depends on the continuation's result type (§4).
- **N5.** That a value used linearly is used only once *in terms*. Erased
  positions may mention it again. `g xs = f xs xs Refl`, with
  `f : (1 xs : L) -> (0 ys : L) -> (0 _ : ys = xs) -> L`, type-checks.

**Consequence.** After defunctionalization idris-mlir sees the whole program
first-order. It can recompute A2-A5 from the IR itself (Beans' owned
parameters are exactly "used once in the body"). So **quantity 1 is not
needed for the soundness of uniqueness, nor for most of its benefit.**
Prelude `map`/`foldr` carry no `1`, but their list parameter is consumed
once in the IR, so fresh lists passed to them can be updated in place too.

Quantity 1 remains load-bearing in three roles:
1. It is a verified invariant that passes cannot break (`LinearUses` after
   every pass).
2. It states the programmer's *demand*, which turns a silent performance
   cliff into a diagnostic or a rejection (§6.11).
3. It carries one-shot closures before defunctionalization.

Quantity 0 is representation, and it is already fully exploited.

## 3. Why a linear binder does not imply unique heap ownership

Counterexample, checked with the Chez backend:

```idris
module Lin1
bump : (1 xs : List Int) -> List Int
bump [] = []
bump (x :: xs) = (x + 1) :: bump xs

twoTails : (1 xs : List Int) -> (List Int, List Int)
twoTails [] = ([], [])
twoTails (y :: ys) = (ys, ys)          -- accepted: ys is ω (field ω × scrutinee 1)

main : IO ()
main = do
  let ys = [1, 2, 3]
  printLn (bump ys)                    -- a shared ys fills a 1 binder: dereliction
  printLn (bump ys)
  printLn ys
  printLn (twoTails ys)
```

Chez prints `[2, 3, 4]`, `[2, 3, 4]`, `[1, 2, 3]`, `([2, 3], [2, 3])`. A
compiler that trusted the binder and rebuilt `xs` in place would print
`[2, 3, 4]`, `[3, 4, 5]`, `[3, 4, 5]`.

The precise reasons, each with its own counterexample:

1. **Dereliction.** Any ω value may fill a 1 binder (`rigSafe`,
   `_ <= RigW`), as above. The IR already reifies the rule:
   `idr.lin.enter`'s documentation says "Idris lets any value fill a
   quantity-1 binder" (IdrOps.td:1034).
2. **Fields are not covered.** Pattern variables of ω fields are ω even
   under a 1 scrutinee (`twoTails`). A unique top cell says nothing about
   the tail, unless construction guaranteed it (§6.2).
3. **Results carry no quantity.** A `1`-consuming function may return an
   alias of anything it can reach.
4. **Laundering through a continuation.** Contrib's
   `newArray : Int -> (1 _ : (1 _ : arr t) -> a) -> a`
   (contrib/Data/Linear/Array.idr:18) leaves `a` free. See §4.
5. **Escape hatches.** `assert_linear (\z => (z, z)) x` type-checks.
   `unsafePerformIO (newArray 4)` as a top-level value hands the same
   array to everyone. Both are rejected by idris-mlir today, and §7 argues
   the rejection is load-bearing.
6. **Idris-mlir itself creates sharing without any `ω` in the source.**
   - Compile-time evaluation and `ConOp::fold` turn a constructor with
     constant fields into a persistent static cell (Ops.cc:369). In the
     experiment `bump (C n (C 2 (C 3 N)))` the tail is `idr.constant
     #idr.con<@Main.L::@C, [2, …]>`.
   - idr-stack gives the top cell `{idr.stack}`, and a stack cell is "never
     exclusive" (idris_rt.h:48-54): a callee's reuse could outlive the
     frame.
   - So *fresh at the source level* is not *exclusive at runtime*.

## 4. Idris idioms that do give uniqueness, and why

**(a) Linear continuation-passing creation of an abstract type.** The QTT
paper (protocols.tex:19-27): "The array must be used exactly once in the
scope of `k`, and if this is the only way of constructing an `Array`, then
all arrays are guaranteed to be used linearly, so we can have in-place
update."

The argument is induction over the program. Every binder that can hold a
value of the type is linear: the continuation's parameter, the linear
fields of the results `Res`/`LPair`, and so on. So no ω binder of the type
ever exists, dereliction can never apply, and linear everywhere implies
unique (Marshall p.349).

Linear Haskell lists the three conditions that make this true
(hlt.tex:913-924):
1. creation introduces *only* a linear value;
2. no consumer returns more than one pointer to it;
3. the continuation "must wrap its result in `Unrestricted`", so nothing
   escapes.

Idris has the third ingredient as `!*` (libs/linear Data/Linear/Notation.idr:
`MkBang : a -> !* a` takes its field at ω). **The contrib API omits the
wrapper, and the omission is observable**:

```idris
module Esc
import Data.Linear.Array
leak : LinArray Int
leak = newArray 4 (\arr => arr)            -- a = LinArray Int
leakF : () -> LinArray Int
leakF = newArray 4 (\arr => \u => arr)     -- a closure hands it out again
main : IO ()
main = do
  let a = leak
      (_ # a1) = write a 0 10
      (_ # a2) = write a 0 20              -- the consumed a, written again
      (v # _)  = mread a1 0
  printLn v                                -- prints Just 20: a1 was aliased
  let f = leakF
      (_ # b1) = write (f ()) 1 7
      (w # _)  = mread (f ()) 1
  printLn w                                -- prints Just 7
```

The sound signature is `withArr : Int -> (1 k : (1 a : Arr) -> !* b) -> !* b`.
Against it, `withArr 3 (\a => MkBang a)` is rejected ("Trying to use linear
name a in non-linear context"), and so is `withArr 3 (\a => MkBang (\u => a))`
("a is not accessible in this context"). The Ur wrapper blocks both escapes.

Two more conditions are needed on the Idris side:
- the constructor must be `export`, not `public export`;
- there must be no `Duplicable` instance.

The implementation module itself stays trusted: contrib builds `LinArray`
with `unsafePerformIO`.

**(b) LIO** (libs/linear Control/Linear/LIO.idr).
- `L io {use} a` records how the result may be used.
- `Action : (1 _ : io a) -> L io {use} a`: the *action's author* chooses
  `use = 1`. This is a trusted claim that the action returns something
  fresh.
- `Bind` binds a `use=1` result with a linear continuation
  (`ContType io Linear … = (1 _ : a) -> …`, lines 63-65).
- `run : L io a -@ io a` exists only at the default `use = Unrestricted`
  (lines 88-93), so a linear resource cannot escape `run`.

Uniqueness follows by the same induction as (a). Its base case, freshness,
is the action author's word.

**(c) The world.** `%World` is linear, and only the root creates one
(`unsafeCreateWorld` is root-only in Registry/Recognized.idr:46-48). It is
the steadfast value par excellence.

**What this means for idris-mlir.** These idioms make uniqueness
*expressible and guaranteed in Idris source*, so a compiler's uniqueness
inference is certain to succeed on them. But the compiler must not *trust*
them: Esc shows the library claim can be wrong. Soundness comes from the
compiler's own inference (§6.5). The idioms give *completeness*: programs
written this way never fall back to runtime tests.

## 5. What idris-mlir does today

- **`!idr.lin<T>`** is exactly Idris's `1`: at most one use per path, verified
  after every pass (Dialect.cc:399). `lin.enter` and `lin.use` are
  `MemAlloc<LinResource>`, so CSE never merges two entries (IdrOps.td:1024-1033).
- **idr-rc** runs Beans' passes in Lean's order:
  1. reset/reuse (ResetReuse.cc);
  2. borrow inference (Borrow.cc);
  3. Perceus counting (Counts.cc).

  Quantity 1 is used once, to keep such parameters owned (Borrow.cc:53).
- **Reuse is dynamic.** `idr.take` lowers to
  `scf.if exclusive(cell) then cell else {inc fields; dec cell; null}`
  (Lower/Counting.cc:92-150). `idr.reuse` tests the token. The runtime's
  `isExclusive` is `count == 1 && !stack` (rc.cc:28), and a persistent cell
  (count 0) is never exclusive.
- **The static version is planned but not built**: "Where a box is proved
  unique, the test can go … That is a fact about callers, not about the
  binder, so it belongs on the parameter's type" (ResetReuse.cc:20-26).

Observed IR after idr-rc (e1: `build`, then `bump ys` twice, then
`bump (build n)`):

```mlir
func.func private @Main.bump(%arg0: !idr.lin<!idr.box<@Main.L>>) -> !idr.box<@Main.L> {
  %1 = idr.lin.use %arg0 …
  %2 = idr.match %1 … {
  case @C(%arg1: i64, %arg2: !idr.box<@Main.L>) {
    %3:3 = idr.take %1 @Main.L::@C : … -> (!idr.token, i64, !idr.box<@Main.L>)   // tests count
    …
    %6 = func.call @Main.bump(%5) …
    %7 = idr.reuse %3#0 @Main.L::@C(%4, %6) …                                 // tests token
// root:
%4 = call @Main.build(%3)
idr.inc %4                     // ys is used again: count 2, bump copies
%6 = call @Main.bump(%5)
…
%18 = call @Main.build(%3)     // fresh: count 1, but bump still tests
%20 = call @Main.bump(%19)
```

**The fractional pattern already happens dynamically.** In e3,
`total' ys + total' (bump ys)` produces no `inc`: `total'`'s parameter is
`{idr.borrowed}`, so `ys` keeps count 1 and the take reuses it at runtime.
The static design has to turn exactly that into a folded fact (§6.9).

## 6. The design in detail

### 6.1 Where exclusivity lives: the linear base

The entente needs a **linear base** (Marshall §3: "we present a system where
linearity is the base and uniqueness is a modality").

- idris-mlir's *pure* stage has an unrestricted base, QTT's. Its values are
  values, so CSE, folding and compile-time evaluation share them freely,
  and "one reference" is meaningless there.
- Its *owned* stage is Perceus's λ1 / Beans' λRC. Once it is typed
  (path step 2: `!idr.own<T>`, used exactly once, with an explicit `idr.dup`),
  it is a linear base with `!` made explicit.
- **In that base, an SSA owned value has never been duplicated**: `dup`
  consumes its operand and makes new values. So exclusivity becomes a
  property of an SSA value's *provenance*. That is what lets
  `idr.exclusive` fold locally (§6.3), with no global invariant to trust.

Exclusivity therefore belongs to the owned stage. It is established when
idr-rc builds that stage, and it is lost only at explicit ops: `dup`, a
store into a cell that is not exclusive, a constant, a stack cell. The same
linear-use rule verifies it, as for `!idr.lin` and the world.

### 6.2 What "exclusive" means: deep, over the cell graph of boxes

A reference is **deeply exclusive** when its **cell graph is a tree of
exclusively held heap cells**:
- the value's own cell (for an unboxed sum, each counted slot's cell);
- and, transitively, every cell reachable through a field of box (or
  boxed-closure) type;
- each has count 1, is on the heap (neither static nor on the stack), and
  is reached only through this reference.

Nullary constructors are exempt. They are persistent atoms with no fields,
so there is nothing to reuse (FP²'s `atom` rule, ⋄0). Non-box leaves
(`str`, `big`, scalars) are not covered: they keep their own counts.

- *Why deep.* The recursive call of `bump` receives the tail, a field of
  the taken cell. With a shallow claim the tail is unknown, and every level
  after the first needs a test. Review-external-2's step 2, "untested reset
  for unique scrutinees", works for one level only, for exactly this
  reason. Deep is FP²'s "linear store" (Def. 1) and Marshall's Theorem 5
  ("all array references in v").
- *Why boxes only.* A list of literal (static) strings can still be
  exclusive. Zippers of trees (FP²'s splay trees) are covered because both
  are boxes.
- *Cost.* A list that holds a *shared* inner list is not exclusive, and
  falls back to the runtime test. A per-position cover
  (`!idr.uniq<T, #idr.cover<…>>`, Clean-style attributes) is the refinement
  if programs need it. That is an open question.
- *Shallow at runtime.* The runtime test (`count == 1 && !stack`) proves
  only *this* cell exclusive. So a field taken from a parent whose
  exclusivity was tested at runtime is unknown. Only statically deep
  exclusivity passes down to fields. Perceus is sound for the same reason:
  it tests at every level.

### 6.3 Representation

- **`!idr.own<T>`** is an owned reference, used exactly once on every path
  (path step 2). Plain `T` in the owned stage is a borrowed reference.
- **`idr.exclusive %v : !idr.own<T> -> i1`**. It borrows `%v`, and
  `true ⇒ %v's cell is exclusive`; `false` is always safe.
  - Its folder decides from provenance, through `lin.enter`/`lin.use`:
    - **true** when `%v` is:
      - an `idr.con`/`idr.reuse` of a box whose box field operands are
        themselves deeply exclusive (folded true) or atoms;
      - a box field of an `idr.take` whose operand's `idr.exclusive`
        folded true, statically and so deeply;
      - a parameter or call result of type `!idr.uniq<T>`.
    - **false** when `%v` is a constant, an `idr.con {idr.stack}`, or a
      `dup` result.
    - Otherwise it does not fold, and it lowers to `idris_rt_is_unique`,
      the runtime count test that exists today (rc.cc:133-137).
  - Folding true from provenance is sound only because `own` is linear:
    between `%v`'s definition and its query, nothing can have duplicated
    it.
- **Consumers.**
  - `idr.take %v, %excl` lowers to `%excl ∨ rt_is_unique(cell)`.
  - `idr.reset` lowers the same way.
  - `idr.drop %v, %excl` lowers to `%excl ? free_tree : dec`.

  With `%excl` a constant true, canonicalization deletes the `scf.if`
  that Lower/Counting.cc:118-133 builds today, along with the incs and the
  dec on its dead branch.
- **`!idr.uniq<T>`** is an owned reference that is deeply exclusive, used
  in function signatures only. It is where the static fact must survive a
  call boundary, which cuts provenance. Inside a body it adds nothing that
  provenance does not already give.
- **Reuse credits.** A take whose indicator folded true gives a
  definitely-present cell: `!idr.cell<N>`, FP²'s ⋄k. It is linear, and it
  is consumed by `reuse` (whose constructor must have size N, a type check
  that replaces Verify.cc's `fits()` walk to the defining reset) or by
  `free`. The nullable `!idr.token` stays for the dynamic path. Whether the
  token type is `cell<N>` or `token` follows from the folded indicator, so
  the two types need no separate flag.
- **Borrowed parameters** are plain `T` in function types, not the
  discardable `idr.borrowed` attribute. A borrow is also what preserves the
  caller's exclusivity (§6.9), and a fact that another fact depends on
  cannot sit in a discardable attribute.

### 6.4 Rules: introduction, preservation, loss

- **Fresh.** A box `idr.con` or `idr.reuse` whose box field operands are
  deeply exclusive or atoms is deeply exclusive. This is necessitation.
- **Call.** A call's argument to a `!idr.uniq` parameter must be
  `!idr.uniq`. `func.call`'s own verifier enforces that. Results follow
  the callee's result type.
- **Take.** The fields of a take whose indicator folded true are deeply
  exclusive; its cell is `!idr.cell<N>`.
- **Borrow.** A read that does not consume (a field read, a match
  inspection, a borrowed argument) leaves `%v`'s exclusivity intact when
  the borrow cannot outlive the call or scope (§6.9, §7.9).
- **Loss.** Exclusivity is lost at:
  - `idr.dup`, which gives both results `false`. Marshall's `&`;
  - an inc of a field of `%v` while `%v` lives. Counts.cc's "a field of an
    owned value takes a reference of its own" is exactly such a demotion,
    so a planner should prefer `take`, which moves fields out;
  - `lin.enter` of a value that is not exclusive.
- **Copy.** `idr.copy : T -> !idr.own<T>` is a runtime deep copy whose
  result is exclusive (Marshall's `copy`/`clone`, One-Shot's
  out-of-place buffer). The planner inserts it only where it chooses to
  thaw, for example a compile-time constant entering an in-place loop.
- **Constants.**
  - No constant is exclusive. `materializeConstant` builds no
    `!idr.uniq`, so a fold that would turn a fresh `!idr.uniq`
    constructor into static data fails by construction: OperationFolder
    abandons a fold whose materialization fails
    (Transforms/Utils/FoldUtils.cpp:275-300).
  - CSE never merges box constructors, which have an `Allocate` effect.
    CSE only merges effect-free or read-only ops
    (Transforms/Utils/CSE.cpp:264-268).
- **Free.** A drop whose indicator folds true frees the tree without a
  single count test: exclusive box fields are freed, other counted fields
  dropped.

### 6.5 Inference and verification

**Inference is dataflow, not a bespoke fixpoint.**
- The lattice per owned box value is `exclusive < unknown`, with an
  uninitialized bottom.
- The analysis is an `AbstractSparseForwardDataFlowAnalysis`:
  - transfer functions are the provenance rules above;
  - arguments of private functions join over all their call sites
    (SparseAnalysis.cpp:263-290);
  - results join over returns.
- It is optimistic, starting at bottom like SCCP (Transforms/SCCP.cpp:
  "assumes that all values are constant until proven otherwise"). That is
  sound for this invariant, "every value flowing in is exclusive", by
  induction on the length of the execution.

Then:
1. Where a function is called with both exclusive and unknown arguments,
   specialize it. One key per function: "all owned box parameters
   exclusive". It is bounded by the existing clone budget.
2. The exclusive clone's recursive calls pass taken fields, which are
   deeply exclusive, so they call the clone again.
3. The public root and closure-named functions stay fixed, as in
   Borrow.cc.
4. Commit: parameters and results whose lattice value is `exclusive` get
   type `!idr.uniq<T>`, and every `idr.exclusive` folds.

**Verification**, after every pass:
- **Types.** `func.call` and `return` type checks. The op verifiers: a
  take whose result is a `cell` needs an indicator that folds true; the
  reuse cell size; no `!idr.uniq` constant.
- **Uses.** `!idr.own`, `!idr.uniq` and `!idr.cell` values are consumed
  exactly once per path. That is `LinearUses` (Dialect.cc:328), tightened
  to exact counts.
- **Borrow liveness.** A borrow of `u` is used only before `u`'s consuming
  use. That is Verify.cc's `alive()`/`owners`, now over types.
- **Provenance.** A `!idr.uniq` result is returned only from values whose
  `idr.exclusive` folds true. The folder is the verifier.

### 6.6 What it licenses

- **Static reuse with no count test.** A folded take gives a cell, and
  `reuse` is a plain store into it. `bump` on an exclusive list becomes,
  after idr-tail-loops, a loop of loads and stores with no branch.
- **In-place update.** Reusing the same constructor with the same fields
  leaves only the changed stores; LLVM removes stores of unchanged loaded
  values.
- **No inc/dec.** Exclusive values are never counted. Their drop is a
  free, and their reuse is unconditional.
- **Loop-carried exclusivity.** A loop's iteration argument that is
  rebuilt by reuse or fresh construction each iteration is exclusive from
  the second iteration on.
  - Carrying its indicator as an `i1` iteration argument makes that
    visible to folding.
  - Peeling the first iteration then leaves one runtime test *outside* the
    loop. That is conjecture: `scf.while` needs a hand rotation, because
    the upstream peeling utilities target `scf.for`.
- **Count-free types.** Conjecture, whole-program. If no value of a
  monomorphic type is ever non-exclusive (no `dup`, no non-atom constant,
  no stack cell), its counting disappears entirely. Linear-API abstract
  types satisfy this by §4(a), which is Wadler's claim that such values
  "require no reference counting or garbage collection".
  - Dropping the count *word* needs runtime support: `releaseOwned` reads
    slot counts.
- **Stack and regions.** Today stack and reuse exclude each other (a stack
  cell is never exclusive, idris_rt.h:48-54).
  - With a "result is equivalent to this parameter's cell" edge in the
    escape summaries (One-Shot's `BufferRelation::Equivalent` is the same
    notion), a cell reused in place inside its frame can stay on the
    stack.
  - A loop-carried cell reused in place is *one* slot.
  - `promote-buffers-to-stack` is the upstream analog of idr-stack.
  - Regions: an exclusive structure built and wholly freed inside a
    non-escaping scope can live in an arena. Conjecture.
- **fip as a property.** A function is fully in place when:
  - every take and reset in it has an indicator folded true;
  - every box construction is a reuse of such a cell;
  - there is no `dup`, `copy` or allocation (FBIP additionally allows
    `free`);
  - and calls within its call cycle are tail calls (FIPS).

  FP² Theorems 2-4 then give no (de)allocation and constant stack.
- **Strings and arrays.**
  - `idr.str.append` on an exclusive string can extend in place, as Lean
    does at runtime.
  - Arrays take the tensor path (§6.10), where most of the payoff is
    (Marshall §4.2; review-external-2 step 5).

### 6.7 Interaction with the existing passes

- **idr-rc** runs in this order:
  1. reset/reuse (destination choice);
  2. borrow inference (into function types);
  3. exclusivity analysis and commit;
  4. counting.

  Counting places `dup`/`drop` conservatively, and canonicalization
  simplifies:
  - `dup` followed by `drop` of the same value cancels;
  - a `drop` of a fresh constructor becomes a free;
  - a `drop` with a true indicator becomes a free of the tree.

  That is the `buffer-deallocation-simplification` style
  (OwnershipBasedBufferDeallocation.md), and it moves correctness out of
  Counts.cc's placement and into a verifier plus patterns.
- **reset/reuse.** The D/S heuristic is unchanged. Only the token's type
  follows the folded indicator.
- **Borrow inference.** A borrowed parameter preserves the caller's
  exclusivity only when it does not escape (§7.9). The escape summaries
  idr-stack already computes (Escape.h, parameter nodes) answer that.
- **idr-stack.** A stack cell's indicator folds false (path step 3). The
  reuse-equivalence edge relaxes that later (§6.6).
- **Compile-time evaluation.** Closed results become persistent constants
  and so fold false. That is correct, and costs at most one `copy` at the
  boundary.
- **Defunctionalized closures.** Captures are fields of the closure sum. An
  apply of an exclusive closure takes the closure apart and moves the
  captures out, so a one-shot continuation's captures stay exclusive. This
  is where Idris's A4 and A5 show up after defunctionalization.

### 6.8 Stages as types, not an attribute

review-external.md's smell is that `idr.stage = "owned"` switches the
meaning of the same ops. Beans separates λpure from λRC:
refcount.tex:84, "The target language λRC is an extension of λpure".
mlir-ownership-types.md gives the MLIR form, and this design depends on it:
- with `!idr.own<T>`, the stage is a type conversion;
- legality is a `ConversionTarget` over types;
- the verifier is one linear-use rule for every linear type (`lin`, world,
  `own`, `uniq`, `cell`) plus borrow liveness;
- `idr.stage`, `inOwnedStage` (Ownership/Ops.cc) and Verify.cc's
  path-by-path count interpreter go;
- a pure pattern cannot match owned IR, because the types differ.

The one cost: shared ops (`idr.con`, `match`, `field`, `func.call`) compare
field types through a projection that strips `own`/`uniq`, as
`unrestricted()` does for `lin` today.

A separate dialect, rather than new types in `idr`, adds nothing the types
do not already give.

### 6.9 What fractional uniqueness adds

Marshall & Orchard 2024 grade the non-uniqueness side: `&p A` with
`p ∈ (0,1] ∪ {*}`, where `*A ≡ &* A`.
- `withBorrow` lends a unique value as `&1`, provided it comes back.
- `split`/`join` halve and recombine permissions.
- `push`/`pull` borrow one part of a product while the rest stays owned
  (§5.2).
- Borrow safety is their Lemma 6.8 and Theorem 6.9.

For idris-mlir this gives three things:
1. **The justification for keeping exclusivity across borrowed calls.**
   `total' ys; bump ys` (e3) is split, then read at 1/2, then join. In the
   typed owned stage that is `idr.borrow %ys`, the call, then the borrow's
   last use, then the consuming use. The join is sound because a borrow is
   plain `T` and cannot be stored without a `dup`, which is the loss rule.
2. **Partial borrows.** A field read from an exclusive value is a borrow
   owned by that value. Reading the head while updating the tail keeps the
   tail exclusive. This is the `push`/`pull` pattern, and FP²'s `let` rule,
   which lends Γ2 to e1 while e2 owns it.
3. **Mutable borrows** are Idris's threading idiom. `(1 a : Arr) -> …
   -> Res x (const Arr)` is `&1`: a `!idr.uniq` parameter returned as a
   `!idr.uniq` result.

What it does *not* add is fraction values in the IR. The existential
identifiers `∃id` of their §4 become SSA owner identity, and `join` becomes
"the borrow's last use precedes the owner's consuming use", which SSA
liveness decides. Fractions would be needed only if borrows could live in
data, as Rust's references in structs do. Idris has no such thing, and
idris-mlir should keep forbidding it.

### 6.10 Bufferization compared: what to adopt

| bufferization | here | verdict |
|---|---|---|
| ownership `i1`, "responsibility to deallocate", lattice uninitialized < unique(X) < unknown | `own` is linear, so responsibility is by construction; the `i1` means **exclusivity**, lattice uninitialized < exclusive < unknown | adopt the mechanism (an SSA `i1`, materialized lazily, folded), not the meaning |
| `bufferization.dealloc … if (%own)`, runtime alias checks that fold when static | `take`/`reset`/`drop` with `%excl ∨ rt_is_unique`, which folds when static | adopt |
| conservative insertion, then simplification patterns | conservative `dup`/`drop`, then cancellation and free patterns | adopt |
| fixed function ABI (arguments never owned, results owned) | inferred ABI in types (`T` borrowed, `own`, `uniq`) | keep ours: whole-program, Lean-style, but typed |
| One-Shot in-place analysis: RaW conflicts over SSA use-def, DPS destinations | reuse tokens as destinations; conflicts reported as a (definition, reuse, later use) triple | adopt the reporting and the DPS view; the analysis is the exclusivity lattice, because buffers-in-buffers are outside One-Shot's alias model |
| out-of-place means an eager copy of the whole buffer at the conflict | Perceus's lazy path copy at a non-exclusive take | keep ours for boxes (a tree insert copies a path, not a tree); use theirs for arrays |
| `memref.alloca` has ownership false; `promote-buffers-to-stack` | stack cells fold false; idr-stack | same shape; relax with reuse-equivalence edges |
| `TensorLikeType`/`BufferLikeType` interfaces (Bufferization/IR/BufferizationTypeInterfaces.td) let custom types enter One-Shot | Idris arrays as `tensor`s (or a TensorLike type) | adopt for arrays; not for boxes (below) |
| One-Shot Module Bufferize, function boundaries | the exclusivity lattice over the call graph | theirs skips the boundaries of recursive functions (OneShotModuleBufferize.cpp:518-523), which is nearly all Idris data code; the DataFlow framework's solver does not |
| a replaceable analysis (`AnalysisState::isInPlace`, Bufferization.md "Modular") | our lattice could be plugged in as the analysis | possible, but One-Shot's rewrite then inserts eager shallow copies for out-of-place operands, which is wrong for cell graphs; there is no gain without its rewrite |

**Why boxes cannot take the bufferization path, precisely.** I evaluated the
cheapest route: make `!idr.box` a `TensorLikeType` and the owned reference a
`BufferLikeType`, then implement `BufferizableOpInterface` on
`con`/`match`/`field`/`take`.

- *Soundness needs aliases that are too coarse.* A field read must alias its
  parent (`BufferRelation::Unknown`), and a constructor its box fields.
  Otherwise, after `replicate 3 ys`, a write through one element is not
  seen to conflict with a later read of another. That is sound, but it
  unions whole structures into one alias set.
- *Its out-of-place fix is a shallow copy.* `memCpyFn` copies one buffer,
  so a callee writing a copied cell's children would corrupt the shared
  original. A deep copy repairs soundness, at an asymptotic price for
  persistent data.
- *Its deallocation cannot see inside cells.* It is typed on
  `BaseMemRefType` (OwnershipBasedBufferDeallocation.cpp:49), frees one
  buffer at a time, and decides aliasing by comparing SSA-visible base
  pointers. Releasing a dead cell's children needs their counts.
- *Its module analysis stops at recursion.*

What remains to reuse for boxes is its *mechanisms*: the foldable `i1`,
conservative insertion then simplification patterns, DPS destinations, and
the conflict report. Those are adopted above. The count is the residue.

**The tensor path for arrays.** An Idris array API is value-semantic:
`write : (1 a : Arr) -> Int -> t -> Arr` is `tensor.insert`, `read` is
`tensor.extract`, and `map`/`zipWith`/`foldl` over indices are
`linalg.generic` or `scf.for` with tensor iteration arguments.

One-Shot Module Bufferize then:
- decides in place per use, statically, and needs no exclusivity types for
  arrays: a RaW conflict *is* a missing exclusivity;
- copies where a conflict exists, which is Marshall's `copy`;
- treats constants as non-writable (Bufferization.md: "the buffer is not
  writable"), our static cells exactly.

Ownership-based deallocation frees them. `linalg` → `vector` gives SIMD
for free.

Arrays stored inside boxes need a counted array object (Lean's), and an
exclusivity query of their own. That is where the two worlds meet.

### 6.11 The promise, and the role of quantity 1

The README promises: "A quantity-1 value that is matched and rebuilt at the
same size will be updated in place with no runtime test, or the program will
not compile". Review-external-2 step 3 wants to reject when "some caller
shares it". But the *type* does not promise exclusivity (§3). Rejecting
`bump ys; bump ys` rejects a correct Idris program on the strength of a
promise Idris never made.

Recommendation:
- **P1, always.** Never miscompile. An indicator that does not fold keeps
  the runtime test.
- **P2, always, reported.** Every take whose indicator does not fold gets
  a remark with its conflict triple: the definition, the reuse that wanted
  it, and the reason it is not exclusive. The reasons are:
  - "used again at L" (a `dup`);
  - "a compile-time constant";
  - "a stack cell";
  - "a field of a value tested only at runtime";
  - "a join of exclusive and shared values";
  - "passed to a borrowed parameter that escapes".

  This is One-Shot's `print-conflicts`.
- **P3, on demand.** A function the user demands be fip, or a quantity-1
  parameter the user demands be in place, is **rejected** with
  `unsupported (in-place): <triple>`.
  - How the user states the demand is open. Idris has no `fip` keyword,
    and the profile rejects unknown pragmas. An option of `idris-mlir`,
    naming the function, is the least magic.
- Programs written in the steadfast idiom (§4a) never trigger P3, so for
  them the README's strong promise holds.
- An optional third lattice value, **shared** (count ≥ 2 proved, because
  the caller holds a reference that lives across the call), would let
  non-exclusive sites copy *without* a test, and let their drops skip the
  zero test. With it, "no runtime test" holds everywhere except at joins.
  That is optional, and it needs a measurement first.

## 7. Soundness pitfalls, with counterexamples

1. **`believe_me` / `assert_linear`.** `assert_linear (\z => (z, z)) x`
   duplicates a linear value. Idris accepts it; idris-mlir rejects it
   (checked). **This rejection is load-bearing for the memory model** and
   has no test (only `believe_me` does: tests/profile/v0/reject/). Add one.
2. **`unsafePerformIO`.** `arr = unsafePerformIO (newArray 4)` as a
   top-level value is one array for every use. Contrib's `LinArray` is
   built on it. It is rejected except at the root. Native arrays must be
   runtime primitives whose uniqueness the compiler derives, never library
   code that asserts it.
3. **Laundering (§4, Esc).** A linear continuation with a free result type.
   The compiler must derive uniqueness, not read it off the library.
4. **`assert_total` and partiality.** These do not duplicate: a crash or a
   divergence leaks a unique value, it does not alias it.
   - Two things do depend on them. First, "exactly once" becomes "at most
     once" (A2): a `ub.unreachable` path ends with unique values
     unconsumed, which the verifier already accepts.
   - Second, the FIPS stack bound assumes termination.
   - The user's `assert_total` is already rejected.
5. **Erased duplication.** `g xs = f xs xs Refl`, with
   `f : (1 xs : L) -> (0 ys : L) -> (0 _ : ys = xs) -> L`, type-checks:
   the erased `ys` *is* `xs`. It is harmless as long as nothing ever
   materializes an erased argument from the term it came from. If Emit or
   a pass ever un-erased `ys` into the value, the in-place update of `xs`
   would be visible through it. "Erased does not mean constant" (AGENTS.md)
   is the same rule seen from the other side.
6. **Closures that capture linear or unique values.**
   - Idris makes such closures linear (A4).
   - But idr.apply *borrows* its callee (Counting.cc `useOf`), so the
     body's captures arrive inc'd, and a unique capture becomes shared at
     the first apply.
   - A one-shot closure must be *consumed* by its apply, which is §6.7:
     take the closure sum apart.
   - `idr.closure` is `Pure` and CSE merges it. Merging is fine only for
     closures that are not `uniq`.
7. **Compiler-made sharing.**
   - Compile-time constants and `ConOp::fold` make persistent cells.
   - Stack cells are lent.
   - CSE of pure ops happens.
   - Two identical fresh cons, `C 1 N` and `C 1 N`, must stay two cells.
     Allocate already ensures that; keep it.
   - All of these are closed by §6.3-§6.4's representation, never by guards.
8. **Cycles.** Deep uniqueness assumes the heap under a unique value is a
   tree. That holds because no mutable references are admitted and Lazy
   thunks are closures that are not memoized. Admitting `IORef` or
   memoized laziness would break it.
9. **Borrowed does not mean non-escaping.** Borrow.cc does not make a
   parameter owned when it is *returned*: `pick xs = xs` borrows `xs`, and
   counting incs it before the return. Passing a `uniq` value to such a
   borrowed parameter creates a second reference. The fractional join is
   sound only when the parameter's deep node does not escape. This is a
   correction to the naive "borrowed calls preserve uniqueness".
10. **Mixed borrow and consume in one op.** `f(^tail(u), u)` lends a field
    of `u` while consuming `u`. FP²'s Theorem 1 requires the borrowed and
    owned stores to be *disjoint*. The verifier must reject a borrow whose
    owner the same op consumes. Verify.cc checks borrows after consumes,
    so extend that check to the owner chain.

## 8. Test plan

**Test API, stated once as properties (idr-expect).**
- `in-place=@f`: every `take`/`reset` in f has an exclusivity operand that
  folded to `true`, every box built in f is a `reuse` of a `cell`, and no
  op in f tests a count. It generalizes today's `reuses-in-place`.
- `fip=@f`: §6.6.
- `counts-nothing=@f` (exists).
- `exclusive-param=@f:i`: parameter i has type `!idr.uniq`.
- For arrays, the upstream `one-shot-bufferize="test-analysis-only
  print-conflicts"` annotations are the property: every operand in place,
  or the expected conflict.
- A runtime allocation counter would let e2e tests assert "bump allocated
  nothing". `IDRIS_RT_LIVE` reports live cells only.

**Must get static in-place code** (checked with `in-place`/`fip`, output
compared with Chez):
1. `bump (build n)`: a fresh argument goes to the unique clone, with no
   `scf.if` in its take.
2. `reverseAcc xs []` on a fresh list (FP² §1): `fip`, zero allocations.
3. `let ys = build n in total' ys + total' (bump ys)`: a borrow, then an
   in-place update (fractional join).
4. Insertion into a red-black or splay tree on a fresh tree (FP² §3):
   `fip` for the zipper moves.
5. A tail loop whose record state is rebuilt each iteration: one cell
   reused, and later one stack slot.
6. A steadfast abstract type, `withArr : Int -> (1 k : (1 a : Arr) -> !* b) -> !* b`
   over a user record: every update in place.
7. Read the head, update the tail: a partial borrow.
8. A linear continuation `(1 k : (1 x : L) -> r)` applied to a fresh value:
   in place inside k's body, after defunctionalization.
9. `g xs = f xs xs Refl`: erased mentions do not demote.

**Must NOT be updated in place** (differential against Chez, plus
`exclusive-param` expected to fail):
1. Lin1: `bump ys` twice, then print ys, gives `[2,3,4] [2,3,4] [1,2,3]`.
2. `twoTails` followed by bump on each copy.
3. `bump (C n (C 2 (C 3 N)))`: a static tail is never written. A write
   would fault on .rodata.
4. `let t = tail xs in (bump xs, total' t)`: the field inc demotes xs.
5. Esc's pattern with a user abstract type *without* `!*`:
   `let a = leak in (bump a, bump a)` gives two independent results.
6. `pick` (a borrowed parameter that is returned) followed by bump:
   pitfall 9.
7. A closure applied twice that captures a value: its captures are shared.
8. A stack cell passed to a reusing callee whose result escapes.
9. `assert_linear` and `believe_me`: rejected (EscapeHatch). Keep them
   rejected; the soundness of 1-8 depends on it.

**Arrays, once they exist** (upstream conflicts are the oracle):
- A must: a fold that writes each index of a fresh array has every
  `tensor.insert` in place.
- A must not: `let b = write a 0 1 in (read a 0, b)` has one conflict and
  one copy, and the result equals Chez's.

**Verifier negatives** (lit, `%status 1`):
- an `!idr.own` used twice, or not at all, on one path;
- a borrow used after its owner's consuming use;
- an `idr.constant` of `!idr.uniq` type;
- a `!idr.uniq` result returned from a `dup` result, whose provenance
  cannot fold;
- `reuse` of a `cell<24>` for a 32-byte constructor;
- a take typed as giving a `cell` whose exclusivity operand does not fold;
- a `func.call` passing an `!idr.own` to an `!idr.uniq` parameter (MLIR's
  own error).

## 9. Open questions

- **Cover.** Is box-deep coverage right, or do real programs need
  per-position covers (an exclusive spine of shared elements)? Measure on
  the v3 corpus and the linear libraries.
- **Stack and exclusivity.** Should the exclusivity analysis run before
  idr-stack so that they cooperate? That needs a reuse-equivalence edge in
  the escape summaries (§6.6).
- **The shared mode.** Is `shared` (count ≥ 2 proved) worth a third lattice
  value, or is exclusive/unknown enough?
- **The user-facing demand** for P3, given an unmodified Idris and a
  profile that rejects pragmas.
- **Arenas as the bridge.** Can count-free exclusive trees live in one
  arena buffer each, so that ownership-based deallocation frees them and
  the residue vanishes for those types? This needs the representation
  stream, and a census of never-shared types.
- **Specializing on exclusivity at the LLVM level.** Could LLVM's function
  specialization on constant arguments (IPSCCP) do the cloning of step 4 if
  the `i1` survived to LLVM? The MLIR-level commit into `!idr.uniq` is
  still needed for the typed ABI and for the demand. Unverified whether it
  is on at the pinned O3.
- **Idris's own checker.** Any known Idris 2 linearity soundness bugs (for
  example around `with`, `case` inference of `UseUnknown`, or holes) would
  break A2-A5. The accepted subset excludes holes; the rest is unaudited.
