<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# What is owed acceptance

Every file below carries a `NEEDS-ACCEPTANCE:` line, written where nothing
is built: its expected output, or a property its RUN lines state, is
what the code should do, not yet what a build has shown it does. The line
says what to confirm. Accept a file on a build by confirming that, then
removing the line; an `expected` file whose first line is the mark is
replaced by the output, when the output says what the line asks.

The files are the tree's own list, `grep -rl NEEDS-ACCEPTANCE tests`
less this page, as it stood on 2026-10-18, each with its first mark as
its reason: 439 files. Proposal 0002's culls removed the marks of the
tests they deleted, and the tests it changed or wrote carry new ones. A
change that adds or removes a mark lists it here again.

## tests/accept (45)

- `tests/accept/action-after-effect/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/action-run-at-once/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/bounded-capped/expected`: that count, which builds n one constructor deeper below the two that Res inspects, is admitted by the growth check through its cap of 3, which the request-chain rule refused, and compiles and runs, its instances Z, S Z and S (S _); and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-dictionary-root/expected`: that describe, given Show Int as snd (MkPair () (dictOf Int ...)) and Show Bool through a let as dictOf Bool ..., is admitted by the growth check with each instance's node split by its dictionary's root, Show Int or Show Bool, never the written head snd or dictOf, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-family-applied/expected`: that W, whose family m is a lambda applied to x in T's static argument, is admitted with T's argument bounded by the lambda's body around x (beta at the instance), where the reading one level above x raised the growth check's internal error, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-family-head/expected`: that W, whose family m is the type constructor List applied to x in T's static argument, is admitted with W's node split by m's head, the applied family read as List applied, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-family-higher/expected`: that W, whose family m is a lambda applying its own family argument to Int and whose f is F, a definition given fewer arguments than it takes, is admitted with T's argument bounded by F's body around Int (each family read as its meaning, the argument applied to as many closed arguments as it takes), where the reading of F as one head raised the growth check's internal error, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-family-partial/expected`: that W, whose family m is F, a definition given fewer arguments than it takes, applied to x in T's static argument, is admitted with T's argument bounded by F's body around x (the family read as its meaning), where reading F as its key's one head raised the growth check's internal error, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-family-scope/expected`: that under, whose scope ns grows by one on every round under the family tm, whose value Tm erases its index, is admitted by the growth check, its node split by tm's head Tm so that ns keys nothing (the shape of the fork's getBinderUnder, which the per-definition reading refused), and compiles and runs, one instance of under; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-field/expected`: that Show (T nm), whose List (String, T nm) field is shown through Show (List a) and Show (a, b), is admitted by the growth check (a dispatch through a dictionary variable carries no arc), which the request-chain rule refused, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-grow-once/expected`: that Maybe at Entry and, inside Entry's fields, at (Bool, Nat) is admitted by the growth check (a constant written once is no arc), which the request-chain rule refused, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-grow-shrink/expected`: that up's S n into down and down's match on S m back into up, a cycle of +1 and -1, is admitted by the growth check, which the request-chain rule refused, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-method-own/expected`: that traverse over Either (List e) with Applicative IO, a method with a constraint of its own whose implementation's e is one List above main's message, is admitted by the growth check with the implementation's arguments carried to the method function's leading positions, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-method/expected`: that out at List Decl and, below it, at List (String, Term) is admitted by the growth check, each method request at its implementation's method function, which the request-chain rule refused, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/bounded-synonym/expected`: that a List (Nat, Vector1 a), Vector1 a a synonym for List1 (Nat, a), is admitted by the growth check with List1 and Pair at (Nat, a) built through the synonym, and compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/default-pragma/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/division/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/equality-proofs/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/erased-elem-later-match/expected`: that a match, after `Here`, on the erased index `Here` made the runtime field it was unified with reads that field, compiles and runs, printing 4; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/erased-elem-match/expected`: that a match of `Here` that makes an erased index the runtime field it was unified with reads that field, compiles and runs, printing 2; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/erased-field/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/erased-index-forced-index/expected`: that a clause whose runtime index end holds add start len, a term the unifier computed and Idris's tree never matches, still matches every input that reaches its leaf, so the leaf reads the erased index start as the runtime field the clause unified it with, in a clause and in a with block; that it compiles and runs, printing 10 twice; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/fib/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/fused-stored-string/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/higher-order-dictionary/expected`: that a user dictionary built by applying a function-valued argument to () is accepted as holding one implementation of Eq Int, compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/indexed-tags/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/linear-ambiguous-let/expected`: that a linear pattern let whose right side names an ambiguous function, which only the linear candidate fits, is accepted, compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/map-pair/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/named-implementations/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/nonterminating/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/pair-maybe/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/partial-application/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/partial-integer/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/partial-stream/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/polymorphic-recursion-swapped/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/recursive-string/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/runtime-partial-integer/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/runtime-partial-stream/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/show-dependent-pair/expected`: that showing a dependent pair, whose Show constraint reaches the instance as a function field applied past its arity, is accepted, compiles and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/static-integers/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/static-list/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/streams/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/totality-past-depth/expected`: that a recursion smaller only under six matching constructors is accepted as total with no pragma, and runs; and that what holds of every compilation holds of it (universal: holds)
- `tests/accept/unreachable/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/with-application-scope/expected`: that a with block called again from its right-hand side, from a local definition and from a record update is accepted, compiles and runs; and that what holds of every compilation holds of it (universal: holds)

## tests/bench (1)

- `tests/bench/smoke/expected`: that fannkuch-linear, qsort and unionfind, now the Linear.Vec programs, print the recorded outputs

## tests/compiler (5)

- `tests/compiler/dialect-syntax/expected`: the regenerated samples write, parse and reprint the same
- `tests/compiler/fork-loops-terminate/expected`: that the fork's size-change decision judges each component of Loops.idr as expected-stdout says, run through this script against the installed fork
- `tests/compiler/growth-check/expected`: that check agrees with brute force on every graph of Box.idr and gives each hand case the verdict expected-stdout says, built from compiler/src against the installed fork on Chez
- `tests/compiler/handoff-readable/expected`: how the printer writes an identified data type (an alias at the head of the module, whose body holds `instance`), which the instance check reads; and how it writes idr.program (`idr.program @<name> root(@<root>) stage(higher) {`), which the program check reads
- `tests/compiler/handoff-round-trip/expected`: the round trip of bench/rbtree, which replaced tests/programs/data/rbtree, and the fixtures named from the root

## tests/determinism (5)

- `tests/determinism/hello/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/leet-rotate/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/rbtree/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process; and that it holds of bench/rbtree, which it now compiles
- `tests/determinism/shapes/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/threads-rbtree/expected`: that bench/rbtree, which this now compiles, gives the same module, statistics and remarks under one thread and under many

## tests/fuzz (3)

- `tests/fuzz/seed-1/expected`: the goldens are gone; confirm the eight property lines hold for both seeds on both targets
- `tests/fuzz/seed-2/expected`: the goldens are gone; confirm the eight property lines hold for both seeds on both targets
- `tests/fuzz/two-hosts/expected`: idris-mlir compiles Gen, Prims, Fuzz, Sem and TwoLevels, and its program prints the committed expected-stdout byte for byte (the generators' text for the seeded requests twoHosts names, each Gen check ok), a draw's loop and a tape's reset reusing their cells in place; the limits measured

## tests/idr/actions (10)

- `tests/idr/actions/accumulate.mlir`: that skipping every idr-accumulate-countdown and idr-accumulate-clone action leaves the module as idr-accumulate received it, and that idr-accumulate changes it otherwise.
- `tests/idr/actions/columns.mlir`: that skipping every idr-columns-convert action leaves the module as idr-columns received it, and that idr-columns changes it otherwise.
- `tests/idr/actions/deduplicate.mlir`: that skipping every idr-deduplicate-merge action leaves the module as idr-deduplicate received it, and that idr-deduplicate changes it otherwise.
- `tests/idr/actions/inner-steps.mlir`: that the root, now the IO root the root rule admits (it prints what it computed), keeps every action of idr-optimize seen at least once. (and 1 more marks in the file)
- `tests/idr/actions/narrow-lanes.mlir`: that skipping every idr-narrow-lanes-version action leaves the module as idr-narrow-lanes received it, and that idr-narrow-lanes changes it otherwise.
- `tests/idr/actions/narrow.mlir`: that skipping every idr-narrow-version, idr-narrow-joint, idr-narrow-word and idr-narrow-fold action leaves the module as idr-narrow received it, and that idr-narrow changes it otherwise.
- `tests/idr/actions/returned-arguments.mlir`: that skipping every idr-returned-arguments-drop action leaves the module as idr-returned-arguments received it, and that idr-returned-arguments changes it otherwise.
- `tests/idr/actions/stack.mlir`: that skipping every idr-stack-cell action leaves the module as idr-rc-stack received it from idr-rc-cells, and that idr-rc-stack changes it otherwise.
- `tests/idr/actions/tail-loops.mlir`: that the root, now the IO root the root rule admits (it prints what it computed), keeps the loops and the actions as before. (and 1 more marks in the file)
- `tests/idr/actions/trmc.mlir`: that the owned-stage input, its boxes now idr.cell.new and idr.cell.init, keeps the actions as before. (and 1 more marks in the file)

## tests/idr/arrays (4)

- `tests/idr/arrays/byte-buffer.mlir`: idr.io.buffer_load of an array of i32 a world orders is refused by its buffer operand's constraint (Idr_ByteBuffer), whose message names the type given; a buffer of i8 is accepted.
- `tests/idr/arrays/closure-linear.mlir`: a closure capturing a linear value whose result is plain is refused by the closure's rule (a PredOpTrait), in ODS's words; one whose result is at quantity one is accepted and applied with no idr.lin.use first.
- `tests/idr/arrays/delay-world.mlir`: idr.delay of the world is refused by its operand's constraint (Idr_Capture), whose message names the world's type.
- `tests/idr/arrays/yield-parent.mlir`: idr.array.yield in a region of an op that holds no YieldTargetsOpInterface is refused by the yield's parent rule (a PredOpTrait), in ODS's words, before anything asks it what it forwards.

## tests/idr/asm (3)

- `tests/idr/asm/aliases.mlir`: that the aliases hold with each constant written with its type first, and that the signatures, the field read and the borrowed Nil constant are checked at the grades the printer writes, each data type by its alias inside the grade. (and 2 more marks in the file)
- `tests/idr/asm/names.mlir`: that the printer's names hold with each constant written with its type first. (and 1 more marks in the file)
- `tests/idr/asm/prefix.mlir`: that the prefix rule holds with the match's default region binding its scrutinee and the signed output op named put_sint.

## tests/idr/bufferize (8)

- `tests/idr/bufferize/aliasing.mlir`: the analysis of released buffers and of call results: each function marked to copy writes a copy, and @fresh writes in place.
- `tests/idr/bufferize/linear-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/link-read-after-release.mlir`: that idr-bufferize copies at the release.
- `tests/idr/bufferize/pop-box.mlir`: that a pop's read of its last element and the write of the fill behind it become one idr.element.update on the vector's buffer, written in place.
- `tests/idr/bufferize/recursive-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/recursive-value.mlir`: that the boundary analysis settles the cycle of @go's calls, so its result is no copy at any level of the recursion.
- `tests/idr/bufferize/release-constant.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/release-copies.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.

