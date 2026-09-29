# Sketch: the owned stage as types, not as a module attribute

This is conjecture: a design sketch, not tested. It belongs with
`mlir-idioms.md` §1.3. Its aim is to make "each reference consumed exactly once
on every path" a local SSA rule, and to give uniqueness an SSA form that can fold.

## What the stage is today

- **The switch.** `idr-rc` inserts `idr.inc %v` / `idr.dec %v` and sets
  `idr.stage = "owned"`.
- **The rule.** The module-attribute verifier `verifyOwned`
  (`lib/Ownership/Verify.cc`) interprets every function path by path. It
  keeps a `held` count per SSA value and an undo log for match regions, and
  special-cases the loops that idr-tail-loops makes (borrowed slots,
  `passedOn`).
- **The in-place counts.** `inc` has no result, so a value's reference count
  is state that changes along a path. That is why the checker must interpret
  paths.
- **The linearity special case.** It is also why the linearity checker
  special-cases `IncOp` (`Dialect.cc:373-376`).
- **Where borrowedness lives.** It is a discardable argument attribute
  (`idr.borrowed`), read by callers and callee alike (`Counting.cc:77-90`).
- **Where uniqueness lives.** Only at runtime:
  - `idr.take` and `idr.reset` test `count == 1 && !stack`
    (`Lower/Runtime.cc` `exclusive`, `Lower/Counting.cc`);
  - `idr.reuse` then tests the token for null.

## The sketch

**Types after `idr-rc`.** A value that holds references (as `Counting::counted`
decides) has one of two types:
- `!idr.own<T>`: it holds one reference of its own;
- plain `T`: borrowed, alive while its owner is.

`!idr.own` is not `!idr.lin`. `lin` is Idris's quantity 1; `own` is a
reference count fact. AGENTS.md: "A linear binder does not imply unique heap
ownership".

**Ops.**
- `%b = idr.dup %a : T -> !idr.own<T>` (was `idr.inc %a`). This makes a new
  owned value, which is Perceus' `dup`. Taking an extra owned copy of an owned
  value is `%a2, %a3 = idr.dup_own %a`, or `idr.borrow` followed by `idr.dup`.
- `idr.drop %a : !idr.own<T>` (was `idr.dec`). It consumes.
- `%x = idr.borrow %a : !idr.own<T> -> T`. This is a view whose lifetime is
  bounded by `%a`'s consuming use.
- Operands that consume (`idr.con` fields, `func.return`, `idr.yield`, owned
  call arguments, `idr.reuse` fields) are typed `!idr.own<T>`.
- Operands that borrow (`idr.field`, `idr.tag`, match scrutinees, borrowed call
  arguments) are typed `T`.
- That typing is the per-operand ownership table that is hand-coded today in
  `useOf` (`Counting.cc:85-100`). It becomes ODS operand constraints, with an
  interface where it depends on the callee.

**Function types.** A borrowed parameter is `T`; an owned one is `!idr.own<T>`.
Borrow inference then rewrites signatures instead of attaching `idr.borrowed`,
so the ABI can no longer be dropped. Bufferization fixes the ABI instead ("args
never owned, results always owned", OwnershipBasedBufferDeallocation.md
"Function boundary ABI"). Ours stays inferred, Lean-style, but *typed*.

**Verification.**
- **Exactly once.** Every `!idr.own<T>` value is used exactly once on every
  path. That is `LinearUses` (`Dialect.cc:328-395`) with "at most" tightened
  to "exactly". It is local and SSA-only, with no count state and no undo log.
- **Loops.** `scf.while` loops carry `own` values as iteration arguments,
  consumed by the terminator, which is ordinary SSA linearity.
- **Borrow lifetimes.** Every use of a borrow `%x = idr.borrow %a` (and every
  field read from `%x`) must come before `%a`'s consuming use on each path.
  That is a dominance-style check, the one remaining non-local rule, and it is
  simpler than today's `alive()` chains (`Verify.cc:87-102`).
