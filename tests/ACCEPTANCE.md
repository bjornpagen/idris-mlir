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
less this page, as it stood on 2026-10-16, each with its first mark as
its reason: 291 files. Proposal 0014's culls removed the marks of the
tests they deleted, and the tests it changed or wrote carry new ones. A
change that adds or removes a mark lists it here again.

## tests/accept (29)

- `tests/accept/action-after-effect/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/action-run-at-once/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/default-pragma/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/division/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/equality-proofs/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
- `tests/accept/erased-field/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds)
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

## tests/compiler (3)

- `tests/compiler/dialect-syntax/expected`: the samples' print in the dialects' syntax: the program wrapper (idr.program, the root and the stage), the array ops, data bodies with their constructors' roles, tags in place of constructor names where an op holds a tag, and no scf loop or #idr.con sample; the print below is the one before it, less the #idr.con samples it no longer holds, and the three status lines are the check
- `tests/compiler/fork-loops-terminate/expected`: that the fork's size-change decision judges each component of Loops.idr as expected-stdout says, run through this script against the installed fork
- `tests/compiler/handoff-readable/expected`: how the printer writes an identified data type (an alias at the head of the module, whose body holds `instance`), which the instance check reads; and how it writes idr.program (`idr.program @<name> root(@<root>) stage(higher) {`), which the program check reads

## tests/determinism (4)

- `tests/determinism/hello/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/leet-rotate/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/rbtree/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process
- `tests/determinism/shapes/expected`: that every artifact and every dump is identical at 1, 3, 5 and 13 threads and in a second process

## tests/fuzz (3)

- `tests/fuzz/seed-1/expected`: the goldens are gone; confirm the eight property lines hold for both seeds on both targets
- `tests/fuzz/seed-2/expected`: the goldens are gone; confirm the eight property lines hold for both seeds on both targets
- `tests/fuzz/two-hosts/expected`: idris-mlir compiles Gen, Prims, Fuzz, Sem and TwoLevels, and its program prints the stock host's text byte for byte, a draw's loop and a tape's reset reusing their cells in place; the limits measured

## tests/idr/actions (11)

- `tests/idr/actions/accumulate.mlir`: that skipping every idr-accumulate-countdown and idr-accumulate-clone action leaves the module as idr-accumulate received it, and that idr-accumulate changes it otherwise.
- `tests/idr/actions/canonicalize.mlir`: that skipping every idr-canonicalize-run action leaves the module as idr-canonicalize received it, and that idr-canonicalize changes it otherwise.
- `tests/idr/actions/columns.mlir`: that skipping every idr-columns-convert action leaves the module as idr-columns received it, and that idr-columns changes it otherwise.
- `tests/idr/actions/deduplicate.mlir`: that skipping every idr-deduplicate-merge action leaves the module as idr-deduplicate received it, and that idr-deduplicate changes it otherwise.
- `tests/idr/actions/inner-steps.mlir`: that skipping idr-optimize-inline, idr-identity-call or idr-constants-replace leaves a module that verifies and differs from the one idr-optimize makes, each action seen at least once.
- `tests/idr/actions/narrow-lanes.mlir`: that skipping every idr-narrow-lanes-version action leaves the module as idr-narrow-lanes received it, and that idr-narrow-lanes changes it otherwise.
- `tests/idr/actions/narrow.mlir`: that skipping every idr-narrow-version, idr-narrow-joint, idr-narrow-word, idr-narrow-fold and idr-narrow-erase action leaves the module as idr-narrow received it, and that idr-narrow changes it otherwise.
- `tests/idr/actions/returned-arguments.mlir`: that skipping every idr-returned-arguments-drop action leaves the module as idr-returned-arguments received it, and that idr-returned-arguments changes it otherwise.
- `tests/idr/actions/stack.mlir`: that skipping every idr-stack-cell action leaves the module as idr-stack received it, and that idr-stack changes it otherwise.
- `tests/idr/actions/tail-loops.mlir`: that skipping every idr-tail-loops-loop, idr-tail-loops-hoist and idr-tail-loops-uplift action leaves the module as idr-tail-loops received it, and that idr-tail-loops changes it otherwise.
- `tests/idr/actions/trmc.mlir`: that skipping every idr-trmc-clone action leaves the module as idr-trmc received it, and that idr-trmc changes it otherwise.

## tests/idr/asm (2)

- `tests/idr/asm/aliases.mlir`: the aliases the printer gives data types, and where it prints them. (and 1 more marks in the file)
- `tests/idr/asm/names.mlir`: syntax swept to the data-type-first form

## tests/idr/bufferize (8)

- `tests/idr/bufferize/aliasing.mlir`: the analysis of released buffers and of call results: each function marked to copy writes a copy, and @fresh writes in place.
- `tests/idr/bufferize/linear-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/link-read-after-release.mlir`: that idr-bufferize copies at the release.
- `tests/idr/bufferize/pop-box.mlir`: that a pop's read of its last element and the write of the fill behind it become one idr.element.update on the vector's buffer, written in place.
- `tests/idr/bufferize/recursive-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/recursive-value.mlir`: that the boundary analysis settles the cycle of @go's calls, so its result is no copy at any level of the recursion.
- `tests/idr/bufferize/release-constant.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/release-copies.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.