## tests/idr/canon (8)

- `tests/idr/canon/apply.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/array-moves.mlir`: that the element moves out across the call of the pure @bump under idr-optimize and under upstream's canonicalize after idr-effects, which writes the call its callee's effects, and not across a call no pass has given effects; and that under idr-optimize it stays read across output, a call that performs IO, a write in another block, and in a word.
- `tests/idr/canon/evaluated-memo.mlir`: that the force became a call of the sum's dispatch, so no force is left.
- `tests/idr/canon/facts.mlir`: @applies declares every effect, as the verifier's effect rule asks of a function that applies a closure; the canonicalizer's answers are unchanged. (and 1 more marks in the file)
- `tests/idr/canon/match-known.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/match-regions.mlir`: a match's default region is first and binds the scrutinee (S2): two defaults ("expected '}'"), a default without its argument ("expected '('"), a default that binds another type ("expects a default region that takes the scrutinee back at its type") and `cases` in the attribute dictionary ("inherent attribute 'cases' cannot be parsed from attr-dict") are refused; an exhaustive idr.match, whose default is empty, merges its two equal cases into a default that binds the scrutinee, and its field read moves into its regions (case-of-case), under upstream's canonicalize with region simplification disabled.
- `tests/idr/canon/output-fusion.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/record-eta.mlir`: syntax swept to the data-type-first form

## tests/idr/contify (2)

- `tests/idr/contify/contify.mlir`: that before idr-contify the property reports @step.case1 at its one call (mlir-22), and that idr-contify, taking cycles of calls from CallCycles (S13), moves it into @step; the second RUN writes no module (S2's default argument).
- `tests/idr/contify/never-returns-twice.mlir`: that idr-contify moves both continuations into @loop, the second into the block the first left unreachable, and erases that block once the sweep ends, so @loop is one block the verifier after the pass accepts, its return gone with the rest (S5, ir-verify-1).

## tests/idr/contracts (4)

- `tests/idr/contracts/break-linear.mlir`: that --idr-contracts names the pass that gives a linear result back unrestricted, at the function (the pass as its textual pipeline writes it, its option included), while the module stays valid, and that the same pass passes with the contracts off.
- `tests/idr/contracts/break.mlir`: that --idr-contracts names the pass that widens a function's effects, at each function it widened (the pass as its textual pipeline writes it, its option included), while the module stays valid; that the same pass passes with the contracts off; and that idr-effects, which narrows nothing here, keeps them.
- `tests/idr/contracts/crash-sites.mlir`: that --idr-contracts reports crash-sites-not-added at @f, a function the pass kept that could not crash and now may, although a lambda of f's definition (@lam, located loc("f")) answers to f too, which made the base skip @f; that effects-not-widened is reported there as well, and nowhere else; and that the same pipeline passes with the contracts off.
- `tests/idr/contracts/nested-run.mlir`: that idr-rc keeps its contracts under --idr-contracts, step by step: idr-rc-exclusive commits the grades it wrote through its own pipeline, on its own op, and that run is part of its run, not checked against the program; and that this module parses with its constant written type first.

## tests/idr/dedup (3)

- `tests/idr/dedup/keep-apart.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)`, `idr.io.put_sint` for the signed `put_int` and a function's effects as the property printed before its symbol), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/dedup/merge-named.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/dedup/merge.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)

## tests/idr/defunc (23)

- `tests/idr/defunc/choice.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/coerce.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/cycle.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/evaluated-coerced.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/evaluated-keyed.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/force-call.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/growing-lazy.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/growing.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/ioref-closure.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/lazy-choice.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/lazy.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/many-labels.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/match-field.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/memo-by-name.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int` and `idr.constant` writing its type first), parses and passes as before.
- `tests/idr/defunc/memo-forced-join.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/memo-rebuild.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/memo-sum.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
- `tests/idr/defunc/nested-sum-failure.mlir`: that idr-defunctionalize reports exactly this one internal error at an unknown location and stops cleanly, where the base handed a null data type to the outer sum's body and crashed.
- `tests/idr/defunc/state.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)`, `idr.io.put_sint` for the signed `put_int` and `idr.constant` writing its type first), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/sum-names.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/tag-limit.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/unreached-cell.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.constant` writing its type first), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/defunc/untaken-region.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)`), parses and passes as before.

## tests/idr/e2e (11)

- `tests/idr/e2e/crash-callsite.mlir`: that a crash at a call site whose callee is unknown names its caller's file, line and column, as the report names the place of such a location.
- `tests/idr/e2e/crash.mlir`: that each match's default region, which binds the scrutinee now, parses and lowers, and that the program's output is as before.
- `tests/idr/e2e/doubles.mlir`: that idr.io.put_sint writes what idr.io.put_int signed wrote, and that the program's output is as before.
- `tests/idr/e2e/eval.mlir`: the program compiles and prints its value without dumps. (and 1 more marks in the file)
- `tests/idr/e2e/even-group.mlir`: that a heap cell of a sum's third group, whose group number is even, is matched and freed without the runtime reading its group word as a reference, beside a cell of the first group and one of the second. (and 1 more marks in the file)
- `tests/idr/e2e/hello.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)
- `tests/idr/e2e/loops.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)
- `tests/idr/e2e/partial-loop.mlir`: that each match's default region, which binds the scrutinee now, parses and lowers, and that the program's output is as before.
- `tests/idr/e2e/put-list.mlir`: that each match's default region, which binds the scrutinee now, parses and lowers, that idr.io.put_sint writes what idr.io.put_int signed wrote, and that the program's output is as before.
- `tests/idr/e2e/statics.mlir`: that each match's default region, which binds the scrutinee now, parses and lowers, that idr.io.put_sint writes what idr.io.put_int signed wrote, and that the program's output is as before.
- `tests/idr/e2e/strings.mlir`: that each match's default region, which binds the scrutinee now, parses and lowers, that idr.io.put_sint writes what idr.io.put_int signed wrote, and that the program's output is as before.

## tests/idr/effects (12)

- `tests/idr/effects/alloc.mlir`: each op's answers, which test-idr-facts reports, are its own declared effects; check each mark against them.
- `tests/idr/effects/call-effects.mlir`: that idr-effects writes each call's effects with its callee's, that a call then answers from them, and that canonicalize and CSE drop and merge the calls of functions that only compute and keep every other.
- `tests/idr/effects/crash-call.mlir`: that a call of a function whose only effect is crash declares what an inline crash declares, the IO write among it, so both answer alike and both stay before the output that follows them.
- `tests/idr/effects/crash.mlir`: the constants written type first, as idr.constant now reads them; the crashes and guards as before.
- `tests/idr/effects/div.mlir`: each op's answers, reported by test-idr-facts, are those its marks state.
- `tests/idr/effects/force-strict.mlir`: the effects idr.force declares before defunctionalization, as test-idr-facts reports what it answers.
- `tests/idr/effects/forced-labels.mlir`: that idr-defunctionalize turns each force into a call of its memo sum's dispatch and marks the labels by_name as the effects say.
- `tests/idr/effects/idr-effects.mlir`: syntax swept to the data-type-first form
- `tests/idr/effects/io.mlir`: each IO op's answers, reported by test-idr-facts, are none.
- `tests/idr/effects/long-cycle.mlir`: that idr-effects reaches every member of a cycle of 3,001 functions with the crash of one, within the suite's time bound.
- `tests/idr/effects/memo-label.mlir`: the dispatch idr-defunctionalize makes of a memo sum and the syntax of idr.memo.enter and idr.memo.settle.
- `tests/idr/effects/queries.mlir`: that each op answers drop, move, delay and merge from its own effects, a call from the effects idr-effects wrote on it, and a match from its regions', an arm that ends in ub.unreachable doing nothing more than what runs before it.

## tests/idr/expect (48)

- `tests/idr/expect/allocation.mlir`: that the -verify-diagnostics run passes: no-heap-allocation, stated of @boxes and of the whole module, reports the idr.con of @cons, which @boxes calls, each request once at that op (one expectation takes both), and nothing else.
- `tests/idr/expect/apart.mlir`: that apart holds of two functions made from code of their own, and that the -verify-diagnostics run passes: apart fails once, at @merged, whose location fuses both names and so has no place in the file (@unknown).
- `tests/idr/expect/by-name.mlir`: that by-name and not-by-name read the memo labels of a sum a parameter holds (the label written in the data type's body as this wave prints a role), and that the -verify-diagnostics run passes: one error each where the label's flag is the other, and one where no label names the function, all at the module.
- `tests/idr/expect/calls.mlir`: that the -verify-diagnostics run passes: each failing request of Calls.cpp reports exactly the one error expected, at the call or the function it names; idr.apply is the call through a value.
- `tests/idr/expect/closures.mlir`: that labels reads the sum of labels at @pick's result and holds of the labels it runs, and no-closures of @pick, whose sum of labels is no closure; that the module parses with the closure constant written type first; and that the -verify-diagnostics run passes: one error at each closure left and one at @pick, whose sum runs more than the list of one names.
- `tests/idr/expect/computes-nothing.mlir`: that computes-nothing holds of a function of a guard and of one of a crash, and that the -verify-diagnostics run passes: one error, at the one op of @computes that computes a value.
- `tests/idr/expect/constant-stack.mlir`: that constant-stack and tail-calls hold of @loop, which calls itself back by a musttail call alone, and that the -verify-diagnostics run passes: one error each where a call keeps its frame or none is made.
- `tests/idr/expect/continuations.mlir`: that the module parses with its defaults binding the scrutinee, and that the -verify-diagnostics run passes: contified fails once, at the one call of @step.case, and not of @count, a recursion that is one function.
- `tests/idr/expect/counted-loop.mlir`: that counted-loop holds of an scf.for, and that the -verify-diagnostics run passes: one error at the scf.while of @tested and one at @straight, which has no loop.
- `tests/idr/expect/counting.mlir`: that the module parses in this wave's printed forms (constants written type first, a default binding the scrutinee), and that the -verify-diagnostics run after idr-rc passes: the idr.cell.init idr-rc's cells step makes of @build's cons, which takes the con's place and location, builds in a fresh cell; @build and @both build in no recycled cell; and the one idr.dup in @both, placed at the con that takes %a twice, is the only count left there (its parameter %b read alone, borrowed, is never dropped). (and 2 more marks in the file)
- `tests/idr/expect/coverage/expected`: that every property's failing fixture is found, folds-balanced aside
- `tests/idr/expect/crash-sites.mlir`: that crash-sites counts a guard and a crash as one place each and nothing else, and that the -verify-diagnostics run passes: one error for each function given another count.
- `tests/idr/expect/dims-known.mlir`: that dims-known holds of the extent of an array a function is given, and that the -verify-diagnostics run passes: one error, at the memref.dim of the array @made made.
- `tests/idr/expect/does.mlir`: that each of Does.cpp's properties holds of the function that does what it says, that the module parses with @takes' default binding the scrutinee, and that the -verify-diagnostics run passes: each fails once on its complement.
- `tests/idr/expect/facts.mlir`: that test-idr-facts reports each op's answers at the op, none of the four for an output and all four for a call idr-effects proved pure; and that the second run fails only because canonicalize erases that unused call before the report, so its expected remark is never produced ("expected remark ... was not produced").
- `tests/idr/expect/folded.mlir`: that folded holds of every function once --canonicalize has folded the arithmetic over constants, and that the -verify-diagnostics run passes: one error, of @left as written, at its arith.addi of two constants.
- `tests/idr/expect/fused.mlir`: that fused holds of one loop, of two loops once upstream's elementwise fusion has made them one, and of an array two loops read, and that the -verify-diagnostics run passes: one error at @two's first linalg.generic and one at @none, which has no structured op.
- `tests/idr/expect/growth.mlir`: that grows-nothing holds of @f against the module itself, and that the -verify-diagnostics run passes: one error, at @f, against the smaller @f pulled out of the SMALL lines, a module that holds no expectation of its own.
- `tests/idr/expect/guards.mlir`: that the -verify-diagnostics run passes: no-guards fails exactly at the one guard @kept keeps.
- `tests/idr/expect/in-place.mlir`: that idr::bufferize::copies answers for this copy into a fresh memref.alloc, and that the -verify-diagnostics run passes: in-place fails at @copied's memref.copy and at @none, which holds no buffer.
- `tests/idr/expect/largest-function.mlir`: that the run of the bounds 4 and `many` passes under -verify-diagnostics: @big past 4 at @big, @small not, and `many` refused at the request, at the module (line 0, the implicit module's location), in the one wording of a malformed argument.
- `tests/idr/expect/linker-names.mlir`: that the -verify-diagnostics run passes: linker-names fails at the symbol with a `-` in it, and at no other.
- `tests/idr/expect/lowered.mlir`: that lowered holds of an llvm.func, and that the -verify-diagnostics run passes: lowered fails at the declaration whose signature takes the world, and in-llvm at the func.func left and nowhere in the llvm.func.
- `tests/idr/expect/malformed.mlir`: that each request whose argument does not have its property's shape is refused once, at the module (line 0, the implicit module's location), in the one wording `idr-expect: <name>=<text> does not read as <name>=<form>`, the next request still read, and the run passes under -verify-diagnostics.
- `tests/idr/expect/memory.mlir`: that the -verify-diagnostics run passes: aligned-access fails at the llvm.load that states no alignment, and reads-nothing and writes-nothing at the load and the store through a pointer parameter.
- `tests/idr/expect/moves-out.mlir`: that moves-out holds of an idr.array.update, and that the -verify-diagnostics run passes: it fails at @readWrite, which reads the element and writes it back as two accesses.
- `tests/idr/expect/narrowed-lanes.mlir`: that narrowed-lanes holds of a loop computing on 32-bit lanes beside its accumulation, and that the -verify-diagnostics run passes: it fails at @scalar, which has no loop on lanes at all, on any target.
- `tests/idr/expect/not-called.mlir`: that not-called holds of @gone, and that the -verify-diagnostics run passes: it fails at the call of @kept and at the call of a copy of Prog.twice.
- `tests/idr/expect/one-clone-two-copies.mlir`: that the -verify-diagnostics run passes: one-clone fails, at the module, of calls of @iter that reach two copies of it.
- `tests/idr/expect/one-clone.mlir`: that one-clone and specialized-once hold of @iter's one copy, which calls only itself, and that the -verify-diagnostics run passes: one-clone fails, at the module, of @loop, which nothing calls, and specialized-once at the call in @walk$a, the copy of walk that calls another copy.
- `tests/idr/expect/output-fused.mlir`: that output-fused holds of a written constant, and that the -verify-diagnostics run passes: it fails at the idr.io.put_str of a string built only to be written.
- `tests/idr/expect/paths.mlir`: that this module parses with the match's default binding its scrutinee, that loops counts @sum's one loop and @line's none, and that the -verify-diagnostics run passes: loops fails at @sum and @line for the counts they do not have, and straight-line at the match of @choose.
- `tests/idr/expect/placement.mlir`: that this module parses with each match's default binding its scrutinee, that each of Placement.cpp's properties holds of the functions that place their work on the paths that need it, and that the -verify-diagnostics run passes: each fails at the op its comment names, in each function that does not.
- `tests/idr/expect/proved.mlir`: that total and not-total read the function's own `total` fact, and that the -verify-diagnostics run passes: each fails at the function that holds the other.
- `tests/idr/expect/quantities.mlir`: that quantities-kept holds of the module against itself and against it without @build.trmc, and that each -verify-diagnostics run over a variant passes: widened, bound, lambda and span each fail at the binders the variant changed, the span's error located at @wide's own line once its sed names the variant's file in @wide's spans.
- `tests/idr/expect/reaches.mlir`: that reaches follows calls from body to body to @leaf, two steps from @top, and that the -verify-diagnostics run passes: it fails at @top for @apart, which nothing @top calls names.
- `tests/idr/expect/resets-unshared.mlir`: that this owned module, in this wave's printed forms (the take with its token, idr.cell.recycle and idr.cell.init, a default that binds the scrutinee), verifies as written, and that the -verify-diagnostics run passes.
- `tests/idr/expect/returns.mlir`: that returns, returns-argument and returns-on-paths hold of what each function returns and that the -verify-diagnostics run passes: one error for each result misstated, returns-on-paths one for the constant not written and one for the written one on no path; the default of @choice binds its scrutinee (this wave's printed form).
- `tests/idr/expect/reuses-every-cell.mlir`: that this owned module, in this wave's printed forms (the take with its token, idr.cell.recycle and idr.cell.init, a default that binds the scrutinee), verifies as written, and that the -verify-diagnostics run passes.
- `tests/idr/expect/signature.mlir`: that the -verify-diagnostics run passes: signature and convention each fail at each function given another type or convention, or no convention to have, and entry only at the second public function, @main being of the C entry's type.
- `tests/idr/expect/solved-effects.mlir`: that effects reads each function's declared set, which covers its body as the program's verifier asks, written as this wave prints a function's effects (`idr.func effects<...> @f`); and that the -verify-diagnostics run passes, one error at each function given another set.
- `tests/idr/expect/stage.mlir`: that stage holds of the stage the program says, and that the -verify-diagnostics run passes, one error at the program for another stage.
- `tests/idr/expect/structured-loops.mlir`: that structured-loops holds of @done and @ordered, and that the -verify-diagnostics run passes: @left fails at its idr.tabulate beside a linalg op, and @none, which holds no structured op, at the function.
- `tests/idr/expect/tests-nothing.mlir`: that this owned module, in this wave's printed forms, verifies as written, the recycle of @exclusive's exclusive token included (the base could not parse it); and that the -verify-diagnostics run passes.
- `tests/idr/expect/typed-reads.mlir`: that typed-reads holds of @typed, and that the -verify-diagnostics run passes: @guarded fails at its tensor.extract of a checked index, and @none, which accesses no tensor, at the function.
- `tests/idr/expect/unknown.mlir`: that each unknown name is refused once, at the module (line 0, the implicit module's location, written @-n from each annotation's own line), and the run passes under -verify-diagnostics.
- `tests/idr/expect/vectorized.mlir`: that vectorized holds of a function computing on vectors, and that the -verify-diagnostics run passes: @scalar fails at its scalar linalg.generic over words, and at the function for computing on no vector at all.
- `tests/idr/expect/words.mlir`: that word-loop holds of a loop on words, that the constant prints in this wave's form (`idr.constant T <attr>`), and that the -verify-diagnostics run passes: @naturals, whose one loop carries a natural, fails at the function.

## tests/idr/fold (16)

- `tests/idr/fold/add-zero.mlir`: a sum with zero folds to its other operand on either side, of Integers and of naturals; the property fails where idr.big.add folds only constant pairs.
- `tests/idr/fold/array-dim.mlir`: the dimensions still fold with the program rooted at a status root, @root, which none of the functions under test is part of.
- `tests/idr/fold/balanced.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before.
- `tests/idr/fold/big-shift.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before.
- `tests/idr/fold/closure.mlir`: how a closure constant prints (#idr.closure<@add, [5]>), which the property reads back
- `tests/idr/fold/data.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before. (and 2 more marks in the file)
- `tests/idr/fold/division.mlir`: the signed and unsigned division ops, idr.divs, idr.mods and idr.divu, fold to the same values as the flagged ops did, and a division by zero still does not fold.
- `tests/idr/fold/nat.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before.
- `tests/idr/fold/pending.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before. (and 2 more marks in the file)
- `tests/idr/fold/poison-fields.mlir`: the module only the deleted folds read is gone; the program is read directly, and defunctionalizes and lowers with and without the canonicalizer.
- `tests/idr/fold/pred.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before.
- `tests/idr/fold/range.mlir`: idr.to_char_s, idr.int_head_s and idr.int_head_u state the ranges the flagged ops did.
- `tests/idr/fold/shift.mlir`: the signed and unsigned shift ops, idr.shls, idr.shrs, idr.shlu and idr.shru, fold to the same values as the flagged ops did, and a shift by 0 is its value.
- `tests/idr/fold/string-offsets.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before. (and 1 more marks in the file)
- `tests/idr/fold/strings.mlir`: each constant written with its type first, idr.constant <type> <value>, folds and is read back as before. (and 1 more marks in the file)
- `tests/idr/fold/to-char.mlir`: idr.to_char_s and idr.to_char_u fold to the same characters as the flagged op did.