- **What goes away.** `idr.stage`, `inOwnedStage` (`Ownership/Ops.cc:31-45`),
  `Rc.cc:24`, the `IncOp` special case and the `select` rule
  (`Verify.cc:179-181`). An `arith.select` of `own` values consumes both
  operands, so it is typed out rather than special-cased.

**Uniqueness, following bufferization's ownership indicator.**
- Give each `!idr.own<box>` a companion `i1`, "exclusive", the way
  bufferization gives each memref an `i1` ownership
  (OwnershipBasedBufferDeallocation.md "Ownerships": uninitialized <
  unique(X) < unknown).
- A fresh `idr.con` or `idr.reuse` produces `true`. `idr.dup` makes both
  copies `false`, statically.
- A parameter that is linear in Idris (`!idr.lin`) and owned can take the
  indicator as an extra argument.
- `idr.reset` / `idr.take` take the indicator and test it together with the
  runtime count. When the indicator is a constant `true`, canonicalization
  removes the test.
- `idr-specialize` already clones a callee for constant arguments. A caller
  passing `true` gets a clone whose resets are test-free. That is the README's
  static reuse promise, reached through machinery we already have. A
  `rejects-if-not-static` check, as in `idr-expect reuses-in-place`, would then
  hold the promise.

**Simplification, following bufferization.**
- Insert conservatively.
- Then run canonicalization patterns: `dup` followed by `drop` of the same
  value cancels; a `drop` of an `own` produced by `idr.con` in the same
  region frees the fields and the cell without a count test; a `drop` whose
  indicator is `true` becomes a free.
- This mirrors `bufferization.dealloc` plus `buffer-deallocation-simplification`
  ("Buffer Deallocation Simplification Pass"). It also moves correctness out
  of the placement algorithm (`Counts.cc`) and into a verifier and patterns.

## How it maps

| today | sketch | bufferization |
|---|---|---|
| `idr.inc %v` (no result) | `%w = idr.dup %v` | `bufferization.clone` |
| `idr.dec %v` | `idr.drop %v` | `bufferization.dealloc (%m) if (%own)` |
| `idr.borrowed` argument attribute | parameter type `T` against `!idr.own<T>` | fixed ABI: arguments never owned |
| runtime `exclusive()` test | `i1` indicator plus runtime count test, folded when constant | `i1` ownership indicator, lattice unique/unknown |
| `idr.reset`/`idr.reuse` token | the same, with the builtin `token` type (LangRef "Token Type") | destination-passing style, in-place bufferization |
| `verifyOwned` path interpreter | linearity on `!idr.own` plus a borrow-lifetime check | pass preconditions plus interfaces |

## Risks and open questions

- **Size.** `Counts.cc`, `Verify.cc`, `ResetReuse.cc`, `Borrow.cc`,
  `TailLoops.cc` and `Lower/Counting.cc` all change. Unboxed sums with counted
  slots need `own` too: `!idr.own<!idr.data<@S>>`.
- **Static data.** Static values (constants; `isStatic`, `Counting.cc:51-58`)
  hold no count today. In the sketch a constant of a counted type is either
  borrowed (`T`, lives forever) or `idr.dup` of it is a no-op at lowering. The
  first is cleaner.
- **Upstream passes.** `idr-tail-loops` turns calls into `scf.while` after rc,
  and its loops must carry `own` values linearly. Today's `Verify.cc` needs
  a special borrowed-slot case (`:211-233`) for that. In the sketch a borrowed
  slot is just a `T` iteration argument whose owner outlives the loop, which
  the borrow-lifetime check covers.
- **Order.** Does borrow inference still need a module-wide fixpoint? Yes, but
  it can become a sparse backward interprocedural dataflow analysis
  (`mlir-idioms.md` §2) whose answer is written into function types.
