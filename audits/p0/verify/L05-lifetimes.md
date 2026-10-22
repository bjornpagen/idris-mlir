<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L05: grades, lifetimes, and allocation into a lifetime

**Lane:** L05 of the P0 verification swarm. **Rulings in scope:** D39, D40,
D48 (one binder for erased parameters), D26, D24, D10, C1 (borrows).
**HEAD:** `e96bb991` at start (2026-10-21T21:30Z); `e96bb991` at finish.
No code, build, test or git write was made; every cost below is *read*,
a *derivation*, or a measurement written out to be taken.

Grounds: *read* (path:line at HEAD), *measured* (how), *recalled* (not in
`sources/`), *conjecture*, *decision* (Dn, Cn), *derivation* (follows from
the cited facts by the stated argument).

Words used throughout, each defined once:
- **counted memory**: a heap cell with a live reference count
  (`idris_rt_header.count` 1 to `UINT32_MAX - 1`, `runtime/idris_rt.h:35-46`).
- **lexical lifetime**: `frame` or a lifetime variable; its memory is freed
  when its scope ends.
- **arena**: the run-time memory of one lexical lifetime whose cells are
  bump-allocated from heap chunks.
- **slot**: a fixed place in a function's native frame, one per allocating
  op, as `LowerCellStack` makes today (`lib/Conversion/Cells.cpp:76-101`).
- **view**: a reference that holds no count and is valid for a stated
  lifetime.
- **put / get**: a function that allocates into a lifetime puts; one that
  only reads values of it gets (Tofte and Talpin's effect words, *recalled*).

## 1. Verification

### D39 (scopes named in types)

1. **"today's three constants, `static < heap < frame`": refuted.**
   *Read*: the lifetime enum has two cases, `Heap` and `Frame`
   (`foreign/idr/include/idr/IR/IdrBase.td:104-108`); `struct Grade`
   holds one of them (`IR/Grades.h:39-48`); `fitsIn` spells a two-point
   order by hand (`lib/IR/Grades.cpp:137-141`). `static` was added by
   467fa2f5 and taken out by c4d38e9b the same evening, whose message says
   the attempt "graded a value static from where it came instead of from
   what it holds, so a constructor of runtime words became static data".
   *Integration mismatch* between the ruling's text and the code: `static`
   is new work (a writer, a reader set, the frontend's spelling), not a
   rename. §5.3's "a `static` lifetime, ordered static < heap < frame"
   repeats the debt.

2. **"A variable is bound by an op whose MLIR region is its extent, or by
   a function's scope parameter": holds, with a correction.** No binder
   exists at HEAD: `idr.func` has no parameter list of erased binders
   (`IdrOps.td:109-111`), and no op binds a lifetime (grep for
   `LifetimeOp`, `idr.lifetime`: none). The correction: D39 names two
   binders (the allocation scope and the function parameter); a third is
   needed for views of a value the function owns. Today such a view comes
   from `idr.borrow`, a pure op with no region
   (`IdrOwnershipOps.td:98-107`), whose scope is enforced only by the owned
   walk ("a view lives only while its owner holds its reference", same
   lines). If the walk goes (item 10), `idr.borrow` must become a region op
   that binds the view's lifetime, or no type states where a local view
   dies. *Structural incompleteness.*

3. **"Lexical, so its checking is local and linear given the signatures":
   holds** (*derivation*, §2.5 lists each check and its cost: per value
   or per edge, each O(1) to O(type size), none following a def-use chain
   across a region boundary). Two conditions the ruling leaves implicit:
   a call in tail position (D30) and a nested jump (D25) never cross a
   lifetime's region, since the region's end runs after them (§2.9).

4. **"Signatures carry scope parameters ... a result can live in its
   argument's scope": holds as design; no producer.** *Read*: every result
   that holds references is written owned (`lib/Transforms/Ownership/
   Signatures.cpp:36-39`), and borrow inference forces a returned
   parameter owned (`lib/Analysis/Ownership/Borrows.cpp:215-217`). A view
   result is not representable today. *Unverified behaviour*.

5. **"A scope parameter is a handle at run time, so it is part of the
   function's type (C2 R3)": integration mismatch with D48**, which makes
   lifetime variables "quantity-0 parameters ... passed at calls at compile
   time only". Both hold of different things: the variable is erased; the
   run-time handle (the arena to allocate into) is a separate ordinary
   parameter, present only when the function puts into that lifetime
   (§2.3). A function that only returns a view (`lookup`) needs no handle;
   giving it one would pass a dead register per call (D10).

6. **"Views first: borrowed parameters and results; an array element a
   view where D27's effects show no write to the array": holds, with a
   correction to the element rule.** Arrays ordered by IO (an IORef, an
   IOArray: `memref<..., #idr.world>`, `IR/Grades.h:237-243`) are shared
   and mutable: a write through another SSA value that aliases the array
   changes the element. A test of "no write effect naming this array
   value" is unsound for them. The sound test is "the view's region
   carries no `write` atom" (D29: `write` on `contents`), or the per-value
   test when the array is exclusive or linear (no alias exists).

7. **"Then allocation: cells bump-allocated into a scope, freed together
   at its end, with no count word": holds, with three corrections.**
   - *The header word stays.* A cell's header is one 8-byte word holding
     the count and the info (tag, object slots, kind) together, and the
     object slots after it are 8-aligned (`idris_rt.h:79-100`). Dropping
     the count saves no byte, and it would give arena cells a layout
     different from static cells', which a reader of a value that may be
     either (both are uncounted) could not tell apart. The count field of
     an arena or slot cell is written 0 by the same single store that
     writes the info, and no code reads or writes it after; every count
     operation goes. (*derivation*)
   - *"frees in O(1)"* holds for a lifetime whose cells hold no owned
     counted reference: its chunks are spliced onto a free list. One whose
     cells hold owned references runs its drop list first, O(owned fields):
     essential, since each must be decremented.
   - *"each scope proven within D26 ... counting the fallback"*: the
     obligations are not stated in P0. §2.6 states them with their proofs.

8. **"A scope moves whole between shards (0007 §5.1)": holds, with
   conditions.** 0007 §5.1's table has no row for a lifetime
   (`proposals/0007-shards.md:244-253`; a stack cell is copied). Moving an
   arena whole is sound only when its cells hold words, references into
   the same lifetime and static data (no view of older data, which stays
   on the sender, and no owned counted reference, which the detach walk
   would have to move), and when the send ends the lifetime's region and
   consumes its handle, used linearly (§2.6.5).

9. **"Static is graded from what a value holds, never from where it
   came": holds.** The mechanism c4d38e9b removed is still the one in use:
   `madeStatic` calls a value static data when its op "has no regions, is
   pure, and reads no reference" (`lib/IR/Verify/Uses.cpp:74-78`), a fact
   about where the value came from. It feeds `isStatic`
   (`Uses.cpp:82-84`) and through it `tracked` (`lib/Analysis/Ownership/
   Values.cpp:30`), reuse (`Reuses.cpp:165`), the program verifier
   (`Program.cpp:176`), narrowing (`lib/Transforms/Narrow/Facts.cpp:42,
   49`), counting's classes (`lib/Transforms/Ownership/Classes.cpp:52`)
   and the owned walk (`Verify/Owned.cpp:100`, `OwnedOps.cpp:284`).

10. **The three deletions.**
    - **"the owned verifier's whole-function def-use walk": holds, with a
      correction: half of it.** The walk (`lib/IR/Verify/Owned.cpp`,
      `OwnedRegions.cpp`, `OwnedOps.cpp`, 966 lines, *measured* `wc -l`)
      does two jobs. (a) *Views alive*: `Viewing`, `placesOf`, `writes`
      and `deadness` (`Owned.cpp:126-208`), `viewOf` and `use`
      (`:222-225, 273-284`), `ownersAcross` and `backEdges`
      (`OwnedRegions.cpp:251-317, 335-370`), the view arm of `make` and
      `readBy` (`OwnedOps.cpp:204-212, 283-288`): this is what a lifetime
      in the type replaces. (b) *Each reference consumed exactly once on
      every path* (`References`, `consume`, `settled`, the agreement of
      alternatives, payloads, the buffer boundary's `Carried` role:
      `Owned.cpp:48-73, 210-220, 227-271, 286-303`,
      `OwnedRegions.cpp:110-209, 319-333`): the
      leak-and-double-free rule, which no lifetime states. It is a
      linearity rule with exactness (an owned reference is a resource used
      exactly once), and it moves into `verify::linearity`
      (`Verify/Linearity.cpp`, which counts "at most once" per path for
      quantity-1 values today), one verifier for both.
    - **"`isStatic`'s search along the definition chain": holds**
      (`Uses.cpp:82-84`, a `definitionChain` walk per query).
    - **"the `dup` of every counted element read from an array
      (`Ownership.h:22-23`) where no write intervenes": holds, anchor
      corrected.** The cited lines are documentation
      (`include/idr/Analysis/Ownership.h:23-24`, and `:160-165`). The
      mechanism is `Classes.cpp:74` (an element is never classed
      `Borrowed`), with `isCountedElement` (`Values.cpp:37-40`) and
      Borrows' two element cases (`Borrows.cpp:259, 273`).

### D40 (the name, the constants, the order)

1. **The name `lifetime`: holds** (`IdrTypes.td:277-305`,
   `include/idr/IR/Lifetimes.h`).
2. **"today's `heap` constant becomes `counted`": holds.** Its Idris
   spellings go too: `data Lifetime = Heap | Frame`
   (`compiler/src/IdrisMLIR/Syntax/Idr.idr:83-89`) and the grade's
   `Maybe Lifetime` with `Nothing` meaning heap (`MLIR/Bytecode.idr:421-422`,
   `Emit/Index.idr:59`): a `Maybe` standing for a default.
3. **The order "static, then counted, then lexical lifetimes from outer to
   inner, frame the outermost of a function's": holds, with a correction.**
   It is a partial order, not a chain: a function's lifetime parameters
   lie below `static` and above `frame`, and are comparable neither with
   `counted` nor with each other (§2.2). The meet of two parameters is
   `frame`, which is what makes inference by meets total.
4. **"The grade prints `!idr.q<1, own, T, ρ>`": the example is a state
   D39 excludes.** An owned grade holds a count; a cell of a lifetime
   variable has none ("with no count word"). The one meaning `own` at a
   lexical lifetime can have is a counted cell whose memory is the
   lifetime's (today's stack cell, generalized), which needs the stack
   bit and its run-time tests (§1 D10). *Integration mismatch* among D26,
   D39 and D40: owner question Q1.
5. **"Synthesis A's locality ... go": holds.** The word is in documents
   only (`audits/p0/synthesis/A-dialect.md:225`,
   `audits/p0/design/match-and-counting.md:640`; no code says it, *measured*
   by grep).

### D48 (one binder for erased parameters)

**Holds, with four corrections.** (a) No binder exists at HEAD (§1 D39
item 2). (b) The handle (§1 D39 item 5). (c) A binder's identity must be
its position (a de Bruijn level), the name text for readers: a name used
as identity is a string key (AGENTS.md), and inlining two functions that
both bind `ρ` would otherwise compare names. (d) Every pass that moves
code across a binder substitutes: the inliner hook
(`lib/IR/Func/Inliner.cpp:22`), specialization's clones, a fold that
inlines a known case (whose index variables are fixed by the equation).
Region binders are three: a match case binds index variables (D48), an
allocation scope and a borrow scope each bind one lifetime.

### D26 (the parts this lane carries)

1. **"A call may hold ... the shells of its stack cells, whose fields are
   released at count 0": holds of HEAD** (`idris_rt.h:62-68`;
   `runtime/Rc/Freeing.cpp:127-135` frees a dead heap cell but sets a dead
   stack cell's count to 0). Under D39's uncounted lexical cells the
   clause has no object; its replacement is §2.6's obligations. Q1.
2. **"never ... a borrowed argument whose last use is the call ... (so an
   argument whose binder in the caller is linear is passed owned)":
   holds.** In QTT a linear binder can be passed only to a quantity-1
   parameter (*recalled*, Brady 2021, `sources/papers/brady-2021-idris2-qtt`);
   Borrows owns every quantity-1 parameter (`Borrows.cpp:83-84`), a
   stronger rule than D26 asks (§1 C1 item 4).
