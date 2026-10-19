<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Constant stack for IO traversals: the causes and the design

SUMMARY.md §5.14 ("Constant stack lost for `traverse_` and `for_`"). This
was investigated on the tree at 6f774119 with `build/dev` (arm64 macOS). No
compiler source or test was changed. The programs were compiled with
`tools/compile.sh` from copies in a scratch directory and run as the
harness runs them (`harness/lib/run.sh`):
`(ulimit -s 1024; printf 'N\n' | IDRIS_RT_STACK=1048576 ./prog)`.

## 0. What fails, and the control experiments

| program | N | result |
| --- | --- | --- |
| tests/for-long-list (`for_`) | 1000000 | `idris-mlir: stack exhausted`, exit 1 |
| tests/traverse-deep (`traverse_`) | 200000 | `stack exhausted`, exit 1 |
| tests/sequence-deep (`sequence_`, marked `default-stack`) | 1000000 | `stack exhausted`, exit 1 |
| tests/foldlm-deep (`foldlM`, marked `default-stack`) | 1000000 | `stack exhausted`, exit 1 |
| tests/map-deep (`map`, one constructor around the call) | 1000000 | passes |
| control e1: `dup (x :: xs) = x :: x :: dup xs`, pure | 1000000 | `stack exhausted`, exit 1 |
| control e2: `inc (x :: xs) = (x + 1) :: inc xs`, pure | 1000000 | passes |
| control e3: `loop (x :: xs) = do when … (printLn x); loop xs` | 1000000 | passes |

