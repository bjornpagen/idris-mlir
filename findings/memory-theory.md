# Memory theory: from Idris's quantities to uniqueness

Stream "memory-theory". This note asks exactly what idris-mlir may soundly
assume from Idris 2's quantities, and how it gets from linearity to
*uniqueness*. Uniqueness is what licenses in-place update, static reuse with
no count test, and no reference counting at all. The note builds on
review-external-2.md ("Where QTT stands", "What the dream takes") and
corrects it in three places: §6.2, §6.9 and §7.9.

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
6. What design puts uniqueness in types, with every piece load-bearing?
7. Which pitfalls break soundness?
8. Which tests pin the design down?

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
   cliff into a diagnostic or a rejection (§6.9).
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
compiler's own inference (§6.4). The idioms give *completeness*: programs
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
The static design has to turn exactly that into a type fact (§6.8).

## 6. A design: uniqueness in types, in the owned stage

### 6.1 Where it lives

The entente needs a **linear base** (Marshall §3: "we present a system where
linearity is the base and uniqueness is a modality").

- idris-mlir's *pure* stage has an unrestricted base, QTT's. Its values are
  values, so CSE, folding and compile-time evaluation share them freely,
  and "one reference" is meaningless there.
- Its *owned* stage, after idr-rc, is Perceus's λ1 / Beans' λRC. Every
  reference is consumed exactly once, and duplication is an explicit op
  (`idr.inc`).
- That is a linear base with `!` made explicit. **Uniqueness therefore
  belongs to the owned stage**:
  - it is inferred by idr-rc, after borrow inference and before counting;
  - it is lost only at explicit points (`inc`/dup, `share`, storing into a
    shared cell, `lin.enter` of a shared value);
  - it is verified by the same kind of type-driven use count as
    `!idr.lin`.

### 6.2 The types

**`!idr.uniq<T>`**, where T is a box or an unboxed sum, is an owned
reference whose **cell graph is a tree of exclusively held heap cells**:
- the value's own cell (for an unboxed sum, each counted slot's cell);
- and, transitively, every cell reachable through a field of box (or
  boxed-closure) type;
- each has count 1, is on the heap (neither static nor on the stack), and
  is reached only through this reference.