## tests/idr/func (5)

- `tests/idr/func/call-effects-contain.mlir`: that a call whose effects lack a bit of its callee's is refused, naming the call and the bits; that one holding more is accepted; and that `effects<crash, diverge>` round-trips bare.
- `tests/idr/func/call-effects-cse.mlir`: that upstream's canonicalize and CSE, on a function, erase an unused call of a pure callee and merge two equal ones, and keep two equal calls that each give a fresh linear value.
- `tests/idr/func/call-effects.mlir`: that a call answers drop, move, delay and merge from the effects it holds, the default everything, and never from its callee's.
- `tests/idr/func/linear-twice.mlir`: the grade refused on the world, which is linear by its own type; a closure of a linear capture linear by its type; and the linear rule's errors.
- `tests/idr/func/two-blocks.mlir`: that idr.func's region constraint refuses a body of two blocks and a function with no body, with upstream's text.

## tests/idr/guards (1)

- `tests/idr/guards/fold-unguarded.mlir`: each op stays unfolded by guardHolds alone

## tests/idr/identity (1)

- `tests/idr/identity/identity.mlir`: that idr-identity, the first step of each function's cleanup, rewrites the calls of each recursive function that gives back its argument, as the identities are solved per component; and that not-called reports each call of @loops, @drift and @flip left, at the line of the call as written (an inlined call keeps its own line), once @main and @leans are inlined and symbol-dce has taken them; the root is an IO root S38 admits, which hands every result to @observe (S2's default argument, ir-ods-8's type-first constant).