3. **"values borrowed past their last use whose type bounds everything
   they reach (a pair of words, not a list)": no code computes the
   bound.** *Structural incompleteness*: §2.6.3 defines `bounded(T)`, a
   fact computed once when a type is made.

### D24 (this lane's part: "the stack inference may not take that parameter")

**Defect confirmed at HEAD, unrepresentable under the exact grade.**
`idr-rc-stack` runs before exclusivity (`lib/Transforms/Pipeline.cpp:38-
41`) and reads nothing of the promise (`Stack.cpp:116-269`), so a cell
later passed to a rebuilding function may become a stack cell, which is
never exclusive (`idris_rt.h:65-68`), and the call is then refused: the
acceptance-depends-on-optimization chain of P0 §8 row 1. Under §2.1, an
exclusive grade implies counted memory, so the promised parameter's type
`!idr.q<1, excl, T>` cannot receive a lexical cell.

### D10 (what this lane's area pays for statically known facts)

| fact | where it is paid | static? |
| --- | --- | --- |
| a stack cell is never exclusive | `isExclusive` tests bit 31 on every uniqueness test (`runtime/Rc/Rc.h:50-53`) | yes: a value typed `heap` is never a stack cell (the verifier refuses frame into heap, `lib/IR/Lifetimes.cpp:157-170`); one typed `frame` is never exclusive (`lib/IR/Types.cpp:344-345`) |
| a dead stack cell's memory is not freed | `freeDead` and `idris_rt_free_cell` test bit 31 (`Freeing.cpp:128`, `Counting.cpp:72`) | dynamic only where a heap value was shared into a frame position (`idr.share`, `Stack.cpp:271-283`); gone with counted shells (Q1) |
| static data is not counted | every `inc`/`dec` tests count 0 (`Rc.h:45, 82, 90`) | static where the operand's type will say `static`; dynamic at a parameter that receives both, and then a key of specialization (§3) |
| what is static data | `isStatic` walks a definition chain per query, at compile time | yes: the grade |
| an element of an unwritten array lives | a `dup` and a `drop` per element read (`Classes.cpp:74`) | yes, where the view's region writes no array (§2.4.3) |
| a forced static memo cell's value is persistent | `persistHeld` walks and re-marks the reached graph at run time (`Freeing.cpp:165-...`) | the walk's extent is dynamic; avoidable by allocating that value into `static` (§4 I9) |

### C1 (borrows)