Nullary constructors are exempt. They are persistent atoms with no fields,
so there is nothing to reuse (FP²'s `atom` rule, ⋄0). Leaf fields that are
not boxes (`str`, `big`, scalars) are not covered: they keep their own
counts.

- *Why deep.* The recursive call of `bump` receives the tail, a field of
  the taken cell. With a shallow claim the tail is unknown and every level
  after the first needs a test. Review-external-2's step 2, "untested
  reset for unique scrutinees", works for one level only, for exactly this
  reason. Deep is FP²'s "linear store" (Def. 1) and Marshall's Theorem 5
  ("all array references in v").
- *Why boxes only.* A list of literal (static) strings can still be
  unique. Zippers of trees (FP²'s splay trees) are covered because both
  are boxes.
- *Cost.* A list that holds a *shared* inner list is not unique, and falls
  back to the dynamic path. A per-position cover attribute
  (`!idr.uniq<T, #idr.cover<…>>`, Clean-style attributes) is the
  refinement if programs need it. That is an open question.

**`!idr.cell<N>`** is a *definitely present* cell of N bytes, the static reuse
credit (FP²'s ⋄k). It is linear: `reuse` consumes it (its size must be N,
a *type* check that replaces Verify.cc's `fits()` lookup of the defining
reset), or `free` does. Today's nullable `!idr.token` stays for the dynamic
path.

**Borrowed parameters become a type** (`!idr.borrow<T>`), not the discardable
`idr.borrowed` argument attribute. Uniqueness depends on borrowedness
(§6.8): a borrowed call preserves the caller's uniqueness. A fact that
another fact depends on cannot sit in a discardable attribute (AGENTS.md).

### 6.3 Typing rules (introduction, preservation, loss)

- **Fresh.** An `idr.con`/`idr.reuse` of a box is `uniq` when every box
  field operand is `uniq` or an atom. Non-box fields are unconstrained.
  This is necessitation.
- **Call.** A result is `uniq` when the callee's result type is. Argument
  to a `uniq` parameter must be `uniq`, and **MLIR's `func.call` verifier
  already enforces that for free** ("operand type mismatch",
  Func/IR/FuncOps.cpp:80). That is the whole caller half of the entente,
  checked by an upstream verifier because it is a type.
- **Take.** `idr.take` of a `uniq<box>` gives `!idr.cell<N>` (none for an
  atom), and its box fields come out `uniq`. It lowers to loads only, with
  no `scf.if`, no inc and no dec.
- **Borrow.** A read that does not consume, such as a field read, a match
  inspection or a call's borrowed argument, leaves the value `uniq` when
  the borrow cannot outlive it (§6.8).
- **Loss.**
  - `idr.share : uniq<T> -> T` is a no-op at runtime (count stays 1).
    Marshall's `&`.
  - It is inserted wherever the value is duplicated, or a field of it is
    inc'd while it lives. Counts.cc's "a field of an owned value takes a
    reference of its own" is exactly such a demotion.
  - `lin.enter` of a `uniq` value stays `uniq`; of a shared value, it
    stays shared.
- **Copy.** `idr.copy : T -> uniq<T>` is a runtime deep copy of the box
  graph (Marshall's `copy`/`clone`). The compiler inserts it only where it
  chooses to thaw, for example a compile-time constant flowing into an
  in-place loop.
- **Constants.** No `idr.constant` has a `uniq` type. `materializeConstant`
  refuses the type, so **folding a `uniq` con into static data fails by
  construction**. OperationFolder abandons a fold whose materialization
  fails (Transforms/Utils/FoldUtils.cpp:275-300). CSE never merges box
  cons, which have an `Allocate` effect (CSE only merges effect-free or
  read-only ops, Transforms/Utils/CSE.cpp:264-268).
- **Free.** A `uniq` value that dies is freed: its uniq box fields are
  freed recursively and other counted fields are dec'd. There is no count
  test anywhere.

### 6.4 Inference and verification

**Inference** is a greatest fixpoint over the call graph, shaped like
Borrow.cc.
1. Start every non-fixed owned parameter and every result `uniq`.
2. Demote a parameter when some call passes a non-`uniq` argument.
3. Demote a result when some return is not `uniq`. Returning a value
   before `share` is fine; returning a constant is not.

Both halves are sound as greatest fixpoints: on a cycle, the invariant
"every value flowing in is unique" holds by induction on the length of the
execution. Then:
- functions whose parameter is `uniq` at some calls and not at others are
  **cloned by mode**, within the existing clone budget;
- the `uniq` clone's recursive calls pass taken fields, which are `uniq`,
  so they call the clone again;
- the public root and closure-named functions stay fixed, as in Borrow.cc.

**Verification** runs after every pass:
1. Types: MLIR's call and return checks, plus the op verifiers (take's
   result types follow its operand type, reuse's cell size, no uniq
   constant, no `inc` of `uniq`).
2. Use counts: `uniq` and `cell` values are consumed exactly once per path,
   by the same worst-path counter as `!idr.lin` and the world
   (`LinearUses`), extended to exact counts as Verify.cc already does.
3. Borrow liveness: no use of a borrow derived from `u` comes after `u`'s
   consuming use. This is Verify.cc's `alive()`/`owners`, which exists
   already.

### 6.5 What it licenses

- **Static reuse with no count test.** `take` gives a cell, and `reuse` is
  a plain store into it. `bump` on a unique list becomes a loop of loads
  and stores after idr-tail-loops, with no branch.
- **In-place update.** Reusing the same constructor with the same fields
  leaves only the changed stores; LLVM removes stores of unchanged loaded
  values.
- **No inc/dec.** A `uniq` value is never counted. Its death is `free` and
  its reuse is unconditional.
- **Count-free types.** Conjecture, whole-program. If no value of a
  monomorphic type is ever shared (no `share`, no non-atom constant, no
  stack cell), the type's counting disappears entirely. Linear-API
  abstract types satisfy this by §4(a), which is Wadler's claim that such
  values "require no reference counting or garbage collection".
  - Dropping the count *word* needs runtime support: `releaseOwned` reads
    slot counts.
- **Stack and regions.** Today stack and reuse exclude each other (a stack
  cell is never exclusive).
  - With `uniq`, a loop-carried cell that is reused in place each iteration
    is *one* slot: the old value dies where the new one is built.
  - Escape.h's rule, that a cell must not be forwarded by a loop terminator
    around its con, can be relaxed for cells reused in place.
  - A callee's summary needs a "result may reuse this parameter's cell"
    edge before a `uniq` stack cell may be passed to a reusing callee.
  - Regions: a `uniq` structure built and wholly freed inside a
    non-escaping scope can live in an arena freed at once. Conjecture.
- **fip checked at compile time.** A function is fully in place when:
  - its parameters are `uniq` or borrowed;
  - every box con is a `reuse` of a cell taken from a `uniq` parameter or
    field;
  - there is no `inc`, `share`, `copy` or allocation (FBIP additionally
    allows `free`);
  - and calls within its call cycle are tail calls (FIPS).

  FP² Theorems 2-4 then give no (de)allocation and constant stack. The
  property is decidable from ops and types, so it is an `idr-expect`
  property (§8) and a demand to reject on (§6.9).
- **Strings and future arrays.** `idr.str.append` on a `uniq` string can
  extend in place (Lean does this at runtime). Mutable arrays are where
  most of the payoff is (Marshall §4.2; review-external-2 step 5).

### 6.6 Interaction with the existing passes

- **idr-rc order:**
  1. reset/reuse;
  2. borrow inference;
  3. **uniqueness inference** (new): it needs borrow types, and a reset
     already forces a parameter owned;
  4. counting.

  Counting emits nothing for `uniq` values, and turns their dec into free.
- **reset/reuse.** The D/S heuristics are unchanged. Only the token's type
  changes: `cell<N>` from a `uniq` operand, `token` otherwise.
- **take.** It has two lowerings, chosen by its operand type rather than by
  a flag.
- **Borrow.cc.** A borrowed parameter keeps the caller's value `uniq` only
  when it does not escape (§7.9). The escape summaries idr-stack already
  computes (Escape.h, parameter nodes) answer that question.
- **idr-stack.** In v1 a stack cell is never `uniq`. Later, as §6.5.
- **Compile-time evaluation.** Closed results become persistent constants
  and are therefore never `uniq`. That is correct, and costs at most one
  `copy` at the boundary.
- **Defunctionalized closures.** Captures are fields of the closure sum. An
  apply of a `uniq` closure takes the closure apart and moves the captures
  out, so a one-shot continuation's captures stay `uniq`. This is where
  Idris's A4 and A5 show up after defunctionalization.

### 6.7 Stages: dialects and types, not an attribute

review-external.md's smell is that `idr.stage = "owned"` switches the
meaning of the same ops. Beans separates λpure from λRC:
refcount.tex:84, "The target language λRC is an extension of λpure".

The design above supports the principled fix: **make the stage a type
conversion.**
- idr-rc converts every reference type to an owned-stage reference type
  (`own<T>`, `uniq<T>`, `borrow<T>`, `cell<N>`, `token`), and puts the
  counting ops in a small dialect of their own.
- Legality is then whatever is legal in the target: a `ConversionTarget`
  with the pure types illegal, and `TypeConverter::isLegal` as the stage
  check. The verifier becomes:
  - the types themselves;
  - one linear-use rule for every linear type (`lin`, world, `own`,
    `uniq`, `cell`), which replaces most of Verify.cc's hand-kept counts
    with the `LinearUses` mechanism;
  - borrow liveness.
- `idr.stage` and `inOwnedStage` (Ownership/Ops.cc) disappear. A pure
  pattern cannot match owned IR, because the types differ.
- The cost is that shared ops (`idr.con`, `match`, `field`, `func.call`)
  compare field types through a projection that strips the mode, as
  `unrestricted()` does for `lin` today.

**Recommended order:**
1. `!idr.uniq`, `!idr.cell` and `!idr.borrow` as wrapper types, which is
   enough for static reuse;
2. then the full conversion.

### 6.8 What fractional uniqueness adds

Marshall & Orchard 2024 grade the non-uniqueness side: `&p A` with
`p ∈ (0,1] ∪ {*}`, where `*A ≡ &* A`.
- `withBorrow` lends a unique value as `&1`, provided it comes back.
- `split`/`join` halve and recombine permissions.
- `push`/`pull` borrow one part of a product while the rest stays owned
  (§5.2).
- Borrow safety is their Lemma 6.8 and Theorem 6.9.

For idris-mlir this gives three things:
1. **The justification for keeping uniqueness across borrowed calls.**
   `total' ys; bump ys` (e3) is split, then read at 1/2, then join. The
   join is sound because Beans-style borrows are scoped to the call and
   cannot be stored (they must be inc'd, which *is* the loss rule).
2. **Partial borrows.** A field read from a `uniq` value is a borrow owned
   by that value. Reading the head while updating the tail keeps the tail
   `uniq`. This is the `push`/`pull` pattern, and FP²'s `let` rule, which
   lends Γ2 to e1 while e2 owns it.
3. **Mutable borrows** are Idris's threading idiom. `(1 a : Arr) -> …
   -> Res x (const Arr)` is `&1`: a `uniq` in-out parameter returned as a
   `uniq` result.

What it does *not* add is fraction values in the IR. The existential
identifiers `∃id` of their §4 become SSA owner identity, and `join` becomes
"the borrow's last use precedes the owner's consuming use", which SSA
liveness decides. Fractions would be needed only if borrows could live in
data, as Rust's references in structs do. Idris has no such thing, and
idris-mlir should keep forbidding it.

### 6.9 The promise, and the role of quantity 1

The README promises: "A quantity-1 value that is matched and rebuilt at the
same size will be updated in place with no runtime test, or the program will
not compile". Review-external-2 step 3 wants to reject when "some caller
shares it". But the *type* does not promise uniqueness (§3). Rejecting
`bump ys; bump ys` rejects a correct Idris program on the strength of a
promise Idris never made.

Recommendation:
- **P1, always.** Never miscompile. Unproved sites keep the runtime test.
- **P2, always, reported.** Every in-place candidate is classified as
  static-unique, static-shared or dynamic, with a reason, as a remark or
  statistic.
  - *static-shared* is provable when the caller holds another reference
    that lives across the call. Its clone then copies without testing, and
    its decs cannot reach zero. It is optional, a third mode `shared`.
  - With cloning, "no runtime test" can hold at both unique and shared
    sites. Only joins of different modes stay dynamic.
- **P3, on demand.** A function the user demands be fip, or a quantity-1
  parameter the user demands be in place, is **rejected** with
  `unsupported (in-place): …`. The reason names the call site and the
  pitfall class: "used again at L", "a compile-time constant", "a field of
  a shared value", "captured by a closure applied twice", "borrowed by a
  call whose parameter escapes".
  - How the user states the demand is open. Idris has no `fip` keyword,
    and the profile rejects unknown pragmas. An option of `idris-mlir`,
    naming the function, is the least magic.
- Programs written in the steadfast idiom (§4a) never trigger P3, so for
  them the README's strong promise holds.

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
   - A one-shot closure must be *consumed* by its apply, which is §6.6:
     take the closure sum apart.
   - `idr.closure` is `Pure` and CSE merges it. Merging is fine only for
     closures that are not `uniq`.
7. **Compiler-made sharing.**
   - Compile-time constants and `ConOp::fold` make persistent cells.
   - Stack cells are lent.
   - CSE of pure ops happens.
   - Two identical fresh cons, `C 1 N` and `C 1 N`, must stay two cells.
     Allocate already ensures that; keep it.
   - All of these are closed by §6.3's types, never by guards.
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

**Test API, stated once as properties (idr-expect):**
- `in-place=@f`: every box built in f is a `reuse` of a `cell` (static) and
  no op in f tests a count. It generalizes today's `reuses-in-place`.
- `fip=@f`: §6.5.
- `counts-nothing=@f` (exists).
- `unique-param=@f:i`: parameter i has type `uniq`.
- A runtime allocation counter (`IDRIS_RT_LIVE` reports live cells only)
  would let e2e tests assert "bump allocated nothing".

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
`unique-param` expected to fail):
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

**Verifier negatives** (lit, `%status 1`):
- `inc` of a `uniq`;
- a `uniq` used twice on one path;
- an `idr.constant` of `uniq` type;
- `reuse` of a `cell<24>` for a 32-byte constructor;
- a `func.call` passing an owned value to a `uniq` parameter (MLIR's own
  error);
- a borrow used after its owner's consumption;
- a `take` of `uniq` whose results are typed `token`.

## 9. Open questions

- **Cover.** Is box-deep coverage right, or do real programs need
  per-position covers (a unique spine of shared elements)? Measure on the
  v3 corpus and the linear libraries.
- **Stack and uniqueness.** Should uniqueness inference run before
  idr-stack so they cooperate? That needs a reuse edge in the escape
  summaries (§6.5).
- **The shared mode.** Is `shared` (count ≥ 2 proved) worth a third mode,
  or is uniq/dynamic enough?
- **The user-facing demand** for P3, given an unmodified Idris and a
  profile that rejects pragmas.
- **Count-free representations.** Worth runtime support? That needs a
  whole-program census of never-shared types.
- **Idris's own checker.** Any known Idris 2 linearity soundness bugs (for
  example around `with`, `case` inference of `UseUnknown`, or holes) would
  break A2-A5. The accepted subset excludes holes; the rest is unaudited.