## tests/idr/canon (7)

- `tests/idr/canon/apply.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/array-moves.mlir`: that the element moves out across the call of the pure @bump under idr-optimize, whose canonicalizer reads the callee's effects, and not under a canonicalizer that has no symbol table; and that under idr-optimize it stays read across output, a call that performs IO, a write in another block, and in a word.
- `tests/idr/canon/evaluated-memo.mlir`: that the force became a call of the sum's dispatch, so no force is left.
- `tests/idr/canon/facts.mlir`: @applies declares every effect, as the verifier's effect rule asks of a function that applies a closure; the canonicalizer's answers are unchanged. (and 1 more marks in the file)
- `tests/idr/canon/match-known.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/output-fusion.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/record-eta.mlir`: syntax swept to the data-type-first form

## tests/idr/contify (1)

- `tests/idr/contify/contify.mlir`: RUN 3 writes no module now; its idr-expect check is unchanged.

## tests/idr/contracts (2)

- `tests/idr/contracts/break.mlir`: that --idr-contracts names the pass that widens a function's effects or makes a linear result unrestricted, while the module stays valid, and lets a pass that keeps both pass.
- `tests/idr/contracts/nested-run.mlir`: that idr-rc keeps its contracts under --idr-contracts: the steps it runs on the program through its own pipeline, between which the program is graded owned and not yet counted, are part of its run and are not checked against that program.

## tests/idr/dedup (3)

- `tests/idr/dedup/keep-apart.mlir`: the two functions that are not total declare diverge, as the verifier's effect rule asks; they are still kept apart.
- `tests/idr/dedup/merge-named.mlir`: that the kept function's location fuses its members', so idr-expect finds the code of either definition there.
- `tests/idr/dedup/merge.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool.

## tests/idr/defunc (7)

- `tests/idr/defunc/choice.mlir`: that @pick's sum holds the labels of @add and @dbl, and that the dispatch in @Main.main calls each.
- `tests/idr/defunc/coerce.mlir`: that each set of labels is its own sum: @Main.mkInc's and @Main.mkAdd's of one label each, @Main.use's of both.
- `tests/idr/defunc/force-call.mlir`: the memo sum's dispatch idr-defunctionalize makes, and the stage it sets.
- `tests/idr/defunc/state.mlir`: that each closure of the state transformers' one type has the sum of the labels that reach it, none leading back to @Main.seq.
- `tests/idr/defunc/sum-names.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool.
- `tests/idr/defunc/tag-limit.mlir`: that a sum of more than 2^16 constructors is a two-level sum and that the 65,537-label module defunctionalizes within the suite's time bound on both targets.
- `tests/idr/defunc/unreached-cell.mlir`: syntax swept to the data-type-first form

## tests/idr/e2e (4)

- `tests/idr/e2e/eval.mlir`: the program compiles and prints its value without dumps.
- `tests/idr/e2e/even-group.mlir`: that a heap cell of a sum's third group, whose group number is even, is matched and freed without the runtime reading its group word as a reference, beside a cell of the first group and one of the second.
- `tests/idr/e2e/hello.mlir`: syntax swept to the data-type-first form
- `tests/idr/e2e/loops.mlir`: syntax swept to the data-type-first form

## tests/idr/effects (8)

- `tests/idr/effects/alloc.mlir`: each op's answers are its own declared effects; check each mark against them.
- `tests/idr/effects/call-effects.mlir`: that a call answers move and delay with its callee's effects as idr-effects found them, and that canonicalize and CSE keep every call.
- `tests/idr/effects/force-strict.mlir`: the effects idr.force declares before defunctionalization.
- `tests/idr/effects/forced-labels.mlir`: that idr-defunctionalize turns each force into a call of its memo sum's dispatch and marks the labels by_name as the effects say.
- `tests/idr/effects/idr-effects.mlir`: syntax swept to the data-type-first form
- `tests/idr/effects/long-cycle.mlir`: that idr-effects reaches every member of a cycle of 3,001 functions with the crash of one, within the suite's time bound.
- `tests/idr/effects/memo-label.mlir`: the dispatch idr-defunctionalize makes of a memo sum and the syntax of idr.memo.enter and idr.memo.settle.
- `tests/idr/effects/queries.mlir`: that a call answers move and delay with the effects idr-effects found for its callee, and drop and merge never.

## tests/idr/expect (38)