The controls settle what the cause is. It is not IO: a pure recursion that
puts its own result **two** constructors deep (e1) overflows exactly as
`for_` does. A recursion that puts it one constructor deep (e2, map-deep)
does not, and neither does an IO recursion written by hand (e3). idr-trmc
handles one constructor level. Prelude's `traverse_ f = foldr ((*>) . f)
(pure ())` puts the recursive fold two cells deep: inside the closure that
`(<*>)` builds, which sits inside the closure that `io_bind` builds. In
for-long-list and sequence-deep a constructor/unpack pair also stands
between those two cells. It comes from a sum injection that did not fold
(§2). foldlm-deep has a different cause (§5).

## 1. The chain from the recursive call to the return, at idr-trmc

Short names: **FOLDR** is
`Prelude.Interfaces.foldr[PrimIO.IO Builtin.Unit, Int, …List…];….lam.e8856f3472188176`,
the one-argument method closure that `foldr_Foldable_List` was inlined
into. The three `io_bind` closures (`MkIO` is erased, so an `IO` closure is
`\w => …`) are:
- **bind₁** = `PrimIO.io_bind[Unit -> Unit, Unit].lam.9fff…`, the closure
  of `map (const id) act`;
- **bind₂** = `PrimIO.io_bind[Unit, Unit -> Unit].lam.4f44…`, the `(<*>)`
  of `a *> b`;
- **bind₃** = `PrimIO.io_bind[Unit, Unit].lam.1611…`, the inner bind of
  `(<*>)`.

**ap** = `Prelude.IO.(<*>_Applicative_IO)[Unit, Unit].lam.e201…`, which is
`\f' => io_bind a (\a' => io_pure (f' a'))` capturing `a`. The sums are:
- **narrow** `fn$.sum.fe678925…`: one label, bind₂. It is the result slot
  of `io_bind[Unit, Unit -> Unit]` and is unboxed.
- **wide** `fn$.sum.199c63fb…`: bind₂ | `io_pure[Unit].lam`. It is FOLDR's
  result slot, and it is boxed because it is recursive through ap.
- **apsum** `fn$.sum.a2476037…`: ap alone, boxed.

The source definitions behind them:
`for_ = flip traverse_`, `traverse_ f = foldr ((*>) . f) (pure ())`,
`foldr f z (x :: xs) = f x (foldr f z xs)`, `a *> b = map (const id) a <*> b`,
`map f io = io_bind io $ io_pure . f`,
`f <*> a = io_bind f (\f' => io_bind a (\a' => io_pure (f' a')))`, and
`io_bind (MkIO fn) k = MkIO (\w => let MkIORes x' w' = fn w; MkIO res = k x' in res w')`
with `(1 act)` and `(1 k)`. Because both arguments are linear, every
`io_bind` closure is a linear value.

### for-long-list (sequence-deep is the same chain)

The cons case of FOLDR, as `--mlir-print-ir-before=idr-trmc` shows it. The
spec clone `FOLDR.spec.0396…` has the same case, ending in an `idr.share`.

| # | op | where it comes from |
| --- | --- | --- |
| 1 | `%foldr = idr.call @FOLDR(%arg0, %f1) effects<none>` | `foldr f z xs` in `foldr_Foldable_List`'s cons case. idr-optimize inlined the method closure's body, and the call kept `effects<none>`: building actions is no IO. |
| 2 | `%lin = idr.lin.enter %4`, `%lin_0 = idr.lin.enter %compose` | `io_bind`'s `(1 act)` and `(1 k)` for `map (const id) act`, where `act` is `%4` (the match_lit choosing `io_pure ()` or `putStr s`) and `k` is `io_pure . const id`. |
| 3 | `%b1 = idr.con !idr.q<one,excl,fn$.sum.905466…> @bind₁(%lin, %lin_0)` | `map_Functor_IO`'s `io_bind`, defunctionalized to a constructor of bind₁'s unboxed sum. |
| 4 | `%5 = idr.cell.new @ap`; `%result = idr.cell.init %5 (%foldr)` | **Cell 1**: ap's closure capturing the fold of the rest. Its constructor became a cell and a write in idr-rc-cells. |
| 5 | `%lin_1 = idr.lin.enter %result` | `io_bind`'s `(1 k)` = ap. |
| 6 | `%b2 = idr.con !idr.q<one,excl,narrow> @bind₂(%b1, %lin_1)` | `map (const id) a <*> b`, the outer `io_bind`, **built in the narrow sum**: the closure is made in `io_bind[Unit, Unit -> Unit]`, whose result slot has one label. |
| 7 | `%6 = idr.lin.use %b2` | idr-defunctionalize's target materialization `rebuild` (Transforms/Defunctionalize/Converter.cpp). It moves a linear value from the narrow slot into foldr's wide result slot: use it, rebuild each constructor, enter it. |
| 8 | `%7:2 = idr.unpack %6 @bind₂` | The rebuild's match has one case, so MatchOp canonicalization (`canon::readField`) inlined it into two `idr.field` reads. idr-rc made the reads of the consumed value an unpack. |
| 9 | `%lin_2, %lin_3 = idr.lin.enter %7#0, %7#1` | the rebuild's `heldAs`: the fields re-entered into the wide constructor's linear fields. |
| 10 | `%8 = idr.cell.new @bind₂`; `%result_4 = idr.cell.init %8 (%lin_2, %lin_3)` | **Cell 2**: the rebuilt wide constructor. It is boxed, so idr-rc-cells gives it a cell. |
| 11 | `idr.yield %result_4` → `return %0` | the cons case's value, returned. |

Steps 6–9 are the con/unpack pair. Without them, the chain is call → cell 1
→ grade → cell 2 → return: two cells, which idr-trmc does not take (§3).

In the same dump, `FOLDR.spec.0396….raise.2999…` is the arity-raised
copy (Specialize/Raise.cpp) that the root calls with the world. Its cons
case still calls the **building** FOLDR at step 1. Raising pushed the
consumer (the dispatch that applies the action to the world) into the
tail, met the known constructor of step 6, and turned the dispatch into a
call of bind₂'s body. The fold of the rest is only run inside that body,
two calls later (§3, option B). There is a second, minor oddity: the spec
clone's own recursion goes to the generic FOLDR, with the constant closures
passed on every iteration, and not to itself.

