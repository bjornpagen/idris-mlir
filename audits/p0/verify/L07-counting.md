<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 verification, lane L07: counting (placement, reuse, drop specialization, the space promise)

Rulings and decisions in scope: D26, C1, D24, D34, D19 (tokens as join
arguments), D10; D48 where it types the token.

- **HEAD** at start `e96bb991` (2026-10-21T21:31Z); at finish `e96bb991`.
  `origin/main` is four commits past HEAD (101edbc5's `Positions` and its
  fixes, 0be4e660, 1e1907ab); everything below is read at HEAD, and where
  `Positions` would change a deletion it is said.
- **Marks.** *read* (path:line at HEAD; paths are under `foreign/idr/`
  unless they start at the root), *measured* (the command given),
  *recalled*, *conjecture*, *decision* (a ruling Dn or decision Cn).
- **"The TR"** is Lorenzen and Leijen, "Reference Counting with Frame
  Limited Reuse", MSR-TR-2021-30 v2 (the ICFP 2022 paper's report), read
  as text from the copy lane 5.10 fetched (`/tmp/rc-lane-dl/flreuse-tr.pdf`;
  `sources/INDEX.md:116` lists the paper as link-only, so it is not under
  `sources/`). Page numbers are the TR's.
- Nothing was built or run. No file but this one was written.

## 1. Verification

Classes of observation: **D** a defect confirmed in the source; **S**
structural incompleteness; **I** an integration mismatch; **U** unverified
behaviour; **O** an optional simplification.

