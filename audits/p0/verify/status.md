<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Swarm status (coordinator's live note)

HEAD `e96bb991` throughout so far. The reviewer was dispatched when L13
returned (the concurrency cap is 20).

## Returned

| lane | verdicts | owner questions (queued, one at a time) |
| --- | --- | --- |
| L13 | D9 holds (189 ops → 166); D10 holds, two run-time costs uncovered (guard conditions, crash sites); D16 corrected (family constants are `bool`s: enums; inline-template meaning; DRR from the spec); D19 holds; D41 corrected (constexpr 64-bit domain, header in `runtime/`); §5.3 stale vs D48, D40; `maxNumRewrites` needs an upstream patch; C3 contradicted by the vocabulary table and G's DP-31 draft | mnemonics all take their family prefix (46 lack one; 9,647 fixture uses)? |
| L16 | D8 holds; D12 corrected (TTC-dropped `let` type refuses valid programs; `total` attribute means "terminates"); D13 two corrections (termination trusted over specialization's new cycles; `delayedLets` vs explicit `let` around `Delay`); D44 five corrections (0003 has 62 items, not 21; absorbed bars are ratios to a native run at `make self`; O6, O7 depend on unabsorbed work; O-skip rule vs "whole"; R1, R2 gated on outside engines); D46 corrected (sizes and breadth too); D48 corrected (frontend drops every index today; one-field collapse goes); D50 corrected; doubles cross hosts as text | Q1 the normaliser's output vs the template: a stated trust in the fork, a second evaluator, or keep the check (recommends trust); Q3 do 0011's O6, O7 pull 0009's plain-Idris layer and 0015's R4 into P0 (recommends no). Q2 (the absorbed bars' baseline) is measurement process: the coordinator's |
| L14 | D2 corrected (analyses declare their reads as types); D22 corrected (row ⊇ derivation after every pass, equality at re-derivation, since the canonicalizer deletes dead cases); D39 corrected (lifetime inference's answer is the function type); D44 holds; §5.4 "every solve unit an action" refuted (a skipped exclusivity unit is unsound); DP-54 refuted in part; new defect `Borrows.cpp:303-304` | OQ1: between passes, is a row an upper bound or exact (recommends upper bound, exact at re-derivation and before lowering) |
| L19 | test rules hold, counts corrected (291 RUN lines in 173 fixtures name a pass; 19 passes); refuted: the runner builds under the stock host only (`contrib`, `test`, `Language.JSON`); D24's boundary test passes before and after (run it with optimizations skipped); D26 holds, unchecked; D30 corrected (fallback under `Conversion/`; five stale "1 MiB" comments); D31 to D34 hold; D35 corrected (`ulimit -v` fails on macOS: strict hosts are Linux only); D36 holds; D37, D38 corrected (86 crash cases' stderr change; program name a compile-time constant); D49 corrected (the stamp has no reader; the generator in the fingerprint); D52 holds; S1, S2 corrected; `tests/spec/` and `tests/build` stop the runner starting | Q1: D26 checked at run time by a typed record from the checked runtime, a bound handed in, or statically only (recommends the typed record) |
| L05 | D39: "three constants" refuted (HEAD has `heap` and `frame` only; `static` added by 467fa2f5, removed by c4d38e9b); the owned verifier's walk goes only half (the views half; consumed-once moves into the linearity verifier); the element-view rule unsound for IORefs and IO arrays (test the lifetime's effect row instead); "a scope parameter is a handle at run time" contradicts D48 (keep it erased; pass an arena handle only to functions that allocate into it); D40 corrected (the outlives order is partial; `!idr.q<1, own, T, ρ>` is a state D39 rules out); D48 corrected (binders by position; passes substitute); D26 corrected (stack-shell clause vs D39; nothing computes "type bounds what it reaches"); D24 a defect at HEAD, unrepresentable under the exact grade; C1 corrected (as written `length` would own its borrowed list). Improvements: the grade as quantity × hold (`own`, `excl`, `borrow ℓ`, `plain ℓ`); `idr.borrow` a region op taking the owner in and giving it back; D26 per lifetime a local verifier rule | Q1: does a counted cell in lexical memory (today's stack cell and its stack bit) survive? (recommends deleting it, after measuring) |
| L15 | D7 corrected (`compile-time-cpp.md` still treats hand TableGen as the source; `template for` absent from the host clang `make typecheck` uses; a recursive lambda is still recursion); D10 corrected (the linearity verifier numbers every op per verification, re-asks the region interface per value); D33 corrected (about 55 of our functions recurse on input size; upstream's verifier already iterative; `upstream/10-*` holds a report, not a patch; the fix is a redesign of upstream's parser, printer, walkers); D41 corrected (`mlir::Value` converts to `bool`: the generic function needs a truth type that cannot be branched on, or the IR-builder domain miscompiles); D47 holds (05 ID10 and synthesis B still allow `TypeSwitch`); §5.2 incomplete; "five forms, exactly one per op" cannot represent `idr.match` (recursive and typed) | OQ-1: does D10 forbid assertions in the shipped compiler? (recommends off in the one toolchain, invariants into types, after measuring) |
| L06 | no ruling refuted; corrections: D7's "Pending" line stale (D47), D30's code under `lib/Conversion`, D36's `StatsRange` is snmalloc's, D39's run-time handle vs D48, C8's four of five "outside" bugs are inside P0's rewrite; 14 stale places in §5 to §8; G: 8 superseded, 25 stand, 24 stand corrected, 6 conflict (DP-27, 28, 40, 52, 74, 80); appendix drafts §3's C9 to C63; DP-07's strike unrecorded (§4 skips 7; five questions and DP-22, DP-24 rest on it); DP-80 (probes in compiled code) conflicts with D32, C5; DP-52, DP-30 skip "patch upstream first" (carry a patch to `mlir::CallGraph`); the reuse token is not linear by type | OQ1: does a lifetime parameter exist at run time (D39 yes, D48 no)? (recommends compile-time lifetime plus a separate linear allocation handle), same as L05's correction |
| L12 | D20 corrected (the update region's guarantee becomes an effect rule; `#idr.world` memory space renamed); D39 corrected (dup at `Reshape.cpp:109-112`; element view a cast after `memref.load`; shared arrays need alias reasoning); D41 holds; D42 corrected (22 externs, most upstream ops or compositions; `merge` drops its extents); D43 corrected (`lowerToLoopsUsingSCFForOp` takes result-free ops: a buffer form per generating op; cell sizes only a cell knows; `to_tensor`/`to_buffer` reject `!idr.lin`, second patch hunk; patch 27's README test absent; new patch 64). **Two suspected miscompiles on main, read, unrun**: `UseModel` marks every linear array read from a cell writable (`Linear.cpp:91`), so a shared record at quantity 1 has its array written in place; `merge` treated as identity, an empty frame's `shape` is `[<0,0]` not `[<0,k]` | OQ1: shape terms as D48 index terms (recommends yes, at signatures); OQ2: `LArray` and `Linear.Vec`'s in-place promise as D24's (recommends yes) |
| L02 | D9 corrected (effects.md 3.6's derivation drops `alloc`, `free` at calls); D10 corrected (hoistability, exclusive-aliases-nothing, the row at the LLVM boundary never reach their readers; the region-op cache is a pointer-keyed map); D22 corrected (row ⊇ derivation after every pass, equality where the writer runs); D29 holds (§5.1 and the vocabulary still print old names); C2 R3 applies inside P0 (D39 vs D48); C2 R4 incomplete (a foreign call also holds crash, divergence, free; never `nosync`); §5.1 lowering refuted in three columns: never `memory(none)` (reuse rebuilds a cell under the same pointer: LLVM merging two calls across an in-place rebuild prints 2, not 3), the `write` column is write-only to LLVM, withhold `willreturn` from any `io` row (blocking; `SIGPIPE`) | Q1: lifetime parameter run-time or erased (same as L05, L06); Q2: a per-parameter part of the row for writes through exclusive owned parameters (recommends yes) |
| L01 | D27 holds, corrected (`Allocate` on `identity` reads as fresh memory to upstream's alias analysis: `lin.enter %arg` would not alias `%arg`); D9 corrected; D13 defect (`handle.string` may crash, declares none); D14 corrected (exact only with D37's ending table); D20, D23 hold; D21 holds if the live-cell counter goes no later than the tree; D22 corrected (three ops with undeclared count writes or frees; runtime state's memory reported); D28, D29 hold (§5.1 prints old names); C2 R2 holds, R5 holds with no type carrying its fact; C3 corrected (idr-expect's `no-heap-allocation` and `builds` break before counting; `alloc` also from runtime builders); F1 wider (`nat.from_big`, `big.shl`, `big.shr`), F2, F3 confirmed; "175 static, 14 typed" refuted (112 static, 57 typed). Improvements: I1 a value of an `in_place` type gets its identity where built (CSE, constant folding, record eta can share it and add a refusal); I2 C3's rule for strings and integers; I3 declarations matching their runtime functions (seven IO ops observe nothing) | none |
| L18 | D10 corrected (the 11% mostly one fixture, `defunc-tag-limit`; a second per-function pattern set at `Identity.cpp:79-81`); D19 target holds (contify handles one call site today; "a linear closure applied once is never counted" true only built and applied in one function or with a linear capture); D44 holds (0003's B7 corrected: nodes keyed by symbol name); D48 corrected (closure and memo families need binders for indices their captures mention; the memo cell needs a declared kind); C3 corrected (a memo cell or `in_place` value takes a fresh identity; `ConOp::fold` makes a capture-free suspension one static memo cell kept until exit); the megamorphic refusal refuted for seven tests refusing a choice among one or two implementations; OPT-14's stale dominance refuted (`Pass.cpp:673-679`); DP-68 refuted. Improvements: nothing optimizing runs before the label solve knots reads (deduplication can create a knot refusal); construction pure only where nothing reads identity (`SuspendOp::fold` goes); `absorb` goes (inlining loses Idris's `total`) | Q1: a runtime choice among implementations the program fixes: megamorphic (refuse) or a closed sum (compile)? (recommends compile); Q2: the knot rule over the label solve's least solution of the program as written (recommends yes) |
| L11 | D23 corrected (under `ulimit -v` snmalloc's fatal error ends a program by SIGABRT with output lost today; the stack-overflow analogy is stale); D32 corrected (no runtime entry carries a stack size; GMP's stack temporaries); D35 target holds (page map 256 GiB read from source; snmalloc ignores a refused commit, `pal_posix.h:244-253`: needs a fix); D36 corrected (the lowest limit up the cgroup tree, minus usage, plus swap if allowed); D37 corrected (every program prints `idris-mlir:`; crashes lose file output `exit` writes; the Status root goes); D38 corrected (cause an enum value; four committed crashes have no site); C2 R1 holds (kernel-written buffers of the counted lifetime); C5 corrected; 0017 holds. Improvements: the heap's span (no region reserved; 4 GiB alignment as the cursor's start; snmalloc's bounded page map over the span; a carried patch); commit failures reported (snmalloc becomes a patch project); one generated ending (leaks an internal error of the checked runtime; no live-cell counter shipped) | Q1: `exitWith` outside 0 to 255: internal error (D37) or a crash at the exit's site? (recommends crash); Q2: in a cgroup that may swap, end at `memory.max` or at the kernel's kill point? (recommends kill point) |
| L17 | D45 corrected (five search depths, 50, 50, 500, 500, 1000, the last dead code; every fork count listed); D53 corrected (universe levels carry fresh names: all universes one symbol; the repeated-goal check reports as an internal error today, which the driver reads as a compiler bug); D54 corrected (the handler copied postpones even at the last chance, `Unify.idr:1449-1455`: a growing search would never be refused by name); D55 holds for a known expected type, the unknown case drafted (a syntax node holding the parts once; a pending choice that elaborates nothing new; linear in the tuple; a checked-terms comparison test against stock Idris); D44's fork items C1, C2, the leaf index, B1 lost at HEAD (B1's number a session counter); D12 holds except `%search_timeout`, `%foreign_impl` and two flags selecting a second behaviour; C8 corrected (the fork reads every path with Windows rules on all targets: `"/tmp/a:b" </> "Main.idr"` gives `/tmp/a/Main.idr`); one POSIX path model | Q1: D53 full embedding with constants by type, or compare only goals of the same type constructor with constants ordered by value (refuses fewer finite searches, `Rose Nat`, an Integer countdown)? (recommends the second) |
| L08 | D24 corrected and its refusal refuted as placed (misses Idris's lifted case blocks, take and build in two functions as in `tests/leet-relink-in-place`, and forwarding functions like `Linear.List.reverse`; decided after contify, inliner, CSE, borrows and placement, so an optimization adds or removes it; G-09 refuses a partial rebuilder applied twice); C1 corrected (derived borrows; the forced-owned reason a fact of the program; rebuilt clause redundant); D26 holds, wording corrected; D10 violated by grade copies, G-09, counts on read-only recursion; D19 holds (crash cases dead ends only with D25's edges); D39 corrected (borrow and lifetime inference one marking); the markings template: four users, exclusivity needs gates. Improvements: `idr-in-place` right after defunctionalization by an exact rule (boundary cases B1 to B20), its verdict grades the verifier keeps, `Demand.cpp` gone; the pairing of rebuilt cell and construction a linear token consumed by `idr.rebuild`; obligations passed back through forwarding functions so the refusal lands at the user's call | Q1: obligation whole-graph `excl` or the family's own cells? (recommends own cells); Q2: D26's never-line "no active call needs it after the call" so derived borrows are allowed (recommends yes); Q3: does the promise reach an in-place value bound at quantity 1 inside another linear value? (recommends yes) |
| L03 | D7 corrected (C++-only facts via printed headers, not TableGen; a spec law gets no `static_assert`; compile-time-cpp, §5.6, synthesis D §2.6 still name the old generator); D15 corrected (the bootstrap's Idris waits on the pinned clang's GMP); D16 corrected (5,900 lines; `IdrRuntime.td` never printed; about 20 construct kinds missing, §2.4; gate A needs today's def names, order, three enums' values); D47 holds; D49 corrected (a spec-wide stamp in every header recompiles 316 includers per edit); D50 corrected (the `.txt` files are read by shell; builders take one argument per operand group; primitives need no builder); D51 corrected (also upstream enums, attributes, bytecode records; the admitted set's C++ side has no generator); D52 holds; C6 challenged; C7 holds with prefix changes. Improvements: one committed manifest of fingerprints, no stamp in a file; references inside an op as positions (`Fin n`), removing three `auto` searches whose depth differs between hosts; bytecode layout and grade rules one typed fact printed to both sides | Q1: how the Idris side names a primitive: one generic builder over the spec's op value, registry rows naming spec ops (withdraws C6); Q2: where D49's fingerprints live (recommends the manifest); Q3: the D51 backend prints the C++ table of admitted ops (recommends yes) |
| L07 | D26 holds (today's code breaks it twice: borrowing unbounded; a branch ending in a crash drops nothing before allocating; match-and-counting §7's join-parameter borrow breaks it too); per-function bound specified, proof sketch after Lorenzen and Leijen Def. 3, Thms 4-5; C1 corrected (borrow rule wrong in part; a type that cannot name a dynamically sized token; rejoins as the least count per layout returned as match results); D24 holds (give the promised parameter's token to its rebuild first; an `in_place` type has exactly one constructor with a cell); D34 corrected (nothing between every TRMC self call and its context, not only on cycles); D19 corrected (no null token where none can be; borrowed join parameters under D26); D10 holds, four new run-time payments (a stack value's take, a token's free, recycle's second test, array element updates). Improvements: the borrow rule fixed three ways; uniqueness as a two-region match with a never-null token, folded on exclusive types; reuse after exclusivity, preferring exclusive tokens | Q1: does D26 hold on a path that ends the process and allocates before it ends? (recommends yes) |
| L09 | D18 target holds, broken four ways today (three ancestor walks rebuild a known constructor; the tail loop's run-time "continue" flag; a crash arm lowered to a yield of poison; contify leaves a second block before lowering); D19 corrected (linearity does not make a continuation non-escaping; join points need erased index arguments; a recursive join point needs its own op); D25 corrected (`!idr.cont` refuted: any-type operands of ours would accept it; the file is `upstream/<NN>-early-exits/llvm.patch`; five hunks fail `git apply`, two still with fuzz; `scf.index_switch` must carry exits too); D30 holds (contification rewrites a moved call's tail fact); nine control-flow costs. Improvements: upstream's builtin `token` (the verifier already refuses an escaping token); five upstream fixes carried beside the PR (all-jump match deleted as dead; region inliner changes IR then fails; dead-input patterns edit another op; region-graph traversal out of bounds; `scf.index_switch` cannot hold a jump); `idr.join` and `idr.loop` split, Fluet-Weeks on regions, case-of-case copying only the dispatch, a join lowering of ours beside upstream's handling irreducible groups | owner items: the builtin `token` amends D25's text; `idr.join`/`idr.loop` split. Q1: "a linear tail continuation is never allocated": promise or optimization? (recommends optimization, it depends on inlining) |
| L04 | D48 holds, none of twelve claims refuted; corrections: labels part of identity (or the printer shows the first creator's names); a group is a cycle among registered instances, not an Idris `mutual` block; `self` a type, not syntax; group re-forming stays as one utility where defunctionalization makes a cycle; `Fin n` one word only when `n` is known and fits 64 bits; 149 body readers, not 147. D10, D12, D18, D24, D43 hold (`in_place` a promise on the family; D43 a family-verifier rule). G DP-40 refuted for boxes. Every consumer of `!idr.box` named (C++, ODS, Idris, 104 test files, 3,144 occurrences). Improvements: layouts grouped into classes with a size budget, a call whose layout changes specialized at that class (or `sum [1,2,3]` passes three words to a body compiled for cells); `idr.reindex`, a cast the verifier checks against enclosing cases (MLIR checks types with no region context, so `map`'s `#Vect[m+1]` cannot meet `#Vect[n]`), and `idr.assume`, a scoped region for erased equality proofs; index variables as de Bruijn levels in one shared binder list (as L05), inlining through one substitution utility (upstream rejects index-polymorphic callees, `InliningUtils.cpp:395, 532`) | Q1: fixed shapes meeting functions compiled for every index: specialize by class (recommends), indices pruning constructors only, or convert at every call; Q2: a runtime value in an index position keeps its link (a Dependent ML singleton, recommends) or stays opaque |
| L20 | AGENTS.md's QTT rule corrected (Emit demotes a linear binder used twice but leaves `!idr.lin` in the signature, FB-28 confirmed; the after-every-pass verifier checks at most once, never that a pass kept the grade); D24 corrected (reads the quantity Emit may have demoted); D26 corrected (read off the type only once demotion goes); D30, D32 Rust's frames open (unbounded; a cycle through a Rust callback grows the native stack); D39 corrected (lifetime erased, arena a run-time operand: same split as L05, L06, L02); D48 corrected (indices bound by run-time values, `replicate`'s `len`, `Linear.Vec`'s `n`, have no binder); C2 R2, R3 hold, R1, R4, R5 corrected, the stale list incomplete; 0007's "every fork is joined" and "lending cannot dangle" refuted (a monadic result is unrestricted, the join not linear: a use after free). Improvements: substitution that respects quantities (Emit never counts; Q-FB2 an unreachable internal error); a lend a lifetime region whose end joins its borrowers, `lent` deleted; a run-time natural equal to an index carries it in its type | Q1: Rust's native stack and cycles through callbacks (recommends the host's limit for foreign code, refuse cycles through callbacks); Q2: when a foreign destructor runs relative to output (recommends at the source's last use, fixed before optimization); Q3: a by-value Rust move refused at compile time (recommends) or checked at run time; Q4: a grade richer than 0, 1, ω in the IR? (recommends no, the grade one algebra in the specification) |
| L10 | D30 corrected (five undoers: idr-returned-arguments, borrow forcing and the stack rule on cycles only, the general loop's flag, `func.call` cannot carry the fact; two definitions of tail position, four cycle deciders, 19 files); D31 corrected (the frame stack an unrestricted box: linear values lose their quantity at the push, `heldAs` re-asserts at the pop; seven gaps, not three; tokens in frames need frames after counting); D32 corrected (`DiagnosticInfoStackSize` in process, `.stack_sizes` ELF-only; the runtime's frames exact from its bitcode; a build-time check: no non-`musttail` edge inside a cycle); D33 partly refuted; D34 corrected (decided before counting; case blocks emitted inside the parent); C4 corrected (associativity and identity suffice, no commutativity; `&&`, `||` need conditions; the countdown a closed form); C5 corrected (GMP is a separate library: the runtime's flag never reaches its `alloca`; the signal stack from the host). **A bug at HEAD**: idr-returned-arguments drops a tail callee's result but not the caller's, breaking the tail call (counterexample in the file). Improvements: `TailKind` on the call, no builder default, `tailcc` everywhere, `TailCallPlan`, `TailPosition`, `Frame.cpp` deleted; frames a D48 family with a linear frame-stack layout, the answer written through the base frame | Q1: the small computed stack charged at start, or committed page by page on fault for D35's letter? (recommends charged at start) |

## The owner's queue (consolidated, in order, one at a time)

Representation first:
1. (D63: a lifetime is an SSA value; the token is the arena handle where allocation needs it) Lifetimes: erased lifetime variables, and a separate run-time arena
   handle passed only to functions that allocate into a caller's
   lifetime (L05, L06, L02, L20 agree; amends D39's "a handle at run
   time").
2. (D88: uses × hold, hold = static | freed-by × sharing) The grade as quantity × hold (L05).
2b. (D89: specialize by hold, the marker the fallback) Static data reaching counted code: the runtime's static marker, or callees specialized by hold.
3. (D58: specialize by layout class) Fixed shapes meeting functions compiled for every index (L04 Q1).
4. (D59: yes) A run-time value in an index position keeps its link to the index (a
   Dependent ML singleton; L04 Q2, L20 I4, L20's D48 correction).
5. (D60: one key) Array shapes as D48 index terms (L12 OQ1).
6. (D61: yes) A per-parameter part of the effect row for writes through exclusive
   owned parameters (L02 Q2).
7. (D62: no) A grade richer than 0, 1, ω? (L20 Q4).
Promises:
8. (D70: own cells) The in-place obligation: the family's own cells, not whole-graph
   `excl` (L08 Q1); (D71: yes) `LArray` and `Linear.Vec` under D24 (L12 OQ2); the
   promise inside another linear value (L08 Q3; D72: yes).
9. (D73: reworded) D26's never-line as "no active call needs it after the call" (L08 Q2,
   L07); D26 on a path that ends the process (L07 Q1; D74: yes); its run-time check
   by a typed record from the checked runtime (L19 Q1; C138).
10. (D75: promised as written, optimized beyond) "A linear tail continuation is never allocated": promise or
    optimization (L09 Q1).
11. (D76: upstream's builtin `token`) D25's token (L09).
Runtime:
12. (D64: crash at the site) `exitWith` outside 0 to 255: a crash at the exit's site, not an
    internal error (L11 Q1; amends D37).
13. (D65: the kill point) A cgroup that may swap: end at the kill point (L11 Q2; amends D36).
14. (D66: at start) The small stack charged at start (L10 Q1; D35's letter).
The specification:
15. (D67: the manifest) D49's fingerprints in one committed manifest (L03 Q2).
16. (coordinator: L03 Q1 (B) and Q3 (A) taken; C6 withdrawn) One generic builder over the spec's op value (L03 Q1; against D50's
    reasoning; withdraws C6); the D51 backend printing the C++ table of
    admitted ops (L03 Q3).
The frontend and scope:
17. (D68: one stated trust in the fork) The normaliser's output against the template: a stated trust (L16 Q1).
18. (D69: both in, with their needs) 0011's O6, O7 and what they pull into P0 (L16 Q3).
Rust (0020):
19. (D92: its own runtime, IO only, no callbacks; the rest waits for 0020) Rust's stack and recursion through callbacks; a foreign destructor's
    timing; a by-value Rust move refused at compile time (L20 Q1 to Q3).
The compiler's build:
20. (D91: off everywhere, priced first by U8) Assertions in the shipped compiler (L15 OQ-1).
Optimization by search (owner, 2026-10-21: "we want to wring as much
perf as possible and nasty, ridiculous unintuitive optimizations ...
once we have the representation, the search could be trivial"):
21. (D57: e-graphs approved in principle; form and place researched) Reopen G's DP-25 ("equality saturation and static reflection are
    out"): search over the legal choices the representation exposes
    (an e-graph over our ops and upstream's, or bounded searches per
    decision), in P0 or after it.

From the integration (owner's, not yet asked):
22. (D77: no probes in compiled code) Stack probes on every function with a one-page guard (L10, L11)
    against D32's build-time frame check (C59 follows D32 for now).
23. (D78: deleted) Today's counted stack cell and its stack bit (L05 Q1).
24. (D79: a use that may still hold the value) How far the in-place promise reaches: every evaluated use, a
    borrowed read included (C90).
25. (D80: the name as data) 11 of 86 crash messages name a function, which D38's fixed cause
    cannot carry.
26. (C139: one decider, rewritten by passes that move calls, verified) D19's formation condition, and contification rewriting a tail fact
    against D30's "decided once".
27. (D81: flush, then die by SIGPIPE) A `SIGPIPE` ending missing from D37's table.
28. (D82: only to a form keeping every fact) D25's "ours moves to it" against D19.
29. (C142: amended in the same change) Amending 0018 (C22), 0017 (C104) and 0011's skip rule across
    proposals.
30. (D83: changed) AGENTS.md's megamorphic example (C67), the owner's text.
From the lifetime research (`design/lifetimes/static-handles.md`, D63):
31. (D93: the kind in the type, the source in the opener) Which op holds a lifetime's lowering class (nothing, a constant
    home, a frame block, a push on a per-computation lifetime stack
    beside D31's, a register-passed pointer): one op per class, as
    `memref.alloc` and `memref.alloca` (recommended).
32. (D94: the kind says whether; the amount on idr.func beside D61) Where the per-parameter "allocates into" fact lives (the function
    type, beside D61's per-parameter row part?).
33. (D96: no; every lifetime ends where it began) Handing a lifetime over at a tail call (not lexical).
34. (D90: names) Names: `lexical` for a value of a lifetime, `idr.frame` for this
    activation's lifetime (constraints.md).
35. (D95: reversed; per-level lifetimes split by packing) C84's ban on lifetimes spanning calls on a cycle, against
    static-handles' per-level lifetimes.
From the e-graph research (`design/egraph.md`):
36. (D84: shared rules and model, one small engine per side) How to read D69's "built once": one e-graph engine across the Idris
    and C++ sides cannot be built under AGENTS.md (a C export or foreign
    call; the two hosts) and sharing its state is unsound; built once:
    the rule language and its laws, the extraction model, the
    termination argument, the rules, shared fixtures; one small core per
    side.
37. (D85: full research form, one engine; researched in design/egraph-full/) Tier 1 in P0: the e-graph (Cranelift's acyclic form: rules once per
    node, capped, one scoped placement walk) as the one simplifier of
    `idr` functions before counting, replacing the greedy
    canonicalizer's redesign; tier 2 (Idris's proved theorems as rules,
    region terms, effect reordering, counting-aware extraction) after
    P0, each a measured cutover.
38. (D107: what O7 consumes, its union-find; D97 reversed) Whether R4 in P0 covers only what O7 consumes (its union-find).
Coordinator: §0, §1 and §9's stale text (three design documents, "the
Idris mirror").

Coordinator, by AGENTS.md or the owner's evident intent (to record):
family prefixes on every mnemonic (L13); rows cover their derivation
after every pass, equal it at re-derivation (L14); D53 refined to same
type constructor comparisons with constants by value (L17); a choice
among implementations the program fixes is a closed sum, not megamorphic
(L18 Q1, AGENTS.md's own definition); the knot rule over the label solve
of the program as written (L18 Q2); `idr.join` and `idr.loop` split
(L09).

## The reviewer (`review.md`)

Verdict: executable after named concrete prerequisites, two of them the
owner's. Claims 1 to 7 survive with prerequisites. D44 as staged is
broken: §7 has no stage for 0003 (62 items), 0011, 0010's A0, 0015's R1
and R2, two of which depend on outside engines (coordinator: stage them
under D56). D48's layout against its erased index parameters is queue
item 3 (`@map<n>` is one body; Θ(n²) code if specialized per index; a
conversion loses identity; an inline `Vect 100000` is 800 KB, past D32's
guard). D53 collapses numerals (`LTE 4 10` and `LTE 3 9` abstract alike;
upstream's `natToFinLT`, `libs/base/Data/Fin.idr:186-187`): numerals as
unary trees, a coordinator refinement beside L17's. D25: the encoding is
ours, and it contradicts match-and-counting §5.4's second tier. CSE is
the one upstream transform that reads the tree's disjointness; LICM moves
only pure ops. D30 against C1's bounded borrow and D39 regions around a
tail call. Packet: two design files read by no lane; `validate.sh` checks
a lane number, not the document; D53 to D55 in no lane's scope (L17 and
L06 were told). Thirteen disagreements tabled in the file.

## The lifetime research (`audits/p0/design/lifetimes/`)

- `static-handles.md`: a lifetime never needs a run-time identity (the
  closed program fixes which `idr.lifetime` site a token comes from; a
  put reaches only the newest open instance unless something inside the
  younger extent puts into the older token, a check local to each
  extent); the token lowers to nothing, a constant home, a frame block, a
  push on a per-computation lifetime stack beside D31's, or a
  register-passed pointer, decided by six linear passes, callees
  specialized by mode only (at most 4^k); never MLKit's run-time tests.
  Owner questions 31 to 33.
- `prior-art.md`: option A's run-time behaviour is where MLKit, Cyclone,
  Rust's arenas, linear regions and Gibbon all ended; B has no precedent.
  **Two wrinkles for D63**: the pinned builtin `token` cannot be a
  function argument or call operand and carries no run-time data, so a
  lifetime crossing a call needs our own type (D76's join tokens, local
  to a function, are unaffected); and keeping the lifetime out of the
  value's type cost Swift def-use-walking verification. Waiting on
  `constraints.md` (how the verifier checks without following def-use
  chains) before D63 is revisited, if it must be. Refinements for the
  owner: a callee putting a fixed number of cells into its caller's
  lifetime takes a destination (D34) instead of an arena; the arena
  handle linear, passed in and returned, so the bump pointer stays in
  registers.
- `constraints.md` (D63's form, designed): one parameterless type
  `!idr.lifetime`, its values from an `idr.lifetime` region's entry, an
  `idr.borrow` region's entry, `idr.frame` (this activation) and function
  parameters, never a result, yield, store or join parameter; a value's
  type says only `lexical`, its producer or binder names the lifetime
  (`in %l`), so finding a lifetime is one step and no check follows a
  def-use chain; outlives is dominance (the verifier's walk keeps a stack
  of open binders); a signature property says which lifetime each value
  parameter and result lives in, with declared bounds between lifetime
  parameters. `frame` leaves the grade (`idr.frame`'s value replaces it;
  `static` stays, `counted` implied by own/excl). `idr.lifetime` must
  not be an `AutomaticAllocationScope` (a slot inside it becomes a
  dynamic alloca, `Instructions.cpp:1324-1331`, breaking D32). Gaps:
  declared bounds between lifetime parameters; frame kinds holding
  lifetime fields; a borrowed view passable where an uncounted one is
  expected. **Upstream LLVM bug**: dead-argument elimination's `tailcc`
  exemption test is always true (`DeadArgumentElimination.cpp:640-641`),
  so under D30 no dead argument is removed: our lowering drops erased
  lifetimes itself, and the bug gets its carried patch (D25). D63's two
  wrinkles are closed: our own type crosses calls, and no def-use walk.
  Owner: names (`lexical`, `idr.frame`); C84's ban on lifetimes spanning
  cycle calls against static-handles' per-level lifetimes.

## To fold when all have returned

Coordinator items into §3 and §5; corrections of rulings' wording that
change no meaning, into §2 with the lane cited; owner questions, one at a
time.