- `tests/idr/expect/apart.mlir`: that apart holds of two functions made from code of their own and fails once, at @merged, whose location fuses both names.
- `tests/idr/expect/by-name.mlir`: that by-name and not-by-name read the memo labels of a sum a parameter holds, and fail once each where the label's flag is the other, and once where no label names the function.
- `tests/idr/expect/calls.mlir`: that each failing request of Calls.cpp reports exactly the one error checked, at the call or the function it names; idr.apply is the call through a value.
- `tests/idr/expect/closures.mlir`: that labels reads the sum of labels at @pick's result, holds of the labels it runs and fails, once, of a list that names fewer; and that the failing request reports exactly the four errors checked.
- `tests/idr/expect/computes-nothing.mlir`: that computes-nothing holds of a function of a guard and of one of a crash, and fails once at the one op of @computes that computes a value.
- `tests/idr/expect/constant-stack.mlir`: that constant-stack and tail-calls hold of @loop, which calls itself back by a musttail call alone, and fail once each where a call keeps its frame or none is made.
- `tests/idr/expect/continuations.mlir`: that contified holds of the module pulled out of the CLEAN lines and fails once, at the one call of @step.case.
- `tests/idr/expect/counted-loop.mlir`: that counted-loop holds of an scf.for and fails once at the scf.while of @tested and once of @straight, which has no loop.
- `tests/idr/expect/counting.mlir`: how the error names the constructor, by its flat name within its type. (and 2 more marks in the file)
- `tests/idr/expect/coverage/expected`: that every property's failing fixture is found, folds-balanced aside
- `tests/idr/expect/crash-sites.mlir`: that crash-sites counts a guard and a crash as one place each and nothing else, failing once for each function given another count.
- `tests/idr/expect/dims-known.mlir`: that dims-known holds of the extent of an array a function is given and fails once at the memref.dim of the array @made made.
- `tests/idr/expect/does.mlir`: that each of Does.cpp's properties holds of the function that does what it says and fails, once, on its complement.
- `tests/idr/expect/facts.mlir`: that facts-as-marked holds of the module pulled out of the CLEAN lines and fails once, at the idr.io.put_str marked as one that may be dropped.
- `tests/idr/expect/folded.mlir`: that folded holds of every function once --canonicalize has folded the arithmetic over constants, and fails once of @left as written, at its arith.addi of two constants.
- `tests/idr/expect/growth.mlir`: that grows-nothing holds of @f against the module itself and fails once against the smaller @f pulled out of the SMALL lines.
- `tests/idr/expect/in-place.mlir`: that idr::bufferize::copies answers for this copy into a fresh memref.alloc.
- `tests/idr/expect/linker-names.mlir`: that linker-names holds of the lowered module pulled out of the CLEAN lines and fails once, at the symbol with a `-` in it.
- `tests/idr/expect/lowered.mlir`: that lowered holds of an llvm.func and fails once at a declaration whose signature takes the world, and that in-llvm holds of the CLEAN module and fails once for the func.func left.
- `tests/idr/expect/memory.mlir`: that aligned-access fails once at the llvm.load that states no alignment, and reads-nothing and writes-nothing once each at the load and the store through a pointer parameter.
- `tests/idr/expect/moves-out.mlir`: that moves-out holds of an idr.array.update and fails once of @readWrite, which reads the element and writes it back as two accesses.
- `tests/idr/expect/narrowed-lanes.mlir`: that narrowed-lanes holds of a loop computing on 32-bit lanes beside its accumulation, and fails once of @scalar, which has no loop on lanes at all, on any target.
- `tests/idr/expect/one-clone.mlir`: that specialized-once holds of @iter's one copy, which calls only itself, and fails once at @walk$a, the copy of walk that calls another copy.
- `tests/idr/expect/output-fused.mlir`: that output-fused holds of a written constant and fails once at the idr.io.put_str of a string built only to be written.
- `tests/idr/expect/paths.mlir`: that loops counts @sum's one loop and @line's none, failing once for each count it is not, and that straight-line fails once at the match of @choose.
- `tests/idr/expect/placement.mlir`: that each of Placement.cpp's properties holds of the functions that place their work on the paths that need it, and fails once, at the op its comment names, in each function that does not.
- `tests/idr/expect/proved.mlir`: that total and not-total read the function's own `total` fact, each failing once on the function that holds the other.
- `tests/idr/expect/reaches.mlir`: that reaches follows calls from body to body to @leaf, two steps from @top, and fails once for @apart, which nothing @top calls names.
- `tests/idr/expect/resets-unshared.mlir`: that this owned module verifies as written, and that resets-unshared fails once, at the take of @shared, whose box a dup of its view gave a second reference.
- `tests/idr/expect/returns.mlir`: that returns, returns-argument and returns-on-paths hold of what each function returns and fail once for each result they misstate, returns-on-paths once for the constant not listed and once for the listed one on no path.
- `tests/idr/expect/reuses-every-cell.mlir`: that this owned module verifies as written, and that reuses-every-cell fails once, at the drop of the token @drop's take yields.
- `tests/idr/expect/signature.mlir`: that signature and convention fail once for each function given another type or convention, or no convention to have, and that entry holds of the CLEAN module and fails once, at the second public function.
- `tests/idr/expect/solved-effects.mlir`: that effects reads each function's declared set, which covers its body as the program's verifier asks, and fails once for each function given another set.
- `tests/idr/expect/stage.mlir`: that stage holds of the stage the program says and fails once, at the program, for another.
- `tests/idr/expect/structured-loops.mlir`: that the idr.tabulate beside a linalg op is the one place @left fails, in the words StructuredLoops.cpp prints.
- `tests/idr/expect/tests-nothing.mlir`: that this owned module verifies as written; that tests-nothing fails once at each of @owned's take and reuse and once of @Prog.main, which takes nothing apart; and that exclusive-copy fails once for @owned.
- `tests/idr/expect/vectorized.mlir`: that vectorized holds of a function computing on vectors and fails of @scalar twice: at its scalar linalg.generic over words, and for computing on no vector at all.
- `tests/idr/expect/words.mlir`: that word-loop holds of a loop on words and fails once of @naturals, whose one loop carries a natural.