## tests/idr/loops (4)

- `tests/idr/loops/accumulate.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool.
- `tests/idr/loops/tail-loop.mlir`: that the root, now the IO root the root rule admits (it prints what it computed), keeps every loop and counted loop as before. (and 1 more marks in the file)
- `tests/idr/loops/trmc-counter.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/loops/trmc.mlir`: that the owned-stage input, its boxes now idr.cell.new and idr.cell.init, gives idr-trmc's clone of @copy and @copyLin, each a loop after idr-tail-loops, and leaves @depth's call. (and 2 more marks in the file)

## tests/idr/lower (29)

- `tests/idr/lower/arrays.mlir`: the lowered signatures, the components of an array at a function boundary (the cell, then its dynamic sizes; a rank-0 array is its cell alone), with the runtime's symbols named as idris_rt.h declares them.
- `tests/idr/lower/atom-unfolded.mlir`: that a nullary boxed constructor reaching idr-lower unfolded lowers to its static atom and its unpack to nothing, so @atom asks the runtime for nothing.
- `tests/idr/lower/atom.mlir`: a nullary boxed constructor taken after idr-rc allocates nothing: idr-rc leaves the atom's idr.con a con, which lowers to the atom's static cell, and its take is an idr.unpack, which frees nothing (§7, ir-ops-6; S4). At the base @nil allocates a cell its take never frees.
- `tests/idr/lower/big-fast-path.mlir`: that a program whose big operands are small by construction imports nothing of the runtime's big functions, its small cases inline, and that one on bigs of any size imports the add's large case, rt::big::addLarge, and not the add's entry.
- `tests/idr/lower/box.mlir`: the match's default binds its scrutinee (S2); the lowered checks are as before. (and 1 more marks in the file)
- `tests/idr/lower/buffer.mlir`: the runtime's copy takes each buffer as its cell alone (driver-runtime-T2), and a word's address is upstream's strided address over the buffer's descriptor (mlir-15); the calls are as before.
- `tests/idr/lower/cells.mlir`: each producer of a cell lowers alone, writing the header, and idr.cell.init writes the fields (S3): a fresh cell is the runtime's, a frame's cell an alloca, a recycle of an exclusive token its cell with no test, and a recycle of a shared token its cell or a fresh one when it is null.
- `tests/idr/lower/closure-left.mlir`: the texts of the stage errors, and the op each is reported at.
- `tests/idr/lower/constants.mlir`: the lowered type of @values, Num as its tag and one slot for each constructor's field, as data-layout.mlir lays a sum out. (and 1 more marks in the file)
- `tests/idr/lower/counting.mlir`: the constructor that builds a cell is an idr.cell.new and its idr.cell.init, and the reuse an idr.cell.recycle of the take's token and its init (S3); each match's default binds its scrutinee (S2). (and 1 more marks in the file)
- `tests/idr/lower/crash.mlir`: the match's default binds its scrutinee (S2); the crash sites are as before. (and 1 more marks in the file)
- `tests/idr/lower/entry.mlir`: the entry body and the release function have their reserved names (S30); the third program, the frontend's IO root `(!idr.world) -> !IORes`, lowers to `() -> ()` and its entry body returns 0 (conversion-8, S38).
- `tests/idr/lower/exclusive.mlir`: a recycle of an exclusive token parses (the base could not parse this file) and lowers to the token's cell with no test; a recycle of an owned token tests it for null (S3).
- `tests/idr/lower/force-by-name.mlir`: the memo cell is an idr.cell.new and its idr.cell.init (S3); the lowered calls are as before. (and 1 more marks in the file)
- `tests/idr/lower/force-excl.mlir`: the memo cell is an idr.cell.new and its idr.cell.init, its box written exclusive (S3); the lowered calls are as before. (and 2 more marks in the file)
- `tests/idr/lower/force-view.mlir`: the memo cell is an idr.cell.new and its idr.cell.init (S3); the lowered calls are as before. (and 1 more marks in the file)
- `tests/idr/lower/internal-errors.mlir`: the target case alone, its message as before; the over-aligned buffer is the program's verifier's case now (tests/idr/verify), no longer the lowering's (conversion-14).
- `tests/idr/lower/io.mlir`: the entry body and the release function have their reserved names (S30); the calls are as before.
- `tests/idr/lower/layout.mlir`: that each program lowers, as the layout lifts the limits: a cell of more counted references than its header counts holds a count word after the header, and a sum of more constructors than a tag counts is a two-level sum.
- `tests/idr/lower/linear-constant.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/llvm-facts.mlir`: @unread, whose box parameter one call passes poison, holds the three pointer facts (none at the base): the poison is the static cell `nothing`; the facts of the other functions are unchanged, now written by the signature conversion (mlir-16, conversion-5). (and 2 more marks in the file)
- `tests/idr/lower/match-lit.mlir`: each default binds its scrutinee (S2); @empty, a string match with only a default, lowers to its default's body with no scf.index_switch (conversion-10). (and 1 more marks in the file)
- `tests/idr/lower/nat.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/static-thunk.mlir`: the release function has its reserved name (S30), and the static cells are written by the one walk that names them, with the same contents (conversion-9). (and 3 more marks in the file)
- `tests/idr/lower/strided-symbol.mlir`: a memref whose layout is an affine map with a symbol carries the stride its map leaves dynamic as a component of its own, as a strided layout would: every walk of its descriptor reads one plan (conversion-3, §7). At the base the affine map gets no stride word, and unpacking the parameter reads past its components.
- `tests/idr/lower/string-build.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/strings-bigs.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/to-llvm.mlir`: the memo cell is an idr.cell.new and its idr.cell.init (S3); upstream still takes the program to the LLVM dialect alone. (and 2 more marks in the file)
- `tests/idr/lower/value-buffers.mlir`: each element of a buffer is addressed by upstream's strided address over its descriptor (mlir-15); the calls are as before. (and 2 more marks in the file)

## tests/idr/names (3)

- `tests/idr/names/edit.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 2 more marks in the file)
- `tests/idr/names/reorder.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 2 more marks in the file)
- `tests/idr/names/reserved.mlir`: that functions the program names as the entry body and the release function were once named lower beside the compiler's own, which the root's entry body calls.

## tests/idr/narrow (3)

- `tests/idr/narrow/descending.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.constant` writing its type first), parses and passes as before. (and 1 more marks in the file)
- `tests/idr/narrow/select-lanes.mlir`: that idr-narrow-lanes leaves this loop as it is, with no version (the base versions it, a select of 64-bit lanes counting there as a wide lane op), and that narrowed-lanes holds of it.
- `tests/idr/narrow/versioned.mlir`: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)`), parses and passes as before. (and 1 more marks in the file)