1. **"a parameter is borrowed only when at every call the caller uses the
   argument afterwards or its type bounds everything it reaches, and the
   callee neither consumes nor stores it": holds, with a correction.** As
   written it owns the parameter of every recursion over a borrowed
   structure. Counterexample: `length (_ :: t) = 1 + length t`. At the
   recursive call the argument `t` is a field of the borrowed list, its
   last use is the call, and a list does not bound what it reaches, so
   C1's text owns `length`'s parameter; then every outer caller that keeps
   its list pays a `dup`, and every level a take. Today's inference keeps
   it borrowed: a field read from a parameter holds a reference only when
   the parameter does (`Borrows.cpp:253-267`). Under D26 nothing is held
   that the program would not hold anyway: the cells reached through `t`
   belong to the outer caller, which keeps them. The correction adds one
   case: "or the argument is a view at a lifetime that outlives the
   caller's frame (a view of the caller's borrowed parameter, or static
   data)" (§2.4.1). *Defect in the decision's text.*
2. **"a parameter D24 rebuilds is owned": holds** (the rebuild consumes it).
3. **"Borrows' forced-owned reason taken from reuse sites
   (`Borrows.cpp:179-181`)" deleted: holds** (*read*: each reuse site's box
   is owned at initialization).
4. **Not in C1, found here.** Borrows owns every quantity-1 parameter
   (`Borrows.cpp:83-84`). C1's rule supersedes it: a quantity-1 parameter
   the callee only reads, whose every caller keeps its argument, saves a
   `dup` at the caller and a `drop` in the callee when borrowed. And
   Borrows owns every returned parameter (`:215-217`), which D39's view
   results replace. Borrows still runs on `DataFlowSolver` with a state per
   parameter and per chain value (07 B-01).
5. **"A runtime function's conventions come from the Idris
   specification": holds as design.** Today the convention is prose
   (`idris_rt.h:260-276`: a primitive borrows its arguments and returns
   an owned result), restated in each pass that reads a runtime call.

## 2. Boundaries

### 2.1 The grade, exactly

A value's type is its carrier `T` or `!idr.q<q, hold, T>`. The grade is
two facts, not three (§3 says why):

- **Quantity** `q ∈ {one, many}`: Idris's. Quantity 0 has no case: an
  erased value does not exist (`IdrBase.td:81-87`).
- **Hold**: what the value holds and for how long, one sum whose every
  case is legal:

| hold | lifetime | meaning | dup | drop |
| --- | --- | --- | --- | --- |
| `own` | counted, implied, never written | one counted reference of its own | n/a | decrements |
| `excl` | counted, implied | the only reference to every cell it reaches | n/a | frees, no count read |
| `borrow ℓ` | `ℓ ∈ {frame, ρ (parameter), λ (scope)}` | a view of counted or static memory, valid for `ℓ` | increments (count 0 left alone) | none |
| `plain ℓ` | `ℓ ∈ {static, frame, ρ, λ}` | a reference into uncounted memory (an arena, a slot, static data) valid for `ℓ` | ill-typed | none |
| `plain` | none | a value that reaches no cell (a word), or a builtin buffer at upstream's boundary | n/a | n/a |

Before counting, a value that holds references is `plain counted`
(unwritten) or `plain static` (a constant); after counting it is `own`,
`excl`, `borrow ℓ` or `plain ℓ` with `ℓ` lexical or static; a builtin
buffer stays `plain` at upstream's ops. The program's stage says which set
applies (01 T38's two meanings of plain are the two stages, an essential
split).

**Unrepresentable by the sum** (each a verifier rule or a guard today):
an owned or exclusive value at a lexical lifetime (the counted shell; Q1);
a view at `counted` (a scope-less borrow, the state the owned walk
guards); an exclusive value of the frame (`Types.cpp:344-345`); a
lifetime on a value that reaches no cell (`Types.cpp:341-343`); a grade
of quantity 0.

**Carrier rules, kept** (`Types.cpp:331-352`): no grade of a grade; none
on a type used once by its type (world before D20, destination, cell); a
tensor only at `(one, plain)`; a runtime carrier.

**Printed**: `!idr.q<1, own, T>`, `!idr.q<many, borrow, T, ρ>`,
`!idr.q<1, plain, T, static>`; `!idr.lin<T>`, `!idr.own<T>`,
`!idr.excl<T>` stay as spellings. D40's lifetime-last position and
`counted` unwritten hold; `own` and `excl` take no lifetime (Q1).

### 2.2 Lifetimes: constants, variables, the outlives order

- **Constants:** `static` (the whole run), `counted` (until the count
  reaches zero), `frame` (this call).
- **Variables:** a de Bruijn level into the scope's telescope: the
  function's erased binders first, then each enclosing binding region,
  outermost first. Printed with a name for readers; compared by level.
- **Outlives (`⊒`)**, at a program point of function `f` with lifetime
  parameters `ρ1..ρn` and enclosing scope variables `λ1` (outer) to
  `λm` (inner): the reflexive, transitive closure of
  `static ⊒ x` for every `x`; `counted ⊒ frame`; `ρi ⊒ frame`;
  `frame ⊒ λ1 ⊒ … ⊒ λm`. Nothing else: `ρi` and `counted` are
  incomparable, and so are `ρi` and `ρj`. The view lifetimes (all but
  `counted`) form a meet-semilattice whose meet of two parameters is
  `frame`. A test of `⊒` is a comparison of levels plus three cases.
- **The holding rule:** a value at `ℓ` may hold a reference at `ℓ'` only
  if `ℓ' ⊒ ℓ`, with these permissions per memory:
  - a *counted* cell's reference fields hold `own` (counted) or
    `plain static`, never a view (today's "frame into heap" refusal,
    `Lifetimes.cpp:163-170`);
  - a cell at a *lexical* lifetime `ℓ`: a field whose type is in the
    cell's own recursive group holds `plain ℓ'` (`ℓ' ⊒ ℓ`: the same arena,
    an outer one, or static); every other reference field holds a
    reference to counted or static memory (`own`, dropped at `ℓ`'s end,
    or `borrow ℓ'` with `ℓ' ⊒ ℓ`). This is D48's "layout, a function of
    the type and its lifetime".
- **The field-read rule:** a field read from a value whose hold is
  `borrow ℓ` or `plain ℓ` is, for a recursive-group field of a lexical
  cell, `plain ℓ`; otherwise `borrow ℓ` (counted referent, so a `dup` of
  it increments). From a counted cell the reader holds a view, so fields
  are read from `borrow ℓ`. Quantity multiplies as today
  (`fieldType`, `Grades.h:193-200`).
- **Subsumption:** at a slot of ours (a field, a call argument, a
  yield, a jump argument) a value at `ℓ` stands where `ℓ'` is asked when
  `ℓ ⊒ ℓ'`; at upstream's ops, whose verifiers ask equal types, the one
  regrade op forgets the difference (`idr.share`, today's heap-into-frame
  use generalized). `static` into an owned slot is a `dup` that the
  lowering emits as nothing (the operand's type says static).

### 2.3 Types, attributes and ops, by name and shape

All generated from the dialect's Idris specification (D16).

- `!idr.q<q, hold, T>` with the hold of §2.1; `#idr.grade` is its
  constexpr algebra (01 C1).
- **Binders.** `idr.func @f<n : nat, ρ : lifetime>`: an erased telescope,
  a property listing each binder's sort (an index sort of D48 or
  `lifetime`). `idr.call @f<k, frame>(...)`: the erased arguments, terms
  over the caller's scope, substituted into the callee's signature to type
  the call. One interface of ours over binding ops, "the variables this
  region binds", read by the scope verifier and the substitution helper.