### traverse-deep

The ops are the same, placed differently (`--mlir-print-ir-after=idr-optimize`
and before idr-trmc):
- The call (1) comes first.
- Steps 2–7 (the action, bind₁, cell 1 around `%foldr`, the narrow bind₂
  and its `lin.use`) are copied into both regions of the `if` (a
  `match_lit`). Case-of-case moved the `(*>)` construction into each
  branch, so `%foldr` has two uses.
- The rebuild's two field reads (8) stand after the join, on the match's
  result. Case-of-case moves only a single consumer, and these are two.
- Then come 9–11.

So the path from the call to the return also crosses a join.

## 2. Why the con/unpack pair is not folded, and the fold that removes it

`idr.field`'s folder and canonicalizer look for the constructor through
`throughLinear(value)`, as do `MatchOp::getTakenRegion`, `TagOp::fold` and
`canon::feeds` (what case-of-case and sinking ask). `throughLinear`
(lib/IR/Grades.cpp) follows only two hand-written shapes:

```cpp
// What `value` was entered into its linear position from, when it is one:
// `lin.enter %x`, or `lin.use (lin.enter %x)`.
std::optional<Value> enteredFrom(Value value) {
  if (auto enter = value.getDefiningOp<LinEnterOp>()) return enter.getValue();
  if (auto use = value.getDefiningOp<LinUseOp>())
    if (auto enter = use.getLinear().getDefiningOp<LinEnterOp>()) return enter.getValue();
  return std::nullopt;
}
```

A closure that holds linear captures is **built** linear: `idr.con
!idr.lin<T> @C(…)`, with no `lin.enter` to find. So `lin.use %c` of such a
constructor ends the chain. The reads of step 8 see an unknown value, and
`builtStateHolds`, `fieldReadOnce` and `heldAs` never run. Both
`idr.lin.use` and `idr.lin.enter` carry `Idr_SameValue`, the trait that
already says "my result is my operand's value". `enteredFrom` restates that
fact for two patterns and misses the third.

**The fold.** `throughLinear` should follow every `Idr_SameValue` grade on
the linear ops: `lin.use %x` → `%x`, and `lin.enter %x` → `%x`. The trait
is read instead of the patterns, so one fact sits in one place and the
two-pattern special case is deleted. The guards that keep quantity 1 are
already in place and see the new case unchanged:
- `FieldOp::canonicalize` takes a linear field out of the constructor only
  when `fieldReadOnce` holds. That function walks the constructor's users
  through every `ResultCarriesOperand` op, `lin.use` included, and refuses
  any other user.
- The field is held as read: `heldAs` gives `lin.use %lin`.
- `LinEnterOp::fold` collapses the following `lin.enter (lin.use %lin)` to
  `%lin` when the use has that one reader.