## tests/idr/obs (12)

- `tests/idr/obs/bitcode-section-option.mlir`: --runtime-bitcode-section is no option of idris-mlir: exit 2, LLVM's unknown-argument error, no object; where the prepared runtime keeps its bitcode is the target entry's, and a compilation reads it off the runtime.
- `tests/idr/obs/debug-counter.mlir`: RUN 1 writes no module now; the counter's report is unchanged.
- `tests/idr/obs/foreign-pass-name.mlir`: -mlir-print-ir-after names only a pass the compiler registers: gpu-kernel-outlining, which it never runs, is LLVM's unknown value, exit 2, no object.
- `tests/idr/obs/lowered-input.mlir`: idris-mlir takes the pipeline's output and runs only LLVM's half on it; the program exits 42.
- `tests/idr/obs/lowered-mixed.mlir`: a module with no idr.program holding a non-LLVM op is refused at that op, naming it, exit 1, verdict internal; so is a func.func module, at its func.func.
- `tests/idr/obs/lowered-untargeted.mlir`: a module of the LLVM dialect alone that names no #llvm.target is refused at the module, naming what it lacks: exit 1, verdict internal, no object; never the compiler's "lost its #llvm.target".
- `tests/idr/obs/print-ir-threads.mlir`: -mlir-print-ir-module-scope without --mlir-disable-threading is a usage error of the command line's: exit 2 with MLIR's reason, no report and no object.
- `tests/idr/obs/print-with-object.mlir`: a --print option with an option of a compilation is a usage error: exit 2, naming the option; alone it answers.
- `tests/idr/obs/report-accepted.mlir`: an accepted compilation's report: verdict accepted, no diagnostic, idr-optimize's statistics in bytewise key order, the same bytes at 1, 3, 5 and 13 threads.
- `tests/idr/obs/report-link-failure.mlir`: a compilation whose --runtime names no file fails as the compiler's: exit 1, stderr idris-mlir: internal error: with the reason, a report of verdict internal with the error's diagnostic line, and no object.
- `tests/idr/obs/report-refused.mlir`: a refusal by the parse's verifier exits 3 and the report says refused, with the rule, file and line.
- `tests/idr/obs/stats.mlir`: the statistics' descriptions.

## tests/idr/optimize (7)