- **`!idr.arena<ℓ>`**: the run-time handle of a lexical lifetime's arena;
  an ordinary word, quantity many, or one when the lifetime may move
  between shards. A function parameter of this type exists exactly when
  the function puts into `ℓ` (C2 R3: it changes the calling convention).
- **`idr.lifetime`**: one region, one block; binds `λ`; its entry block's
  argument is `%a : !idr.arena<λ>` (used only if something allocates by
  it; the lowering opens no arena otherwise); results may not mention
  `λ`. Traits: `AutomaticAllocationScope` (upstream's, as
  `memref.alloca_scope` has, `MemRefOps.td:424-448`),
  `RecursiveMemoryEffects`; its own effects `Free` on `idr.heap` (the
  chunks) and, when its cells hold owned fields, `Read`/`Write`/`Free` on
  `idr.count`. Does not implement upstream's control-flow-break
  propagation: no jump leaves it.
- **`idr.borrow` (region form)**: `%o2, %r... = idr.borrow %o { ^bb(%v :
  borrow λ) ... idr.yield ... }`. Binds `λ`; takes the owner, gives it
  back as the first result (the same value, `Idr_SameValue`); its
  region's views die at its end. Replaces the pure `idr.borrow`.
- **Cell sources** (one family, each source its own op as memref's are):
  `idr.cell.new : !idr.cell<C, counted>` (`Allocate` on `idr.heap`);
  `idr.cell.stack : !idr.cell<C, ℓ>` with `ℓ` lexical (a slot, one per
  op per frame, rewritten each run; `Allocate` on upstream's
  automatic-allocation-scope resource); `idr.cell.arena %a : !idr.cell<C,
  ℓ>` (a bump in `%a`'s arena; `Allocate` on `idr.heap`, since a chunk
  may be acquired); `idr.cell.recycle` (counted only).
- `idr.cell.init` on a lexical cell gives `plain ℓ` at the constructor's
  quantity; on a counted cell `own` or `excl`, as today.
- `idr.dup` takes `borrow ℓ` or `plain static` only; `idr.drop` takes
  `own`/`excl` only.

### 2.4 Inference: algorithms and costs

Every step is an optimization: a site it does not decide stays counted,
and no program is refused because of lifetimes (AGENTS.md: acceptance is
a property of the program). A budget may stop specialization, never
refuse.

1. **Borrowed parameters** (C1, corrected): a monotone two-point marking
   (borrowed until owned) over the program graph, the solver layer's
   template (§5.5). A parameter becomes owned when the callee consumes or
   stores it or a value read from it; when it is rebuilt (D24); or when
   some call passes an argument whose root is owned by the caller and
   whose last use is the call, unless its type is bounded. A view of the
   caller's borrowed parameter, or static data, never forces it. Cost
   O(V + E), a bit per parameter.
2. **View results and lifetime parameters**, bottom-up over the call
   graph's SCCs (the effect rows' order, D22): per result, a set of
   parameter indices it may view, or "owned". Start every result at the
   empty set; for each return, follow the operand's root (field reads,
   case bindings, same-value ops, a callee's result summary); a root that
   is a borrowed parameter adds its index, static adds nothing, anything
   else makes the result owned. Iterate the SCC to a fixpoint; each state
   only grows (empty, sets, owned), at most `params + 2` changes per
   result. A result that ends as a set `S` is `borrow ρ` for one fresh
   `ρ`, and each parameter in `S` is typed `borrow ρ`; every other
   borrowed parameter is `borrow frame`, or `borrow ρ'` when it reaches a
   call in tail position (its true lifetime outlives the caller's frame,
   D30). Recursive calls instantiate `ρ` with itself (monomorphic
   recursion); calls from outside the SCC instantiate it with the meet of
   their arguments' lifetimes. Cost: O(Σ over SCCs of iterations × body
   size); a result's state is one machine word for up to 64 parameters.
   Replaces Returned's "gives back argument i" for views (05 R5).
