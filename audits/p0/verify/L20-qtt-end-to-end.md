<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 verification, lane L20: QTT end to end; concurrency and Rust

The quantities Idris proves (0 erased, 1 linear, ω unrestricted), traced
from the fork's checked TT to LLVM under the design P0 now states; where
each is held, who reads it, where it can still be lost; what quantities
could prove that the design does not yet use; and the stress of proposal
0007's shards, futures and waits and proposal 0020's Rust ownership,
io_uring's buffers among them, against D39 and D48.

- **HEAD** at start: `e96bb991` (`git rev-parse --short HEAD`,
  2026-10-21T21:43Z). At finish: `e96bb991` (unchanged; every anchor below
  is at that commit and the working tree as the coordinator left it).
- **Scope**: AGENTS.md's rule that no pass drops multiplicities, erasure
  or linearity; D24, D26, D30 (Rust's frames, open), D39, D48; C2;
  proposals 0007 and 0020.
- **Marks**: *read* (path:line), *measured* (with its command),
  *recalled* (not in `sources/`), *conjecture*, *decision* (Dn, Cn).
- **Read for this lane**: the representation-first skill, AGENTS.md and
  `proposals/0000-mlir-native.md` in full; 17 §2.3 to §2.5, §4, §5 and
  Q-FB2; 14 §2 to §4 (the grade and Emit rows); 01 §2.2, §5.7, §6 and its
  grade rows; 07 §1 (the 5.7 and 5.10 notes), §6 (rc-Q1); 08 §1, T13, §6
  (NQ1 to NQ4); `design/typed-effects.md` §0 to §2;
  `design/effect-vocabulary.md` §8 and its identity rows; proposals 0007
  and 0020 whole; 5.7's M1 passages; 5.10 §G, M4 to M6, R2, R3;
  `design/match-and-counting.md` §4 and §9's tested view; Brady's
  `erasure.tex`, `linearity.tex`, `protocols.tex`, `conclusion.tex`; and
  the code named below. Not readable here: the PDFs of Atkey 2018 and
  Marshall 2022 and 2024 (no PDF text tool in this checkout); Marshall
  2022 is cited through 5.10 G1, which quotes it with its page.

## 1. Verification

Each claim: *holds*, *holds with a correction*, or *refuted*, with its
evidence and its class (defect confirmed in the source; structural
incompleteness; integration mismatch; unverified behaviour; optional
simplification).

### 1.1 AGENTS.md: no pass drops multiplicities, erasure or linearity

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| What Idris erased is no value: no parameter, field or argument | holds | The `Term` binder's quantity is `One \| Many` (`Syntax/Idr.idr:144-148`, `Types.idr:127-130`); `coreBinder` raises an internal error on quantity 0 (`Frontend/Translate/Types.idr:1124-1133`), so an erased position never reaches Emit (*read*) | — |
| Erasure is Idris's fact, read once | refuted at HEAD, corrected by D44 | `eraseArgs` is kept by the TTC (`compiler/idris/src/Core/TTC.idr:1326`) and read by nothing; five readers re-derive it with different defaults (17 FB-15, `audits/p0/17-fork-boundary.md:532`) | integration mismatch (lanes 16, 17 own the fix) |
| Quantity 1 is a type, `!idr.lin<T>` | holds | Emit writes `QType One Plain t Nothing` for every quantity-1 binder but the world (`Emit/Index.idr:58-59`, `Emit/Monad.idr:80-83`); `!idr.lin<T>` is that grade's spelling (`IdrTypes.td:265-276`) (*read*) | — |
| Every transformation keeps it, and the verifier checks after every pass | holds with a correction | The verifier that runs after every pass checks *use*, at most once on every path (`lib/IR/Verify/Linearity.cpp:3-4, 91-100`), not *keeping*: a pass that rewrites a block argument from `!idr.lin<T>` to `T` leaves no linear value to count and passes. Keeping is checked only by idr-expect's `quantities-kept`, in tests, keyed by location, colliding keys dropped (`Transforms/Expect/Quantities.cpp:3-19`; 17 FB-31). Each pass that rebuilds a signature restates linearity by hand (`Defunctionalize/Declare.cpp:39-42`, `Specialize/Patterns.cpp:43-45`, `Specialize/Keys.cpp:218-222`) (*read*) | structural incompleteness (§4 I7) |
| Emit keeps what Idris proved | refuted | Emit counts each linear binder's uses (`Emit/Bodies.idr:56`) and holds it plain when they reach two (`heldAs`, `:139-146`), a parameter included (`Emit/Declarations.idr:44-45`), while the function's type keeps `!idr.lin` (the arguments come from `bound`, `:44, 48`) (*read*; 17 FB-28) | defect confirmed in the source (§4 I1) |
| Idris's quantity 1 means used exactly once | holds with a correction | Brady: "an argument with multiplicity 1 is guaranteed to be used exactly once" (`sources/papers/brady-2021-idris2-qtt/linearity.tex:5-7`). The IR keeps only the *at most once* half (`Linearity.cpp:4`); `idr.borrow` is not counted as a use (`:115-117`), and constants are exempt (`:144-151`). Nothing in the tree reads the *at least once* half; the obligations it would carry (a join, a close) are kept from deletion by their ops' effects, not by the grade (*read*). The IR's linearity is affine by design; the specification should say so (§3.6) | structural incompleteness |
| A fact in a discardable attribute can be dropped; none is kept there | holds for quantities | No quantity crosses in an attribute (17 §4 categories, `audits/p0/17-fork-boundary.md:582-585`); `total` is an inherent `UnitAttr` of `idr.func` (`Emit/Declarations.idr:56-59`) (*read*) | — |

### 1.2 D24: the in-place promise

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| An `in_place` type promises a rebuild with no run-time test; the kinds are `LList` and `LNat` | holds | `Registry/Recognized.idr:183-186`, `InPlaceType` (`Registry/Entry.idr:260, 343, 409`) (*read*) | — |
| Quantity 0 is never a cell, so the rule never reads it | holds | §1.1 row 1 | — |
| Linearity makes a parameter subject to the rule | holds with a correction | The quantity the rule reads must be the one proved of the body. At HEAD a parameter used twice in its body keeps `!idr.lin` in its type and is `lin.use`d at entry (§1.1 row 5), and `Demand.cpp:70` reads `isLinear(param.getType())`. So the rule would bind a parameter the body reads twice; placement then needs a `dup` D24 forbids (an internal error), or, if the rule follows `lin.use` (an `Idr_SameValue` op, `IdrOwnershipOps.td:416-425`), an in-place rebuild of a cell read again. The subject must be the match whose scrutinee is the linear parameter itself (`takenApart`, `Emit/Bodies.idr:415-416`), never a `lin.use` of it | integration mismatch (§4 I1) |
| Exclusivity (`!idr.excl`) is the obligation at every call, "since a linear binder does not imply unique ownership" | holds | Brady: "there is no requirement that it has not been shared in the past" (`erasure.tex:36-39`); the near/far pair `tests/uniqueness-shared-rebuild` (*read*: `Main.idr:1-31`, `expected`) | — |
| The refusal is exact against the rule | holds with a correction | Exact only if the marking's own precision bugs go: §8's crash-case row (`ExclusivityGraph.cpp:208-222`) marks a fresh linear value shared and refuses it; §4 I3 makes such values exclusive by a local rule the marking cannot override | integration mismatch (§4 I3) |
| Deleted: `Demand.cpp`'s `rebuilt` | holds | `Transforms/Demand/Demand.cpp:62-77` reads the token of an `idr.take` behind an `idr.cell.recycle` (*read*) | — |

### 1.3 D26: frame-limited

| claim (the QTT parts) | verdict | evidence | class |
| --- | --- | --- | --- |
| "An argument whose binder in the caller is linear is passed owned, read off its type" | holds with a correction | At a call the operand for an unrestricted parameter is the result of `lin.use`, typed ω (`Emit/Operations.idr:148-154`), and that result may be used again where Emit demoted (§1.1 row 5). The fact is "the operand's one use is the call", true only once demotion is gone (§4 I1); read off the use, not the type | integration mismatch |
| A call may hold reuse tokens | holds | Tokens are linear by their type (`isLinearByType`, `IdrInterfaces.td:43-47`; `IdrOwnershipOps.td:135-139`), so held at most once (*read*) | — |
| Under ten thousand suspended tasks, a suspended task's frame is an active frame | holds | C2 (`effect-vocabulary.md:843-846`); 0007 §2's task frame holds only values live at the wait (`proposals/0007-shards.md:93-100`) (*read*) | — |
| Nothing else about quantities | — | D26 promises space, not counts; quantity 1 does not bound space by itself (a linear list is still a list) | — |

### 1.4 D30 and D32: Rust's frames (open)

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| "A runtime op is a primitive, not a call of the program" covers a Rust call | holds | A shim "is part of the runtime and never an `idr.func`" (`proposals/0020-rust-interop.md:806-812`) (*read*) | — |
| D30's promise holds across a cycle through a Rust callback | refuted (the ruling marks it open) | A cycle Idris → shim → callback dispatch → Idris → shim keeps Rust's native frames on every turn; no jump or musttail removes a foreign frame (the shim's convention is the C ABI, `0020:828-833`), and D31's typed stacks cannot hold them | structural incompleteness (owner question 1) |
| D32's static bound covers a program that calls Rust | refuted (open) | The bound is "the longest acyclic path of the call graph, weighted by each function's frame size" (D32); Rust code's recursion and indirect calls are outside it. 0020 says nothing of stack depth (*measured*: `grep -n -i stack proposals/0020-rust-interop.md` finds only the freeing worklist, `:32, 787`, stack cells, `:792-793`, and `std`'s guard, `:858`). Rust expects megabytes (*recalled*: 8 MiB on the main thread, 2 MiB on spawned threads), where C5 expects tens to hundreds of KiB | structural incompleteness (owner question 1) |
| A callback may wait | refuted by construction of 0007 | Stackless coroutines (0007 §2, `:118-145`) cannot suspend with Rust's frames on the native stack; nothing in 0020 §8.8 or C2 forbids a `wait` in a callback | structural incompleteness (§4 I11) |

### 1.5 D39: lifetimes named in types

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| The grade's lifetime becomes `static < counted < frame` plus variables, bound by `idr.lifetime` or a function's parameter | holds as a design | Today two constants (`IdrBase.td:104-108`); the grade's parameters are quantity, permission, value, lifetime (`IdrTypes.td:283-291`) (*read*) | — |
| "A scope parameter is a handle at run time, so it is part of the function's type (C2 R3)" | holds with a correction | D48 makes lifetime variables "quantity-0 parameters ... passed at calls at compile time only". Both hold of two things: the lifetime is erased (quantity 0); the arena a function allocates into is a run-time value whose type names the lifetime, present only where the function allocates into it. L05 reaches the same split (`audits/p0/verify/L05-lifetimes.md:74-82`) | integration mismatch (§4 I5) |
| Views first: borrowed parameters and results | holds | The permission `borrow` and `idr.borrow` exist (`IdrBase.td:89-94`, `IdrOwnershipOps.td:93-107`); a lifetime parameter on a view result is what 0020's borrowed results need (§1.8) | — |
| "A scope moves whole between shards (0007 §5.1)" | holds with a correction | A move ends the lifetime on the sender: every view into it must be dead at the send, so the arena handle is consumed by the move (an owned value moved, its views ended), which the arena's grade states (§2.1) | structural incompleteness |
| Static is graded from what a value holds | holds | D39 text; c4d38e9b's lesson (*read*: proposal D39) | — |

### 1.6 D48: data types as inductive families

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| An erased field does not exist; a field's quantity is one or many | holds | §1.1 row 1; `Emit/Index.idr:78` writes each field's grade from its binder (*read*) | — |
| "Erased parameters share one binder: index variables and lifetime variables are quantity-0 parameters" | holds with a correction | Idris also has indices bound by *run-time* parameters and fields: `replicate : (len : Nat) -> (x : elem) -> Vect len elem` (`third_party/Idris2/libs/base/Data/Vect.idr:237-239`), `withIteratorString : (str : String) -> (1 it : StringIterator str) -> ...` (`libs/mlir-linear/Linear/String/Iterator.idr:74`), `MkVec : {0 cap : Nat} -> (n : Nat) -> (0 fits : LTE n cap) -> ... -> Vec n a` (`libs/mlir-array/Linear/Vec.idr:38-40`). An index equal to an ω value has no quantity-0 binder, so it is opaque and "refines nothing": `replicate`'s `Z` arm cannot type `Nil : #Vect[len]` | structural incompleteness (§4 I4) |
| A known index fixes the shape (`#Vect[3]` inline) | holds with a correction | Quantity 0 decides representation though erased (`match-and-counting.md:203-205`); a function over `#Vect[n]` called at `#Vect[3]` meets two layouts. Specializing on the index is a budgeted optimization (AGENTS.md), so the design needs the conversion a spent budget leaves, and must never require the specialization for acceptance | integration mismatch (lane 04's) |
| A match refines the index; a false equation's case does not exist | holds for constructor matches | It needs I4 for a match on a run-time value equal to an index | — |
| The specification writes a field's quantity as a type with no erased case | holds | D48 text; matches `Quantity = One \| Many` | — |

### 1.7 C2: the tree under shards, the kernel and Rust

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| The tree holds per shard, unchanged | holds | 0007 D1 (`proposals/0007-shards.md:628-637`): a heap, output buffer, handle table and constants per shard; no mutable memory shared (*read*) | — |
| R1: kernel-touched memory is held by ownership; a read consumes an exclusive buffer, its completion returns it; cancel drops it at completion | holds with a correction | Ownership is half of it; the other half is the lifetime and the result's exclusivity. A buffer the stack inference frames, or a D39 lifetime allocates into a task's scope, is freed when a cancel ends that frame or scope (`coro.destroy` on cancel, 0007 `:130-140`) while the kernel may still write it (R1's own *recalled* io_uring fact). And with results ungraded (§3.2), the returned buffer is exclusive only if the operation's signature says its result is the consumed argument, exclusive | defect in the rule's statement (§4 I9) |
| R2: `heap` names any cell's memory, kernel rings and foreign allocations included | holds | `effect-vocabulary.md:817-821` | — |
| R3: an effect that changes a calling convention lives in the function's type; `wait` is the first | holds, with a consequence | A callback handed to Rust must then carry no `wait` (§1.4 row 4); D39 cites R3 for the arena handle, which is an operand, not an effect (§1.5) | — |
| R4: a foreign call's effects come from its operands' types and grades | holds with a correction | A crate may end the process (`clap`, `0020:747-754`), so every foreign call writes `exit` (D14), beside `io`, `crash`, `divergence` | integration mismatch (§4 I11) |
| R5: a drop of a value whose type may reach a foreign cell writes `IO` | holds with a correction | The effect orders the drop among IO, but its *place* is counting's last use after optimization: a pass deleting a dead total use of a Rust handle (D13 licenses it) moves the destructor's flush earlier than the program's output that followed it. The place must be the program's, as D24's rule is | integration mismatch (owner question 2) |
| Stale in 0007 and 0020: the world, `Here`, task frames, `idr.wait` as a terminator, `wait` in `Idr_Effect` | holds, incomplete | Add: 0007's "the join is linear, so every fork is joined" (`:354`) and the lend's safety (`:385-389`), refuted in §1.8; 0007's `lent` permission (`:272-281`), a lifetime under D39 and D40; 0020's run-time borrow state of constants and statics (`:555-568`), a static fact | structural incompleteness (§4 I8) |

### 1.8 Proposal 0007 against QTT

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| "The join is linear, so every fork is joined" (`0007:354`) | refuted | `fork` returns the `Join` as a `Shard` result; a bind's continuation takes its argument unrestricted, as `io_bind`'s does (`third_party/Idris2/libs/prelude/PrimIO.idr:41`), and "multiplicities are associated with binders, not with return values or types" (`protocols.tex:13-17`). A program may drop a `Join` or join it twice. Harmless for plain forks only because `runShards` joins everything at the end (D5, `0007:681-683`) | defect confirmed in the source (§4 I8) |
| "Lending cannot dangle: runST's region on a linear join, so every borrower is joined before `lend` returns" (`0007:385-389`) | refuted | Same reason: `forkL`'s `Join'` is unrestricted. A dropped `Join'` lets `lend` return while a borrower on another shard still reads the lent value: a use after free. And AGENTS.md: "Linearity is a performance property, never a correctness one" | defect confirmed in the source (§4 I8) |
| A value at the exclusive grade crosses as a move; "a linear binder does not imply unique heap ownership", the detach walk reads the count, never the quantity (`0007:69-70, 256-262`) | holds | consistent with D24 | — |
| `Here` is linear with no runtime component, as the world | holds as Idris; stale in the IR | Under D20 it goes at Emit as the world does; its shard index is a quantity-0 index (D48) | — |
| The shard index is quantity 0; a `Local`'s home is its erased index (`0007:65-68, 335-339`) | holds | Idris's type checking does the home check; after Emit the index is a family index or nothing (D48) | — |
| A task frame is linear "(it holds the world)" (`0007:99, 137-140`) | holds with a correction | Stale reason (D20); the frame is linear by its type (owned by the reactor), as tokens and cells are | — |
| 0007's frames versus D31's frame stacks | unverified behaviour | D31 does not say where a frame stack's top lives; a wait inside a call cycle (D32 puts it on D31's stacks) interleaves two tasks' frames on one shard unless the top is a value of the task (§4 I10) | integration mismatch |

### 1.9 Proposal 0020 against QTT

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| A by-value object parameter is `(1 _ : Rust t)`, moved out of its cell, which needs the only reference, checked at run time (`0020:415-417, 684-688`) | holds with a correction | This is D24's shape: quantity 1 makes the parameter subject, exclusivity at the call is the obligation. D24 decides it statically and refuses; 0020 tests it at run time and crashes. A shared handle at a by-value call is a property of the program the exclusivity analysis decides before the optimizer | integration mismatch (owner question 3) |
| `&T` is borrowed shared for the call; `&mut T` exclusive for the call (`0020:418-420, 676-683`) | holds | Objects are references with identity, as an `IORef` (`0020:398-406`), every call `IO` (§9): the borrow state guards aliasing inside one call and re-entrancy, facts not known until run time in general; an `excl` operand folds the check (`0020:705-714`) | — |
| A borrowed result is a borrow handle released after its last use (`0020:424-430`) | holds with a correction | D39's lifetime parameter is this fact made static: a result in its argument's lifetime is a view, with no handle cell or count; the borrow state is then written at the lifetime's region ends, which are static (L05's area) | optional simplification |
| An exclusive or by-value use of a constant or immutable static object "stops the program" at run time (`0020:555-557, 567-569`) | holds with a correction | The state "shared forever" is static, so such a use is a statically certain crash: compiled as a plain crash where evaluation reaches it, with no state word read (D13, D10) | defect against D10 |
| Linear handles rejected: "an `IO` result is unrestricted ... and correctness may not rest on linearity" (`0020:1197-1201`) | holds | The same reading of QTT that refutes 0007's join (§1.8); exclusivity for a handle bound unrestricted and used once comes from the marking (§3.3) | — |
| Every call takes and gives the world (`0020:632-633, 820-826`) | refuted by D20 | C2 R4 replaces it | — |

### 1.10 Claims of the reread audits this lane rests on

| claim | verdict | evidence |
| --- | --- | --- |
| 5.7: "a quantity-1 value is used exactly once, so for linear values the IR has static single use" (`wave1/5.7-library.md:406-407`) | holds with a correction | Before counting. After counting a linear value has its views as extra uses (`idr.borrow` is not a use, `Linearity.cpp:115-117`), and Emit's demotions break it at HEAD |
| 5.10 M5: exclusivity is "killed by the first `dup` or ω binding" (`wave1/5.10-rc.md:545-550`) | holds with a correction | An ω binding used once does not kill it: `tests/uniqueness-shared-rebuild/near` binds `xs` unrestricted, uses it once, and is accepted exclusive (*read*: `expected`, "near: compile: exit 0"). The kill is a second use on a path |
| 5.10 M5: quantity 1 "removes no dup that Perceus would have emitted"; its gains are an unrepresentable `dup` and uniqueness carried forward | holds; the first gain is not built | `idr.dup` takes any counted view (`IdrOwnershipOps.td:57-58, 74`), quantity unrestricted (§4 I2) |
| `match-and-counting.md` §4: a linear value "is never dup'd; its last use is syntactic" | holds as the design; not enforced | the same `dup` constraint |
| 17 Q-FB2: is a demotion stated, an internal error, or a refusal? | answered by the evidence | Never needed: a substitution that respects quantities let-binds instead (§4 I1); L16 reaches the internal error for parameters (`L16-frontend.md:808-813`) |

## 2. Boundaries

### 2.1 The end state, by name and shape

The QTT facts of the redesigned compiler, each with its one holder.

**Idris side (fork and frontend).**
- `RigCount` on TT binders, checked by `Core.LinearCheck`, kept by the TTC
  (`TTC.idr:609-620`); `eraseArgs` per definition (`TTC.idr:1326`).
  `ZeroOneOmega` public (17 FB-22).
- One runtime signature per definition: `data Position = Absent | Runtime
  Quantity ClosedTerm`, `Signature (arity : Nat)` with `Vect arity
  Position` (17 C2, `audits/p0/17-fork-boundary.md:636-654`; lanes 16, 17).
  Under §4 I4 a `Runtime` position whose variable later types mention also
  names the index it stands for.
- `Term` binders carry `Quantity = One | Many`, proved of that `Term`
  (§4 I1; L16 I4).
- Emit writes the grade from a generated view that admits only what the
  frontend may write (17 C4, 14 G03): `!idr.lin<T>` or the bare type;
  results bare (Idris grades no result); a family attribute per data
  declaration, index and lifetime parameters on `idr.func`, index terms
  on `idr.call` (D48).

**Types and attributes.**
- The grade: `!idr.q<quantity, permission, T, lifetime>` printed
  `!idr.q<1, own, T, ρ>` with `counted` unwritten (D40), as one
  `#idr.grade` with its algebra (01 C1). Quantity ∈ {1, many}; 0 is
  absence. Permission ∈ {plain, borrow, own, excl}. Lifetime ∈ {static,
  counted, frame} ∪ variables.
- `!idr.lin<T>` = (1, plain, T); `!idr.excl<T>` = (many, excl, T);
  `(1, excl)` is legal and is what D24's obligation writes on a rebuilt
  parameter (01 `audits/p0/01-ods-types.md:592`).
- Linear by type, no grade (`isLinearByType`): tokens, destinations, cells,
  join tokens `!idr.cont<...>` (D25), D31's frame-stack tops (§4 I10),
  0007's `!idr.join<T>` and task frames when built. The world is gone (D20).
- `#idr.family<...>` with erased indices, per constructor its index
  variables and equation, each field's quantity (D48); `!idr.data<#F[idx]>`.
  Under §4 I4, a natural whose value equals an index carries the index in
  its type (`!idr.nat<n>`; spelling lane 04's).
- Under §4 I5 (L05's representation), an arena handle whose type names its
  lifetime, an ordinary run-time operand.

**Ops.**
- `idr.lin.enter` (a value handed to a linear position) and `idr.lin.use`
  (a linear value's one use, the only demotion); each `Allocate` on
  `identity` of its result (`effect-vocabulary.md:295`), so CSE never
  merges two and LICM never hoists one. Whether they become one regrade op
  is lane 03's (01 T43).
- `idr.borrow` (a view; not a use), `idr.dup` (operand: a view at quantity
  many, §4 I2), `idr.drop`, `idr.share` (forgets exclusivity),
  `idr.take`, `idr.is_unique` (folds on `excl`), `idr.cell.recycle`.
- `idr.lifetime` (region = extent); `idr.match` binds fields at the
  product of the scrutinee's quantity and the field's (`Grades.h`
  `fieldType`).

**Interfaces and verifiers.** `ValueFactsTypeInterface.isLinearByType`;
the linearity rule (at most once per path, regions that exclude each
other as alternatives, a repetitive region as many); the lifetime rule
(D40's outlives order); the owned rule (views before their owner's
consuming use); the exclusivity provenance rule (§4 I3).

**Passes that read or write a quantity.** Emit (writes); defunctionalization
(keeps a linear closure as `!idr.lin<sum>`, `Defunctionalize/Declare.cpp:39-42`,
`Converter.cpp:86-98`); specialization (linear leaves, `Specialize/Keys.cpp:218-222`;
rebuilt positions re-entered, `Patterns.cpp:124-126`); the inliner (types
match); D24's rule (reads quantity 1, writes the obligation); Borrows
(quantity 1 is owned, `Analysis/Ownership/Borrows.cpp:20-27, 83-84`);
the exclusivity marking (reads uses); idr-lower (erases the grade:
`lin.enter`, `lin.use`, `borrow`, `share` have no runtime form,
`Conversion/Lower.cpp:66-76`).

**Runtime.** No quantity reaches it. Its consequences do: no count on an
exclusive take, a recycled cell, no `inc`/`dec` on what counting proved.

### 2.2 Invariants

1. No value, field, operand or SSA name exists for a quantity-0 position.
2. A quantity on a `Term` binder is proved of that `Term`; a parameter's
   is its Pi binder's.
3. A value of quantity 1 (by grade or by type) is used at most once on
   every path; its only demotion is `lin.use`.
4. A pass never changes a grade's quantity except through `lin.enter` or
   `lin.use`; function clones copy grades by construction (§4 I7).
5. `excl` is written by idr-rc alone, and only on a value whose provenance
   or marking proves it.
6. An index variable is quantity 0 and never a run-time operand; an arena
   handle is a run-time operand and never an index.
7. A view never outlives its lifetime's region.
8. Every obligation a quantity-1 binder carried in Idris (join, close,
   release) is an op whose effect keeps it from deletion.

### 2.3 Constructor provenance

| fact | constructed by | who alone may | read by |
| --- | --- | --- | --- |
| a position is erased (quantity 0) | Idris: `findErased` → `eraseArgs` (`compiler/idris/src/TTImp/Elab/Utils.idr:38-61`) | the fork; the frontend's one signature reader copies it | the translation (no binder), Emit (no operand) |
| a binder's quantity 1 or ω | Idris's elaborator, checked by `Core.LinearCheck` | the fork | the signature reader → `Term` → Emit |
| `!idr.lin<T>` on a value | Emit (`heldType`, `Emit/Index.idr:58-59`; `lin.enter` by `coerce`, `Emit/Operations.idr:148-154`) | Emit; a pass only copies one, or enters a value it rebuilt fresh (`Patterns.cpp:124-126`, `Converter.cpp:86-98`) | the linearity rule, Borrows, D24's rule, the provenance rule |
| a linear value made plain | `lin.use` | any pass, only as that op at the one use | counting, the marking |
| linear by type | the type's declaration in the specification | the specification | the linearity rule |
| a family and its fields' quantities | the frontend from Idris's declaration; a pass that declares a sum (defunctionalization) | those | the verifier, layout, specialization |
| an index variable of a function or region | the frontend from a quantity-0 Pi binder, and (§4 I4) beside a run-time parameter later types mention | the frontend | the verifier (substitution at calls) |
| an index term at a call | the frontend | the frontend; specialization substitutes | the verifier |
| a lifetime variable, and an arena handle | the lifetime inference, bottom-up over SCCs (D39), and `idr.lifetime` | that pass | counting, layout, the verifier |
| `frame` and `static` | the stack inference; grading from what a value holds | idr-rc's stack step; the static grader | layout, counting |
| `excl` | the exclusivity marking; the provenance rule (§4 I3) | idr-rc | `is_unique`'s fold, the take's expansion, D24's check, the lowering (§4 I6) |
| the in-place obligation on a parameter, `(1, excl)` | D24's rule before counting: an `in_place` kind and the function's match on that linear parameter | that rule | reuse (must recycle), the stack inference (must not take it), placement (no `dup`), the call check |
| `own` or `borrow` on a parameter | Borrows (C1) | idr-rc | placement, the lowering |
| a fresh identity | `Allocate` on `identity`: `lin.enter`, `lin.use`, a recycle, a call's owned results | the specification's rules | CSE, DCE, LICM |

### 2.4 Consumers, error and cleanup paths

- **A call the marking cannot prove exclusive** where D24 binds:
  `unsupported (uniqueness)` at the call, with a note at the `dup` that
  shared it (`Demand.cpp:89-97`).
- **A linear value used twice after a pass**: the linearity rule fails;
  an internal error naming the pass (never a user's refusal).
- **A crash region**: a linear value unused there is legal (affine); the
  crash ends the run, and nothing counts it.
- **0007's cancel path**: a cancel region consumes the live owned and
  linear values (C2's stale note); a buffer in flight is dropped by the
  reactor at the completion, never by the cancel (§4 I9).
- **A Rust panic**: a crash, no unwinding (`0020:716-723`); a linear
  value live across the call is dead with the run.
- **The world**: no path; it is gone at Emit (D20).

### 2.5 What the area deletes

- `Emit/Bodies.idr:48-146` (`mostUses` and helpers, `heldAs`, `holdFor`);
  `Emit/Declarations.idr:45`'s hold; `Emit/Monad.idr:80-83`'s world branch
  (with D20) and `madeAt`'s compare of two `Bool`s (`:134-136`), and
  `coerce`'s pair of `Bool`s (`Emit/Operations.idr:149`), for a `Held`
  sum (14 E07).
- The per-pass restatements of linearity (`Declare.cpp:41`,
  `Patterns.cpp:45`), behind the one clone-and-key template (§4 I7).
- `Demand.cpp`'s token walk (D24).
- For 0007, when taken: the `lent` permission, the "linear join" claims.
- For 0020, when taken: the run-time borrow state of constants and
  statics; the by-value uniqueness test, if owner question 3 picks (a).

### 2.6 Essential distinctions

- Quantity (Idris's, about the future) and exclusivity (proved, about the
  past): never one fact (AGENTS.md; 5.10 G1, G2).
- Erased and constant: an index varies at run time (`StringIterator str`
  over a run-time string; `Vect n` from input).
- Linear by grade and linear by type.
- The IR's at-most-once and Idris's exactly-once: the IR keeps the first;
  effects keep the obligations of the second.
- A lifetime (quantity 0) and an arena (a run-time value).
- An index bound at quantity 0 and an index equal to a run-time value.
- A move (consumes; needs exclusivity), a shared borrow, an exclusive
  borrow (needs no alias inside the call).

### 2.7 Seams

| with | the declaration both sides write against | state |
| --- | --- | --- |
| lanes 16, 17 (fork, frontend) | the runtime signature (17 C2); `Term` quantities proved of the term | fixed by 17 C2 and L16 I4; §4 I1 adds the substitution rule |
| lane 04 (families) | the index binder; the layout of a known index | unfixed: §4 I4 (run-time indices), §1.6 row 3 (layout conversion) |
| lane 05 (lifetimes) | lifetime variable at quantity 0; arena handle as an operand | convergent (L05 §1 item 5) |
| lanes 07, 08 (counting, exclusivity) | the `(1, excl)` obligation in the function type; the provenance rule; result exclusivity | §4 I3 proposes; unfixed |
| lane 02 (rows) | foreign calls' rows (`exit`; callbacks without `wait`); drops reaching a foreign cell | §4 I11; owner question 2 |
| lane 10 (frames) | where a frame stack's top lives | unfixed: §4 I10 |
| lane 11 (endings) | a foreign stack exhausted | owner question 1 |
| lane 12 (arrays) | `LArray` born fresh and leaving only by `freeze` (0009 §3.8); `to_tensor restrict` asserts what only `excl` proves | §3.5 item 5 |
| lane 18 (specialization, defunctionalization) | the clone-and-key template copies grades | §4 I7 |
| lane 19 (tests) | `quantities-kept` keyed by binder | 17 FB-31 |

## 3. QTT

### 3.1 Quantity 0, traced: `Linear.Vec`'s `{0 cap}` and `(0 fits : LTE n cap)`

Source: `MkVec : {0 cap : Nat} -> (n : Nat) -> (0 fits : LTE n cap) ->
(fill : a) -> (1 cells : LArray [<cap] a) -> Vec n a`
(`libs/mlir-array/Linear/Vec.idr:38-40`), and the implicit `a`, which
Idris gives quantity 0 ("Implicitly bound arguments are also given
multiplicity 0", `erasure.tex:72-77`).

| stage | holder | reader | loss, and its fix |
| --- | --- | --- | --- |
| elaboration | `Pi` binders at `Rig0`; `eraseArgs` from `findErased` (`Elab/Utils.idr:38-61`) | `LinearCheck` | — |
| TTC | the binder's `RigCount` (`TTC.idr:609-620`); `eraseArgs` for user names (`:1326`) | — | a non-user name's `eraseArgs` reads back empty (17 FB-08, *conjecture*): measure, keep for the definitions the frontend reaches |
| frontend | at HEAD five readers (17 FB-15) | translation, growth check, keys | an argument erased by one reader and runtime by another: the one signature (17 C2) |
| `Term` | absence: no binder (`Quantity = One \| Many`) | — | — |
| Emit | nothing written; the constructor's fields are `n`, `fill`, `cells` (`Emit/Index.idr:78`) | — | — |
| dialect (D48) | `#Vec`'s declaration: index `n`; `MkVec` binds `cap` (existential) and has no `fits` field | the verifier (refinement), layout | the field `n` equals the index; without §4 I4 that equation is unwritable and `n` is just a word |
| specialization | the erased `a` decides the instance's layout (`match-and-counting.md:203-205`) | keys by layout | — |
| counting, lowering, LLVM | nothing | — | — |

What it buys at run time: no word for `fits` or `cap`, no count, no
check. What the design still pays: the frontend's five readings
(compile time; 17 C2 deletes them).

### 3.2 Quantity 1, traced: `reverseOnto : LList a -@ LList a -@ LList a`

Source: `libs/mlir-linear/Linear/List.idr:30-32` (`reverseOnto acc (x :: xs) =
reverseOnto (x :: acc) xs`), `LList` an `in_place` type
(`Registry/Recognized.idr:185`).

| stage | holder | reader | loss, and its fix |
| --- | --- | --- | --- |
| elaboration | both `Pi` binders at `Rig1` | `LinearCheck` | — |
| TTC | `RigCount` (`TTC.idr:609-620`); `linearChecked` read back `True` and unread (17 FB-21) | — | — |
| frontend | `Resolve.use rig` → `Used One` (`Resolve.idr:204-205`), at 43 sites (17 §2.4) | translation | a rewrite (beta, a normal form, an alias) copies `Rig1` onto a binder its result uses twice (17 FB-28; L16 `Translate/Terms.idr:553-555`): quantity-respecting substitution (§4 I1) |
| `Term` | `MkBinder One t` | Emit | — |
| Emit | the function type `(!idr.lin<!L>, !idr.lin<!L>)` (`Declarations.idr:44-51`); the match on a linear scrutinee binds fields at the constructor's quantities (`Bodies.idr:413-428`); the self call's arguments enter linear slots (`Operations.idr:150-153`) | the dialect | `heldAs` demotes a binder used twice, the signature still linear (`Bodies.idr:139-146`, `Declarations.idr:45`): deleted by §4 I1 |
| dialect | `!idr.lin<!L>` | the linearity rule after every pass | the rule checks use, not keeping (§1.1 row 4): §4 I7 |
| defunctionalization, specialization, inlining | kept (`Declare.cpp:39-42`; `Keys.cpp:218-222`; `Patterns.cpp:124-126`) | — | hand restatements per pass: §4 I7 |
| D24's rule (before counting) | `xs` is taken apart and an `LList` built from it: the second parameter becomes `(1, excl)`, an obligation in the function type | reuse, the stack inference, placement, the call check | the rule must read the match on the linear parameter itself (§1.2 row 3) |
| counting | Borrows: both owned (`Borrows.cpp:83-84`); the take of an `excl` value moves its fields out and its token is the cell; `x :: acc` recycles it | the lowering | — |
| tail (D30) | the self call in tail position is a loop; its carried values typed `!idr.lin` | — | — |
| lowering | the grade erased; `lin.enter`/`lin.use` lower to their operand (`Lower.cpp:66-76`); the take reads no count; the recycle stores in place | LLVM | `excl` reaches LLVM as nothing: no `noalias` (`Conversion/Facts.cpp:22-55`): §4 I6 |

What quantity 1 buys here (5.10 M5): the owned convention by type; a
`dup` of it unrepresentable (once §4 I2 lands); the in-place rule's
subject; uniqueness carried forward once proved (§4 I3). What it does
not buy: that the cell is unique at the call (D24's obligation).

### 3.3 Quantity ω, traced: `main`'s `let xs = build ...`

Source: `tests/uniqueness-shared-rebuild/Main.idr:25-30` and its `near/`.

| stage | holder | reader | loss, and its fix |
| --- | --- | --- | --- |
| elaboration, TTC, frontend | `RigW` → `Used Many` | translation | — |
| Emit | the bare type (`heldType Many t = mlirType t`); passing it to `bump`'s linear slot writes `lin.enter` (`Operations.idr:150-153`) | — | — |
| dialect | (many, plain, counted) | everything | none: ω is the top, nothing to lose |
| counting | far: two uses on one path → shared → `bump`'s obligation fails → `unsupported (uniqueness)`, line 30. near: one use of a fresh value → `excl` → accepted | D24's check | "used once" is re-derived by the marking from uses; correct (§1.10 row 2), and the right holder for a fact Idris did not prove |
| lowering | counts where not `excl` | — | — |

### 3.4 Erased indices and proofs

- A proof (`fits`, `LTE`, `Elem`, `Agree`) at quantity 0 is no value, a
  free invariant (the skill: "Proofs are values, and quantity 0 makes them
  free").
- An index is not a constant: `StringIterator str` is indexed by a
  run-time string ("The index exists at compile time only",
  `Iterator.idr`'s `StringIterator`); `Vect n` of input has an unknown `n`.
  D48's opaque term is sound for both; §4 I4 makes the refinement work
  where the index equals a run-time value.
- An erased type decides layout and the instance key (§3.1); an erased
  index decides layout only through D48's "known index fixes the shape",
  which must stay an optimization (§1.6 row 3).
- A shard index (`Fin n` at quantity 0 in `Here`, `Shard`, `Local`,
  `0007:346-360`) and 0007's lend region (`{0 l : Region}`, `0007:386`)
  are the same kind of fact as D39's lifetime variable: erased indices
  Idris checks, which the IR keeps as index or lifetime parameters or
  drops.

### 3.5 What quantities prove that the design does not yet use

1. **A value created at quantity 1 and never shared is exclusive.**
   Marshall's line (5.10 G1): uniqueness is a promise about the past,
   linearity about the future; a unique value used only linearly stays
   unique. Brady says the same of construction: "if this is the only way
   of constructing an `Array`, then all arrays are guaranteed to be used
   linearly, so we can have in-place update" (`protocols.tex:25-27`).
   The design computes every value's exclusivity by a whole-program
   marking; for a fresh value that enters a linear position and moves
   only through linear positions, exclusivity follows locally and cannot
   be lost by the marking's imprecision (§4 I3).
2. **An unrestricted value used once.** Already used: the marking accepts
   `near/`'s `xs` (§3.3). The specification of the marking should say
   "killed by a second use on a path", not "by an ω binding" (§1.10).
3. **A linear value's last use is its only use** before counting (5.7's
   static single use). Counting's reverse walk keeps no live state for a
   linear value: its drop, if any, follows its one use when that use
   borrows. A compile-time saving (D10's compiler half); measured by the
   walk's live-set size on stage 1 split by quantity.
4. **A linear value is never duplicated**: `idr.dup`'s operand at quantity
   many (§4 I2). Measured: 68 `idr.dup` lines in `tests/` and
   `foreign/`, none of a quantity-one operand but one negative fixture
   refused for another reason (`tests/verify-widths/verify-widths.mlir:70`)
   (*measured*: `grep -rhE 'idr\.dup ' tests foreign | wc -l`, and the
   same filtered by `!idr\.(lin|q<one)`).
5. **A type unique by construction.** `LArray` is "born fresh
   (`withArray`, or `thaw`, which copies unless its argument is dead) and
   leaves only by `freeze`" (`proposals/0009-typed-apl/README.md:250-258`;
   `Array/Core.idr:221, 226`): "The library supplies the past". 0007 then
   relies on it ("an `LArray` is exclusive by type and moves",
   `0007:448-449`), and D43 hands fields to One-Shot through `to_tensor
   restrict`, which asserts no alias. On the closed program this is
   checkable: every producer of the type gives its result to a quantity-1
   binder of a continuation; then every value of the type is `excl` with
   no marking, and a `restrict` on it is proved, not trusted. A trusted
   library's claim becomes a checked fact (lane 12's to build).
6. **A result's exclusivity.** Idris grades no result, so "fresh" is lost
   at every return and re-derived by the caller's marking. A result that
   is a fresh cell on every returning path, or the consumed exclusive
   argument (an io_uring completion, a Rust owned result, `reverse`), is
   a signature fact derived bottom-up over SCCs as rows are (§4 I3, I9).
7. **Exclusivity reaching LLVM**: `noalias` on an exclusive cell
   parameter; contents loads marked invariant between rebirths (§4 I6).

### 3.6 Representations that make a misuse of a quantity unwritable

- A quantity-0 binder given a runtime value: `Position = Absent | Runtime
  Quantity ...` (17 C2) and `Quantity = One | Many`.
- A `Term` binder of quantity 1 used twice: substitution that respects
  quantities (§4 I1); then a use count in Emit has nothing to count.
- A grade the frontend may not write: the generated view admits
  `!idr.lin<T>` and the bare type only (17 C4, 14 G03).
- A linear value duplicated: `idr.dup` at quantity many (§4 I2).
- A pass dropping a grade: one clone-and-key template (§4 I7).
- An obligation deleted: the specification's law that an op discharging a
  quantity-1 obligation carries an effect that keeps it (`join` runs
  unknown code; a Rust destructor writes `IO`); the IR's linearity stays
  affine, stated as such.
- A view outliving its lifetime: D40's outlives rule over `idr.lifetime`.
- A borrower outliving a lend: the lend is a lifetime region whose end
  joins (§4 I8).

### 3.7 Richer grades: what they would buy

- **Affine.** The IR already verifies affinely (§1.1 row 6). A source
  affine quantity would be a language Idris does not have (D12).
- **Borrowing as a grade.** Idris has no borrow syntax (C1: "Users declare
  nothing"); the IR's permission `borrow` and D39's lifetime carry it,
  inferred. A borrow quantity in the semiring (Granule-style) would
  restate them.
- **Fractional uniqueness** (`sources/papers/marshall-2024-fractional-uniqueness`,
  README only): 0007's `lent` is its one use case, and D39 makes it a
  lifetime (§4 I8).
- **A semiring of lifetimes.** D40's lifetimes are an order with
  variables, checked by substitution; no case in the tree composes them
  multiplicatively.
- **Polymorphic quantities** (Brady's future work, `conclusion.tex:186-192`):
  a monomorphic, closed program instantiates every quantity, so nothing to
  carry after the frontend.
- **What does pay**: the grade as one algebra in the Idris specification
  (the quantity semiring {1, ω} with product as `fieldType` uses it, the
  permission lattice, the lifetime order), its laws proven there and
  generated as `consteval` tables (D16). Owner question 4.

## 4. Improvements

**I1. Substitution respects quantities; Emit reads quantities and never
counts them.** *Coordinator* (AGENTS.md: no pass drops what Idris proved;
convergent with L16 I4, which owns the frontend's code).
- *Evidence*: `Emit/Bodies.idr:56, 139-146`; `Emit/Declarations.idr:44-45`
  (signature linear, body plain); `Demand.cpp:70` reads the signature;
  17 FB-28; `assert_linear = believe_me id` lets trusted code pass a linear
  value to an unrestricted function (`third_party/Idris2/libs/prelude/Builtin.idr:196-199`).
- *Counterexample* (latent): a trusted library function with a quantity-1
  `LList` parameter whose body passes it through `assert_linear` to an
  unrestricted function the frontend beta-reduces, then takes the list
  apart and builds an `LList`. Emit keeps `!idr.lin<!L>` in the signature
  and `lin.use`s it at entry; D24's rule makes the parameter `(1, excl)`;
  placement needs a `dup` for the second use, which D24 forbids: an
  internal error on a program the frontend accepted. Latent: no `in_place`
  library uses `assert_linear` (*measured*: `grep -rln assert_linear libs
  third_party/Idris2/libs/base third_party/Idris2/libs/prelude` finds only
  its definition).
- *Root cause*: a `Term` binder's quantity is copied from Idris onto terms
  the translation rewrote, where Idris's proof no longer applies.
- *Correction*: QTT's substitution rule, applied where the translation
  substitutes: substituting a variable of quantity 1 for a binder of
  quantity ω scales its use to ω, so the translation let-binds it once
  through the one demotion (`let y = lin.use x`) instead of substituting;
  an alias of a linear variable is a `lin.use` binding at ω. Then no `Term`
  binder of quantity 1 is used twice, a parameter keeps its Pi binder's
  quantity, and D24's subject is a match whose scrutinee is the linear
  parameter itself. Answers 17 Q-FB2: an internal error, unreachable.
- *Deletes*: `mostUses` and helpers, `heldAs`, `holdFor`
  (`Emit/Bodies.idr:48-146`), the hold in `Declarations.idr:45`.
- *Discriminated by*: a test with a trusted fixture over an `LList`
  parameter through `assert_linear`: the IR's parameter stays linear, its
  body holds one `lin.use`, D24 does not bind the `lin.use` result, and the
  program compiles; `quantities-kept`, keyed by binder, shows no demotion
  on the suite.

**I2. A `dup` takes a view at quantity many.** *Coordinator* (5.10 M5;
evidence settles it).
- *Evidence*: `Idr_ViewType` is "holds no reference and is counted"
  (`IdrOwnershipOps.td:57-58`), `idr.dup`'s operand (`:74`); `view()` keeps
  the quantity (`Grades.cpp:85-91`, 01 §2.2), so `(1, borrow)` is
  constructible; `idr.borrow` is not a use (`Linearity.cpp:115-117`).
  No fixture dups a quantity-one value (§3.5 item 4).
- *Counterexample*:
  ```mlir
  %v = idr.borrow %x : !idr.q<1, own, !idr.box<!L>>   // not a use
  %d = idr.dup %v : !idr.q<1, borrow, !idr.box<!L>>   // verifies today
  ```
  `%x` and `%d` are two owned, linear references to one cell, each used
  once: the linearity rule passes, and a value Idris proved used once is
  shared; if `%x` was `excl`, its type now lies and an in-place rebuild
  through it is seen through `%d`.
- *Root cause*: the operand constraint reads the permission and ignores
  the quantity.
- *Correction*: `idr.dup`'s operand is a counted view at quantity many,
  declared in the specification (D16).
- *Deletes*: nothing in code; the state.
- *Discriminated by*: the constraint refuses the IR above (a negative
  verifier fixture); the program suite unchanged (*measured* above: no
  fixture uses the state).

**I3. Exclusivity is a type rule where QTT already proves it.**
*Coordinator* (lane 08 owns the analysis; AGENTS.md: acceptance is a
property of the program).
- *Evidence*: the marking is whole-program (`DenseMap<Value, Sharing>`,
  08 `audits/p0/08-counting.md:497` citing `Ownership.h:304`);
  §8's suspected bug: "a crash case counts as an unknown predecessor, so
  every live crash case shares all its match's results"
  (`ExclusivityGraph.cpp:208-222`; L08 confirms, `L08-exclusivity.md:145,
  315`); 5.10 M5 (exclusive at birth, kept through moves and quantity-1
  binders).
- *Counterexample*:
  ```idris
  mk : Int -> LList (!* Int)
  mk n = if n < 0 then idris_crash "negative" else [MkBang n]
  step : LList (!* Int) -@ LList (!* Int)   -- rebuilds in place
  main = ... step (mk k) ...
  ```
  `mk`'s result is fresh on its one returning path and goes straight into
  a linear position, used nowhere else; the crash case marks the match's
  result shared, and D24 refuses `step (mk k)`: acceptance decided by the
  analysis's imprecision.
- *Root cause*: a fact QTT and freshness give locally (exclusive at birth,
  no second use at quantity 1) is recomputed by a global marking, and a
  result's freshness is dropped at every return.
- *Correction*: one rule, two halves. (a) Inside a function: a value is
  `excl` when it is fresh (a constructor, a recycled cell, or a call result
  whose signature says exclusive) or taken from an `excl` value at a
  linear position, and it flows only through linear positions to its use;
  the verifier checks the rule; the marking's domain is the rest (ω values
  and `lin.enter` of values not shown exclusive). (b) A result's
  exclusivity is in the function type, derived bottom-up over SCCs as rows
  are (D22) and verified per function: exclusive when every returning path
  returns a fresh value or an `excl` argument it consumed. A crash path
  returns nothing, so it contributes nothing.
- *Deletes*: the marking's nodes for linear chains; "gives back argument
  i" solved twice (05 §2.2, R5) where (b) holds it.
- *Discriminated by*: the program above is accepted, with the crash-case
  bug left in place; a type: a linear value from an `excl` source at a
  linear position cannot be typed shared by the marking (the verifier
  refuses the regrade); measured: the marking's node count on stage 1,
  split by quantity, before and after.

**I4. A run-time value equal to an index carries the index in its
type.** *Coordinator* (structural incompleteness of D48's binder; lane 04
owns the representation).
- *Evidence*: §1.6 row 2 (`Vect.idr:237-239`, `Linear/Vec.idr:38-40`,
  `Iterator.idr:74`); D48's index language makes
  "anything richer an opaque term, sound and refining nothing"; Dependent
  ML links run-time integers to static indices by singleton types for
  bound-check elimination (`sources/papers/xi-1998-dml-bounds`; the
  mechanism *recalled*, the PDF not read here).
- *Counterexample*: `replicate Z _ = []` at type `Vect len elem`, `len`
  a run-time `Nat`. A match on the run-time `%len` refines nothing about
  the index `len` (it has no binder), so the `Z` arm's `Nil :
  #Vect[len]` needs `len = 0`, which the verifier cannot see: it refuses
  its own frontend's output (an internal error) or the type is weakened to
  opaque, losing `#Vect[3]`'s layout at `replicate 3 x` and the bound
  `index (FS (FS FZ))` needs.
- *Root cause*: D48 binds indices only by quantity-0 parameters; an index
  that is the value of a run-time parameter or field has no binder.
- *Correction*: a run-time natural equal to an index has the index in its
  type (`!idr.nat<n>`; the unindexed `!idr.nat` stays the natural of
  unknown index): a dependent run-time parameter is that operand plus an
  index variable in the function's index binder; a field equal to its
  family's index (`MkVec`'s `n`) is typed by it; a match on such a value
  refines its index (`0` in one arm, `m + 1` with the predecessor at
  `!idr.nat<m>` in the other). The equation is Idris's proof, never checked
  again at run time (D10).
- *Deletes*: the bound checks the types prove where a `Fin n` meets a
  `!idr.nat<n>` (0018's seam); the opaque fallback for these cases.
- *Discriminated by*: `Data.Vect.replicate` and `Linear.Vec` translate
  with typed results and verify; a property test that `index` on
  `replicate 3 x` with a constant `Fin` compiles with no bound check.

**I5. The lifetime is quantity 0; the arena is a run-time operand.**
*Coordinator* (D39 and D48 both hold of different things; convergent with
L05, which owns the representation, `L05-lifetimes.md:74-82`).
- *Evidence*: D39 ("a scope parameter is a handle at run time"); D48
  ("passed at calls at compile time only").
- *Counterexample*: `idr.func @lookup<ρ>(%t : !idr.q<many, borrow, !T, ρ>)
  -> !idr.q<many, borrow, !V, ρ>` only views; `idr.func @build<ρ>(...) ->
  !idr.q<1, own, !L, ρ>` bump-allocates into ρ. If the lifetime is a
  run-time handle, `lookup` passes a dead register on every call (a static
  fact paid at run time, D10); if it is compile time only, `build` has no
  arena to allocate into.
- *Root cause*: one binder for two facts.
- *Correction*: the lifetime variable stays a quantity-0 parameter (D48);
  a function that allocates into ρ takes an arena operand typed by ρ,
  inferred with the lifetimes; the operand is owned by the `idr.lifetime`
  that binds ρ and lent to allocations, and a move of the lifetime to
  another shard consumes it (§1.5 row 4).
- *Deletes*: nothing existing.
- *Discriminated by*: the verifier refuses an allocation into ρ with no
  arena of ρ in scope; a test that `lookup`'s lowered signature has no
  extra parameter.

**I6. What exclusivity proves reaches LLVM.** *Coordinator* (AGENTS.md:
"What the compiler knows of effects reaches LLVM", and D10's spirit for
what types prove; the conversion lane owns the code).
- *Evidence*: `Conversion/Facts.cpp:22-55` writes `nonnull`, `align`,
  `dereferenceable` and a tag's `range` only; `noalias` appears only on a
  fresh array (`Arrays.cpp:41-45`) and the result slot
  (`PassThroughMemory.cpp:50-52`); no load carries invariance (*measured*:
  `grep -rn 'invariant' foreign/idr/lib/Conversion` finds none). LLVM's
  `invariant.group`: "every load and store to the same pointer operand can
  be assumed to load or store the same value", with
  `llvm.launder.invariant.group` for a pointer whose contents change
  (`.toolchain/llvm-project/llvm/docs/LangRef.md:8818-8828`, *read*;
  marked experimental there); MLIR's `llvm.load` has `invariantGroup`
  (`.toolchain/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:391-392`).
- *Counterexample*: a loop rebuilding an exclusive list in place while
  reading a field of a borrowed second list: after each store into the
  exclusive cell, LLVM must reload the borrowed field, since the two
  pointers may alias. A load per iteration the types rule out.
- *Root cause*: the grade is erased at the lowering with nothing told.
- *Correction*: `noalias` on every exclusive cell parameter (its cell graph
  is reachable through it alone); field loads of a cell's contents carry
  `invariant.group`, and every write of contents in place (a recycle, an
  exclusive update) goes through a laundered pointer. Counts stay outside
  (the header is not a field).
- *Deletes*: nothing.
- *Discriminated by*: a property check over the lowered module (every
  `excl` cell parameter is `noalias`; every contents store after a
  recycle uses a laundered pointer); a measured loop in `bench/`.

**I7. Grades are kept by construction.** *Coordinator* (AGENTS.md;
lanes 18 and 19 own the template and the contract).
- *Evidence*: §1.1 row 4: the per-pass restatements
  (`Declare.cpp:39-42`, `Patterns.cpp:43-45`, `Keys.cpp:218-222`); the
  contract keyed by location (17 FB-31).
- *Counterexample*: a pass that clones a function and writes its block
  argument as `!L` where the original had `!idr.lin<!L>`: the linearity
  rule passes (nothing linear to count), the program verifier passes, and
  Borrows' fixed-owned case and D24's rule no longer see the parameter;
  only a test catches it, and only if the keys do not collide.
- *Root cause*: each pass that builds a signature re-derives its grades.
- *Correction*: every function clone or retype goes through the one
  clone-and-key template (G DP-55's), which copies each parameter's grade
  from the original by construction and changes a grade only through
  `lin.enter`/`lin.use` in the body; `quantities-kept` keys binders by
  identity.
- *Deletes*: the restatements above.
- *Discriminated by*: a test that runs the pipeline on a module of linear
  parameters and compares every function's parameter grades with the
  emitted module, keyed by binder.

**I8. A lend is a lifetime region whose end joins its borrowers; `lent`
is a borrow at that lifetime.** *Coordinator*, for when 0007 is taken
(added to C2's stale list; AGENTS.md: correctness never rests on
linearity).
- *Evidence*: §1.8 rows 1 and 2; `0007:272-281` (`lent`), `:385-389`;
  `PrimIO.idr:41`; `protocols.tex:13-17`; 0007 already rejects a
  spawn/await pair because "a dropped handle is work the body never
  evaluates, which only a linear type would forbid" (`0007:801-803`).
- *Counterexample*:
  ```idris
  lend big $ \l => do
    j <- forkL 1 (work l)   -- Join' l n s r: an unrestricted result
    pure ()                  -- j dropped, never joined
  ```
  Idris accepts it; `lend` returns, the lent value's last reference dies
  on shard 0, and shard 1 still reads it.
- *Root cause*: the safety rests on a linearity QTT does not give a
  monadic result.
- *Correction*: the lend is an `idr.lifetime` region (D39, D40); a task
  forked inside it holding a value at its lifetime is joined at the
  region's end (the outlives rule, made structural), whether or not the
  program joined it; the lent value is a `borrow` at that lifetime, and a
  value leaving the lifetime is the copy the lifetime check requires
  (0007's "deep copy at a `dup` at `lent`"). `fork`'s "every fork is
  joined" is restated as `runShards`' end join (D5).
- *Deletes*: the `lent` permission; the two "linear join" claims.
- *Discriminated by*: the verifier refuses a fork holding a view at ρ
  outside ρ's region; a test where a borrower's dropped join still runs
  the borrower to its end before `lend`'s continuation's output.

**I9. A buffer in flight is exclusive, `counted`, and returned
exclusive.** *Coordinator* (C2 R1's correction).
- *Evidence*: §1.7 row 2; 0007's cancel path (`0007:130-140`); R1's
  recalled io_uring fact (`effect-vocabulary.md:813-816`).
- *Counterexample*: `recv : (1 buf : Buffer) -> Shard n s (Int, Buffer)`.
  The completion "returns" the buffer, so a pass reading the op as giving
  its operand back may leave the cell local: the stack inference frames it
  (in a coroutine, the frame lives in the task frame), or a D39 lifetime
  puts it in the task's scope. A cancel destroys the frame or ends the
  scope and frees the cell while the kernel writes into it until the
  cancelled request completes.
- *Root cause*: R1 states ownership but not the lifetime, and the result's
  exclusivity is left to the caller's marking.
- *Correction*: the submit's operand type is `(1, excl)` at lifetime
  `counted` (never `frame`, never a variable), so neither the stack
  inference nor lifetime allocation can take it; the completion's result
  is the consumed buffer, exclusive, in the op's signature (I3 (b)); a
  zero-copy send takes an owned reference or a `static` view; a registered
  buffer slot is a linear token of the ring's lifetime.
- *Deletes*: nothing existing.
- *Discriminated by*: the verifier refuses a framed or scoped buffer at a
  submit; a test cancelling a task mid-receive at one shard with zero live
  cells after the completion.

**I10. A frame stack's top is a linear value of the computation.**
*Coordinator* (lane 10 owns D31's representation; this is 0007's stress).
- *Evidence*: D31 (one typed stack per result type, linear, uncounted)
  does not say where a stack's top lives; D32 puts every recursion on a
  cycle on those stacks; 0007's frames are LLVM coroutines that spill
  only SSA values live at the suspend (`0007:118-145`).
- *Counterexample*: two tasks on one shard, each in a non-tail recursion
  on a call cycle, each waiting mid-recursion. With a per-thread top, A
  pushes F1 and F2 and waits, B pushes G1 and waits, A resumes and pops
  G1: B's frame, of the same result type, runs A's continuation.
- *Root cause*: a stack shared by computations that interleave.
- *Correction*: each stack's top is a linear-by-type SSA value threaded
  through the functions on cycles (D31's "linear" made literal), so a
  coroutine split spills it into the task frame as any live value; each
  task has its own chunks; a suspended task's chunks are its active frames
  (D26).
- *Deletes*: any thread-local top.
- *Discriminated by*: the type (a function on a cycle without its top
  does not verify); a test interleaving two waiting recursions on one
  shard whose output equals the sequential runs'.

**I11. A foreign call writes `exit`; a callback handed to it carries no
`wait`.** *Coordinator* (C2 R3, R4; lane 02 owns rows).
- *Evidence*: `0020:747-754` (a crate ends the process); D14 ("a function
  that may exit is never lowered `willreturn`"); §1.4 row 4.
- *Counterexample*: a callback that reads a socket on its shard (it
  waits), passed to a Rust iterator's `for_each`: the coroutine suspends
  with Rust's frames on the native stack, and resumes over whatever the
  reactor ran in between.
- *Root cause*: rows and the callback's type do not say what a foreign
  frame forbids.
- *Correction*: specification rules: `idr.rust.call`'s row carries `io`,
  `exit`, `crash`, `divergence`; its callback operands' function types
  carry no `wait` (R3 puts it in the type), so the op's verifier refuses
  one and the frontend reports `unsupported` naming the callback.
- *Deletes*: nothing.
- *Discriminated by*: a reject fixture (a waiting callback); the row
  derivation's test reads `exit` on a function that calls Rust.

The three most important: **I1** (D24's rule must read a quantity proved
of the body), **I8** (memory safety in 0007 rests on a linearity QTT does
not give), **I4** (D48's binder misses Idris's indices bound by run-time
values).

## 5. Work units

Drafts; none dispatched by this swarm. Paths under `compiler/spec/` are
the specification's planned home (C7).

| unit | exclusive write set | outcome | deletes | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| Q1 substitution and Emit (I1; with L16's U6) | `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`, `compiler/src/IdrisMLIR/Emit/Bodies.idr`, `Emit/Declarations.idr`, `Emit/Monad.idr`, `Emit/Operations.idr` | substitution scales a variable's use by the binder's quantity and let-binds through `lin.use`; Emit reads a `Held` sum | `mostUses`, `heldAs`, `holdFor`, the two `Bool` compares | demote a parameter; count uses in Emit | suite unchanged; the `assert_linear` fixture of I1 compiles with one `lin.use`; no demotion by `quantities-kept` keyed by binder |
| Q2 grade algebra and `dup` (I2; owner question 4 (a)) | `compiler/spec/IdrisMLIR/Spec/Grades.idr`, `compiler/spec/IdrisMLIR/Spec/Ops/Ownership.idr` (planned), their generated outputs under `foreign/idr/include/idr/IR/` | the grade as product of the quantity semiring, permission lattice and lifetime order, laws proven; `idr.dup` at quantity many | `struct Grade`, `times`' switch (01 C1, T36) | add a quantity | generated `static_assert`s of the laws; a negative verifier fixture for a linear `dup` |
| Q3 exclusivity by provenance (I3) | `foreign/idr/lib/Analysis/Ownership/Exclusivity.cpp`, `ExclusivityGraph.cpp`, `ExclusivityAnalyses.cpp`, `foreign/idr/include/idr/Analysis/Ownership.h`, `foreign/idr/lib/IR/Verify/Owned.cpp` | the local rule and result exclusivity in signatures | the marking's linear nodes; the second "gives back" solve | make a refusal depend on the marking where the rule decides | I3's program accepted with the crash-case bug unfixed; node count recorded |
| Q4 indexed naturals (I4; lane 04) | the family types in the specification (planned); `compiler/src/IdrisMLIR/Frontend/Translate/Types.idr`, `Translate/Terms.idr`; the family verifier | dependent run-time parameters and fields typed by their index | opaque fallbacks for these cases | check the equation at run time | `replicate` and `Linear.Vec` verify typed; no bound check on `index` at a constant `Fin` |
| Q5 lifetime and arena (I5; lane 05) | the lifetime types in the specification (planned); the lifetime inference pass (planned) | erased lifetime parameters; arena operands where a function allocates | — | pass an arena to a views-only function | the verifier refuses allocation without an arena; `lookup`'s signature has none |
| Q6 grades to LLVM (I6) | `foreign/idr/lib/Conversion/Facts.cpp`, `Conversion/Fields.cpp`, `Conversion/Cells.cpp` | `noalias` on exclusive cells; invariant contents loads; laundered in-place writes | — | mark the header's count | suite unchanged; the lowered-module property; a measured loop |
| Q7 grades kept (I7; lanes 18, 19) | `foreign/idr/lib/Transforms/Specialize/Patterns.cpp`, `Specialize/Keys.cpp`, `Defunctionalize/Declare.cpp`, `Defunctionalize/Converter.cpp`, `foreign/idr/lib/Transforms/Expect/Quantities.cpp` | one clone-and-key template copies grades; the contract keyed by binder | the per-pass restatements | retype a parameter by hand | the pipeline-wide grade comparison test |
| Q8 proposals' stale text (I8 to I11; C2) | `proposals/0007-shards.md`, `proposals/0020-rust-interop.md` (the coordinator's) | the lend region and its join; in-flight buffers' type; frame-stack tops per task; foreign rows; statics' borrow state static; the owner's answers to questions 1 to 3 | `lent`; the linear-join claims; the world | build 0007 or 0020 | the texts agree with D20, D39, D40, C2 and the answers |

## 6. Owner questions

**1. How much native stack does a Rust call get, and may a recursion pass
through a Rust callback?** (D30's and D32's open part for 0020.) Rust's
frames cannot move to D31's stacks, so D32's bound cannot cover them, and
a cycle through a callback grows the native stack on every turn (§1.4).
- (a) *Bound everything or refuse*: extend D32's computed bound over Rust
  code from LLVM's frame sizes in the one joined module; refuse a Rust
  recursion, an unresolved indirect call and a cycle through a callback.
  Keeps every promise; refuses most real crates (recursive-descent
  parsers, serde-style visitors: *conjecture*).
- (b) *The host's stack for foreign code; no cycle through it*: a program
  that reaches Rust reserves, beside D32's bound, the host's stack limit
  (`RLIMIT_STACK`, read as D36 reads the memory limit; address space only,
  committed as used, so D35 holds); D30 and D32 stay promises of compiled
  Idris code; a call cycle through a Rust callback is refused, decided on
  the label sets frozen before the optimizer (0007 §7.3's precedent);
  exhausting the foreign stack is a new named ending, not an internal
  error. Costs address space per program that uses Rust and one ending row;
  buys real crates.
- (c) As (b), but cycles through callbacks allowed, each turn growing the
  native stack up to the host's limit. Buys callback-recursive visitors;
  costs D30's promise at every foreign boundary.
- *Recommendation*: (b).

**2. When does a foreign object's destructor run, relative to the
program's output?** (C2 R5; 0020's "right after its last use, in program
order", `0020:397-398`.) A drop that writes `IO` is ordered among IO, but
counting places it at the last use after optimization, and deleting a dead
total use (D13 allows it) moves a `BufWriter`'s flush before output that
followed it in the source.
- (a) *The source program's last use*, fixed before optimization: the
  frontend places the release of a foreign-reaching value where the
  program as written last uses it, an op that writes `IO`, and counting
  honours it as D24's rule is honoured. Costs a liveness walk in the
  frontend for those values; buys output order that is the program's.
- (b) *Counting's last use* (C2 R5 as written). Costs: output order chosen
  by the optimizer, against AGENTS.md's rule that the meaning is the
  program's.
- (c) *The end of the binder's scope* (Rust's own rule). Costs: holds
  objects longer than 0020 promises, and a value stored in data has no
  lexical scope.
- *Recommendation*: (a).

**3. Is a by-value move of a Rust object decided at compile time, as D24
decides the in-place promise?** (`0020:415-417, 684-688`.)
- (a) *D24's rule*: a quantity-1 by-value object parameter is subject;
  exclusivity at the call is proved before the optimizer or the call is
  `unsupported (uniqueness)`; no run-time uniqueness test for moves. Costs:
  a program whose handle is shared statically but unique dynamically is
  refused; buys one rule shape, no crash on a decidable fact, a test
  deleted per move.
- (b) *0020 as written*: tested at run time, a crash naming the call when
  shared, the test folded where `excl`. Costs a test and a crash path per
  unproved move.
- Either way, an exclusive or by-value use of a constant or static object
  is a statically certain crash (D13), with no state read.
- *Recommendation*: (a).

**4. Does the IR carry a grade richer than Idris's quantities?** (§3.7.)
- (a) *No*: the grade is Idris's quantity (1, ω; 0 is absence) × the
  compiler's permission × the lifetime, specified in Idris as one algebra
  with its laws proven (unit Q2). Costs nothing new.
- (b) *Inferred bounded or affine quantities in the IR* (Granule-style), to
  carry the use counts the marking computes. Restates what permission and
  the marking already hold; nothing in the source can write them (D12).
- (c) *Fractional permissions* for lending. Its one case is a lifetime
  (I8).
- *Recommendation*: (a).