## tests/idr/fold (6)

- `tests/idr/fold/closure.mlir`: how a closure constant prints (#idr.closure<@add, [5]>), which the property reads back
- `tests/idr/fold/data.mlir`: how the printer writes a constructor constant (#idr.con), which the property reads back alone, its data type written with its body (and 1 more marks in the file)
- `tests/idr/fold/pending.mlir`: the destination results of idr.con with a hole, and that canonicalize folds the fields given and keeps the read of the hole. (and 1 more marks in the file)
- `tests/idr/fold/poison-fields.mlir`: the module only the deleted folds read is gone; the program is read directly, and defunctionalizes and lowers with and without the canonicalizer.
- `tests/idr/fold/string-offsets.mlir`: the op of the offset after a character is gone; the other folds and their values are unchanged.
- `tests/idr/fold/strings.mlir`: syntax swept to the data-type-first form

## tests/idr/func (1)

- `tests/idr/func/call-effects.mlir`: that idr.call declares every effect to upstream, so canonicalize keeps every call, and answers move and delay with its callee's effects.

## tests/idr/identity (1)

- `tests/idr/identity/identity.mlir`: that idr-identity, the first step of each function's cleanup, rewrites the calls of each recursive function that gives back its argument, as the identities are solved per component.

## tests/idr/loops (4)

- `tests/idr/loops/accumulate.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool.
- `tests/idr/loops/tail-loop.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/loops/trmc-counter.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/loops/trmc.mlir`: that idr-trmc's clone of @copy, which keeps its location, takes the destination of the constructor's hole (the con's results) and idr-tail-loops makes it a loop. (and 1 more marks in the file)

## tests/idr/lower (21)

- `tests/idr/lower/arrays.mlir`: the lowered signatures, the components of an array at a function boundary (the cell, then its dynamic sizes; a rank-0 array is its cell alone), with the runtime's symbols named as idris_rt.h declares them.
- `tests/idr/lower/big-fast-path.mlir`: that a program whose big operands are small by construction imports nothing of the runtime's big functions, its small cases inline, and that one on bigs of any size imports the add's large case, rt::big::addLarge, and not the add's entry.
- `tests/idr/lower/box.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/closure-left.mlir`: the texts of the stage errors, and the op each is reported at.
- `tests/idr/lower/constants.mlir`: the lowered type of @values, Num as its tag and one slot for each constructor's field, as data-layout.mlir lays a sum out. (and 1 more marks in the file)
- `tests/idr/lower/counting.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/crash.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/force-by-name.mlir`: the dispatch idr-defunctionalize makes of a memo sum whose label is by name: its label's case calls the function and neither enters nor settles the cell.
- `tests/idr/lower/force-excl.mlir`: the form a force of an exclusive memo cell takes after idr-rc: its state taken apart and its token freed, with no idr.memo.enter or idr.memo.settle; and the syntax of idr.take of a constructor without fields. (and 1 more marks in the file)
- `tests/idr/lower/force-view.mlir`: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes of a memo sum.
- `tests/idr/lower/internal-errors.mlir`: the text of the alignment error; check it against idr-lower.
- `tests/idr/lower/layout.mlir`: that each program lowers, as the layout lifts the limits: a cell of more counted references than its header counts holds a count word after the header, and a sum of more constructors than a tag counts is a two-level sum.
- `tests/idr/lower/linear-constant.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/llvm-facts.mlir`: @walk reads no offset after a character now; the lowered facts of the other functions are unchanged. (and 1 more marks in the file)
- `tests/idr/lower/match-lit.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/nat.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/static-thunk.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it. (and 2 more marks in the file)
- `tests/idr/lower/string-build.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/strings-bigs.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/to-llvm.mlir`: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes. (and 1 more marks in the file)
- `tests/idr/lower/value-buffers.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it. (and 1 more marks in the file)

## tests/idr/names (2)

- `tests/idr/names/edit.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)
- `tests/idr/names/reorder.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)

## tests/idr/narrow (2)

- `tests/idr/narrow/descending.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/narrow/versioned.mlir`: that a loop whose natural descends through 70 predecessors in one trip, and one that carries a word beside its natural, are each versioned into a loop on words.

## tests/idr/obs (6)

- `tests/idr/obs/debug-counter.mlir`: RUN 1 writes no module now; the counter's report is unchanged.
- `tests/idr/obs/lowered-input.mlir`: idris-mlir takes the pipeline's output and runs only LLVM's half on it; the program exits 42.
- `tests/idr/obs/lowered-mixed.mlir`: a module with no idr.program holding a non-LLVM op is refused at that op, naming it, exit 1, verdict internal; a func.func module does not parse, exit 1, verdict internal.
- `tests/idr/obs/report-accepted.mlir`: an accepted compilation's report: verdict accepted, no diagnostic, idr-optimize's statistics in bytewise key order, the same bytes at 1, 3, 5 and 13 threads.
- `tests/idr/obs/report-refused.mlir`: a refusal by the parse's verifier exits 3 and the report says refused, with the rule, file and line.
- `tests/idr/obs/stats.mlir`: the statistics' descriptions.

## tests/idr/optimize (6)

- `tests/idr/optimize/caller-cap.mlir`: the chain's sizes against the cap as idr::inlineSize counts them, and the run time of the 24,000-op module.
- `tests/idr/optimize/case-of-case-calls.mlir`: that case-of-case reads a call between a match and its consumer, or in the match, as its callee's effects under idr-optimize, and as anything without the program's table.
- `tests/idr/optimize/once.mlir`: how the action log prints the node's function after its tag, as the pinned MLIR's ActionLogger writes an IR unit.
- `tests/idr/optimize/pure-call.mlir`: that idr-pure-calls erases the unread calls of pure callees, one that takes a linear value among them, and merges the identical ones, and keeps every other call; and that counting then releases the linear string the erased call took.
- `tests/idr/optimize/specialize-ends.mlir`: that idr-optimize ends on recursions whose static argument changes at every call: a key that differs from an earlier one only in its scalars is lifted to the key with those scalars as parameters, one with more structure is refused and its call stays a call, and each function is specialized at most one step deep.
- `tests/idr/optimize/totality.mlir`: the run time of the module, whose 1,025 requests make as many copies as the rule over recursive components keys.

## tests/idr/pipeline (4)

- `tests/idr/pipeline/known-label.mlir`: that the specialization on the known constructor is made and @inc inlined into it.
- `tests/idr/pipeline/stages.mlir`: the stages each pass sets and idr-entry taking the program apart.
- `tests/idr/pipeline/steps.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)
- `tests/idr/pipeline/time-trace.mlir`: the pipeline's output under one thread is byte-identical to its output under the pool. (and 1 more marks in the file)