- `tests/idr/optimize/caller-cap.mlir`: the chain's sizes against the cap as idr::inlineSize counts them, and the run time of the 24,000-op module; symbol-dce after idr-optimize, as the pipeline runs it, takes the functions the root absorbed, so the call left is one the cap kept; before the optimizer, largest-function reports each function of the chain at its own line of the written module, where the first RUN line writes its annotation (mlir-22).
- `tests/idr/optimize/case-of-case-calls.mlir`: that case-of-case reads a call between a match and its consumer, or in the match, by the call's own effects (mlir-12): its callee's under idr-optimize, which writes them once the callee is final, and every effect for a call at its default effects, where upstream canonicalize alone leaves each value built and each string allocated at the line reported (mlir-22); the patterns converge under upstream's canonicalizer with region simplification disabled (S2's default argument, ir-ods-8's type-first constant, S21's show_sint).
- `tests/idr/optimize/never-returns-twice.mlir`: that idr-optimize's inline step takes both never-returning callees into @both, the second where the first left the rest of @both's block unreachable, and erases that rest once after its loop, so @both is one block the verifier after every pass accepts and its return is gone with the rest (S5, ir-verify-1).
- `tests/idr/optimize/once.mlir`: how the action log prints the node's function after its tag, as the pinned MLIR's ActionLogger writes an IR unit; five nodes, each begun once, with each node's state one variant (transforms-b-14) (S2's default argument).
- `tests/idr/optimize/pure-call.mlir`: that once idr-effects writes each call's effects (mlir-12), upstream canonicalize and cse alone erase the unread calls of pure callees, one that takes a linear value among them, and merge @sum's identical ones, keep every call of @spin and @check, and keep @fresh's two calls, each giving a fresh linear value, two; that the inner pipeline of idr-optimize, upstream's canonicalize and cse on calls whose effects it writes, does the same; that each call left is reported at its line (mlir-22); and that counting then releases the linear string the erased call took (S2's default argument, S21's show_sint).
- `tests/idr/optimize/specialize-ends.mlir`: that idr-optimize ends on recursions whose static argument changes at every call: a key that differs from an earlier one only in its scalars is lifted to the key with those scalars as parameters (its holes counted by position, S22), one with more structure is refused and its call stays a call, and each function is specialized at most one step deep; the same output at one thread and many with the node lifecycle as one state (transforms-a-10); symbol-dce after idr-optimize, as the pipeline runs it (S2's default argument, ir-ods-8's type-first constant, S18's constant compared by its cells).
- `tests/idr/optimize/totality.mlir`: the run time of the module, whose 1,025 requests make as many copies as the rule over recursive components keys (S2's default argument).

## tests/idr/pipeline (8)

- `tests/idr/pipeline/do-block.mlir`: that each closure over linear captures, now of the linear closure type itself (S41), defunctionalizes and unfolds into the root as before, no closure left.
- `tests/idr/pipeline/known-label.mlir`: that the specialization on the known constructor is made and @inc inlined into it.
- `tests/idr/pipeline/rc-steps.mlir`: that idr-rc's steps are passes MLIR's tools name and run: --mlir-print-ir-after=idr-rc-place prints each function as idr-rc-place left it, and idr-rc-place run without idr-rc-grades before it refuses, naming the Reuses it reads.
- `tests/idr/pipeline/reported-error-fails.mlir`: the driver's diagnostic for an action log it cannot write, its one verdict exit 2.
- `tests/idr/pipeline/runtime-names.mlir`: that a program symbol the runtime defines or refers to is a refusal of the program (exit 3, `unsupported (program): `), its message as before.
- `tests/idr/pipeline/stages.mlir`: that a pass run at a stage its record does not state is refused, naming the pass and both stages. (and 1 more marks in the file)
- `tests/idr/pipeline/steps.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)
- `tests/idr/pipeline/time-trace.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)

## tests/idr/raise (11)

- `tests/idr/raise/apply.mlir`: that the call of @pick is raised, as a call whose result a dispatch consumes is, with the raise key holding its consumer's form by digest (S22) and symbol-dce after idr-optimize as the pipeline runs it (S2's default argument).
- `tests/idr/raise/branches.mlir`: that each region's dispatch meets the constructors @greet builds once it is inlined, as the inner pipeline folds them, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, ir-ods-8's type-first constant).
- `tests/idr/raise/builds-actions.mlir`: that the call of @actions carries @actions's entry, none, once @actions is final (idr.call's effects, mlir-12), so it is raised across the output, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument).
- `tests/idr/raise/chain.mlir`: that the chain folds in the root, by inlining and the case of a known constructor, with symbol-dce after idr-optimize as the pipeline runs it.
- `tests/idr/raise/closed-world.mlir`: that no copy is made and the loop runs as a loop; @bind's closure, capturing two linear actions, is linear by its type (S41) (S2's default argument).
- `tests/idr/raise/io-loop.mlir`: that the loop is left as one self tail call with no dispatch over a box, after the sums and the cleanup; @bind's closure, capturing two linear actions, is linear by its type (S41) (S2's default argument).
- `tests/idr/raise/projection.mlir`: that the projection and dispatch fold in the root once @greet is inlined, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, ir-ods-8's type-first constant).
- `tests/idr/raise/shared-key.mlir`: that calls with equal raise keys share one node, the key holding its consumer's form by digest in the run's table (S22), with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument).
- `tests/idr/raise/sunk-call-paths.mlir`: that a call that may crash or not return sinks only into every region, past nothing but computing, reading the call's own effects (mlir-12), and that a pure call taking a linear value sinks onto fewer paths, its value released where unused; calls-where-used reports each @cmk call that stays at its line (mlir-22) (S2's default argument, S21's show_sint).
- `tests/idr/raise/sunk-call.mlir`: that sinking reads a call's own effects, its callee's written on it once the callee is final (mlir-12), so the call of the total @pmk moves into the one region that applies its result and is raised there, while the call of the partial @mk stays before the match, where calls-where-used reports it at its line (mlir-22) (S2's default argument).
- `tests/idr/raise/through-linear.mlir`: that the linear enter and use of the action fold away, as the canonicalizer folds a use of an enter, with symbol-dce after idr-optimize as the pipeline runs it; the root's IORes holds a unit, a root S38 admits.

## tests/idr/rc (19)

- `tests/idr/rc/atom-pairs.mlir`: that @withCell's take of the first list of the pair it gets back, which may be the static pair's shared cell, tests the count, now that the pair's own take is an idr.unpack that tests nothing. (and 2 more marks in the file)
- `tests/idr/rc/buffers.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/consumed.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/counted-linalg.mlir`: that the program's verifier refuses, from the first stage on, a linalg op whose payload takes a value that holds references, which idr-rc no longer lowers to loops of its own.
- `tests/idr/rc/counts.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/dies-apart.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/exclusive.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/kept-fields.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/live.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/nested-reuse.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
- `tests/idr/rc/regions-counted.mlir`: idr-rc's counting of region ops and loops, which the owned verifier then holds after the pass.
- `tests/idr/rc/returned.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/second-redirect.mlir`: that idr-rc follows the exclusive call of @keep to the call its result feeds, so @sum gets its exclusive copy in the same run.
- `tests/idr/rc/share-trap.mlir`: that a list which reaches @bump only through an idr.share is never taken apart without the runtime's count test: exclusivity does not follow a share, which forgets that its value was exclusive.
- `tests/idr/rc/stack-cell.mlir`: that idr-rc puts a cell that dies in its frame on the stack before reuse and exclusivity are decided: no heap allocation in @local, the init of its stack cell not exclusive, and no cell recycled from it in @rebuilt.
- `tests/idr/rc/statistics.mlir`: that each step of idr-rc reports its own statistics under its own pass, in the pipeline's order, where it acts.
- `tests/idr/rc/take-at-death.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/twice.mlir`: that idr-rc's first step, idr-rc-cells, refuses a program in the owned stage by its record's stage (StagedPass), naming itself.
- `tests/idr/rc/verify.mlir`: the recycled cell's size rule reported at its idr.cell.recycle (L03's Program.cpp), the cell ops, and every match's default binding its scrutinee (and 1 more marks in the file)

## tests/idr/returned (1)

- `tests/idr/returned/threaded.mlir`: that idr-returned-arguments drops each result returned as its function's argument through scf.if, scf.while, scf.execute_region and mutual recursion (five), keeps a result only a call that never returns gives and one that is an argument on some paths only, and that every caller uses the argument it passed.

## tests/idr/roles (3)

- `tests/idr/roles/contify.mlir`: that skipping every idr-contify-move action leaves the module as it was, and that idr-contify changes it otherwise.
- `tests/idr/roles/optimize-statistics.mlir`: that idr-optimize reports its inner canonicalize's and cse's counts, and that the inner cse merged the two equal products.
- `tests/idr/roles/pure-calls.mlir`: that skipping every idr-pure-calls action keeps the unread pure call of @unread, and that the module verifies.

## tests/idr/specialize (8)

- `tests/idr/specialize/binding-times.mlir`: each remark at its function under -verify-diagnostics, the two binding times after S14 (free and fixed are fixed, decreasing, bounded and other vary), and @thread's linear parameter fixed through idr.lin.use and idr.lin.enter (S11).
- `tests/idr/specialize/countdown-long.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position; one copy of @loop once symbol-dce, which the pipeline runs after idr-optimize, has taken the functions nothing names (S2's default argument, S22's parameterless holes).
- `tests/idr/specialize/countdown.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position; one copy of @loop once symbol-dce, which the pipeline runs after idr-optimize, has taken the functions nothing names (S2's default argument, S22's parameterless holes).
- `tests/idr/specialize/dictionary.mlir`: that @sumTo is specialized on the whole record and @plus inlined into the copy, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, S22's parameterless holes).
- `tests/idr/specialize/growing.mlir`: one node for @iter, by the rule over recursive components, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, S14's two binding times).
- `tests/idr/specialize/higher-order.mlir`: that @map is specialized on the known constructor of @add with its capture a hole, with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, S22's parameterless holes).
- `tests/idr/specialize/partial-list.mlir`: that only the entry copy for [1, 2, n] is made and its recursive call passes the tail as a value (inside a recursive component a call keys only the positions passed unchanged along the recursion), with symbol-dce after idr-optimize as the pipeline runs it (S22's parameterless holes).
- `tests/idr/specialize/static-table.mlir`: the rule over recursive components: the table passed unchanged along the recursion keys the copy once; the index going down keys nothing; with symbol-dce after idr-optimize as the pipeline runs it (S2's default argument, ir-ods-8's type-first constant, S18's constant compared by its cells).

## tests/idr/stack (3)

- `tests/idr/stack/escapes.mlir`: that idr-rc's stack step puts the cell of a box only read in its frame on the stack, and leaves the cell of a returned box on the heap.
- `tests/idr/stack/expect.mlir`: that a cell made on the stack is no heap allocation and the con of a box is one, and that idr-rc's cells and stack steps put the cell only @head reads on the stack and leave the returned one on the heap.
- `tests/idr/stack/linear-box.mlir`: that the cell of a linear box only a callee reads goes on the stack after idr-rc (a box at any grade has a cell), where it made a heap cell before.

## tests/idr/structure (6)

- `tests/idr/structure/columns.mlir`: idr-columns' signatures: a tensor of one-constructor records becomes one tensor per field, in the fields' order.
- `tests/idr/structure/dynamic-cells.mlir`: that idr-structure-loops lowers a tabulation of cells whose size only the cells know at ranks 0, 1 and 2 and over an empty domain, each to the first cell made at the zero index and one loop over the rest of the domain's linear index, leaving no array op.
- `tests/idr/structure/never-returns.mlir`: a region ending in ub.unreachable, lowered by idr-structure-loops.
- `tests/idr/structure/ordered.mlir`: the forms idr-structure-loops gives each op from the effects idr-effects finds.
- `tests/idr/structure/tabulate.mlir`: the lowering of idr.tabulate: a region over words that does nothing beyond compute and crash is one linalg.generic.
- `tests/idr/structure/transpose.mlir`: idr.transpose's folds and its lowering to a linalg op.

## tests/idr/syntax (5)

- `tests/idr/syntax/constants.mlir`: that a run is spelled with its last cell holding every field, the tail among them, and a constant with its type first; the 10,000-cell run, whose generated module now names its roles and has an i64 root, parses, prints flat and round-trips through text and bytecode. (and 1 more marks in the file)
- `tests/idr/syntax/facts-roundtrip.mlir`: that a function's effects print before its symbol as `effects<io, crash>`, its other facts after `attributes`, and the text reads back as itself.
- `tests/idr/syntax/grades-invalid.mlir`: that a grade of the world, at (many, own) or at (one, plain), and a grade of a destination are each refused by the one rule, "which is used exactly once by its type".
- `tests/idr/syntax/grades.mlir`: that the spelled grades print as their spellings with no world among them, the world being a type of its own that takes no grade.
- `tests/idr/syntax/inherent-invalid.mlir`: that each restated inherent fact is refused as the op is read, the matches' default regions binding their scrutinees and the constant written with its type first.

## tests/idr/tail-calls (4)

- `tests/idr/tail-calls/decided-loops.mlir`: that a call whose path to the return goes round a loop its constants decide, entering a block again with other values, is a guaranteed tail call, and one round a loop an argument decides is none.
- `tests/idr/tail-calls/long-continuation.mlir`: that a call whose path to the return crosses 5,000 blocks is a guaranteed tail call, and one whose path comes back to a block knowing what it knew there before is none.
- `tests/idr/tail-calls/mutual.mlir`: that idr-tail-calls is the pipeline's last module pass, and the tree printer's file names. (and 2 more marks in the file)
- `tests/idr/tail-calls/positions.mlir`: that the tail-calls and convention properties hold where the printed module showed them, and fail at each call that keeps its frame.

## tests/idr/tie-shape (2)

- `tests/idr/tie-shape/dims-fold.mlir`: the RUN line runs upstream's canonicalize (idr-canonicalize is deleted); confirm it converges on the dialect's patterns as before.
- `tests/idr/tie-shape/verify.mlir`: the verifier's error texts, idr.tie_shape's; check each against it.

## tests/idr/vectorize (3)

- `tests/idr/vectorize/lanes-x86-64.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 2 more marks in the file)
- `tests/idr/vectorize/rows-aarch64.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 2 more marks in the file)
- `tests/idr/vectorize/rows-x86-64.mlir`: that this test, rewritten to the representation wave's printed forms (`idr.io.put_sint` for the signed `put_int`), parses and passes as before. (and 2 more marks in the file)

## tests/idr/verify (20)

- `tests/idr/verify/attributes.mlir`: the texts of the unknown-attribute errors and of the refusals rule, and that the frontend's refusals verify on the top-level module alone; the stack property and the expect.facts marks are gone (S3, mlir-23).
- `tests/idr/verify/cells.mlir`: that a recycle of an exclusive token and the init of an exclusive box print and parse back (RUN 2-3); that each split below is refused as its expected-error says, the hole at an i64 field in a release build too.
- `tests/idr/verify/closure.mlir`: a world captured is refused by the capture's operand constraint (Idr_Capture, S17), with the message ODS writes for it.
- `tests/idr/verify/con-owned-field.mlir`: that an owned value fills a constructor's plain field, and a borrow does not.
- `tests/idr/verify/cycle.mlir`: the knot rule runs as the pass idr-knots (mlir-4), not in the verifier: the programs of the first stage are refused by it with the same texts, the last program verifies and is refused only once idr-defunctionalize has made its closures data; a knot only a library makes, whose type the program's own code builds nowhere, is reported at the program (the base expected it at the library's function, which knots never names); constants type first (ir-ods-8), idr.io.put_sint (mlir-1). (and 1 more marks in the file)
- `tests/idr/verify/data.mlir`: the texts of a body's errors, as the type's setBody and parser write them, a constructor's role now carrying its payload (S19): a memo sum without its running state and a list without its cons's box still refused.
- `tests/idr/verify/effects.mlir`: the text of the program verifier's effects error, and that a covered pair verifies, with the effects printed before a function's symbol and after a call's arguments (S6), each call holding its own.
- `tests/idr/verify/flow.mlir`: the texts of the flow rule's errors, as verifyFlow and verifyFlowEdges write them; idr.io.put_sint (mlir-1).
- `tests/idr/verify/function.mlir`: a function's effects are its property, printed before its symbol (S6), beside the facts it holds under `attributes`.
- `tests/idr/verify/generic.mlir`: the generic form of a match after S2 (the default region first, binding the scrutinee; the cases as tags), with the messages L01's verifiers write; a constant naming no constructor of its type, written type first (ir-ods-8).
- `tests/idr/verify/match.mlir`: the default region first (S2): a case is region #1 on, idr.match_lit's missing default is its region constraint's message, a default binds the scrutinee (default(%d: T)), a case for no constructor is the parser's message, and two cases for one constructor read "has two cases for @B".
- `tests/idr/verify/nat.mlir`: a natural is made only by idr.big.from_uint, so from_sint's result constraint refuses one (mlir-1); constants written type first (ir-ods-8); the default binds the scrutinee (S2).
- `tests/idr/verify/only-atoms.mlir`: that an exclusive reference to a constant run held in place, whose second cell is a box with fields, is refused (it verifies at the base, which read the run's cells and its tail and never the box its spine holds).
- `tests/idr/verify/ops.mlir`: idr.str.show_uint's operand constraint refusing an i1 (S21, mlir-1); a Double's show is its own op, which has no signedness to refuse.
- `tests/idr/verify/owned-stage.mlir`: the printed form of idr.take, idr.cell.recycle and idr.cell.init (S3) and of a default that binds the scrutinee (S2); that the owned stage refuses a box built as a value with fields, a cell never filled, and an exclusive box filled in a cell of the frame, each as its expected-error says. (and 1 more marks in the file)
- `tests/idr/verify/program.mlir`: the texts of the program verifier's errors and the ops they are reported at, the root's kinds (a world and a status refused, IORes of a unit and a unit beside the world accepted), the graded stage (grades admitted, counts not yet checked), and the owned stage's buffer and linalg rules.
- `tests/idr/verify/reduce-regions.mlir`: that idr's reduction pattern leaves no arith op in the reduced module, each value made ub.poison; the literal match's default binds the scrutinee (S2).
- `tests/idr/verify/roundtrip.mlir`: the wave's spellings round-trip: constants type first (ir-ods-8), a default that binds the scrutinee (S2), one op per signedness (mlir-1: divs, modu, to_char_s, int_head_s/_u, str.show_sint/_uint/_double, str.to_sint/_uint, big.from_sint, io.put_sint). (and 2 more marks in the file)
- `tests/idr/verify/values.mlir`: constants written type first, their values holding no type of ours (ir-ods-8), each refused as before. (and 2 more marks in the file)
- `tests/idr/verify/widths.mlir`: one op per signedness (mlir-1), each refusing a width Idris has not: idr.divs, idr.to_char_u, idr.io.put_uint.

## tests/idr/world (4)

- `tests/idr/world/world-capture.mlir`: that a closure capturing a world is refused by its captures' operand constraint (Idr_Capture), whose message names the world's type.
- `tests/idr/world/world-carrier.mlir`: that the world's old carrier spelling no longer parses, so no world can be written at quantity many; at the base this module verifies, a world used twice.
- `tests/idr/world/world-once.mlir`: that the module verifies with the literal match's default region binding its scrutinee. (and 1 more marks in the file)
- `tests/idr/world/world-twice.mlir`: that each world used twice on one path is refused, with the matches' default regions binding their scrutinees.

## tests/lib (2)

- `tests/lib/lit.sh`: every dialect input round-trips through the generic form and bytecode, and every pass a RUN line runs keeps its contracts (--verify-roundtrip --idr-contracts on every idris-mlir-opt).
- `tests/lib/properties.sh`: universal prints one line, universal: holds, where the object, dump and quantity checks printed one each; a failing check still prints its own lines.

## tests/programs (24)

- `tests/programs/arrays/ioarray-fannkuch/expected`: that the fixture built from bench/fannkuch-redux's Main.idr compiles, prints expected-stdout and holds its mlir.expect
- `tests/programs/arrays/linarray-bubble/expected`: that the port to the size-indexed vector, each position a Fin its loop's test against the size gives, prints the same and keeps its loops count-free and allocation-free
- `tests/programs/arrays/linarray-fannkuch/expected`: that the port to the size-indexed vector, positions checked against the size where they are used, prints the same and keeps its loops count-free, allocation-free and in place; and that the fixture, now built from bench/fannkuch-linear's Main.idr and packages, holds the same
- `tests/programs/arrays/linarray-fill-sum/expected`: that the port to the size-indexed vector, each position a Fin its loop's test against the size gives, prints the same and keeps its loops count-free and allocation-free
- `tests/programs/arrays/linarray-push-pop/expected`: that the port to the size-indexed vector, the stack's size carried with it and a pop on an empty one Nothing, prints the same
- `tests/programs/arrays/linarray-qsort/expected`: that the port to the size-indexed vector, positions checked against the size where they are used, prints the same and keeps its loops count-free, allocation-free and in place; and that the fixture, now built from bench/qsort's Main.idr and packages, holds the same
- `tests/programs/arrays/linarray-read-past-size/expected`: that a read at the size of a grown vector, inside its capacity, is refused by the checked conversion of its index (Nothing, printed as out of range) rather than ending the program, and that every check of the expected file holds
- `tests/programs/arrays/linarray-reserve/expected`: that the port to the size-indexed vector, the pushes giving back their size, prints the same
- `tests/programs/arrays/linarray-spectral-norm/expected`: that the fixture built from bench/spectral-norm-linear's Main.idr and packages compiles, prints expected-stdout and holds its mlir.expect
- `tests/programs/arrays/linarray-unionfind/expected`: that the port to the size-indexed vector, nodes checked against the size where they are read or written, prints the same and keeps its loops count-free and allocation-free; and that the fixture, now built from bench/unionfind's Main.idr and packages, holds the same
- `tests/programs/arrays/linarray-write-past-size/expected`: that a write at the slot a pop left, inside the capacity but at the size, is refused by the checked conversion of its index (Nothing, printed as out of range) rather than ending the program, and that every check of the expected file holds
- `tests/programs/arrays/vec-pop-then-push/expected`: that the port to the size-indexed vector, whose pop gives the element itself, prints the same
- `tests/programs/data/cfold/expected`: that the fixture built from bench/cfold's Main.idr compiles, prints expected-stdout and holds its mlir.expect
- `tests/programs/data/dependent-pair-family-eta/expected`: that a box built at Box Nat (Q b) and held by a dependent pair at Box Nat ( => Q b a) is one data instance, so the match on the box the pair holds sees the constructor build made and its Ord field (no unreachable alternative), compiles and runs, printing expected-stdout; and that what holds of every compilation holds of it (universal: holds)
- `tests/programs/data/pidigits/expected`: that the fixture built from bench/pidigits's Main.idr compiles and prints expected-stdout
- `tests/programs/data/rbtree/expected`: that the fixture built from bench/rbtree's Main.idr compiles, prints expected-stdout and holds its mlir.expect
- `tests/programs/data/sortedmap-map-after-insert/expected`: that map over a SortedMap built by insert, and keySet, which maps it, match the constructors insert built (no unreachable alternative in Dependent.map), compile and run, printing expected-stdout; and that what holds of every compilation holds of it (universal: holds)
- `tests/programs/interfaces/method-runtime-implicits/expected`: that a call through an interface of a method whose leading arguments are runtime implicits (an auto-implicit IORef, a Nat) gives the implementation's method function each in its place, compiles and runs, printing expected-stdout; and that what holds of every compilation holds of it (universal: holds)
- `tests/programs/io/mandelbrot-pbm/expected`: that the fixture built from bench/mandelbrot-pbm's Main.idr compiles and prints expected-stdout
- `tests/programs/io/system-info/expected`: that the values the run reads from tools/host.sh (darwin on macOS or unix on Linux, no, mlir, ncpu_total) are what the program prints on both targets
- `tests/programs/nat/bits8-past-127/expected`: that a Bits8 of 200, made at run time, is 200 as a Nat and as an Integer, greater than 127 and equal to 200, with no poison from a range put on the tagged word
- `tests/programs/prelude/negate-fixed-width/expected`: that prim__negate at every fixed width compiles and is two's-complement negation (the most negative signed value is its own negation; an unsigned width wraps)
- `tests/programs/semantics/prim/expected`: that each test of Sem.names, run as programs/semantics/prim@<name>, compiles, prints the values its table computes and allocates nothing on the heap
- `tests/programs/stack/mutual-pure-tail-calls/expected`: that constant-stack holds after idr-tail-calls of the program root, named as the frontend writes it ($idris-mlir.root)

## tests/registry (4)

- `tests/registry/base-surface/expected`: that Idris loads a fixture's own module named as a base or prelude module under --no-prelude, and the validation refuses each case at its entry (a missing ruled-out definition as found missing)
- `tests/registry/broken-entry/expected`: that Idris loads a fixture's own module named as a prelude module (Builtin, Prelude.IO) under --no-prelude, and the validation refuses each case at its entry
- `tests/registry/scalar-bytes/expected`: that the iterator reads every scalar value back as the string was packed, with the step idr.str.scalar_bytes computes
- `tests/registry/string-iterator/expected`: that Idris loads the fixture's own Linear.String.Iterator before the installed package's, and the validation refuses each case at its entry; and that it refuses scalarBytes, a definition with a body, at its entry as it refuses the %extern ones

## tests/reject (16)

- `tests/reject/cycle-array-knot/expected`: where the cycle refusal is now reported. The header keeps line 15 (the definition that makes the array), but the identified-type rule that moved cycle-ioref-knot reports at the first idr.con of a type on the cycle, the Nothing on line 17; set the header to what the compiler says, if it is one of the two
- `tests/reject/cycle-ioref-knot/expected`: that the cycle refusal is reported at the first idr.con the program's own code builds of a type on the cycle (line 18), since an identified data type has no location of its own
- `tests/reject/escape-hatch-phrase-in-comment/expected`: one refusal of rule escape hatch at line 6, though the source line holds the phrase (the verdict and line come from the module's refusal)
- `tests/reject/finalizer-collect-any/expected`: that onCollectAny is refused once, as a finalizer, at register's declaration (line 10), naming Prelude.IO.onCollectAny
- `tests/reject/idris-interface-body/expected`: that a data declaration in an interface body is refused at the declaration, line 12, as an error of Idris and no rule of ours, not at its use
- `tests/reject/idris-totality-depth-pragma/expected`: that %totality_depth is refused by the parser at its line, as an error of Idris and no rule of ours
- `tests/reject/polymorphism-growing-rank/expected`: that deeper, which calls itself at s :< 2, is refused once as polymorphism at its declaration (line 12), by the growth check, whose message names the cycle and its growth of 1 a round, rather than with the refusal of a shape with no spine
- `tests/reject/polymorphism-growing-shape/expected`: that grow, which calls itself at S n over Ints, a type that needs all of n, is refused once as polymorphism at its declaration (line 19), by the growth check, whose message names the cycle and its growth of 1 a round; Ints's pair, one head per level, adds no cause
- `tests/reject/polymorphism-growth-dictionary/expected`: that quote, which passes itself the implementation quoted built over its own, is refused once as polymorphism at its declaration (line 15), by the growth check on its dictionary argument sh, whose message names the cycle and its growth of 1 a round
- `tests/reject/polymorphism-growth-family-recursion/expected`: that W, which applies its family m to a closed type in T's static argument, where m's value is a lambda stuck on its argument in G's type-level recursion, is refused once as polymorphism at T's declaration (line 17), by the growth check, whose message names the family m, where it raised the growth check's internal error
- `tests/reject/polymorphism-growth-family-sum/expected`: that W, which applies its family m to two closed arguments in T's static argument, where m's value applies its family argument to what holds its other argument (a sum of the two arguments' heights), is refused once as polymorphism at T's declaration (line 15), by the growth check, whose message names the family m, though its instances are finite: a sum of two arguments' heights is no weight the check states (a known limit)
- `tests/reject/polymorphism-growth-mutual/expected`: that up and down, whose cycle adds two constructors and takes one off, are refused once as polymorphism at up's declaration (line 22, the cycle's first definition in the source), by the growth check, whose message names the cycle through down and its growth of 1 a round (the sum, not the larger arc)
- `tests/reject/polymorphism-growth-recursion/expected`: that wrap, whose second argument's type Two n is a recursion stepping two constructors at a time, stuck on its first, is refused once as polymorphism by the growth check's opaque arc, at its declaration, line 19, the message naming the type-level recursion; HEAD's frontend admits it
- `tests/reject/polymorphism-nested-data/expected`: that the nested data type T is refused once as polymorphism at its declaration, line 11, by the growth check over its represented argument a (an index, since N changes it), whose message names N's field and the growth of 1 a level; and that it does not hang
- `tests/reject/polymorphism-nested/expected`: that depth, which calls itself at (a, a), is refused once as polymorphism at its declaration (line 12: TT read from a TTC holds no call-site location), by the growth check, whose message names the cycle and its growth of 1 a round
- `tests/reject/raw-pointer-malloc/expected`: that malloc is refused once, as a raw pointer, at scratch's declaration (line 12), naming System.FFI.malloc

## tests/toolchain (11)

- `tests/toolchain/heap-region/expected`: that every cell of a heap under 4 GiB lies in the first cell's 4 GiB region and the heap grows past it, its arrays usable and every cell freed, on both targets
- `tests/toolchain/io-buffer/expected`: that the IO units built for a buffer of 4 and of 7 bytes print what the default build prints, and that echo gives back its input
- `tests/toolchain/runtime-api/expected`: the results equal the base runtime's on both targets: handles.c is new, its lines the base runtime's results (read from its code, and run on arm64 macOS against it), and rc's crash names its cause after the runtime's `idris-mlir: `; confirm every check of rc.c passes and its total reads 101
- `tests/toolchain/runtime-bigs/expected`: that the pinned clang builds bigs.cpp through prop_build with no C++ library on both targets, that every property and box below holds at the run's case count, and that the count, marked as debt in run, ends well within step_limit
- `tests/toolchain/runtime-counting/expected`: that the counting model holds on every case: live cells, each count and exclusivity as idris_rt.h defines them, wide cells, odd words in slots, arrays, view copies and memo cells included
- `tests/toolchain/runtime-doubles/expected`: runtime-doubles is new: confirm that doubles.cpp builds through prop_build with no C++ library and that its 13 properties hold on both targets (each target's strtod and nextafter are its C library's), that runtime-doubles/report is written, and set --cases in run
- `tests/toolchain/runtime-prepared/expected`: that every symbol the prepared runtime needs is one its target's allowlist allows (allowed, with linux/allowed or macos/allowed), on both targets, and that rc.c still behaves alike against the archive and the prepared runtime; the per-target symbol lists are gone
- `tests/toolchain/runtime-start/expected`: that the entry names a missing bit no feature names by its number (this processor lacks bit 63), on both targets
- `tests/toolchain/runtime-strings/expected`: runtime-strings is new, with the property of the one empty string: confirm that strings.cpp builds through prop_build with no C++ library and that its 9 properties hold on both targets, that runtime-strings/report is written, and set --cases in run
- `tests/toolchain/runtime-text/expected`: that the pinned clang builds text.cpp through prop_build with no C++ library on both targets, that every property and box below holds at the run's case count, and that the count, marked as debt in run, ends well within step_limit
- `tests/toolchain/runtime-utf8/expected`: runtime-utf8 is new: confirm that utf8.cpp builds through prop_build with no C++ library and that its 7 properties hold on both targets (each target's simdutf kernel), that runtime-utf8/report is written, and set --cases in run

## tests/two-levels (1)

- `tests/two-levels/terms/expected`: expected-primitives lacks the values of the terms added for the 56 primitives TwoLevels did not cover; add each "no expected value" line the owner's build prints, after review

## tests/upstream (8)

- `tests/upstream/constructor-implicit-mark/expected`: that definitions whose clauses leave a constructor's implicit to the elaborator, relevant in v1 and erased in the quantity-0 v3, are accepted as covering under %default total, that implicits the clauses write are still matched (w3 at C3 {x = B} takes its second clause), and that the program compiles and runs, printing (1, 2); and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/erased-constant-pattern/expected`: that a quantity-0 definition splits what its clauses write on an erased argument (a constant in h and pv, a type in tp), so that h 5 reduces to 2 in hFive and in the type of five, which only Two inhabits, and that it does not split a constructor's type implicit that unification solved (len), nor the types inside a pair that unification fixed to the pair a clause writes (heads, whose headsTwo reduces); and that the program compiles and runs, printing 2; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/erased-coverage-nested-match/expected`: that erased definitions whose clauses leave their list index to the elaborator are accepted as covering under %default total, compute in types, and the program compiles and runs; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/evaluator-char-text/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/one-shot-module-function-interface/expected`: written before a toolchain carried the extended patch 24 (upstream's boundary models on FunctionOpInterface and CallOpInterface, the analysis of cycles of calls, results that are not writable and the definite-alias rule, the nearest symbol table) and before idr-bufferize used those models on idr.program: confirm each line below.
- `tests/upstream/relevant-implicit-split/expected`: that definitions above quantity 0 whose clauses leave their relevant list index to the elaborator, with a case block and a with block over it, are accepted as covering under %default total, and the program compiles and runs, reading at run time what only that index holds; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/termination-closure/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/totality-unimported-callee/expected`: that the fork refuses Main.caller as not total, Loop.loop, in a module Main does not import, being reachable through ViaLoop.viaLoop, with Idris's own error at exit 3, and does not refuse Main.counted, which reaches the total Count.count the same way