3. **Local borrow scopes** (placement, L07's walk): where today's
   placement classes a read `Borrowed` (`Classes.cpp:62-86`), it outlines
   the smallest contiguous run of ops of the owner's block holding every
   use of the views into one `idr.borrow` region, the owner threaded
   through. Several owners whose view runs coincide share one region. An
   element read inside a region whose row has no `write` (or whose array
   is exclusive or linear) is a view; otherwise it takes a reference, as
   today. A field read is sunk into the one case that uses it first, so
   the scope stays inside that case. Cost: O(ops) per function.
4. **Allocation into a lifetime** (the step that replaces
   `idr-rc-stack`), per function, callees first:
   - *Candidates*: each `idr.cell.new`, with the escape marking of today's
     inference over the flow edges (`IR/Lifetimes.h:41-93`), extracted per
     function; a call edge reads the callee's summary (which parameters
     escape; which results are put into a caller's lifetime) instead of
     linking one whole-program graph (`Stack.cpp:116-135`).
   - *The lifetime*: the innermost lexical lifetime whose extent holds
     every use of every value the cell may reach; `frame` when that is the
     body; a new `idr.lifetime` when a tighter scope exists; the caller's
     lifetime when the box flows into a result (a put parameter).
   - *The source*: `cell.stack` when the site runs at most once per run
     of the scope and no value it reaches is carried into another run;
     `cell.arena` otherwise.
   - *The proof* (§2.6): the step builds it; a site that has none stays
     `cell.new`.
   - *Put results*: per SCC, a two-point state per result ("built in the
     caller's lifetime" until a cell of it fails its proof). A caller
     passes a handle when its own proof covers the result; a caller that
     does not uses the callee's counted copy, made by specialization keyed
     by the vector of allocation modes, on demand, under a budget.
   - Cost: O(ops) per function for the marking and the proof; copies
     bounded by the budget.

### 2.5 The verifier rules, all local

Run in each function's region verifier, in parallel, after every pass:
1. Every variable in every type is bound in scope: O(values × type size).
2. The holding rule on every edge an op declares (`flowEdgesOf`), and
   subsumption at every slot: O(edges), each an order test.
3. A binding region's results and terminator operands mention no variable
   it binds: O(results).
4. A call's argument and result types equal the callee's signature with
   the erased arguments substituted: O(signature).
5. Owned references are consumed exactly once on every path and
   quantity-1 values at most once: the one linearity verifier (§1 D39
   item 10). The threaded owner of a borrow region makes "consumed during
   its loan" a second use.
6. A borrow region over an element or a memo capture: its row has no
   `write` (no `memo_state` for a capture), unless the array is exclusive
   or linear: O(ops in region), from the derived rows.
7. Per `idr.lifetime`, and per put parameter: the D26 proof of §2.6.
8. No call in tail position and no jump lies inside an `idr.lifetime` or
   `idr.borrow` region (read from the call's tail fact, D30, and from
   upstream's early-exit verifier, D25).

### 2.6 Allocation into a lifetime

#### 2.6.1 Memory

- **Slots** (`cell.stack`): the function's native frame, one slot per op
  (`Conversion/Cells.cpp:93-99` already places them at the entry of the
  nearest automatic allocation scope). They count in D32's static stack
  bound through the frame size code generation reports.
- **Arenas** (`cell.arena`): chunks drawn from snmalloc, so inside the
  heap's window aligned to 4 GiB (C5; `runtime/Alloc/Cells.cpp:31-39,
  93-105`): references into an arena share bits 32 to 55 with every heap
  cell's, which Apple's prefetcher follows (0017). Chunks are committed
  as snmalloc commits them (D35), counted by D36's committed-bytes range,
  and a failed acquisition is D23's out-of-memory ending. The first chunk
  is sized from the lifetime's static size when one is known, and chunks
  grow geometrically after it: a policy, measured, never a limit.
- **Header**: one word, count 0, info as today (§1 D39 item 7).
- **The end**: a lifetime whose cells hold no owned counted field
  splices its chunks onto the shard's free chunks, O(1). One with owned
  fields drops them first: a slot lifetime by drops the compiler emits at
  the end of each path (the slots are known), an arena lifetime by its
  drop list (each `cell.init` that stores an owned field into an arena
  cell appends the field's address). Which applies is static per
  lifetime, read from the types of the inits in its extent.

#### 2.6.2 Static

`static` is written by a constant's type, inferred from its attribute
(the attribute holds only constants), by the frontend for a literal, and
by the field-read rule from a static value. A fold that turns a counted
value into a constant materializes the constant at `static` and regrades
it to the original type, since upstream's folding asks the same type;
grading then narrows. Static is never inferred from an op being pure or
reading no reference (c4d38e9b).

#### 2.6.3 The D26 obligations, each with its proof or its fallback

`bounded(T)`: `T` reaches no type on a cycle of containment and no
dynamically sized cell (string, bignum, array), computed once when the
type is made (D48's layout facts). Roots of a lifetime `ℓ`: the boxes of
`ℓ` that no init of an `ℓ` cell takes as a field.

| # | obligation (D26) | proof | checked by | fallback |
| --- | --- | --- | --- | --- |
| A1 | dead bytes of `ℓ`'s cells held at an allocation are a fixed amount per frame | *count*: every site of `ℓ` runs at most once per run of `ℓ`'s scope and is not reached through a call on a cycle with `ℓ`'s handle, so the bytes are the static sum of its cells' sizes; or *spine*: every non-root box of `ℓ` is taken as a field by an init of an `ℓ` cell on every path from its definition, `ℓ`'s cells are immutable (no memo cell, no array), and no op whose row has `alloc` follows any root's last use inside the scope, so at every allocation each cell is reachable from a value still to be used | rule 7 of §2.5 | the site stays `cell.new` |
| A2 | a counted structure held by an owned field of an `ℓ` cell is not held dead at an allocation | under *spine*, the cell is reachable, so is the field (D26 counts reachability); under *count*, `bounded` of the field's type | rule 7 | store the field as a view when its owner outlives `ℓ`, or keep the cell counted |
| A3 | no dead dynamically sized cell is held past an allocation | strings, bignums and arrays are never allocated into a lexical lifetime; an owned field of such a type only under *spine* | the cell sources' types | counted |
| A4 | a function putting into a caller's `ρ` | *spine* relative to its returns: every box of `ρ` it allocates is taken into the returned value on every path | rule 7, in the callee | the callee's counted copy |
| A5 | a borrow scope holds its owner until its end | no op with `alloc` follows the last use of its views inside it | rule 7 for `idr.borrow` | placement shrinks it |
| A6 | lifetimes and calls | no scope holds a tail call (D30) or spans a call on its function's cycle (whose rest D31 moves into a frame) | rule 8 | counted |
| A7 | reuse | a lexical cell gives no token (`take` takes only `own`/`excl`), so reuse holds nothing of a lifetime | the grade | n/a |

#### 2.6.4 Recursion

`map f xs` putting into the caller's `ρ`: each level's cell is taken
into the result (A4, *spine*), and the recursive call passes `ρ`'s
handle on. Under D34 (destinations) the cell is built first and its hole
filled later: it is reachable from its parent all along.

#### 2.6.5 Shards

A lifetime moves whole when its cells hold only words, `plain ℓ`
references into itself and static data; its handle has quantity one;
the send is the terminator of its scope and consumes the handle; the
receiver opens a scope binding the received arena. Its chunks then free
on the receiver (snmalloc's remote free). Anything else crosses by 0007's
detach walk.

### 2.7 Constructor provenance

| fact | constructed by | and by no one else |
| --- | --- | --- |
| quantity one | the frontend (Emit, `Emit/Index.idr:59`), from Idris's TT | no pass raises many to one; `lin.use` forgets it |
| `own` / `borrow` of a parameter | the borrow marking (§2.4.1) | |
| `borrow ρ` results, lifetime parameters | the view-result inference (§2.4.2) | |
| local `borrow λ`, borrow scopes | placement (§2.4.3) | |
| `excl` | the exclusivity marking (L08) | |
| `static` | a constant's inferred type; the frontend's literal types; the field-read rule | never from purity |
| `frame`, `λ`, `plain ℓ` cells, arena handles, put parameters | the allocation step (§2.4.4) | |
| the D26 proof of a lifetime | the allocation step; checked by the verifier | |
| erased call arguments | whoever writes the call (frontend, specialization, the allocation step) | |
| tail position of a call | L10's one fact (D30) | read here |
| the in-place promise | L07's (D24), in the function's type | read here as a constraint |

### 2.8 Consumers, error and cleanup paths

- **Placement**: no `dup`/`drop` for `plain` values; borrow scopes.
- **Reuse**: lexical cells give no token; `cell.recycle` is counted only.
- **Exclusivity**: views are never exclusive; it follows only `own`.
- **Lowering**: `cell.stack` to a slot; `cell.arena` to the inline bump
  (`idris_rt_arena_alloc`, the chunk refill out of line); `idr.lifetime`
  to open and close; the slot drops or the drop list; header count 0.
- **Runtime** (contract only; internals are L11's): open (with a size
  hint), alloc, close, close-with-drops, note-owned-field, adopt (a moved
  arena). No stack bit.
- **Errors**: a verifier failure here is a compiler bug (internal error),
  never a refusal. Out of memory at a chunk is D23's ending.
- **Cleanup**: a scope's end runs on every normal exit; a crash
  (`ub.unreachable`) or `exit` ends the process and frees nothing; no
  jump or tail call leaves a scope (rule 8).

### 2.9 Seams with other lanes

| seam | the declaration both sides write against | state |
| --- | --- | --- |
| L01/L02 effects | `cell.arena` declares `Allocate` on `idr.heap`; `idr.lifetime` `Free` on `idr.heap` (and count effects with owned fields); `cell.stack` upstream's scope resource; the `alloc` atom is what A1 reads | fixed here, theirs to declare |
| L04 families | the field rule needs "same recursive group" and `bounded(T)` from the family; layout is a function of type and lifetime | fixed by D48; the fact names are unfixed |
| L07 placement, reuse | borrow scopes are placement's output; the allocation step runs before placement on SSA liveness and reads the in-place promise | proposed here |
| L08 exclusivity | `excl` implies counted; views not followed | fixed by §2.1 |
| L09 control flow | `idr.lifetime` and `idr.borrow` do not propagate breaks; contification forms no join point whose jump would cross one | proposed here |
| L10 tail, frames, stack | a call's tail fact is read; no scope spans a tail call or a cycle call; slots count in D32's bound | proposed here |
| L11 runtime | the arena entries of §2.8; count 0 in lexical headers; bit 31 gone | proposed here (Q1) |
| L14 analyses | the three markings share one template; per-SCC summaries for results | fixed by §5.5 |
| L16 frontend | literal types `static`; the grade's parts imported from the specification (D50) | fixed by D50 |

### 2.10 What it deletes

- `Lifetime::Heap` and every `heap` spelling of the lifetime; the hand
  enum (`IdrBase.td:96-108`); `fitsIn`/`joined` written by hand
  (`Grades.cpp:137-141`); `holdsOwn`'s switch (`:55-65`); `mayBeFrame`'s
  carrier test becomes the type's fact; the frame rules of `QType::verify`
  (`Types.cpp:341-345`) become unrepresentable states.
- `madeStatic`, `isStatic` and their nine callers (§1 D39 item 9);
  counting's `Phantom`, `Constant`, `StaticRead` classes (08 C-04).
- The owned walk's view half (§1 D39 item 10); its exact-once half
  merges into `Verify/Linearity.cpp`; `Owned*.cpp` go whole once merged.
- `isCountedElement` and the element-owning cases (`Values.cpp:37-40`,
  `Classes.cpp:74`, `Borrows.cpp:259, 273`).
- `idr-rc-stack`'s whole-program graph, its byte budgets as the only
  proof, its select case and its own tail and cycle readings
  (`Stack.cpp:78-80, 116-269, 371-375, 233-241`); `loopsInFrame`'s tail
  questions (`Lifetimes.cpp:59-66`).
- Borrows on `DataFlowSolver`, its quantity-1 rule, its returned rule and
  its reuse-site rule (`Borrows.cpp:83-84, 179-181, 215-217`, B-01).
- With Q1 answered "delete": `IDRIS_RT_STACK_CELL` and every test of it
  (`Rc.h:47-53`, `Counting.cpp:34, 72`, `Freeing.cpp:128, 174`,
  `CellInfo.cpp:49`, `Conversion/MemoCells.cpp:41`,
  `Conversion/Cells.cpp:80-101`'s mark), the `idr.share` raise of heap
  into frame.
- The Idris side's `Lifetime` and `Maybe Lifetime` (`Syntax/Idr.idr:83-89`,
  `Bytecode.idr:421-422`).

### 2.11 Essential distinctions that must remain

Quantity apart from hold (Idris's fact against counting's, Brooks'
limit). `borrow` apart from `plain ℓ` (a `dup` increments one and cannot
touch the other). Counted, slot and arena memory (three freeing rules).
Get and put lifetimes (a handle exists only for put). The two stages'
meaning of `plain` (before and after counting).

## 3. QTT

**Where each quantity enters, is kept, read and lost.**
- *Quantity 0.* Idris erases it (the fork's `eraseArgs`, read once by the
  frontend under D44); the frontend emits no value for it (AGENTS.md).
  Lifetime and index variables are quantity-0 binders of the telescope:
  kept in types and in calls' erased arguments, read by the scope and
  substitution checks, gone at the lowering, where nothing needs them. The
  only run-time trace of a lifetime is its arena handle, a quantity-many
  word, present only for a put.
- *Quantity 1.* Emit writes `!idr.lin<T>` on every linear binder but the
  world (`Emit/Monad.idr:80-83`, 01 §2.2); kept in types, verified after
  every pass; read by the linearity verifier, by Borrows
  (`Borrows.cpp:83-84`) and by D26's rule that a linear binder's argument
  is passed owned; lost at LLVM, correctly, since it orders nothing there.
- *Uniqueness is not quantity 1.* Linearity restricts the future (one
  use), uniqueness guarantees the past (no other reference): §5.10 G1,
  G2 on Marshall, Vollmer and Orchard 2022
  (`sources/papers/marshall-2022-linearity-uniqueness`). `excl` stays its
  own case, proved by exclusivity, never inferred from quantity 1.

**One grade or two.** In QTT a usage is an element of a semiring:
contexts add when a variable is used in two subterms and scale under
application (Atkey 2018, `sources/papers/atkey-2018-qtt`; Idris's
`{0, 1, ω}`, Brady 2021). Quantity is that, and our `times`
(`Grades.cpp:143-151`) is its product, used where a case binds a field.
Permission is not: two uses of an exclusive value do not add to an
exclusive value but forget it (`idr.share`), a one-way coercion of a
modality, not a sum. Lifetime is a mode with a submoding order, as
OxCaml's locality (*read from the abstract*, §5.10 G4). And three of the
four permissions fix or forbid the lifetime. So: quantity and permission
are two grades, as 01 C1 found; permission and lifetime are one, the hold
sum of §2.1, whose cases carry exactly the lifetime each may have.

**Facts a quantity proves that the design still pays for.**
1. A quantity-1 parameter that the callee only reads is owned
   (`Borrows.cpp:83-84`), so a caller that keeps its argument pays a
   `dup` and the callee a `drop`. C1's rule borrows it.
2. A linear or exclusive array cannot be written through another
   reference, so its elements are views under any borrow scope with no
   effect check (§2.4.3).
3. A quantity-1 value at a lexical lifetime has one use, so its scope
   can end right after it: tightness, and A1's last-use condition, are
   syntactic for it.
4. A movable lifetime's handle at quantity 1 makes "the sender uses the
   arena after the send" a second use, refused by the linearity verifier.
5. D31's frames are linear, uncounted and unique from birth: ownership
   without a count, which linearity plus uniqueness at birth proves (a
   pattern this lane does not extend; L10's).
6. Static data at a parameter that also receives counted values pays the
   count-0 test on each `inc`/`dec`. With `static` in the type, an
   argument's lifetime is a key for specialization, under a budget whose
   fallback is the test.

**Misuse made unwritable.** The hold sum (an owned value of a lexical
lifetime, a scope-less view); `plain ℓ` (a `dup` of an arena reference is
ill-typed); an erased binder has no SSA value, so no op can read a
lifetime at run time; `!idr.arena<ℓ>` is the only way to allocate into
`ℓ`; the threaded owner (consuming a loaned value is a second use);
`excl` implies counted (the D24 parameter cannot receive a lexical cell).

## 4. Improvements

**I1. The grade is quantity × hold** (*owner*, through Q1; *coordinator*
if Q1 is answered "delete").
- *Evidence*: three independent enums admit 2 × 4 × 4 states per carrier
  once `static` and variables exist, and today's verifier refuses part
  of them by hand (`Types.cpp:341-345`).
- *Counterexample*: `!idr.q<many, borrow, !L>` (lifetime counted) is a
  view with no scope; a pass that writes one leaves the deleted walk's
  job to nobody, and a use after its owner's drop reads freed memory.
- *Root cause*: lifetime as an independent coordinate of a reference
  whose permission fixes it.
- *Correction*: §2.1's sum, declared in the specification, generated.
- *Deletes*: the frame and exclusive rules of `QType::verify`, `holdsOwn`,
  `mayBeFrame`'s grade use.
- *Discriminated by*: the generated parser refusing
  `!idr.q<many, own, T, frame>` and a view without a lifetime after
  counting.

**I2. The lifetime variable is erased; the arena handle is a separate
parameter, only for a put** (*coordinator*: reconciles D39 and D48 by
their words).
- *Evidence*: §1 D39 item 5.
- *Counterexample*: `lookup<ρ>(t : borrow ρ) -> borrow ρ` would carry a
  handle register per call, never read: a static fact (it puts nothing)
  paid at run time.
- *Root cause*: the type-level name and the run-time capability held as
  one thing.
- *Correction*: `!idr.arena<ρ>` parameters, inferred with put results
  (§2.4.4).
- *Deletes*: nothing yet built; prevents a dead parameter class.
- *Discriminated by*: the verifier refusing a `cell.arena` whose handle
  is not in scope, and a function signature carrying no handle for a
  get-only lifetime.

**I3. `borrow ℓ` and `plain ℓ` are different holds** (*coordinator*,
inside I1's shape).
- *Evidence*: today every cell is counted or persistent, so a `dup` of
  any view is meaningful (`Rc.h:79-84`); uncounted arena cells end that.
- *Counterexample*: `tail' (_ :: t) = t` with an owned result, called
  with a list built in a caller's arena. `dup t` increments the count
  field of an arena cell (0, read as persistent), and returns a
  "counted" reference that the caller keeps past the arena's end: a use
  after free.
- *Root cause*: whether a view's referent is counted, lost in a single
  "view" case.
- *Correction*: §2.1, with §2.2's field rule deciding which a read gives.
- *Deletes*: the need for a run-time "is this counted" mark.
- *Discriminated by*: `idr.dup` refusing a `plain ℓ` operand; a test
  where the arena list reaches an owned result runs the callee's counted
  copy and frees every cell.

**I4. The borrow scope is a region op that threads its owner**
(*coordinator*: follows from D39's "a view's scope is its type and its
region").
- *Evidence*: §1 D39 item 2; the walk's view half (§1 D39 item 10).
- *Counterexample*: `%v = idr.borrow %o; idr.drop %o; idr.field %v`:
  today only the walk refuses it; without the walk and without a scope,
  nothing does.
- *Root cause*: a view's extent held by a whole-function analysis
  instead of a binder.
- *Correction*: §2.3's region `idr.borrow`; placement outlines it.
- *Deletes*: `Viewing`, `places`, write epochs, `deadness`,
  `ownersAcross`, `backEdges`, the pure `idr.borrow`.
- *Discriminated by*: the same IR fails to parse or verify (the owner
  has a second use inside its loan); the owned stage's programs keep
  their outputs and leave no live cell.

**I5. The D26 proof is a local verifier rule of every lifetime**
(*coordinator*: D26 is a promise, and promises are kept by
construction).
- *Evidence*: D39 asks every scope proven, and states no proof; MLKit
  added a collector for its region leaks (Hallenberg, Elsman and Tofte
  2002, *recalled*).
- *Counterexample*: a loop over a list that builds a temporary pair per
  element into the enclosing `idr.lifetime` and reads it once: a million
  dead pairs held at every later allocation, with a correct output.
- *Root cause*: allocation into a scope decided by escape alone (today's
  stack rule, `Stack.cpp:6-28`), which bounds nothing once the cell count
  is dynamic.
- *Correction*: §2.6.3's *count* and *spine* proofs, checked per
  lifetime; counting the fallback.
- *Deletes*: the byte budgets as the only bound (`Stack.cpp:78-80`) stay
  as a performance policy only.
- *Discriminated by*: a high-water-mark test (live bytes at each
  allocation, from the checked runtime) that fails with the pairs in the
  scope and passes with them counted or in an inner scope per iteration.

**I6. C1's borrow rule takes views of the caller's borrowed parameters**
(*coordinator*: the evidence settles it).
- *Evidence, counterexample*: §1 C1 item 1 (`length`).
- *Root cause*: "uses the argument afterwards" read of the argument
  value, not of the owner that keeps its cells.
- *Correction*: §2.4.1.
- *Deletes*: nothing; prevents a regression against
  `Borrows.cpp:253-267`.
- *Discriminated by*: `length` over a borrowed list compiles to no count
  operation per level (an idr-expect property on the function).

**I7. Element views by the scope's row, not by a per-value write test**
(*coordinator*).
- *Evidence*: §1 D39 item 6.
- *Counterexample*: `x <- readIORef r; writeIORef r' y; use x` with `r'`
  an alias of `r` held in another SSA value: no write effect names `r`,
  so the per-value rule makes `x` a view of a cell that the write freed.
- *Root cause*: MLIR effects name values, and distinct values may alias.
- *Correction*: no `write` atom in the borrow scope's row, or an
  exclusive or linear array.
- *Deletes*: `Classes.cpp:74`'s blanket owned element.
- *Discriminated by*: that program keeps its `dup` and runs; a fold over
  a linear array's elements has none.

**I8. One binder mechanism, positional** (*coordinator*: D48 settles it).
- *Evidence*: §1 D48.
- *Counterexample*: inlining `@f<ρ>` into `@g<ρ>` with binders compared
  by name: `@f`'s `ρ` and `@g`'s are taken as one, and a view of `@f`'s
  argument is typed as living as long as `@g`'s.
- *Root cause*: a name used as identity.
- *Correction*: de Bruijn levels, one interface for binding ops, the
  inliner hook substituting.
- *Deletes*: nothing yet built.
- *Discriminated by*: the scope verifier refusing an unbound level after
  a rewrite that forgot to substitute.

**I9. A static memo cell's forced value is built into `static`**
(*coordinator*; seam with L11 and the memo ops).
- *Evidence*: `persistHeld` walks the forced value's graph at run time
  and re-marks every cell (`Freeing.cpp:165-...`; `Rc.h:110-115`).
- *Counterexample*: a top-level table of a million entries forced once:
  a million cells counted, built, then walked again to uncount them.
- *Root cause*: the force does not know the cell is static, though its
  type will.
- *Correction*: the label's function specialized with its result put
  into `static`, its cells from a never-freed arena (*spine* holds:
  static data is live by D26's own exclusion).
- *Deletes*: `persistHeld` and `idris_rt_persist_held`.
- *Discriminated by*: `lower-static-thunk`'s program keeps its output,
  and the checked runtime counts no live cell from the forced table.

**I10. 0007's `lent` permission is a lifetime** (*owner*: amends 0007,
scope between proposals; for when 0007 is taken).
- *Evidence*: 0007 §5.3 adds a fourth permission whose meaning is "a view
  valid until the structured fork joins, of memory another shard counts"
  (`0007-shards.md:272-281`).
- *Counterexample*: none in P0; under 0007 as written, `lent` and
  `borrow ℓ` are two spellings of a view at an extent.
- *Root cause*: no lifetime existed when 0007 was written.
- *Correction*: `plain ℓfork`, with the fork binding `ℓfork`, and one op
  that copies a `plain` value into counted memory where 0007's `dup` of
  `lent` copies.
- *Deletes*: the `lent` permission.
- *Discriminated by*: 0007's send check refusing a `plain ℓfork` value
  past the join.

## 5. Work units (draft; none dispatched)

Each unit lands whole, deletes what it replaces, and passes `make check`,
`make build`, `make test`, `make test-idr`, `make test-unit` and
`make test-mlir-tools` on the four targets.

**WU-1. The grade and the lifetime in the specification.**
- *Writes*: the specification's grade module under `compiler/spec/`
  (C7); the generated `.td` and C++ it yields; `include/idr/IR/Grades.h`,
  `lib/IR/Grades.cpp`, `lib/IR/Types.cpp` (`QType`);
  `compiler/src/IdrisMLIR/Syntax/Idr.idr`, `Encoding/Idr.idr`,
  `MLIR/Bytecode.idr`, `Emit/Index.idr`.
- *Outcome*: §2.1 and §2.2: quantity, hold, constants, levels, `⊒` as a
  decidable relation with its laws proved in Idris (a partial order;
  meets exist for view lifetimes), the holding rule as a table.
- *Deletes*: §2.10's first and last items.
- *Must not*: add a lifetime anywhere but the hold; keep `heap` as an
  alias.
- *Acceptance*: every existing fixture's `frame` grade reads as `frame`;
  the owned stage's programs keep their outputs; the parser refuses the
  states §2.1 lists.

**WU-2. Binders.**
- *Writes*: `lib/IR/Func/Func.cpp`, `Call.cpp`, `Inliner.cpp`, a new
  `lib/IR/Verify/Scope.cpp`; the binder interface in the specification.
- *Outcome*: the telescope, erased call arguments, levels, the scope
  verifier (§2.5 rules 1, 3, 4), substitution in the inliner and clones.
- *Deletes*: nothing standing; index binders of D48 land on it (L04).
- *Must not*: compare binders by name.
- *Acceptance*: inlining and specializing programs with lifetime
  parameters keep their outputs; a rewrite that leaves an unbound level
  fails verification.

**WU-3. Static.**
- *Writes*: `lib/IR/Constants.cpp`, `lib/IR/Verify/Uses.cpp`,
  `lib/Analysis/Ownership/Values.cpp`, `lib/Transforms/Narrow/Facts.cpp`,
  `lib/IR/Verify/Program.cpp`, `lib/Analysis/Ownership/Reuses.cpp`,
  `lib/Transforms/Ownership/Classes.cpp`, `lib/Conversion/StaticData.cpp`.
- *Outcome*: §2.6.2.
- *Deletes*: `madeStatic`, `isStatic`, their callers' static branches.
- *Must not*: grade static from purity.
- *Acceptance*: `lower-static-thunk`, `specialize-static-table` and every
  program with literals keep their outputs; a constructor of run-time
  words is never static data (the case c4d38e9b reverted).

**WU-4. Views: borrowed parameters and view results.**
- *Writes*: `lib/Analysis/Ownership/Borrows.cpp` (rewritten on the
  solver layer's marking), `lib/Transforms/Ownership/Signatures.cpp`,
  `include/idr/Analysis/Ownership.h`.
- *Outcome*: §2.4.1 and §2.4.2.
- *Deletes*: Borrows' solver states, its quantity-1, returned and
  reuse-site rules.
- *Must not*: read reuse decisions; borrow a parameter D24 rebuilds.
- *Acceptance*: a recursive `lookup` over a borrowed tree returns a view
  and runs no count operation (an idr-expect property); outputs and live
  cells unchanged across the suite. *Measurement to take*: the number of
  borrowed parameters (`Borrows::borrowed()`) before and after, on the
  suite and stage 1.

**WU-5. Borrow scopes and the one linearity verifier.**
- *Writes*: `lib/IR/Verify/Linearity.cpp`, `Owned.cpp`,
  `OwnedRegions.cpp`, `OwnedOps.cpp`, `lib/IR/OpsOwnership.cpp`,
  `lib/Transforms/Ownership/Placement.cpp`, `Classes.cpp`.
- *Outcome*: §2.3's region `idr.borrow`; placement outlines scopes;
  element and capture views by row (§2.5 rule 6); exact-once merged into
  linearity.
- *Deletes*: the owned walk whole; `isCountedElement`.
- *Must not*: let a jump or tail call into a scope.
- *Acceptance*: every owned-stage program keeps its output and leaves no
  live cell; a fold over an unwritten array runs no `dup` per element.

**WU-6. Allocation into a lifetime.**
- *Writes*: `lib/Transforms/Stack/Stack.cpp` (replaced),
  `include/idr/IR/Lifetimes.h`, `lib/IR/Lifetimes.cpp`, a new
  `lib/IR/Verify/Lifetimes.cpp` (the D26 rule), the cell ops in the
  specification.
- *Outcome*: §2.4.4, §2.6.3; `idr.lifetime`, `cell.arena`,
  `!idr.arena`, put parameters; the per-function marking on the solver
  layer.
- *Deletes*: the whole-program graph, the budgets as proof, the select
  case, the tail and cycle readings of `Stack.cpp`.
- *Must not*: take a cell the in-place promise rebuilds; refuse
  anything.
- *Acceptance*: `rc-stack-cell`, `stack-linear-box` and `verify-frame`
  keep their behaviour; a tree built and traversed in a scope allocates
  no counted cell for it (`no-heap-allocation` property) and the
  high-water-mark test of I5 holds. *Measurement to take*: cells
  placed in a lifetime against today's `numStackCells`, on the suite and
  stage 1, and the step's time with `-ftime-trace`-style pass timing.

**WU-7. Lowering and the runtime contract.**
- *Writes*: `lib/Conversion/Cells.cpp`, `MemoCells.cpp`,
  `lib/IR/Layout/CellInfo.cpp`, `runtime/idris_rt.h`, `runtime/Rc/Rc.h`,
  `Counting.cpp`, `Freeing.cpp`, a new `runtime/Alloc/Arena.cpp`
  (behind L11's internals).
- *Outcome*: §2.6.1, §2.8.
- *Deletes*: with Q1 "delete", bit 31 and every test of it.
- *Must not*: put a per-target case outside the target's entry; reserve
  or commit memory before use.
- *Acceptance*: on all four targets, every program's output and status
  unchanged; the checked runtime finds no count operation on a lexical
  cell; strict-host start (D35) still holds.

**WU-8. Specialization by allocation mode.**
- *Writes*: `lib/Transforms/Ownership/Specialize.cpp`.
- *Outcome*: callee copies keyed by put modes, on demand, under a
  budget whose fallback is the counted copy.
- *Must not*: refuse at the budget.
- *Acceptance*: a function called with an arena and with counted
  memory has two copies and each frees what it built.

## 6. Owner questions

**Q1. Does a counted cell in lexical memory survive?** Today's stack cell
is counted: its fields are released at count 0 and its memory at the
frame's end (D26's clause, `idris_rt.h:62-68`). D39 says a lifetime's
cells have "no count word"; D40 prints `!idr.q<1, own, T, ρ>`, an owned
value of a lifetime variable, which only such a counted cell could be.
- *(a) Keep it*, as a third kind beside counted heap cells and uncounted
  lexical cells. Buys: a cell whose D26 proof fails (§2.6.3) can still
  live in the frame, its fields released dynamically. Costs: the stack
  bit and its run-time tests (in every uniqueness test, a static fact;
  in every free of a value that may be either kind, a dynamic one); an
  `own` grade at a lexical lifetime; two freeing rules for frame memory.
- *(b) Delete it.* Every lexical cell is uncounted; a cell without a
  proof goes to the counted heap. Buys: one representation per memory;
  the hold sum of §2.1 exactly (no `own` at a lexical lifetime); the
  stack bit and its tests go (D10). Costs: some of today's stack cells
  become heap cells (those holding an owned field dead long before the
  scope ends), until a tighter scope covers them; D40's printed example
  changes to `!idr.q<1, borrow, T, ρ>` or `!idr.q<1, plain, T, ρ>`.
- *Recommendation*: (b), measured: today's `numStackCells` against
  cells placed in a lifetime on the suite and stage 1 before the stack
  bit is removed.