## tests/idr/raise (9)

- `tests/idr/raise/apply.mlir`: that the call of @pick is raised, as a call whose result a dispatch consumes is.
- `tests/idr/raise/branches.mlir`: that each region's dispatch meets the constructors @greet builds once it is inlined, as the inner pipeline folds them. (and 1 more marks in the file)
- `tests/idr/raise/builds-actions.mlir`: that the effects summary gives @actions no effect, so its call is raised across the output.
- `tests/idr/raise/chain.mlir`: that the chain folds in the root, by inlining and the case of a known constructor.
- `tests/idr/raise/io-loop.mlir`: that the loop is left as one self tail call with no dispatch over a box, after the sums and the cleanup.
- `tests/idr/raise/projection.mlir`: that the projection and dispatch fold in the root once @greet is inlined. (and 1 more marks in the file)
- `tests/idr/raise/sunk-call-paths.mlir`: that a call that may crash or not return sinks only into every region, past nothing but computing, and that a pure call taking a linear value sinks onto fewer paths, its value released where unused.
- `tests/idr/raise/sunk-call.mlir`: that sinking reads a call's effects as its callee's, so the call of the total @pmk moves into the one region that applies its result and is raised there, while the call of the partial @mk stays before the match.
- `tests/idr/raise/through-linear.mlir`: that the linear enter and use of the action fold away, as the canonicalizer folds a use of an enter.

## tests/idr/rc (15)