### 1.1 D26, the space promise

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D26.1 | Garbage-free is out because no reuse can keep it | holds | — | *read* TR §4, p.8: "since reuse analysis keeps heap cells alive until they can be reused, it means that no reuse analysis can preserve the garbage-free property"; TR p.2 says the same of borrowing ("Transformations like reuse and borrowing no longer have the garbage-free property"), and §4.2, p.9, that unrestricted borrow inference is not frame-limited |
| D26.2 | The promise: at every allocation each heap cell is reachable from what the program will use, or held by an active call, each call holding at most a fixed number of bytes it no longer needs | holds; it is the TR's Definition 3 restated per call | — | *read* TR Def. 3, p.15: at every allocation step `Hi \| E[v]`, `Hi = H1, H2` with `H1` reachable and `\|H2\| ≤ c·\|E\|`. The TR's `E ::= □ \| E x \| let x = E in e` (Fig. 5, p.12) does not grow at a tail application, so `\|E\|` counts pending non-tail work: our native frames, our heap frames (D31) and the pending `let`s inside one frame, whose number per function is static. A bound per active call (D26) is therefore the TR's bound up to a constant, and the one that fits a compiler with proper tail calls (D30) |
| D26.3 | A call may hold reuse tokens of statically sized cells | holds | — | *read*: a token comes only from `idr.take` of a constructor's cell (`include/idr/IR/IdrOwnershipOps.td:304-327`); its size is a constant of the target's layout (`lib/Analysis/Ownership/Reuses.cpp:192`) |
| D26.4 | A call may hold the shells of its stack cells, whose fields are released at count 0 | holds | — | *read*: one slot per op in the entry block (`lib/Conversion/Cells.cpp:84-102`); at count 0 the slots are released and the memory kept (`runtime/Rc/Freeing.cpp:127-135`); a cell of a loop iteration is dead before its slot is written again, since no frame value is forwarded into the next iteration (`include/idr/IR/Lifetimes.h:11-26`, the `Repeated` escape) |
| D26.5 | A call may hold values borrowed past their last use whose type bounds everything they reach | holds as a rule | S | *read*: no type fact says "bounds everything it reaches": `ValueFactsTypeInterface` (`include/idr/IR/IdrInterfaces.td:24` on) has none, and nothing computes one. §2.10 defines it (`reach(T)`); it is a type fact computed when the type is made (seam with L04) |
| D26.6 | Never a dead dynamically sized cell held past an allocation | holds for tokens and stack cells; refuted for today's borrows | D | *read*: no token for an array, a string or a big (D26.3); stack cells are constructor cells of at most 256 bytes (`lib/Transforms/Stack/Stack.cpp:78`). But today's borrow inference is unrestricted: a parameter is owned only for named reasons, never because the caller's last use is the call (`lib/Analysis/Ownership/Borrows.cpp:3-26`), so a string or an array passed to a borrowed parameter as its last use is held across every allocation the callee makes. C1's rule removes it; §1.2 C1.7 corrects C1 |
| D26.7 | Never a borrowed argument whose last use is the call unless its type bounds what it reaches; so an argument whose caller binder is linear is passed owned, read off its type | holds by QTT, with one integration gap | I | *read*: Idris lets a quantity-1 name fill only a quantity-1 parameter, and a quantity-1 parameter is owned (`Borrows.cpp:22-25`). The gap: `idr.lin.use` turns a linear value into a plain one at its one use (`IdrOwnershipOps.td:415-424`), and nothing ties the plain value to "dead after this call". §3 and I6: the borrow marking reads an argument made by `lin.use` as dead at the call, with no liveness |
| D26.8 | Never any structure held past its last use | holds for field views and for regions that run many times; refuted in two places of today's code and one of the design | D | holds: a field takes its own reference when its root dies first (`lib/Transforms/Ownership/Placement.cpp:24-29`); a value used inside a loop is needed by its later runs. Refuted: (a) a region that ends in a crash gets no drop of the values from outside it (`Placement.cpp:201`; `lib/Transforms/Ownership/Reshape.cpp:83, 97, 104, 280`), so a crash path that allocates (a message built at run time) holds every one of them at those allocations, without bound (I5, Q1); (b) unrestricted borrows (D26.6); (c) `design/match-and-counting.md` §7 makes a join parameter borrowed whenever "the join op's scope owns and drops after the op" the value passed, which holds a whole list while a loop walks its suffix (I1) |
| D26.9 | Outside: allocator overhead and spare room in a live cell; persistent static data; a saturated count | holds | — | *read* `runtime/Rc/Rc.h:21, 44-45` (saturated, persistent); `Freeing.cpp:166-189` (`persistHeld`: what static data reaches becomes persistent) |
| D26.10 | Not carried over: the cycle-free qualifier; thread-shared counts; the run-time uniqueness test as part of space; the lambda rule; an uncomputed constant; safety for space; an abstract evaluation context | holds | — | cycles: arrays are the only cells that can close a knot and `idr-knots` refuses every such type graph (*read* `include/idr/Transforms/Passes.td:193-204`, which argues why a memo cell closes none). Threads: no atomic in `runtime/Rc/` (lane 08's *measured* grep). The uniqueness test: both arms of a take keep exactly what dup-then-drop would (`lib/Conversion/Counting.cpp:91-107`). Lambda: closures are constructors after defunctionalization, so the TR's `[lam]` is our `[con]`. Constant: D48 makes every cell layout static (§2.6) |
| D26.11 | Each call's bound is computed by the compiler for each function from its types | holds as a ruling; nothing computes it | S | §2.10 gives the computation from three facts the passes already produce |
| D26.12 | The order of counting and the extent of borrowing follow | holds | — | *decision* C1; corrected in §1.2 |

### 1.2 C1, counting's order and borrows

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| C1.1 | The reverse walk places drops at last use | holds as the target | S | today placement plans each value forward along its block with per-region use scans (`Placement.cpp:8-9, 184-236`); §2.2 states the walk |
| C1.2 | A forward walk per function, a map from layout to available tokens, intersected at rejoins | holds with four corrections | S | (i) a token defined in a region reaches the code after the match only as a match result, so "intersected" is the least count per layout over the regions that rejoin, given back as results (the match is rebuilt with results through `MatchOpInterface::rebuild`, *read* `IdrInterfaces.td:164-170`); (ii) a region that ends the process or jumps is no predecessor of the rejoin and takes no part in the least count; (iii) a token beyond what any path ahead can use is freed where that becomes true (at a region's head, or where the region stops allocating its layout), or it is held for nothing; (iv) no outer token enters a region that runs any number of times. §2.4 |
| C1.3 | Turns a drop whose cell a later construction fits into `cell.recycle` | holds; wording | — | the drop becomes a take (which gives the token) and the construction's `cell.new` becomes `cell.recycle` of it (TR §3.2, p.7: "rewrite the drop to a dropru") |
| C1.4 | The token passed on as a join argument across a rejoin | holds as corrected by `match-and-counting.md` §2 | — | across a match's own rejoin the token is a match result; join arguments carry it to a shared continuation (*read* `match-and-counting.md:109-131`) |
| C1.5 | D24 is read before placement and makes its rebuild an obligation of this walk | holds; needs a choice rule | S | when several tokens of one layout are available, the walk must give the promised rebuild the promised parameter's token, or a run-time null test lands on a promised rebuild (§2.4, choice order) |
| C1.6 | A token of a dynamically sized cell is used before the next allocation or freed | refuted as a rule; replaced by a representation | I | no such token exists, and none should: a token's type names a constructor's cell, whose layout D48 makes static, so the type cannot name a dynamic cell; dynamic cells are reused only as the destination of the op that consumes them (§2.7, I4) |
| C1.7 | A parameter is borrowed only when at every call the caller uses the argument afterwards or its type bounds everything it reaches, and the callee neither consumes nor stores it | refuted in part: too strict in one case, too weak in two | D, I | (a) too strict: an argument that is a view of the caller's own borrowed parameter is never "used afterwards" by the caller, yet its owner is used after the caller returns; read literally, C1 owns every parameter down a chain of borrows and costs an `inc` and a `dec` per call, the cost borrowing exists to remove. (b) too weak at a call in tail position (D30) and at a self call in tail position modulo a context (D34): a bounded borrow there needs a drop after the call, which is then no jump; today's code applies the rule only within a cycle (`Borrows.cpp:236-237`), and off a cycle placement puts the drop after the call (`Placement.cpp:226-233`). (c) silent on join parameters, which `match-and-counting.md` §7 borrows on a weaker rule (D26.8 (c)). I1 |
| C1.8 | A parameter D24 rebuilds is owned | holds | — | it is quantity 1, owned by type (`Borrows.cpp:22-25`) |
| C1.9 | A runtime function's conventions come from the Idris specification | holds as a decision | U | the specification does not exist yet (*decision* D16, C7); seam with L01, L03 |
| C1.10 | Users declare nothing; Idris has no borrow annotation | holds | — | *recalled*: Idris 2 has quantities, no borrow annotation |
| C1.11 | Reason: the TR proves drop-guided reuse frame-limited and Lean's order not; ours is Lean's order, with reuse predicted by the guess that any call takes its arguments over and simulated, the source of 9db9813d's 1088 errors | holds | — | *read* TR Thm. 5, p.16, and §3.1 example (B), p.6 (algorithm D "holds on to the full xs list during evaluation of f"); `Reuses.cpp:193-195` (the guess); `Reuses.cpp:57-65, 129-151, 183-191, 232-265` (the simulation); `git show 9db9813d` ("1088 take-on-borrow verifier errors"). Ours is Lean's *order*, not algorithm D: it predicts a death point and makes it true (lane 08 §3.1, M7 row) |
| C1.12 | Deleted: the predicted death points, the guess, the simulation, Borrows' reuse reason | holds | — | each has no reader once reuse follows placement: `whereDies` is read only by `Reuses.cpp` and `Reshape.cpp`, `onlyReads`, `decides`, `usedAfter` only by counting (*measured*: `grep -rln` of each name under `lib include tools`; `IR/Canon/Sink.cpp` and `MoveOut.cpp` have local functions of the same names). §1.8 |

### 1.3 D24, counting's half

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D24.1 | Reuse must recycle the rebuilt cell | holds for `LList` and `LNat`; must be stated for any later type | I | each has one constructor with a cell (*read* in lane 08 §4.10, which cites `compiler/src/IdrisMLIR/Registry/Recognized.idr:183-186`), so a rebuild is always the taken cell's layout. A later `in_place` type with cell constructors of two sizes would let the rule bind a rebuild no token fits (I13) |
| D24.2 | The stack inference may not take that parameter | holds; today's code breaks it | D | `Stack.cpp:344-353` writes parameters of the frame; `Reuses.cpp:158` never reuses a frame box: the chain of lane 08 NQ1, deleted by D24 |
| D24.3 | No placement may add a dup of it | holds once placement's domain is quantity ω | S | the parameter is quantity 1, so no placement may dup it; today placement classes values with no reading of quantity (`lib/Transforms/Ownership/Classes.cpp:39-87`), and `sinkConsumers` decides whether a dup appears (`Reshape.cpp:149-210`). §3 |
| D24.4 | A pass that would break the promise is a bug, not a refusal | holds | — | the walk's post-check (§2.4, R6) is an internal error |
| D24.5 | Deleted: `idr-demand` deriving the promise from `cell.recycle` and the take's token | holds | — | `lib/Transforms/Demand/Demand.cpp:56-77` |

### 1.4 D34, counting's half

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D34.1 | Counting honours the promise | holds with a correction | I | placement must place nothing between a self call in tail position modulo a context and the constructors of its context, and no borrowed parameter may receive at that call an owned value whose last use is the call. Today both hold only on a cycle (`Borrows.cpp:13-19, 236-237`); under D34 they hold at every such call, read from the call's one tail fact (D30) |
| D34.2 | On an exclusive value reuse rebuilds the cells in place | holds | U | the walk holds the scrutinee's token across the self call (one cell, within D26) and recycles it at the context's `cell.init`; idr-trmc then makes the cell first and passes the hole (TRMC finds its context on `cell.init`, lane 10 §3.1). That TRMC moves the recycle with the init is lane 10's to verify |

### 1.5 D19, tokens as join arguments

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D19.1 | A join point is jumped to with typed arguments, reuse tokens among them | holds | S | the walk decides each join region's token parameters (least count over its jumps, capped by what it can use) and their grade (`excl` when every jump passes an exclusive token there); §2.4 |
| D19.2 | `match-and-counting.md` §2: a token reaches the code after a match only as a match result, "all cases give one" | holds with a correction | — | the yielding cases give the least count of each layout; a case that ends the process or jumps gives none and does not lower the count |
| D19.3 | §7: a path with no token jumps to a copy specialized for "no token", never passing a null | holds as the D10 rule | O | a null token on a path where it is statically absent pays at run time what the compiler knew; specialization is under a code budget, whose spent case keeps the least count (frees the token on the richer path), never a null |
| D19.4 | §7: "at most one copy per key bit" | corrected | — | one copy per *key*, the vector of token counts and grades a jump passes: finite (at most 2^b for b key bits), so it ends by construction; the budget may stop it |
| D19.5 | §7: a join parameter is borrowed when every jump passes a view whose owner outlives the join op | refuted in part | D | under D26 the owner must be used after the op, or be a borrowed parameter of the function, or have a bounded type (I1 (c)) |
| D19.6 | §7, §12: the take's expansion puts the rest in a join region specialized by the token's presence | holds; improved | O | where the token is recycled on every path from the take, the expansion gives the cell itself (the old cell in the unique arm, a fresh one in the shared arm): no copy and no second test (I3) |

### 1.6 D10, the facts counting pays for

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D10.1 | Uniqueness is a C++ branch in two lowering patterns, not an op that folds | holds, and there is a third site | D | `Counting.cpp:91-107`, `Cells.cpp:123-127`; and `lib/Conversion/Elements.cpp:64-82` tests uniqueness at every take of a boxed element (line 75) with no static case at all, though an exclusive array's elements are exclusive too (exclusivity is "the only reference to every cell their cell graph reaches", `include/idr/Analysis/Ownership.h:260-263`) |
| D10.2 | An exclusive drop still reads the count | holds | D | `Counting.cpp:42-55` calls `Runtime::dec`, which reads `count` (`Rc.h:86-96`) |
| D10.3 | (new) A take of a frame value tests uniqueness at run time, always false | confirmed | D | takes are made of any owned scrutinee, frame or not (`Reshape.cpp:78`); `LowerTake` branches only on `isExclusive` (`Counting.cpp:91`); a stack cell is never exclusive (`Rc.h:50-53`, `Cells.cpp:76-83`). Lane 18 R-RC-3 covers the runtime's stack bit; this is the compile-time half |
| D10.4 | (new) A token's free tests three facts, two of them static | confirmed | D | `idris_rt_free_cell` tests NULL, "counted" and "not a stack cell" (`runtime/Rc/Counting.cpp:67-74`); a non-null token is the cell of a take that found it exclusive, and only a counted heap cell is exclusive (`Rc.h:50-53`), so only the NULL test carries information, and none for an exclusive token. `LowerDrop` chooses free or decrement by the operand's type (`Counting.cpp:47-49`): two meanings in one op |
| D10.5 | (new) A recycle re-tests what the take tested | confirmed | D | the take's run-time answer becomes a null-or-cell token (`Counting.cpp:93-107`) and the recycle tests it for null again (`Cells.cpp:128-140`) |
| D10.6 | (new) An array element update frees the old boxed element's cell and allocates one of the same layout | confirmed | D | `LowerUpdate` calls `takeElement` (`lib/Conversion/Arrays.cpp:253`), which frees the cell when unique (`Elements.cpp:75-79`), then `placeElement` (`Arrays.cpp:263`), which allocates (`Elements.cpp:46-49`): a reuse the lowering decides against, where the proposal says the lowering decides nothing (§5.5) |
| D10.7 | Compile time: facts rebuilt per step | holds | D | `Classes` built per match and per block (`Reshape.cpp:78, 160`); `decides` asks the region interface per query (`lib/Analysis/Ownership/Uses.cpp:96-104`); linear values placed as if they could be counted more than once (`Classes.cpp:39-87`); the simulation keeps a shadow of the rewrite (`Reuses.cpp:57-65`). All go (§2.15) |

### 1.7 D48 and the token's type

| # | claim | verdict | class | evidence |
| --- | --- | --- | --- | --- |
| D48.1 | `!idr.box` is no longer a type | holds; the token must be re-keyed | I | today `!idr.token` has no parameters (`IdrOwnershipOps.td:33-36`); synthesis A's owed `!idr.token<!idr.box<T>, @C>` names a type D48 deletes. §2.6 keys it on the set of family applications and constructors it may come from; a rejoin of two sources of one layout would otherwise have no single type |
| D48.2 | A recursive field at an unknown index is a cell; a value of a known index has a fixed size | holds, and gives D26's "statically sized" by construction | — | so every constructor cell's layout is a function of the type alone: a token type cannot name a cell of unknown size (§2.6) |

### 1.8 The deletions the dispatch names

| item | where (read) | verdict |
| --- | --- | --- |
| Reuses' predicted death points | `Reuses.cpp:172-201` calling `whereDies` (`Uses.cpp:133-154`) | deletable: the drops placement places are the death points (TR §3.2: "the drop operations signify precisely when a cell may become available for reuse") |
| The guess that any call takes its arguments over | `Reuses.cpp:193-195` | deletable: after placement every call's conventions are in the signatures and the drops exist |
| The simulation | `Held`, `Virtual`, `moved`, `virtuals`, `takesAt`, `claimed`, `boxes` (`Reuses.cpp:57-65, 254-265`); `readBoxes`/`visit`/`considerTake` (`:94-127`); 9db9813d's guard (`:183-189`); `fieldType` from workers (`:244`) | deletable: reuse rewrites drops that exist, so nothing is decided on IR not yet made |
| `Classes` and its switches | `Classes.cpp:24-37` (switch 1), `:99-122` (switch 2), `Placement.cpp:105-132` (switch 3); readers `Reshape.cpp:78, 117, 160, 232, 262`, `Placement.cpp:80` | deletable: the grade is the class once the static lifetime is in the grade (D40) and the walk decides view or owned at a field read |
| Placement's per-region scans | `usersIn` per block (`Placement.cpp:185, 243`), `usedIn` per region (`:199, 214, 245`), `decides` per user (`:193, 247`) | deletable: the walk visits each region once with the live set |
| Reshape's predictors | `takeApart` (`Reshape.cpp:69-107`), `takeReadSums` (`:231-254`), `takeReadBoxes` (`:261-284`), `keepsCountedField` (`Take.cpp:66-78`) | deletable: drop specialization at the drops the walk placed; under D48 every field read's operand is a refined value, so "a box only read through one constructor" is no case of its own (§2.3) |
| (also) `Uses.cpp` whole, counting's readers of `Values.cpp`, `Reuse.cpp`, `Take.cpp`, `Conversion/Fields.cpp` | as §2.15 | deletable. On `origin/main`, 101edbc5's `Positions.cpp` replaced `Uses.cpp`'s queries; it goes the same way (D17) |

## 2. Boundaries

### 2.1 Counting's passes, in order

1. **idr-rc-cells** (nested on `idr.func`): a constructor with a cell
   becomes `cell.new` and `cell.init`; a select of references becomes a
   match (lane 08 T11).
2. **idr-rc-stack** (program): the frame marking (solver layer). It never
   frames a parameter D24 rebuilds, nor a cell a tail call may reach (D30).
3. **Borrows** (program analysis, L08): the conventions of every
   parameter, call and join parameter, under I1.
4. **Placement and drop specialization** (nested): §2.2, §2.3.
5. **Exclusivity** solve, grade specialization, commit (L08).
6. **Reuse** (nested): §2.4. After exclusivity, so that the walk sees which
   tokens are exclusive (I2).
7. **The take's expansion** (nested), then canonicalization folds it by
   grade: §2.5.
8. Then the tail passes (L10). Frames after counting, so that tokens ride
   in frames (I9, seam).

Pass names are generated from the specification (D16) and named by
nothing else (AGENTS.md: tests name no pass).

### 2.2 Placement: the reverse walk

**Domain.** `V(f)`: the values of `f` whose type holds references
(`ValueFactsTypeInterface`), at quantity ω, of lifetime `counted` or
`frame` (never `static`, which no count reaches; never a lifetime
variable's cell, which has no count word: L05). Quantity-1 values are
outside it: their one use is their last use (§3). Each value of `V(f)` is
`own` (holds one reference) or a view (holds none). Values are numbered
densely in one pre-order walk (the solver layer's typed ids).

**State.** `Live`, a bit set over the owned values of `V(f)`: the values
some later use on some path needs. One set per walk position, scoped:
pushed at a region's end, popped at its head; never copied per region or
per edge.

**Order.** Backward over the region tree. In a join op, its join regions
first, callees before callers in the graph of jumps between them; a set of
join regions that jump to each other (a loop) takes the least fixed point
of its live-ins, a union that only grows over a finite set, so it ends by
construction. Then the body.

**Rules**, at op `o`, going backward:
1. *Leaving the frame or the region.* `return`, `yield`, `idr.jump`, a
   call in tail position (D30's one fact on the call): `Live` becomes the
   operands it takes over, plus, for a yield, `Live` after the parent op,
   and for a jump, the target's live-in. Nothing follows a call in tail
   position.
2. *Ending the process* (`crash`, `exit`, D14): `Live` is empty at the
   terminator; see rule 8.
3. *A consuming use* of `v` (declared `Read` and `Free` on `count`; a
   call's operand when the callee's parameter is owned): if `v` is a view,
   or `v ∈ Live`, or `o` consumes `v` twice, put `dup v` before `o`. Then
   `v` joins `Live`.
4. *A borrowing use* of an owned `v`: if `v ∉ Live`, put `drop v` right
   after `o`. By the borrow marking (I1), `o` is then neither a call in
   tail position nor a D34 site. `v` joins `Live`.
5. *A result* `r` of `o` leaves `Live`; an owned `r` not in `Live` is
   dropped right after `o`.
6. *An op that decides* (each run enters exactly one region once and comes
   back: read once per op from `RegionBranchOpInterface` when the function
   is numbered): each region is walked with `Live` after `o` as its exit
   set; `Live` before `o` is the union of the regions' entry sets and `o`'s
   operands. At the head of region `i`, `drop v` for each owned `v` live
   before `o` and not at region `i`'s entry, except a value `o` writes (an
   update holds its array until its region ran, `Placement.cpp:152-161`,
   kept), which is live across `o`.
7. *An op whose regions run any number of times* holds each value from
   outside it that a region uses: the value is live across `o`, and inside
   it is a view, each consuming use taking a `dup`.
8. *A region that ends the process*: drops at its head as rule 6 says;
   then each such drop with no allocation and no call between it and the
   terminator is deleted, since the process ends (I5, Q1).
9. *Field views.* A view `w` of a field of an owned root `r` (a case
   argument, or a field read of a refined `r`) is valid while `r ∈ Live`.
   When the walk reaches `r`'s last use (`r ∉ Live` after `o`, `r` used at
   `o`) with views of `r` live after `o`, it records a *take point*: `o`,
   with those views. A view whose root is itself a view (a borrowed
   parameter, or a field of one) needs nothing: its owner outlives the call
   (I1 (a)).

**Output.** `dup`s, `drop`s, take points; each owned value graded `own`,
each view at the view grade. Nothing per point outlives the walk (lane 08
C-32's output shape).

**Invariants.**
- P1: every owned value is consumed exactly once on every path that does
  not end the process (the owned stage's verifier, unchanged).
- P2: garbage-free on `V(f)`: at every allocation in `f`, every owned
  value in scope is in `Live` (the TR's condition `Γ ⊆ fv(e)`, p.14).
- P3: nothing is placed after a call in tail position or a D34 site.
- P4: a view is used only while its owner is live.
- P5: cost: one visit per op and region, bit-set operations of width
  `|V(f)|`, one fixed point per set of mutually jumping join regions; no
  query of the IR's order, no use scan per region, no class map.

### 2.3 Drop specialization

At each take point and each `drop v` whose `v` has a constructor `C` its
type states (a case argument `!idr.ctor<T, @C>`, or the refined operand of
a field read: D48 and lane 03 §5.2a):
- `v`'s constructor has a cell and a field holding references is live
  after the point: `idr.take v @C` gives a token and the fields; the live
  fields' later uses read the take's results (owned); each dead field is
  dropped there; the token goes to the reuse walk.
- it has a cell and no such field lives on: the `drop v` stays; the reuse
  walk turns it into a take when a cell of its layout is ahead (§2.4).
- it has no cell (an unboxed sum, an atom): `idr.unpack v @C`; no token.
- never a memo cell, whose constructor a force may change under the match
  (`include/idr/Analysis/Ownership.h:153-158`); never a static value (no
  count) or a lifetime variable's cell (L05). A frame value may be taken:
  its expansion folds to the shared arm (§2.5), which keeps the dying
  fields precise.

Under D48 every field read reads a refined value, so a box "only read
through one constructor" (`Uses.cpp:172-205`, `Reshape.cpp:261-284`,
`Reuses.cpp:94-120`) and an unboxed sum read through one constructor
(`Reshape.cpp:231-254`) are refined values like any other: no special
case survives.

### 2.4 Reuse: the forward walk, exact over regions and join points

**Terms.**
- *Layout* `κ`: the size and alignment of a constructor's cell in the
  target's data layout, from the family application and the constructor
  (§2.6), computed once per type.
- *Source*: an `idr.take` (or an upgradable known-constructor `drop` of a
  cell, §2.3) giving a token of layout `κ`, at grade `excl` (never null) or
  `own` (null when the take finds the cell shared). A take whose operand is
  of lifetime `frame` is no source: its token is null on every run.
- *Sink*: an `idr.cell.new` of layout `κ`.

**Pass 1, demand (backward).** `d(p)[κ]`: the largest number of sinks of
layout `κ` on any path from point `p` until the frame's tokens die (a
`return`, a call in tail position, a terminator that ends the process).
Transfer: a sink adds one; an op that decides takes the per-layout maximum
of its regions' entry demands, each region's exit demand being the
demand after the op (a yielding region), after the join op (an exit
jump), at the target's entry (a jump), or zero (a region that ends the
process); a region that runs any number of times contributes nothing
outside it (its sinks cannot take an outer token) and is given its own
demand with zero at its terminator; a set of mutually jumping join regions
takes the least fixed point of a maximum over counts capped at the number
of sources of that layout in `f`, which ends by construction. Pass 1 also
keeps the *local* demand of each region (zero at its exit), used to place
frees.

**Pass 2, assignment (forward).** `A(p)[κ]`: the tokens of layout `κ`
available at `p`, as an ordered list of SSA values. Scoped like `Live`
(entry tokens shared by a region's walk, not copied).
1. *Source* giving `t`: if `d` after it exceeds `|A[κ]|`, `t` joins
   `A[κ]` (an upgradable drop becomes the take); otherwise the source stays
   a drop, or, if it is a take made for its live fields, `t` is freed at
   once (`idr.token.free`, I7).
2. *Sink* of layout `κ` with `A[κ]` non-empty: take one token by the
   choice order below; the sink becomes `idr.cell.recycle t`; when the
   token's set of sources is the sink's own family application and
   constructor alone, its `cell.init` becomes `idr.cell.update` of the
   fields that differ (a field given as the take's result at the same
   index, through ops that change only grades, is kept; so is the header)
   (lane 12 T3).
3. *Choice order* among tokens of one layout, a total order: (1) the
   token a D24 obligation names for this sink; (2) `excl` before `own`;
   (3) a token whose one source is the sink's; (4) the earlier
   source in the function's pre-order numbering. The order is a pure
   function of the IR: no pointer order, no map iteration.
4. *Region heads.* Where `d` at a region's entry is below `|A[κ]|`, the
   surplus is freed at the head, the worst tokens by the choice order
   first.
5. *An op that decides*: each region starts from `A` before the op (less
   its head's frees). After walking every region: an entry token left
   untouched by every yielding region stays as it is (it dominates the
   rest); beyond those, `k[κ]` = the least count of `κ` tokens left at the
   ends of the yielding regions, capped by `d` after the op; the op gains
   that many token results of layout `κ` (each region yields its best `k`
   by the choice order; each result's type is the union of the sets the
   regions yield in its slot, §2.6); each region frees its surplus at the
   first point from which its local demand is below what it holds.
   Regions that end the process or jump take no part.
6. *A jump* to join region `k` passes `TP_k[κ]` tokens, best first, and
   frees the rest before the jump. An exit jump (to the join op's results)
   merges like a yield (rule 5).
7. *A join op.* For each join region `k`: `TP_k[κ]` = the least of `d` at
   its entry and the counts available at every jump into it; for a set of
   mutually jumping join regions, start from the jumps from outside, walk,
   lower `TP` to what the inner jumps can supply, and walk again while any
   count falls: a descent on finite counts, which ends by construction. A
   token parameter is `excl` when every jump passes an exclusive token in
   its slot, and its type's set is the union of the sets the jumps pass
   there (as a match result's is, rule 5). Specialization of `k` by the
   key a jump passes (counts and grades) is an optimization under a code
   budget; a spent budget leaves this least-count rule, never a null token.
8. *An op whose regions run any number of times*: inside, `A` starts
   empty; tokens made in a run are used or freed in that run; outer tokens
   wait outside.
9. *A call not in tail position*: `A` passes through (tokens held across
   it are within D26; TR's balanced-tree example holds its node's token
   across the recursive `ins`, p.8). The same for 0007's `wait` (C2 R3).
10. *A call in tail position, a `return`*: every token in `A` is freed
    before it. *A terminator that ends the process*: nothing.
11. *A frame push* of idr-frames (if frames runs after counting, I9): the
    tokens the rest needs are fields of the frame, as an escaped join
    region's parameters (D31).
12. *Fusion* (I3): a token recycled on every path from its take, by
    recycles that all name one constructor, is fused with them: the take
    gives the cell (`idr.take_into`), and the recycles go.

**Invariants.**
- R1, linearity: each token is consumed exactly once on every path (by a
  recycle, a free, a yield, a jump, or a frame field): the owned stage's
  rule, a token being quantity 1 by type (§2.6).
- R2, layout: a recycle's token and cell have one layout: the recycle's
  generated verifier, reading two types and the module's data layout,
  locally.
- R3, scope: no token is an operand of a call, a return, or an op inside
  a region that runs many times: an operand constraint on those ops (no
  op but recycle, free, yield, jump and the frame push takes a token).
- R4, tightness: `|A(p)[κ]| ≤ d(p)[κ]` everywhere: no token is held that no
  path ahead can use.
- R5, greed per path: no sink allocates while a token of its layout is
  available on its path.
- R6, the promise: every sink a D24 rule names recycles its parameter's
  token: checked after the walk; a miss is an internal error.
- R7, determinism: the choice order is total over the IR's own data.
- R8, cost: one backward and one forward visit per op and region, plus
  the bounded descents of mutually jumping join regions; state sized by
  the function's tokens, never per value of the program.
- R9, bound: the bytes `f` holds in tokens at any point `p` are
  `Σ_{t ∈ A(p)} size(κ(t))`, whose maximum over `f` is `T(f)` of §2.10.

**Example 1** (a match's rejoin; illustrative IR):

```mlir
%t, %v = idr.match %x : !idr.excl<!idr.data<#T>> -> (!idr.excl<!idr.token<{#T @Node, #T @Pair}>>, i64) {
case @Node(%c: !idr.ctor<#T, @Node>, %a: i64, %b: i64) {
  %k, %_a, %_b = idr.take %c @Node      // source, κ = two words
  %s = arith.addi %a, %b : i64
  idr.yield %k, %s
}
case @Pair(%c: !idr.ctor<#T, @Pair>, %a: i64, %b: i64) {
  %k = ... idr.take %c @Pair ...         // same κ as a Node's cell
  idr.yield %k, %a                       // the result's set holds both sources
}
case @Bad(%c: !idr.ctor<#T, @Bad>) { idr.crash ... }   // no predecessor: not in the least count
}
%cell = idr.cell.recycle %t : ... -> !idr.cell<!idr.data<#T>, @Node>  // the sink after the match
```

**Example 2** (a join region's token parameter): jumps from two cases
pass a token of `κ`; a third case has none, so `TP_k[κ] = 0` and the two
jumps free their tokens before jumping, unless the budget lets `k` be
copied for the key "one token", in which case those two jumps go to the
copy and the third to the original.

### 2.5 The take's expansion and uniqueness

After reuse, each take becomes **`idr.match_unique %x`**, a region op of
the match family with two regions:
- `unique(%t: !idr.excl<!idr.token<...>>, %f...)`: the token is the cell,
  never null by its grade; the fields moved out, owned; the region drops
  the dying fields (one run per kind of word, §2.8) and yields the token
  and the living fields.
- `shared(%v...)`: views of the fields, valid because `%x` still holds
  its reference; the region `dup`s the living fields, then `drop`s `%x`,
  and yields the living fields.

What the token becomes depends on what the walk did with it, one case
each: a token the walk freed at once is freed in the unique region, and
neither region yields one; a fused `take_into` (rule 12) yields a cell
from both regions (the token as the target's cell in the unique one,
`idr.cell.new` of the target in the shared one); a token recycled on only
some paths has the rest up to its recycles copied into both regions under
a code budget (the unique copy recycles, the shared copy allocates), and
only past the budget does the shared region yield `idr.token.null`, the
one op that writes a null token, for the recycle to test.

It implements `RegionBranchOpInterface` (exactly one region runs), so
placement, exclusivity, SCCP and dead code read it as they read a match.
**Folding** is canonicalization reading the operand's grade: `excl`
inlines the unique region; lifetime `frame` (a stack cell is never
unique, `Rc.h:50-53`) inlines the shared region. Only a value proved
neither keeps both regions and is lowered by idr-lower to `scf.if` on
`idris_rt_is_unique`, whose test is then only "count is 1" (a counted
lifetime is no stack cell and no persistent cell: lane 18 R-RC-3, seam
L11). The null test of a token from `idr.token.null` is the budget's
fallback alone, and the lowering that emits it says why, as AGENTS.md asks
of a run-time cost. The same op serves a boxed element's take (lane 12
seam): an exclusive array's element take folds.

Effects (D27): reading the count is `Read` on `count`; `dup` and `drop`
write it, so no upstream pass moves a `dup` above the test (Swift's
hazard, §5.10 C4). This replaces §5.5's "`idr.is_unique` folds to true",
whose `scf.if` would carry the arm's fact in no type (I3).

### 2.6 Tokens typed by layout and by family

- **Type**: `!idr.token<{#F[i] @C, ...}>`: the non-empty set of the
  family applications and constructors whose cell it may be, all of one
  layout. A take gives a set of one; a merge (a match result, a join
  parameter, rule 5 and rule 7 of §2.4) gives the union of what its
  inputs carry, so a rejoin of a `Node` token and a `Pair` token of one
  layout is `!idr.token<{#T @Node, #T @Pair}>`: the type keeps exactly what
  is known on every path, and no merge has to forget a source or lie about
  one (D18). Its layout `κ` is derived (a function of any member and the
  target's data layout, computed once, D48), never stored beside it; the
  type's verifier checks that the members share it. It has no lifetime
  parameter: only a counted heap cell gives a non-null token.
- **Grade**: `excl` (never null) or `own` (null when its take found the
  cell shared); quantity 1 only: the grade verifier refuses a token at ω
  (§3).
- **Static by construction**: D48 gives every family application a fixed
  cell layout (a variable index gives the generic layout, a recursive
  field at an unknown index is a pointer), so no token type names a cell
  of dynamic size.
- **Readers**: the walk keys its map by `κ`; the recycle's verifier checks
  `κ(token) = κ(cell)`; the lowering keeps the header when the token's set
  is the one member the cell names (deleting `Fields::sameConstructor`,
  `lib/Conversion/Fields.cpp:32-51`); reuse specialization is written by
  the walk as `cell.update`, only for a set of one equal to the sink's
  (deleting `Fields::kept`).
- Cross-constructor and cross-family reuse is by layout, as Koka matches
  by size (§5.10 A4): a `Node` cell becomes a `Leaf`, a frame of one
  continuation sum a frame of another.

### 2.7 Dynamically sized cells

Arrays (buffers), strings and big integers:
1. **No token exists for one** (§2.6): a token names a constructor's cell.
2. **Reuse happens only inside the op that consumes the cell**: an
   in-place update of an exclusive buffer, bufferization taking a dead
   input as the destination (D43), the runtime's in-place string and big
   operations. The dead memory is never a value across another op.
3. **Never borrowed while dead**: such a type bounds nothing it reaches,
   so a parameter receiving one at a call where it dies is owned (I1).
4. **Never on the stack**: `cell.stack` takes constructor cells only.
5. **Dropped at its last use** by placement, and freed eagerly at count
   zero: `release` frees the whole dead structure before it returns and
   allocates nothing (*read* `runtime/Rc/Freeing.cpp:137-159` and the
   header's "no recursion and no allocation", `Rc.h:3-7`).

This replaces C1's sentence by a representation: no checker is needed,
since the state it would check cannot be written.

### 2.8 Runs of slots, and coalescing, under D26

- A run decrement (`dec_slots` over a contiguous run of one kind of word,
  lane 12 T4, lane 18 T-RC5) combines only drops placed at **one point**
  (the dying fields of a take, the region head's drops), so it delays
  nothing. A run increment combines the `dup`s at one point.
- **Coalescing** counts of one value (Lean's `coalesceRC`, §5.10 B5) may
  move an increment earlier, never a decrement later past an allocation or
  a call: a decrement that would reach zero frees a structure, and moving
  it past an allocation holds that structure there.
- The dying list of `release` frees every cell that dies within the one
  call, allocating nothing (§2.7 item 5): no allocation sees it.

### 2.9 Every holding of memory, accounted to D26

| # | holding | where | D26 clause | adds to the bound | status |
| --- | --- | --- | --- | --- | --- |
| 1 | An owned value before its last use | placement | reachable | 0 | holds (P2) |
| 2 | A value used inside a region that runs many times, held across the op | rule 7 | reachable: a later run may use it | 0 | holds |
| 3 | An array held across its update | `Placement.cpp:152-161` | reachable: written back | 0 | holds |
| 4 | A root kept alive for its field views | rule 9 | only while the root is live anyway | 0 | holds (`Placement.cpp:24-29`) |
| 5 | A borrowed argument used after the call (or a view of the caller's borrowed parameter) | I1 | reachable | 0 | design |
| 6 | A borrowed argument dead after the call, of a bounded type | I1 | held by the caller | `W(f)` | design |
| 7 | A borrowed argument dead after the call, of an unbounded type | — | never | — | today: violated (D26.6); design: owned |
| 8 | A borrowed join parameter | I1 (c) | as 5 to 7 | `W(f)` | corrected |
| 9 | A token between its take and its recycle or free | §2.4 | held by the active call | `T(f)` | design |
| 10 | A token across a call not in tail position | rule 9 | held by the caller | in `T(f)` at the call | design |
| 11 | A token as a match result, a join argument, a loop-carried join parameter | rules 5 to 7 | held by the active call | `T(f)` | design |
| 12 | A token in a heap frame (D31) | rule 11 | held by that frame, an active call | `T` of the rest's function | design; seam L10 |
| 13 | A token across a `wait` (0007) | rule 9 | held by the suspended frame | `T(f)` | for 0007 |
| 14 | A stack cell's shell | `Cells.cpp:84-102`, `Freeing.cpp:127-135` | held by the frame | `S(f)` | holds |
| 15 | A live stack cell | | reachable | 0 | holds |
| 16 | The dying list during `release` | `Freeing.cpp:137-159` | no allocation inside it | 0 | holds |
| 17 | A run of slots | §2.8 | released at the point its drops were placed | 0 | design |
| 18 | Coalesced counts | §2.8 | no decrement moved past an allocation | 0 | rule |
| 19 | Persistent cells; what static data reaches | `Rc.h:110-115`, `Freeing.cpp:166-189` | outside: persistent static data | — | holds |
| 20 | A saturated count | `Rc.h:21`, `runtime/Rc/Counting.cpp:3-5` | outside | — | holds |
| 21 | Allocator overhead; spare room in a live cell (a forced memo cell's larger constructor) | | outside | — | holds |
| 22 | A memo cell after its force | forces move a label's captures out (*read* `lib/Analysis/Ownership/Captures.cpp:3-5`) | its value reachable while the cell is | 0 | holds (the runtime side U) |
| 23 | A path that ends the process | `Placement.cpp:201`; `Reshape.cpp:83, 104` | today: dead values held at that path's allocations | unbounded | D; I5, Q1 |
| 24 | A dynamically sized cell | §2.7 | never held dead | 0 | rule |
| 25 | A destination of D34 (a hole) | | a field of the result being built: reachable | 0 | holds |
| 26 | A buffer in a kernel operation (C2 R1) | 0007 | held by the operation in flight, given back at its completion | 0 | for 0007 |
| 27 | A cell of a lifetime variable (D39) | L05 | "each scope proven within D26" | L05's | seam |
| 28 | A chunk of D31's frame stack kept after its frames popped | L10 | memory no call needs, at most one chunk | must be stated by L10 | seam |
| 29 | A take's shared arm | `Counting.cpp:93-107` | dup living fields, decrement the box: holds nothing | 0 | holds |

### 2.10 The per-function bound

For a function `f`, in bytes of the target's layout (its entry in
CMakeLists.txt, through the `Layouts` analysis):

> `B(f) = S(f) + max over p ∈ P(f) of ( T(p) + W(p) )`

- `P(f)`: the points of `f` where it may be at an allocation or suspended
  under one: its sinks and every other allocating op, its calls not in
  tail position, its frame pushes, its waits.
- `T(p) = Σ_{t ∈ A(p)} size(κ(t))`: the tokens the reuse walk leaves
  available at `p` (rules 5 to 7 included). `T(f)` is its maximum.
- `W(p)`, at a call: `Σ reach(type(a))` over the arguments `a` passed to
  borrowed parameters and dead after the call in `f` (not used after it,
  and not a view of `f`'s own borrowed parameters); at a join op, the same
  over its borrowed join parameters whose owner is dead after the op. By
  I1 each such type is bounded. `W(f)` is its maximum.
- `S(f) = Σ` over `f`'s `cell.stack` ops of the slot's size (one slot per
  op: `Cells.cpp:84-102`).
- `reach(T)`: the bytes of every cell a value of type `T` may reach:
  finite when the type graph from `T` reaches no cell through a cycle
  (`self[...]` at an unknown index) and no array, string or big; a type
  fact computed once when the type is made, from the D48 family (seam
  L04).

Program-level statement: at every allocation, the cells no one will use
total at most `Σ_{active calls c} B(f_c)`, over native frames, D31 heap
frames and suspended tasks.

**Who computes it.** The placement walk and the reuse walk know `W` and
`T` at each point as they run; `S` is a sum over the function. Each pass
keeps a running maximum and reports it as a pass statistic; the
qualification property (L19) reads it. No pass reads it to decide
anything, and no second walk computes it (D10). Finiteness is not
checked at all: it is held by construction (R1 to R4, I1, §2.6).

### 2.11 Proof sketch: our form is frame-limited in the TR's sense

Claim: for every compiled program and every run, at every allocation step
the heap splits into `H1`, reachable from the rest of the computation, and
`H2` with `|H2| ≤ Σ_{active calls c} B(f_c)`.

1. **Translation.** Read each function's SSA as A-normal `let`s; a match
   as the TR's `match` (in a `let`'s bound position or in tail position);
   a call as the TR's application; `cell.new` with `cell.init` as `[con]`;
   a closure, after defunctionalization, as a constructor (so the TR's
   `[lam]` is `[con]`); a join region as a local function applied only in
   tail position, equivalent to its body inlined at each jump (jumps
   allocate nothing, D19: never a closure); a recursive join region as a
   local tail-recursive function. A tail application does not grow the
   TR's `E` (Fig. 5, p.12), as our tail calls (D30) grow no frame.
2. **Placement is a garbage-free derivation** on `V(f)` (TR Fig. 6 with
   `(★) = Γ2 ⊆ fv(e2)`, Thm. 3, p.14): `dup` only before consuming uses of
   live values, `drop` after last uses and at region heads (the TR's
   `[drop]` inside a branch). A quantity-1 value stays in `Γ` until its
   one use, so the condition holds of it trivially. A view of a live root
   with no `dup` is Lean's derived borrow: against the TR's form (`dup` of
   each pattern variable at the branch, `drop` after its last use) it
   changes counts and not the set of reachable cells, since the root keeps
   the field's cell reachable.
3. **Borrows keep it frame-limited** (TR Thm. 4, p.15). A borrowed
   argument used after the call is the TR's `[app]` borrow ("we can safely
   borrow since we use the variable later", p.15); a view of the caller's
   borrowed parameter is reachable by induction on the active calls; a
   dead argument of bounded type is the TR's `[let]` under the
   frame-limited `(★)`, `Γ2 = Γ′, Γ″` with `sizeof(Γ″) ≤ c` (p.14), with
   `c = W(f)`.
4. **Drop specialization preserves the heap at every allocation**:
   `take x @C` is `dup` of the living fields then `drop x` in the shared
   arm, and the TR's `(dconr)`/`(dconru)` steps in the unique arm (Fig. 5),
   except for the token (step 5).
5. **The reuse walk is a drop-guided derivation** (TR Fig. 7, p.15): a
   source is `[rdrop-reuse]` at a drop whose size the type states (the TR
   allows "type information", p.16); token frees are `[rdropr]`; the
   choice at a sink is `[rlet]`'s split and `[rdropr]`'s free choice (p.16
   names both as choice points); a region is `[rmatch]`. TR Thm. 5 (p.16):
   a garbage-free derivation followed by drop-guided reuse is a
   frame-limited derivation. Two extensions lie outside Fig. 7, whose
   leaves require `R` empty: a token given out as a match result or a jump
   argument. Each is an owned value of size at most `max κ` held inside
   one frame until it is used or freed, so it falls under Def. 3's `H2`
   with `c ≥ T(f)`; `T(f)` counts every token available at every point,
   these included.
6. **Stack cells**, outside the TR's heap: a shell is `S(f)` bytes of
   `f`'s frame; a live stack cell's fields are counted cells, released at
   count zero like a heap cell's; a slot written again in a loop held a
   dead cell (`Lifetimes.h:24-26`).
7. **Frames** (D31, D32): a heap frame is an escaped join region whose
   fields are the rest's live-ins (reachable) and its tokens (step 5). The
   native stack holds only acyclic depth. Both are active calls.
8. **Paths that end the process**: with I5, placement drops what such a
   path does not need before its first allocation or call, and Def. 3
   speaks only of allocation steps. Without I5 the claim fails (I5's
   counterexample).
9. **Outside the claim**, as D26 says: allocator overhead, spare room,
   saturated counts, persistent static data. No cycle needs the TR's
   cycle clause (Thm. 2, p.13), since `idr-knots` refuses every knot; no
   thread shares a count.

What this sketch does not prove (debt): step 1's reading of regions and
join points as λ1n is argued, not mechanized; P2 and R4 are properties of
the implementation, to be checked by the qualification tests of I11.

### 2.12 The end state: types, ops, passes, runtime entries

| kind | name and shape | invariant | replaces |
| --- | --- | --- | --- |
| type | `!idr.token<{#F[i] @C, ...}>` at `own` or `excl`, quantity 1 | a non-empty set of sources of one layout, derived and static; linear | the parameterless `!idr.token` (`IdrOwnershipOps.td:33-36`) |
| op | `idr.dup %v` | operand a view at quantity ω (new constraint, §3) | today's `Idr_ViewType` operand (`:74`) |
| op | `idr.drop %v` | operand owned at quantity ω; never a token | `Idr_OwnType` operand (`:89`), the token branch of its lowering |
| op | `idr.token.free %t` | `Free` on `heap`; an exclusive token frees with no test, a maybe-null one tests null only | `drop` of a token (`Counting.cpp:47-49`) |
| op | `idr.take %x @C -> (token, fields)` | before expansion; consumes `%x` | kept, re-typed |
| op | `idr.take_into %x @C -> (!idr.cell<..., @C′>, fields)` | the fusion of rule 12 | new |
| op | `idr.unpack %x @C -> fields` | no cell | kept (essential, lane 08 C-43) |
| op | `idr.cell.recycle %t -> !idr.cell<...>` | layouts equal (generated verifier) | kept; its prose stops naming the Reuses analysis (`IdrOwnershipOps.td:216-229`) |
| op | `idr.cell.update %cell (changed fields)` | the fields not given are the token's own | new (lane 12 T3) |
| op | `idr.match_unique %x` with `unique` and `shared` regions | exactly one runs; folds by grade | the C++ branches of `LowerTake` and `LowerCellRecycle`, `Elements.cpp:75` |
| op | `idr.token.null` | the one source of a null token, written only in a shared region past the copy budget | the lowering's null component in `LowerTake` (`Counting.cpp:105`) |
| pass | placement and drop specialization; reuse; expansion; each nested on `idr.func` | §2.2 to §2.5 | idr-rc-grades' body work in `parallelForEach` (`lib/Transforms/Ownership/Grades.cpp:41-65`) |
| statistic | the largest `B(f)` | read by the qualification property | new |
| runtime | `idris_rt_is_unique(cell)`: count is 1 | only for a counted lifetime | today's count-and-stack-bit test (`Rc.h:50-53`), L11 |
| runtime | token free: no test (exclusive), null test (maybe null) | | `idris_rt_free_cell`'s three tests (`runtime/Rc/Counting.cpp:67-74`), L11 |
| runtime | `inc_slots`, `dec_slots` per run per kind of word | §2.8 | per-field calls (lane 18 R-RC-4), L11 |

### 2.13 Constructor provenance

| fact the design depends on | constructed by | who alone may |
| --- | --- | --- |
| a value's constructor, statically | the case region of `idr.match` binding `!idr.ctor<T, @C>` (D48 refinement) | matches (frontend, canonicalization) |
| a cell's layout `κ` | the layout of the family application and constructor in the module's data layout | the `Layouts` analysis, once per type |
| `reach(T)` | the type's builder, when the type is made | L04's family types |
| a value's quantity | Emit, from Idris's checked TT; `lin.enter` and `lin.use` at the boundaries Idris wrote | the frontend |
| a parameter's, call's or join parameter's convention | the borrow marking (I1) | L08's marking |
| a call's tail kind (tail; tail modulo context) | D30's one decider | L10 |
| the frame lifetime; `cell.stack` | idr-rc-stack | idr-rc-stack |
| a D24 obligation (the parameter rebuilt, the rule's sinks) | the rule read off the program before counting | L08, L16 |
| `dup`, `drop` | placement | placement |
| `take`, `unpack` | drop specialization (the reuse walk may turn a known-constructor drop into a take) | drop specialization, the reuse walk |
| a token, `own` | `take` | `take` |
| a token, `excl` | the exclusivity commit, or a take of an `excl` value | L08's commit; type inference of `take` |
| `cell.recycle`, `token.free`, token results and join parameters, `cell.update`, `take_into` | the reuse walk | the reuse walk |
| `match_unique` | the expansion | the expansion; its folding, canonicalization by grade |
| `B(f)` | the running maximum of placement and reuse | those passes |

### 2.14 Consumers, errors and cleanup

- **The owned stage's verifier** (after every pass): each owned value and
  each token consumed exactly once per path; a recycle's layouts equal; no
  token at ω; no `dup` or `drop` of a quantity-1 value.
- **idr-lower**: `match_unique` to `scf.if` on `idris_rt_is_unique`;
  `cell.update` to stores of the listed fields; `token.free` to the free
  entry its grade names; `cell.recycle` to a header store when the
  constructor differs, read off the two types. It decides nothing.
- **Tail passes** (L10): TRMC reads `cell.recycle` and `cell.init` as the
  context; frames reads join parameters, tokens among them.
- **Errors**: a D24 obligation the walk cannot meet is an internal error
  (D24: a bug, never a refusal); a verifier failure after a counting pass
  is an internal error (D37: `SIGABRT` after the message). Counting
  refuses nothing.
- **Cleanup**: tokens freed before tail calls and returns, and where
  demand falls; drops on paths that end the process by I5.

### 2.15 What it deletes

- `lib/Analysis/Ownership/Reuses.cpp` whole; `Reuses`, `Reuses::Site`,
  `Reuses::TakenField` and its `DenseMapInfo`
  (`include/idr/Analysis/Ownership.h:195-237, 313-321`).
- `lib/Analysis/Ownership/Uses.cpp` whole, with `BlockStart`, `After`,
  `Point`, `blockOf`, `firstAt`, `pointBefore`, `definedAt`, `heldIn`,
  `usersIn`, `decides`, `usedAfter`, `whereDies`, `Field`, `fieldsOf`,
  `onlyReads` and their `DenseMapInfo`s (`Ownership.h:56-141, 177-193`);
  on `origin/main`, `Positions.cpp` instead.
- `lib/Analysis/Ownership/Values.cpp`: counting's readers go;
  `isCountedElement`, `tracked`, `isMemoCell`, `followed` become type facts
  (L08, L04, L01).
- `lib/Transforms/Ownership/Classes.cpp` whole: `Class`, `ownsReference`,
  `Classes`, `usedIn`, `endsInCrash` (declared in
  `include/idr/Transforms/Ownership.h`).
- `lib/Transforms/Ownership/Placement.cpp`: the `Placement` class, the
  terminator `assert` (`:231-232`), `rebindDefaults` (`:364-375`, once the
  match forwards its scrutinee into its default region, lane 08 C-08, L13).
- `lib/Transforms/Ownership/Reshape.cpp`: `takeApart`, `takeReadSums`,
  `takeReadBoxes`, `ownFields`, `movable`'s resource comparisons;
  `rewriteSelects` moves to idr-rc-cells; `sinkConsumers` stays an
  optional action, without `Classes`.
- `lib/Transforms/Ownership/Take.cpp` whole.
- `lib/Transforms/Ownership/Reuse.cpp`: replaced by the walk (its action
  tag kept, one unit per sink).
- `lib/Transforms/Ownership/Grades.cpp`: both `parallelForEach` loops; the
  pass becomes nested passes.
- `lib/Conversion/Counting.cpp`: `LowerTake` (to `match_unique`'s
  lowering), the token branch of `LowerDrop` (`:47-49`), the fusion by
  shape (`:74-76, 108-110`).
- `lib/Conversion/Cells.cpp:123-140`: the exclusive branch and the null
  test, kept only as the budget's fallback form.
- `lib/Conversion/Fields.cpp`, `include/idr/Conversion/Fields.h` whole.
- `lib/Conversion/Elements.cpp:64-82`: the run-time test of `takeElement`
  (L12).
- L08's files: `Borrows.cpp:179-181` (the reuse reason), the cycle
  restriction `:236-237`; `Demand.cpp:56-77`.
- Tests of a deleted state: `tests/rc-reuse-read-field` pins the
  simulation's bug (9db9813d); L19 judges.

### 2.16 Distinctions that stay (each essential)

- `take` (a cell, a token) and `unpack` (no cell).
- An `excl` token (never null) and an `own` token (maybe null).
- `dup` (one more), `drop` (one fewer, freeing at the last), `token.free`
  (freeing an emptied cell): three meanings, three ops.
- A heap cell and a stack cell: two storages, two releases.
- An op that decides and an op whose regions run many times.
- A take whose token is recycled on every path (`take_into`) and one whose
  token is not.
- A call in tail position or a D34 site, and any other call.
- A region that ends the process, and one that returns.
- An owned parameter and a borrowed one.

### 2.17 Seams

| with | the declaration both write against | state |
| --- | --- | --- |
| L08 | the borrow marking's rule (I1) and its output on signatures, calls and join parameters; the D24 rule and refusal before counting; exclusivity's commit before reuse (I2) | fixed here as proposed; L08 owns the marking |
| L09 | `idr.join`'s join regions take token parameters that the reuse walk adds after formation; `idr.jump` passes them | the encoding must allow a later pass to add parameters (unfixed) |
| L10 | the call's tail kind, read by placement and borrows; TRMC moving `recycle` with `init`; frames after counting, tokens as frame fields (I9); D31's chunk retention (row 28) | unfixed: the order of frames and counting |
| L04 | `!idr.data<#F[i]>`, the refined case binding, the layout function, `reach(T)` | unfixed: `reach` is new |
| L05 | the lifetime parameter (`static`, `counted`, `frame`, variables) read by placement's domain and the fold | fixed by D40 |
| L11 | `idris_rt_is_unique`, the token frees, `inc_slots`/`dec_slots` | L11 owns the runtime |
| L12 | element takes and updates as `match_unique` and recycles at the idr level (I8) | unfixed |
| L13 | `token.free`, `cell.update`, `take_into`, `match_unique` in the ops' specification; the fold as a canonicalization | unfixed |
| L01, L02 | `Read` on `count` for the test, `dup` and `drop` writing it; consumption as `Read` and `Free` on `count` | fixed by D27 |
| L19 | the qualification property reading the statistic of §2.10 | unfixed |

## 3. QTT

**Where quantities enter, are kept and are read, Idris to LLVM.**
- *Quantity 0*: Emit writes no value, field or argument for it (AGENTS.md).
  Counting meets nothing, counts nothing, makes no token. The erased
  indices still decide layout (D48): `#Vect[3]` is three words inline, no
  cell, no count; a variable index gives the generic layout. So every
  token's size is fixed by erased data the compiler knows: D26's
  "statically sized" is a theorem of the type, not a check.
- *Quantity 1*: `!idr.lin<T>`, kept by every pass and verified after each.
  Counting reads it in five places: (1) placement excludes it from its
  domain, since its one use is its last use, syntactically: no liveness,
  no `dup`, no `drop`; (2) a quantity-1 parameter is owned by type, no node
  in the borrow marking (`Borrows.cpp:22-25`); (3) D24: what makes a
  parameter subject to the in-place rule; (4) an argument made by
  `lin.use`, the caller's binder's one use, is dead after the call, which
  the borrow marking reads with no liveness (D26.7); (5) the take of a
  value gives its quantity-1 fields at quantity 1 (D48's per-field
  quantity), so placement places no `dup` or `drop` of them afterwards;
  the take's shared arm still increments them, since a shared cell's
  other holder will release them (linearity is not uniqueness).
- *Quantity ω*: placement's whole domain.
- *Linearity of counting's own artefacts*: a token is consumed exactly
  once (recycled, freed, passed on); a join point's continuation is
  jumped to once per path (D19); a D34 destination is written once; D31's
  frames are pushed once and popped once, uncounted. Each is quantity 1 by
  construction, so the owned stage's one linear rule checks all of them.
- *Lost today*: placement treats a linear value as any owned value
  (`Classes.cpp:39-87` reads no quantity): compile time paid for what
  Idris proved; Emit demotes a quantity-1 binder used twice (proposal §8,
  17 FB-28), so counting then places `dup`s Idris ruled out; `idr.drop`
  accepts a quantity-1 owned value (`Idr_OwnType`, `IdrOwnershipOps.td:89`),
  so a pass that deletes a linear use and lets placement drop the value
  passes every check.

**Using the quantities harder.**
1. Placement's live set has bits for ω values only (§2.2); the linear
   values' consumption is read off their one use.
2. `idr.dup` and `idr.drop` take operands at quantity ω only, an operand
   constraint generated from the specification: a pass that discards a
   linear value becomes a verifier error, not a silent drop (I6).
3. A token's grade has no ω: the grade verifier refuses `!idr.token` at
   ω, so a token used twice is unwritable (I6).
4. The borrow marking takes "dead at the call" from `lin.use` for free
   (I6), and liveness only for ω arguments.
5. Linearity does not prove uniqueness (G1, G2; AGENTS.md): `match_unique`
   folds on `excl` (exclusivity, the past), never on `lin` (the future).
   Quantity 1 removes counts (no `dup`, no `drop`); only `excl` removes the
   test.
6. A D24 marker on a parameter type is admitted only on a quantity-1
   parameter of an `in_place` family with one cell constructor (I13): a
   local check where the type is made.
7. Where counting skips analysis entirely: a function none of whose
   values that hold references is at quantity ω has an empty placement
   domain, so placement does nothing there (FP²'s fully-in-place fragment,
   linear in owned variables, §5.10 G3); if its quantity-1 parameters are
   also exclusive at every call, as D24 demands of a promised one, every
   take in it folds to its unique arm and the function runs with no count
   operation and no test at all.

## 4. Improvements

**I1. The borrow rule, corrected three ways** (*coordinator*: it follows
from D26, D30 and D34; L08 owns the marking).
- Evidence: C1.7; `Borrows.cpp:236-237`; `Placement.cpp:226-233`;
  `match-and-counting.md` §7.
- Counterexamples. (a) `count t = size t + 1`, `count`'s parameter
  borrowed, `size` only reading: read literally, C1 owns `size`'s
  parameter (the caller does not use `t` after), so every call of `size`
  pays an `inc` and a `dec` on a tree its owner up the chain still holds.
  (b) `data Q = MkQ (Maybe Int) (Maybe Int)` (bounded: three cells);
  `g : Q -> Int` reads only; `f x = g (MkQ (Just x) Nothing)`, a tail call
  in which the `Q` dies: C1 lets `g` borrow, placement must drop the `Q`
  after `g` returns, and the tail call is no jump (D30); on a cycle, the
  stack grows per round. (c) `total xs = loop xs 0` contified into a
  recursive join region with `ys` borrowed and `xs` dropped after the
  join op: the whole list stays allocated while the loop walks its
  suffix, `n` cells held by one frame, against D26.
- Root cause: liveness judged at the call, not along the owner's chain;
  the call's tail kind not read for bounded borrows; join parameters under
  no space rule.
- Correction: a parameter (or join parameter) is borrowed only when the
  callee neither consumes nor stores it and, at every call (jump), the
  argument is used after the call, or is a view of the caller's borrowed
  parameter, or is static, or is dead after the call with a bounded type,
  the call being neither in tail position nor a D34 site. A two-point
  marking, monotone (owned propagates down the chain).
- Deletes: the cycle restriction (`Borrows.cpp:236-237`) and its
  `CallCycles` read; Borrows' reuse reason (`:179-181`).
- Discriminator: the verifier's tail rule (a call in tail position is
  followed directly by its return: D30's one fact, verified) refuses (b);
  a qualification test runs (c) and compares peak live cells with the
  owned form.

**I2. Reuse after exclusivity, with a total choice order** (*coordinator*:
D10).
- Evidence: today reuse is decided before exclusivity
  (`Grades.cpp:45-65`, then idr-rc-exclusive); a recycle of a box built in
  a recycled cell is new either way (the cell is the old one only when its
  take found it unique, else fresh), so exclusivity's answer does not
  depend on reuse (*read* `IdrOwnershipOps.td:216-229`; `Values.cpp:17-21`).
- Counterexample: a function takes apart `xs` (exclusive at every call)
  and `ys` (shared at one call), both `Cons`, and builds one `Cons`. Chosen
  by program order, `ys`'s token may get the sink: where `ys` is shared,
  its take gives null, the recycle allocates, and `xs`'s cell is freed: an
  allocation and a free instead of a reuse, and a null test.
- Root cause: the token's grade is written after the walk that needs it.
- Correction: placement, then exclusivity, then the reuse walk, then the
  expansion; the choice order of §2.4.
- Deletes: nothing more; the walk reads `excl` from the token's type.
- Discriminator: the fixture above; after counting, the recycle's token is
  `excl` and the lowered code calls neither `idris_rt_is_unique` nor a
  null test for it.

**I3. Uniqueness as a two-region match; the cell given where the token is
always recycled** (*coordinator*: representation first).
- Evidence: D10.1, D10.3, D10.5; proposal §5.5.
- Counterexample: today a non-exclusive take tests uniqueness
  (`Counting.cpp:93-107`) and the recycle tests the token for null
  (`Cells.cpp:128-140`): two tests of one run-time answer on every reuse
  of a shared-or-unique value. With §5.5's `scf.if (idr.is_unique %x)`,
  the then-arm's take is on a value no type says is unique: the lowering
  must test again or trust the position.
- Root cause: the answer is a boolean; its consequence (the cell is the
  program's) is in no type.
- Correction: §2.5's `idr.match_unique` binding the never-null token in
  its unique region, folded by grade; rule 12's `take_into` where every
  path recycles.
- Deletes: `LowerTake`'s branch, `LowerCellRecycle`'s branches (but for
  the budget's fallback), `Fields.cpp`, the take of a frame value's test,
  the element take's test.
- Discriminator: a lowered-IR property (L19): no `idris_rt_is_unique` on
  an `excl` or `frame` operand, at most one uniqueness test per take, no
  null test after a `take_into`.

**I4. A dynamically sized cell has no token** (*coordinator*: elegance).
- Evidence: C1.6; §2.7.
- Counterexample: a future op giving an array's memory as today's
  parameterless `!idr.token` would satisfy every type and need a walk to
  enforce C1's sentence.
- Root cause: the token's type names no cell.
- Correction: §2.6's type; dynamic reuse only as an op's destination.
- Deletes: the rule and any checker of it.
- Discriminator: the token type's generated verifier refuses anything but
  a constructor of a family.

**I5. Paths that end the process under D26** (*owner*, Q1).
- Evidence: `Placement.cpp:201`; `Reshape.cpp:83, 97, 104, 280`; D26
  ("at every allocation").
- Counterexample:
  ```idris
  f : List Int -> Int -> Int
  f xs n = if n < 0 then idris_crash (concat (replicate 1000000 "!"))
                    else sum xs
  ```
  The crash arm does not use `xs`, gets no drop of it, and builds a
  million-character message while the whole list stays allocated: memory
  a garbage-free program would not hold, and an out-of-memory ending (111)
  where the program should crash (1).
- Root cause: "ends in a crash" stands for "allocates nothing before
  ending", which is a different fact.
- Correction: rule 8 of §2.2. Compiler-generated crash arms allocate
  nothing (D38's site is data), so they still place nothing.
- Deletes: `endsInCrash` and its five uses.
- Discriminator: the fixture above under a memory limit (D36): ends with
  status 1, not 111.

**I6. Quantities in counting's types** (*coordinator*).
- Evidence: §3 "lost today".
- Counterexample: dead code removes the use of a linear value; placement
  sees an owned value with no use and drops it at its definition; the
  verifier passes, since `drop` takes any owned value.
- Root cause: counting's ops constrain the permission and not the
  quantity, which the grade holds apart.
- Correction: §3 items 1 to 4.
- Deletes: placement's work on linear values; the liveness query for
  arguments made by `lin.use`.
- Discriminator: the verifier refuses `drop` of a quantity-1 value and a
  token at ω; the placement statistics count no `dup` or `drop` of a
  linear value.

**I7. Freeing a token is its own op, with only the test its grade needs**
(*coordinator*; lane 12 CV-31 proposed the split).
- Evidence: D10.4.
- Counterexample: every free of an exclusive token runs three tests whose
  answers its type fixes.
- Root cause: two meanings in `drop`; the runtime entry knows nothing of
  the grade.
- Correction: `idr.token.free`; two runtime entries (seam L11).
- Deletes: `LowerDrop`'s type branch; two of `idris_rt_free_cell`'s tests.
- Discriminator: the lowered IR of a function freeing an exclusive token
  has no compare before the free.

**I8. Array element updates reuse and fold at the idr level**
(*coordinator*; L12 owns arrays).
- Evidence: D10.1 (third site), D10.6.
- Counterexample: updating a boxed element of an exclusive array frees
  its cell and allocates one of the same layout, after a run-time
  uniqueness test the array's grade answers.
- Root cause: the update's old element is taken and rebuilt in the
  lowering, where no counting fact lives.
- Correction: the old element enters the update's region as an owned
  value of known layout; drop specialization, the walk and
  `match_unique` decide in IR; the lowering lowers.
- Deletes: `takeElement`'s test, `writeElement`'s allocate-after-free.
- Discriminator: a fixture updating every element of an exclusive array
  of boxes allocates nothing in the loop (the live-cell count stays flat).

**I9. Frames after counting, so tokens ride in frames** (*coordinator*;
the order is L10's to fix).
- Evidence: D31 ("reuse tokens carried in it"); today frames runs before
  counting (lane 08 §2.2); D31's frames are uncounted, so counting never
  needs to see them.
- Counterexample: a tree map with two non-tail recursive calls, under
  D32: frames turns each call into a push and a tail call; the matched
  node's token cannot cross the tail call, so it is freed and every node
  of a unique tree is allocated again, losing the TR's spine reuse (p.8).
- Root cause: frames decides a frame's fields before counting makes the
  tokens.
- Correction: counting, then frames; the rest's token parameters become
  frame fields.
- Deletes: nothing in this area.
- Discriminator: the tree map on a unique tree allocates no node (live
  cells constant across the map).

**I10. Runs and coalescing under D26** (*coordinator*). Evidence and
correction: §2.8. Counterexample: coalescing two decrements of `v` in one
block moves the first past an allocation; if it was the last reference,
`v`'s whole structure is held across the allocation. Discriminator: a
property over counting's output: no decrement follows an allocation that
the drop placement put before it.

**I11. The bound reported, and the qualification tests** (*coordinator*;
L19 owns tests). Evidence: D26.11; P2 and R4 are implementation
properties. Correction: §2.10's running maximum as a statistic; two
differential tests: peak live cells with reuse at most peak without reuse
plus depth times `T`; peak with borrows at most peak all owned plus depth
times `W`. Discriminator: the tests fail on today's unrestricted borrows
(I1 (c)) and on today's crash rule (I5).

**I12. One word for two concepts** (*owner*: a name). D25's prose calls
the join point's handle a "token" (`!idr.cont<...>`, "a token defined by
the target op"), while `!idr.token` is the reuse token. D28 and D29 name
"one name per concept". Proposal: keep "token" for the reuse token (the
type's name since it exists) and call the continuation handle by its
type's name everywhere.

**I13. `in_place` only on a family with one cell constructor**
(*coordinator*; L08, L16 own the rule).
- Evidence: D24.1.
- Counterexample: a future `data T = A Int | B Int Int` made `in_place`;
  `f (B x y) = A x` falls under D24's rule, and no token of `B`'s layout
  fits `A`'s cell: an internal error on a valid program.
- Root cause: the kind is admitted on any family.
- Correction: the registry admits `in_place` only for a family with one
  constructor that has a cell (`LList`, `LNat` today); checked when the
  registry's table is built.
- Discriminator: the registry refuses the counterexample's declaration.

*Considered, not selected*: matching tokens by the allocator's size class
rather than exact layout (spare room is outside D26) would raise reuse but
make snmalloc's table a compiler fact; no measurement supports it.

## 5. Work units (draft)

**U1. Counting's types and ops in the specification.**
- Write: the specification's module for ownership ops and types (path
  per L03's layout under `compiler/spec/`, *decision* C7) and its
  generated output.
- Outcome: §2.12's types and ops, with the constraints of §3.
- Deletes: the parameterless token; `drop` of tokens.
- Must not: give a token a lifetime parameter or an ω grade; restate a
  layout beside the type.
- Acceptance: the generated verifier refuses a recycle with unequal
  layouts, a token at ω, a `dup` or `drop` of a quantity-1 value.

**U2. Placement and drop specialization.**
- Write: `foreign/idr/lib/Transforms/Ownership/Placement.cpp`; delete
  `Classes.cpp`, `Take.cpp`, `Reshape.cpp`'s predictors and `ownFields`,
  `lib/Analysis/Ownership/Uses.cpp`, their declarations in
  `include/idr/Transforms/Ownership.h` and
  `include/idr/Analysis/Ownership.h`.
- Outcome: §2.2, §2.3, nested on `idr.func`.
- Must not: read quantity-1 values into the live set; place anything after
  a call in tail position or a D34 site; keep a class map.
- Acceptance: the program suites and the live-cell differential pass with
  dup and drop counts per test no higher than the baseline; I5's fixture
  ends with status 1.

**U3. The reuse walk.**
- Write: `foreign/idr/lib/Transforms/Ownership/Reuse.cpp`; delete
  `lib/Analysis/Ownership/Reuses.cpp` and `Reuses` in
  `include/idr/Analysis/Ownership.h`.
- Outcome: §2.4 after exclusivity, R1 to R9.
- Must not: decide on IR not yet made; give a null token on a static
  path; let a token cross a tail call.
- Acceptance: reuses per test at least the baseline on the `rc-*`
  fixtures; I2's and I9's fixtures; the D24 post-check never fires on the
  suites.

**U4. The expansion and its fold; the lowering emptied.**
- Write: a new `foreign/idr/lib/Transforms/Ownership/Expand.cpp`;
  `lib/Conversion/Counting.cpp`, `lib/Conversion/Cells.cpp`; delete
  `lib/Conversion/Fields.cpp`, `include/idr/Conversion/Fields.h`.
- Outcome: §2.5.
- Must not: branch on a grade in the lowering.
- Acceptance: I3's lowered-IR property on the suites.

**U5. Pass wiring.** Write: the pipeline's generated list (L13, L03) and
`lib/Transforms/Ownership/Grades.cpp` (deleted). Outcome: §2.1's order.
Must not: name a pass in a test. Acceptance: the five suites and the
invariant set unchanged (§7's gate).

**U6. The bound's statistic and the qualification tests.** Write: the
statistic in U2's and U3's passes; the tests are L19's. Acceptance: I11's
two differential tests pass on the suites' programs.

**U7. Runtime entries** (L11 owns `runtime/Rc/`): the two token frees,
`inc_slots`/`dec_slots`, `is_unique` for a counted lifetime. Acceptance:
the checked runtime's live-cell differential unchanged.

**U8. Element updates** (L12 owns arrays): `lib/Conversion/Elements.cpp`,
`Arrays.cpp` lose their decisions; I8's fixture allocates nothing in its
loop.

## 6. Owner questions

**Q1. Does D26's promise hold on a path that ends the process (a crash or
`exit`) before it ends?**
- *Why it is open*: D26 says "at every allocation"; D21 says that after a
  crash nothing observes the heap, and counting has always placed nothing
  in a region that ends in a crash. A path that allocates before ending
  (a message built at run time) then holds every value from outside it.
- *(A) Yes.* Placement drops what such a path does not need before its
  first allocation or call (§2.2 rule 8). Costs: drops in the few ending
  paths that allocate; compiler-generated crash arms allocate nothing
  (D38) and are unchanged. Buys: the promise holds on every path, and a
  crash whose message is large crashes (1) instead of running out of
  memory (111).
- *(B) No.* D26 gains "except on a path that ends the process". Costs: a
  program may end out of memory where a garbage-free one would crash, an
  ending the program's own code did not ask for. Buys: smaller code in
  ending paths that allocate.
- *Recommendation*: (A).