So the wide constructor receives the very `!idr.lin<…>` operands the
narrow one took, and the quantity stays in the types. The narrow `con` and
its `lin.use` are then dead: `lin.use` has only an Allocate effect on
`LinResource`, and an unboxed `con` is pure. The fold belongs before idr-rc
(idr-optimize's inner canonicalizer), where the reads are `idr.field` and
not yet `idr.unpack`.

What the fold does by itself:
- **for-long-list and sequence-deep**: steps 6–9 vanish, and the chain is
  call → cell 1 → `lin.enter` → cell 2 (wide) → return.
- **traverse-deep**: with `feeds` now seeing the constructor, the field
  reads still stay after the join, because they are two consumers.
- **Stack**: neither program becomes constant stack. Both still have two
  levels.
- **Heap**: it removes the string allocation of a `printLn` whose
  `io_bind` body was inlined (§5, a1).

## 3. idr-trmc today, and the design

### What it handles

`moduloAt` (lib/Analysis/Tail.cpp) and Trmc.cpp handle **one level**. A
block's terminator must return the result of an `idr.cell.init`. One field
of that init must be, through grade ops of one use, the result of a self
call in the same block, and that call must have one use. Every op between
the call and the init must be the cell's producer, one of those grades, or
both memory-effect-free and speculatable. Tails under a tail match are
visited region by region. In the clone, a plain self tail call passes the
destination on.

It does not handle:
- (i) the call reaching the returned cell through another cell (e1,
  for-long-list after the fold);
- (ii) through an unboxed constructor and its field read (for-long-list
  before the fold);
- (iii) through a match join (traverse-deep);
- (iv) ops with effects between the call and the init, even when the call
  itself only computes. traverse-deep's `if` regions hold a lazy cell's
  `memo.enter`/`memo.settle` and string building, and the call is before
  them.

### The representation: the hole travels, the context is anything that only carries it

A recursion modulo **context** is the general case, and the one-level case
is its length-one path. Write `C[·]` for the value the tail returns with
the call's result as the hole. TRMC is sound whenever these three hold:
1. the call's result is stored, through grades, into a field of a fresh
   cell (`cell.init` of a `cell.new`/`cell.recycle`), the **holed cell**;
2. the holed cell is reachable from the returned value and from nothing
   else. Its box may be moved into parts of values (fields of cells,
   unboxed constructors), read back out as a part (`idr.field`/`unpack` of
   those values), regraded, and carried through a match's yield to its
   result. It must never be read whole: no match on it, no field read of
   it, no call taking it, no drop of it;
3. the call can move to the return. This holds when the call only computes
   (`effects<none>`), or when every op it would move past only computes.

These are exactly the moves the escape analysis already classifies. Its
use rules in lib/Analysis/Escapes.cpp ("moved into a part of a value",
"read out of as a part", "handed on by an op whose result is its operand's
value at another grade", "forwarded by a region branch") are read off
every op's `Idr_FlowOpInterface` edges. So condition 2 is a query on the
reference-flow representation the dialect already has, not a new pattern:
the holed box's only sink is the function's return. Condition 3 is the rule
raising already applies before moving a consumer to its call
(`consumerOf` in Specialize/Consumer.cpp: "A call that only computes may
run later, after anything between it and its consumer; any other only
after ops that only compute"). TRMC and raising must share that predicate
as one function. Today they hold two versions, and TRMC's is the stricter
one that blocks traverse-deep.

The rewrite, for each tail whose return value is such a context:
- The holed cell's `cell.init` is rebuilt with the field as a hole
  (`withHole`). It yields `!idr.dest`.
- The destination is carried from where the holed cell is built to the
  return. Where a match lies on the path, every region that builds a holed
  cell yields its destination as one more match result. Only one region
  runs, so exactly one destination arrives. This is the context as a
  first-class value, `(root box, hole destination)`, composing through
  fields and through joins.
- The call moves to just before the terminator, after the root is built.
  In the first level the call is to the clone and the root is returned. In
  the clone, the root is `dest.write`n into the incoming hole and the call
  is a self tail call. idr-tail-loops makes the clone an `scf.while`, as it
  does today.

`Modulo{call, built, index, grades}` gives way to a context: the holed init
and the path its destination takes. The one-level case is the context
whose holed cell is the returned one. That is a representation change, not
a branch: the depth special case disappears, together with the "between"
check that duplicates raising's.

How the failing programs go through it:
- **e1 (`dup`)**: the recycled cell `::` (holed) is moved into the new
  cell `::`, which is returned. The context has length two, and the call
  moves past the outer init.
- **for-long-list and sequence-deep, with the fold**: cell 1 (ap, holed) →
  `lin.enter` → cell 2 (wide bind₂) → return. Without the fold, conditions
  1–3 still hold: the box is moved into the narrow constructor, read back
  as part 1, and moved into cell 2. So the fold is not a prerequisite for
  the stack, though it is for the heap.
- **traverse-deep**: in each `if` region cell 1 is holed and its
  destination is yielded. The join's part reads and `lin.enter` carry the
  box into cell 2. FOLDR is `effects<none>`, so the call moves past the
  regions' memo ops and string building (condition 3). The program then
  builds in constant stack.

This is a guarantee, not an optimization. It rests on the shape of the
returned value and on the call's own effects, with no budget, as the
one-level TRMC does today. A program that is constant-stack stays so
whatever inlining did, provided the context is formed. That follows
AGENTS.md: optimizing passes may stop at a budget, and a property tests
assert must not depend on one.

**MLIR mechanisms.**
- The clone is the destination-passing form of the recursion. Upstream's
  analog for memrefs is `-buffer-results-to-out-params` (a result becomes
  an out-parameter) and, for tensors, `DestinationStyleOpInterface`'s
  inits. Upstream has no TRMC, so the clone stays ours.
- Condition 2 should be a query of the existing `DataFlowSolver`-based
  escape analysis, not a hand walk.
- The loop is `scf.while` (idr-tail-loops), and the call that stays a call
  becomes `musttail` in idr-tail-calls.

### Option B, run instead of build: evaluated, and kept as a follow-up

The ideal program never builds the action. `FOLDR.raise(xs, w)` would run
`act` and then tail-call itself: the loop e3 should also become, with no
cells per element. The raise machinery already exists (Raise.cpp: "where
the tail is the callee's own recursion, which idr-tail-loops makes a
loop"), and the dispatch that applies an action to the world is the
consumer it raises. It does not get there, for three reasons:
1. **Interpreter steps are never inlined.** Raising meets bind₂'s
   constructor and turns the dispatch into `call @bind₂(b1, ap(%foldr), w)`.
   The dispatch of `%foldr` is in bind₃, two calls down. bind₂ and bind₃
   form a call cycle (bind₂ → bind₃ → dispatch on the action sum → bind₂),
   so the inline rule never inlines them (`factsOf`: `shared`). A
   specialization of either is a `stepOfRecursion`, kept a call since
   7232d3e9 so that static recursion does not unroll.
2. **The bound of a step never reaches the raise.** Inside bind₂'s body the
   continuation parameter of bind₃ varies along the cycle, so its binding
   time is dynamic and no node is keyed on it.
3. **The arguments are not known constructors.** Before the fold, bind₂'s
   arguments are not known constructors at all (§2), so not even the first
   specialization is requested.

The principled rule that would enable it: an apply of a **known closure**
is beta reduction, not a step of a data recursion. Inlining the body of a
cycle member at a call whose dispatched argument is a closure constructor
built in the caller consumes that constructor. Each step consumes one
constructor of the caller's own code, and the existing caller cap
(`kCallerCap`) bounds the rest. That is the distinction `Keys.cpp` already
draws for specialization inside a chain of nodes ("only on a closure … a
closure static at a later call is new knowledge, where data would
re-abstract what the key already fixed"). With it:
- the bind₂ step, ap, bind₁ (run of `act`) and bind₃ all inline into
  `FOLDR.raise`;
- `%foldr`'s one use becomes the dispatch, and Sink (lib/IR/Canon/Sink.cpp)
  copies the pure call into each region where it meets that dispatch;
- raising redirects it to `FOLDR.raise(rest, w')` in tail position, after
  the record eta already done in bind₃.

B is the better program, but it cannot be the fix. Its success depends on
inlining budgets, and constant stack is a property tests assert. It should
come after the TRMC context, measured by the per-element cells it removes
(§4) in for-long-list, traverse-deep, sequence-deep and e3.

### Order of work

1. The fold (§2): `throughLinear` follows `Idr_SameValue` linear grades.
2. TRMC over contexts (§3): conditions 1–3, the destination carried
   through joins, and the call-motion predicate shared with raising.
3. Option B as a separate optimization with its own measurements.

## 4. Running the chain: stack and heap

**Stack.** Running is already constant stack. In the final LLVM dialect
(`--mlir-print-ir-after=idr-tail-calls`), bind₂ and bind₃ are `tailcc`, and
each calls the other `musttail`:

```
llvm.call tailcc musttail @BIND[U, U].lam.1611…(%11)               // in bind₂, after running act
llvm.call tailcc musttail @BIND[U, U -> U].lam.4f44…(%7, %9, %11)   // in bind₃, the dispatch of the rest
```

- bind₃'s continuation `\a' => io_pure (f' a')` with `f' = const id` was
  eta-reduced by the optimizer: the record eta traverse-deep's comment
  names. So applying the rest to the world is bind₃'s tail.
- `FOLDR.spec.raise` reaches bind₂ by a `tailcc` call, which adds one
  frame.
- The only frames that grow are FOLDR's building recursion
  (`llvm.call @…foldr…lam.e8856…` followed by two `idris_rt_cell`).
- After the context TRMC, building is the clone's `scf.while` and running
  is the `musttail` cycle: both are constant stack.

**Heap.** Each element builds an ap cell of 16 B (`idris_rt_cell(16, …)`)
and a wide bind₂ cell of 32 B (`idris_rt_cell(32, …)`): 48 B per element
on top of the list. The whole chain is built before any of it runs, so for
1 000 000 elements the peak is about 48 MB of actions plus the list. The
run frees each cell as it goes: bind₂ and bind₃ test `idris_rt_is_unique`
and call `idris_rt_free_cell`. A printed element also allocates its
string. With the context TRMC the cost is unchanged, because the same
cells are built by a loop instead of a recursion. Option B would remove
the 48 B per element, leaving only the strings.

## 5. What else the change touches

### Traversals over long lists

| test | effect |
| --- | --- |
| for-long-list | fixed by the context TRMC. |
| traverse-deep | fixed by the context TRMC: it needs the join and the call-motion rule. Its comment credits record eta for the loop. Record eta is why **running** is a tail call; the failure is the **building** recursion, so the comment must say so. Its `mlir.expect` (`constant-stack=@$idris-mlir.root`) is the right contract. |
| sequence-deep | fixed (same chain as for-long-list). Its `default-stack` marker and the comment that says building goes a million calls deep become false: delete the marker in the same change. |
| foldlm-deep | **not fixed**: another cause. `foldl` builds the left-nested `((pure a0 >>= f 1) >>= f 2) >>= …` in constant stack, and running a bind runs its left action as a non-tail call, so the run is as deep as the list. The cure is a representation of running, not of building: reassociating binds, or an interpreter whose continuation stack is data. It stays `default-stack` until that is designed. |
| map-deep, replicate-take-deep, loops-trmc, loops-trmc-counter, actions-trmc | unchanged: each is a length-one context. loops-trmc's `@depth` (the call's result inspected) must stay refused. |
| short traversals: sortedmap, content-hash, directory-listing, linear-string-iterator, probe-names, growth-check, dependent-pair-family-eta, closed-literal-conversion, closed-double-text, closed-char-to-string, every-interfaces-export, linarray-reserve, sum-of-seventy-thousand-constructors; bench regex-redux, regex-dna, k-nucleotide | output unchanged; FOLDR gains a `.trmc` clone. linear-string-iterator's `no-heap-allocation=@Main.codeSum` should be rechecked. |

New tests, each a property:
- a length-two pure recursion like e1 at the harness's 1 MiB stack, run
  with a million elements;
- loops-trmc fixtures with `constant-stack` for a two-cell context and for
  a context through a join;
- a refused one: the holed cell is read (matched or passed to a call)
  before the return, so `constant-stack` must fail;
- `%differential` on all of these.

### The heap-free tests

`idr-expect no-heap-allocation` was run on the module before idr-lower.
Three causes appear:

- **(a) The pair of §2, in the root.** The first `printLn x` of `main`
  builds its string with `show ++ "\n"`. That string reaches `put_str`
  through `con PUTSTR(s)` → `lin.enter` → `con lin bind₃(…)` → `lin.use` →
  field reads. Output fusion (`put_str (show x ++ s)` →
  `put_sint x; put_str s`) never sees the append, because the reads do not
  fold. There are two forms:
  - **(a1)**: bind₃'s body is inlined into the root and `put_str` reads the
    unpacked string. The fold of §2 is enough. The root's later `printLn`s
    in the same programs already show the fused form (`idr.io.put_sint`).
  - **(a2)**: the program's action sum nests binds in binds, so the
    `io_bind` bodies form a call cycle. The unpacked closures are then
    passed to `call @bind₃(…, %w)`, which is never inlined. After the fold
    they are known constructors, but bind₃ is the cycle member of option B
    (§3, reason 1). The string stays built until the beta-reduction rule
    inlines that step. This is the same cause as the stack problem's
    "run instead of build".
- **(b) A `Lazy (IO b)` forced once still gets a memo cell.** `(>>)` takes
  its second action as `Lazy`. After inlining, the force is a match on a
  freshly built lazy cell (or one read off a constant `(>>)` closure). Its
  delay case builds the action value (the string, the `PUTSTR` closure),
  `memo.settle`s it into the cell, drops the cell, and then runs the
  action's inlined, fused code. The settled value is never read. It keeps:
  - the strings and the lazy cells (`cell.new`);
  - through the labels in the settled closures and in the lazy cell's tag,
    whole functions that nothing calls: `Main.main.delay.*` and
    `Main.main.lam.*`, which `symbol-dce` cannot drop while a type or a
    constructor names them.

  This is the same shape as the IO problem: an action built as data where
  only its run is needed. The cause is the memo representation, though,
  not `io_bind`. A lazy value with one reference, forced once, has no
  observable `forced`/`running` states. Its force is call-by-name, so the
  memo cell, its settle and the delay function are dead.
- **(c) A different consumer.** `digits` is not raised into a writer with
  `put_str` as its consumer. Raising takes only a closure dispatch as a
  consumer (`eliminationAt`), and `put_str` is none.

| test | allocations (before idr-lower) | causes |
| --- | --- | --- |
| absurd-body | root: show+append; `Main.main.lam.*`: show+append | a1; b (the lam is kept by the settled `io_bind` closure naming it) |
| crash-mod-zero | root ×2; `Main.main.delay.*`; the `(>>)` body | a1 (first printLn); b (the memo case builds the action; delay and `(>>)` kept alive) |
| double-cast-nan | root ×2 | a1; b (inside the memo case) |
| erased-witness | root; `Main.main.lam.*` | a1; b |
| double-basics | root; 32 lazy `cell.new` and the strings in `Main.main.delay.*` | a2; b |
| interface-ring-power | root; strings in 11 `Main.main.delay.*` | a2; b |
| nbody | root (inside the memo case) and `Main.main.lam.*`: a lazy `cell.new`; strings in `Main.main.delay.*` | b only (its first printLn prints a folded constant) |
| recursive-string | `Main.digits`: show+append | c only |

Is it the same root cause, and does one representation fix both? Only in
part:
- **The fold of §2** is the shared prerequisite. It removes the con/unpack
  pair in for-long-list and cause (a1). For (a2) it supplies the known
  constructors that option B's rule needs.
- **Option B's rule** (beta-reduce a known closure even when its body is a
  member of the bind cycle) is the same mechanism as "run instead of
  build". It covers (a2) and the per-element action cells of the stack
  tests.
- **The stack itself** needs the TRMC context. That is the only part that
  is a guarantee.
- **(b)** needs a call-by-name force of a lazy value forced once.
- **(c)** needs raising to accept an output consumer.

No heap-free test turns green from the fold alone: every test with (a)
also has (b), nbody has only (b), and recursive-string has only (c).