- `tests/idr/rc/atom-pairs.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/buffers.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/consumed.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/counts.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/dies-apart.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/exclusive.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/kept-fields.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/live.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/nested-reuse.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
- `tests/idr/rc/regions-counted.mlir`: idr-rc's counting of region ops and loops, which the owned verifier then holds after the pass.
- `tests/idr/rc/returned.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/second-redirect.mlir`: that idr-rc follows the exclusive call of @keep to the call its result feeds, so @sum gets its exclusive copy in the same run.
- `tests/idr/rc/statistics.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/take-at-death.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/verify.mlir`: syntax swept to the data-type-first form

## tests/idr/roles (3)

- `tests/idr/roles/contify.mlir`: that skipping every idr-contify-move action leaves the module as it was, and that idr-contify changes it otherwise.
- `tests/idr/roles/optimize-statistics.mlir`: that idr-optimize reports its inner canonicalize's and cse's counts, and that the inner cse merged the two equal products.
- `tests/idr/roles/pure-calls.mlir`: that skipping every idr-pure-calls action keeps the unread pure call of @unread, and that the module verifies.

## tests/idr/specialize (8)

- `tests/idr/specialize/binding-times.mlir`: the remark text of each binding time, after defunctionalization made each closure a constructor.
- `tests/idr/specialize/countdown-long.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
- `tests/idr/specialize/countdown.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
- `tests/idr/specialize/dictionary.mlir`: that @sumTo is specialized on the whole record and @plus inlined into the copy.
- `tests/idr/specialize/growing.mlir`: one node for @iter, by the rule over recursive components.
- `tests/idr/specialize/higher-order.mlir`: that @map is specialized on the known constructor of @add with its capture a hole.
- `tests/idr/specialize/partial-list.mlir`: that only the entry copy for [1, 2, n] is made and its recursive call passes the tail as a value (inside a recursive component a call keys only the positions passed unchanged along the recursion).
- `tests/idr/specialize/static-table.mlir`: the rule over recursive components: the table passed unchanged along the recursion keys the copy once; the index going down keys nothing. (and 1 more marks in the file)

## tests/idr/structure (5)

- `tests/idr/structure/columns.mlir`: idr-columns' signatures: a tensor of one-constructor records becomes one tensor per field, in the fields' order.
- `tests/idr/structure/never-returns.mlir`: a region ending in ub.unreachable, lowered by idr-structure-loops.
- `tests/idr/structure/ordered.mlir`: the forms idr-structure-loops gives each op from the effects idr-effects finds.
- `tests/idr/structure/tabulate.mlir`: the lowering of idr.tabulate: a region over words that does nothing beyond compute and crash is one linalg.generic.
- `tests/idr/structure/transpose.mlir`: idr.transpose's folds and its lowering to a linalg op.

## tests/idr/syntax (1)

- `tests/idr/syntax/constants.mlir`: syntax swept to the data-type-first form

## tests/idr/tail-calls (4)

- `tests/idr/tail-calls/decided-loops.mlir`: that a call whose path to the return goes round a loop its constants decide, entering a block again with other values, is a guaranteed tail call, and one round a loop an argument decides is none.
- `tests/idr/tail-calls/long-continuation.mlir`: that a call whose path to the return crosses 5,000 blocks is a guaranteed tail call, and one whose path comes back to a block knowing what it knew there before is none.
- `tests/idr/tail-calls/mutual.mlir`: that idr-tail-calls is the pipeline's last module pass, and the tree printer's file names. (and 1 more marks in the file)
- `tests/idr/tail-calls/positions.mlir`: that the tail-calls and convention properties hold where the printed module showed them, and fail at each call that keeps its frame.

## tests/idr/tie-shape (1)

- `tests/idr/tie-shape/verify.mlir`: the verifier's error texts, idr.tie_shape's; check each against it.

## tests/idr/vectorize (3)

- `tests/idr/vectorize/lanes-x86-64.mlir`: the tree printer's file names for a function. (and 1 more marks in the file)
- `tests/idr/vectorize/rows-aarch64.mlir`: the tree printer's file names for a function (func_func_<symbol>/<n>_<m>_<pass>.mlir). (and 1 more marks in the file)
- `tests/idr/vectorize/rows-x86-64.mlir`: the tree printer's file names for a function (func_func_<symbol>/<n>_<m>_<pass>.mlir). (and 1 more marks in the file)

## tests/idr/verify (12)

- `tests/idr/verify/attributes.mlir`: the texts of the unknown-attribute errors and of the stack rule, and the data types' syntax.
- `tests/idr/verify/con-owned-field.mlir`: that an owned value fills a constructor's plain field, and a borrow does not.
- `tests/idr/verify/cycle.mlir`: syntax swept to the data-type-first form
- `tests/idr/verify/data.mlir`: the texts of a body's errors, as the type's setBody and parser write them.
- `tests/idr/verify/effects.mlir`: the text of the program verifier's effects error, and that a covered pair verifies.
- `tests/idr/verify/flow.mlir`: the texts of the flow rule's errors, as verifyFlow and verifyFlowEdges write them.
- `tests/idr/verify/generic.mlir`: the text of a constant naming no constructor of its type. (and 1 more marks in the file)
- `tests/idr/verify/owned-stage.mlir`: the printed form of idr.take and idr.reuse. (and 1 more marks in the file)
- `tests/idr/verify/program.mlir`: the texts of the program verifier's errors and the ops they are reported at.
- `tests/idr/verify/reduce-regions.mlir`: that idr's reduction pattern leaves no arith op in the reduced module, each value made ub.poison.
- `tests/idr/verify/roundtrip.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)
- `tests/idr/verify/values.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)

## tests/idr/world (1)

- `tests/idr/world/world-once.mlir`: the module verifies; the FileCheck of its own function names is gone.

## tests/lib (2)

- `tests/lib/lit.sh`: every dialect input round-trips through the generic form and bytecode, and every pass a RUN line runs keeps its contracts (--verify-roundtrip --idr-contracts on every idris-mlir-opt).
- `tests/lib/properties.sh`: universal prints one line, universal: holds, where the object, dump and quantity checks printed one each; a failing check still prints its own lines.

## tests/programs (13)

- `tests/programs/arrays/linarray-bubble/expected`: that the port to the size-indexed vector, each position a Fin its loop's test against the size gives, prints the same and keeps its loops count-free and allocation-free
- `tests/programs/arrays/linarray-fannkuch/expected`: that the port to the size-indexed vector, positions checked against the size where they are used, prints the same and keeps its loops count-free, allocation-free and in place
- `tests/programs/arrays/linarray-fill-sum/expected`: that the port to the size-indexed vector, each position a Fin its loop's test against the size gives, prints the same and keeps its loops count-free and allocation-free
- `tests/programs/arrays/linarray-push-pop/expected`: that the port to the size-indexed vector, the stack's size carried with it and a pop on an empty one Nothing, prints the same
- `tests/programs/arrays/linarray-qsort/expected`: that the port to the size-indexed vector, positions checked against the size where they are used, prints the same and keeps its loops count-free, allocation-free and in place
- `tests/programs/arrays/linarray-read-past-size/expected`: that a read at the size of a grown vector, inside its capacity, is refused by the checked conversion of its index (Nothing, printed as out of range) rather than ending the program, and that every check of the expected file holds
- `tests/programs/arrays/linarray-reserve/expected`: that the port to the size-indexed vector, the pushes giving back their size, prints the same
- `tests/programs/arrays/linarray-unionfind/expected`: that the port to the size-indexed vector, nodes checked against the size where they are read or written, prints the same and keeps its loops count-free and allocation-free
- `tests/programs/arrays/linarray-write-past-size/expected`: that a write at the slot a pop left, inside the capacity but at the size, is refused by the checked conversion of its index (Nothing, printed as out of range) rather than ending the program, and that every check of the expected file holds
- `tests/programs/arrays/vec-pop-then-push/expected`: that the port to the size-indexed vector, whose pop gives the element itself, prints the same
- `tests/programs/nat/bits8-past-127/expected`: that a Bits8 of 200, made at run time, is 200 as a Nat and as an Integer, greater than 127 and equal to 200, with no poison from a range put on the tagged word
- `tests/programs/semantics/sem-index/expected`: that runtests --sem-names (tests/Main.idr) lists the 72 chunks and matches the 72 prim- directories
- `tests/programs/stack/mutual-pure-tail-calls/expected`: that constant-stack holds after idr-tail-calls of the program root, named as the frontend writes it ($idris-mlir.root)

## tests/registry (4)

- `tests/registry/base-surface/expected`: that Idris loads a fixture's own module named as a base or prelude module under --no-prelude, and the validation refuses each case at its entry (a missing ruled-out definition as found missing)
- `tests/registry/broken-entry/expected`: that Idris loads a fixture's own module named as a prelude module (Builtin, Prelude.IO) under --no-prelude, and the validation refuses each case at its entry
- `tests/registry/scalar-bytes/expected`: that the iterator reads every scalar value back as the string was packed, with the step idr.str.scalar_bytes computes
- `tests/registry/string-iterator/expected`: that Idris loads the fixture's own Linear.String.Iterator before the installed package's, and the validation refuses each case at its entry; and that it refuses scalarBytes, a definition with a body, at its entry as it refuses the %extern ones

## tests/reject (8)

- `tests/reject/cycle-array-knot/expected`: where the cycle refusal is now reported. The header keeps line 15 (the definition that makes the array), but the identified-type rule that moved cycle-ioref-knot reports at the first idr.con of a type on the cycle, the Nothing on line 17; set the header to what the compiler says, if it is one of the two
- `tests/reject/cycle-ioref-knot/expected`: that the cycle refusal is reported at the first idr.con the program's own code builds of a type on the cycle (line 18), since an identified data type has no location of its own
- `tests/reject/finalizer-collect-any/expected`: that onCollectAny is refused once, as a finalizer, at register's declaration (line 10), naming Prelude.IO.onCollectAny
- `tests/reject/idris-interface-body/expected`: that a data declaration in an interface body is refused at the declaration, line 12, as an error of Idris and no rule of ours, not at its use
- `tests/reject/idris-totality-depth-pragma/expected`: that %totality_depth is refused by the parser at its line, as an error of Idris and no rule of ours
- `tests/reject/polymorphism-growing-rank/expected`: that the request-chain rule refuses at the recursive call, line 14, as it refuses polymorphism-nested at its own, rather than with the refusal of a shape with no spine
- `tests/reject/polymorphism-nested-data/expected`: that a nested data type is refused at its constructor N, line 11, in the polymorphism category, and does not hang
- `tests/reject/raw-pointer-malloc/expected`: that malloc is refused once, as a raw pointer, at scratch's declaration (line 12), naming System.FFI.malloc

## tests/toolchain (11)

- `tests/toolchain/heap-region/expected`: that every cell of a heap under 4 GiB lies in the first cell's 4 GiB region and the heap grows past it, its arrays usable and every cell freed, on both targets
- `tests/toolchain/io-buffer/expected`: that the IO units built for a buffer of 4 and of 7 bytes print what the default build prints, and that echo gives back its input
- `tests/toolchain/runtime-api/expected`: rc.c gained the checks of wide cells, of odd words in object slots and of idris_rt_caf_release, and idris_rt_is_unique takes a cell now, so its checks of NULL and odd words are gone; confirm every check passes and the total reads 101
- `tests/toolchain/runtime-bigs/expected`: that the pinned clang builds bigs.cpp through prop_build with no C++ library on both targets, that every property and box below holds at the run's case count, and that the count, marked as debt in run, ends well within step_limit
- `tests/toolchain/runtime-counting/expected`: that the counting model holds on every case: live cells, each count and exclusivity as idris_rt.h defines them, wide cells, odd words in slots, arrays, view copies and memo cells included
- `tests/toolchain/runtime-doubles/expected`: runtime-doubles is new: confirm that doubles.cpp builds through prop_build with no C++ library and that its 13 properties hold on both targets (each target's strtod and nextafter are its C library's), that runtime-doubles/report is written, and set --cases in run
- `tests/toolchain/runtime-prepared/expected`: that every symbol the prepared runtime needs is one its target's allowlist allows (allowed, with linux/allowed or macos/allowed), on both targets, and that rc.c still behaves alike against the archive and the prepared runtime; the per-target symbol lists are gone
- `tests/toolchain/runtime-start/expected`: that the entry names a missing bit no feature names by its number (this processor lacks bit 63), on both targets
- `tests/toolchain/runtime-strings/expected`: runtime-strings is new: confirm that strings.cpp builds through prop_build with no C++ library and that its 8 properties hold on both targets, that runtime-strings/report is written, and set --cases in run
- `tests/toolchain/runtime-text/expected`: that the pinned clang builds text.cpp through prop_build with no C++ library on both targets, that every property and box below holds at the run's case count, and that the count, marked as debt in run, ends well within step_limit
- `tests/toolchain/runtime-utf8/expected`: runtime-utf8 is new: confirm that utf8.cpp builds through prop_build with no C++ library and that its 7 properties hold on both targets (each target's simdutf kernel), that runtime-utf8/report is written, and set --cases in run

## tests/upstream (8)

- `tests/upstream/constructor-implicit-mark/expected`: that definitions whose clauses leave a constructor's implicit to the elaborator, relevant in v1 and erased in the quantity-0 v3, are accepted as covering under %default total, that implicits the clauses write are still matched (w3 at C3 {x = B} takes its second clause), and that the program compiles and runs, printing (1, 2); and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/erased-constant-pattern/expected`: that a quantity-0 definition splits what its clauses write on an erased argument (a constant in h and pv, a type in tp), so that h 5 reduces to 2 in hFive and in the type of five, which only Two inhabits, and that it does not split a constructor's type implicit that unification solved (len); and that the program compiles and runs, printing 2; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/erased-coverage-nested-match/expected`: that erased definitions whose clauses leave their list index to the elaborator are accepted as covering under %default total, compute in types, and the program compiles and runs; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/evaluator-char-text/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/one-shot-module-function-interface/expected`: written before a toolchain carried the extended patch 24 (upstream's boundary models on FunctionOpInterface and CallOpInterface, the analysis of cycles of calls, results that are not writable and the definite-alias rule, the nearest symbol table) and before idr-bufferize used those models on idr.program: confirm each line below.
- `tests/upstream/relevant-implicit-split/expected`: that definitions above quantity 0 whose clauses leave their relevant list index to the elaborator, with a case block and a with block over it, are accepted as covering under %default total, and the program compiles and runs, reading at run time what only that index holds; and that what holds of every compilation holds of it (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/termination-closure/expected`: that what holds of every compilation holds of this program: its objects import only what is allowed, its dumps parse and verify, no step drops a quantity (universal: holds); the artifacts line is the kinds lib/compile.sh names
- `tests/upstream/totality-unimported-callee/expected`: that the fork refuses Main.caller as not total, Loop.loop, in a module Main does not import, being reachable through ViaLoop.viaLoop, with Idris's own error at exit 3, and does not refuse Main.counted, which reaches the total Count.count the same way
