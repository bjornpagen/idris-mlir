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
less this page, as it stood on 2026-10-15, each with its first mark as
its reason: 211 files. HANDOFF.md gave 134 for the same list at
bfdcac70, which held 145 (`git grep -l NEEDS-ACCEPTANCE bfdcac70 --
tests`), one of them under tests/upstream. Since then the restated
call-effects tests dropped `tests/idr/canon/unused-call.mlir`, whose case
idr-pure-calls now states, and the fixtures of this wave's changes, and
those restated as properties, joined, and so did every fixture whose
constructor constants were swept to the form that writes the data type
first (`#idr.con<!T, @C, [...]>`). A change that adds or removes a mark
lists it here again.

## tests/accept (5)

- `tests/accept/higher-order-dictionary/expected`: that a user dictionary built by applying a function-valued argument to () is accepted as holding one implementation of Eq Int, compiles and runs
- `tests/accept/linear-ambiguous-let/expected`: that a linear pattern let whose right side names an ambiguous function, which only the linear candidate fits, is accepted, compiles and runs
- `tests/accept/show-dependent-pair/expected`: that showing a dependent pair, whose Show constraint reaches the instance as a function field applied past its arity, is accepted, compiles and runs
- `tests/accept/totality-past-depth/expected`: that a recursion smaller only under six matching constructors is accepted as total with no pragma, and runs
- `tests/accept/with-application-scope/expected`: that a with block called again from its right-hand side, from a local definition and from a record update is accepted, compiles and runs

## tests/compiler (3)

- `tests/compiler/dialect-syntax/expected`: the samples' print in the dialects' syntax: the program wrapper (idr.program, the root and the stage), the array ops, data bodies with their constructors' roles, tags in place of constructor names where an op holds a tag, and no scf loop or #idr.con sample; the print below is the one before it, less the #idr.con samples it no longer holds, and the three status lines are the check
- `tests/compiler/fork-loops-terminate/expected`: that the fork's size-change decision judges each component of Loops.idr as expected-stdout says, run through this script against the installed fork
- `tests/compiler/handoff-readable/expected`: how the printer writes an identified data type (an alias at the head of the module, whose body holds `instance`), which the instance check reads; and how it writes idr.program (`idr.program @<name> root(@<root>) stage(higher) {`), which the program check reads

## tests/idr/asm (2)

- `tests/idr/asm/aliases.mlir`: the aliases the printer gives data types, and where it prints them. (and 1 more marks in the file)
- `tests/idr/asm/names.mlir`: syntax swept to the data-type-first form

## tests/idr/bufferize (11)

- `tests/idr/bufferize/aliasing.mlir`: the analysis of released buffers and of call results: each function marked to copy writes a copy, and @fresh writes in place.
- `tests/idr/bufferize/branch-and-match.mlir`: the printed block argument and match result types after idr-bufferize's retyping.
- `tests/idr/bufferize/linear-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/link-read-after-release.mlir`: that idr-bufferize copies at the release.
- `tests/idr/bufferize/pop-box.mlir`: that a pop's read of its last element and the write of the fill behind it become one idr.element.update on the vector's buffer, written in place.
- `tests/idr/bufferize/record-fields.mlir`: which step makes an array of a record one tensor per field is not decided yet; this fixture states the two tensors' bufferization only.
- `tests/idr/bufferize/recursive-thread.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/recursive-value.mlir`: that the boundary analysis settles the cycle of @go's calls, so its result is no copy at any level of the recursion.
- `tests/idr/bufferize/release-constant.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/release-copies.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.
- `tests/idr/bufferize/runtime-cells.mlir`: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc, the buffer idr-rc later adopts; in-place is read right after idr-bufferize.

## tests/idr/canon (7)

- `tests/idr/canon/apply.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/array-moves.mlir`: that the element moves out across the call of the pure @bump under idr-optimize, whose canonicalizer reads the callee's effects, and not under a canonicalizer that has no symbol table; and that under idr-optimize it stays read across output, a call that performs IO, a write in another block, and in a word.
- `tests/idr/canon/evaluated-memo.mlir`: the memo sum's printed body, an identified type with its roles, and that the force became a call of the sum's dispatch, so no force is left.
- `tests/idr/canon/facts.mlir`: that a canonicalizer without the program's symbol table keeps every call where it is and moves nothing across one, and keeps every unused call.
- `tests/idr/canon/match-known.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/output-fusion.mlir`: syntax swept to the data-type-first form
- `tests/idr/canon/record-eta.mlir`: syntax swept to the data-type-first form

## tests/idr/constants (1)

- `tests/idr/constants/run.mlir`: syntax swept to the data-type-first form

## tests/idr/dedup (2)

- `tests/idr/dedup/merge-named.mlir`: that the kept function's location fuses its members', so idr-expect finds the code of either definition there.
- `tests/idr/dedup/merge.mlir`: how the kept functions' fused locations print with -mlir-print-debuginfo.

## tests/idr/defunc (27)

- `tests/idr/defunc/block-argument.mlir`: the sum's printed form and the dispatch.
- `tests/idr/defunc/choice.mlir`: that @pick's sum holds the labels of @add and @dbl, and that the dispatch in @Main.main calls each.
- `tests/idr/defunc/coerce.mlir`: that each set of labels is its own sum: @Main.mkInc's and @Main.mkAdd's of one label each, @Main.use's of both.
- `tests/idr/defunc/curried-apply-poison.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/cycle.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/evaluated-coerced.mlir`: the memo sum's printed form.
- `tests/idr/defunc/evaluated-keyed.mlir`: the printed dispatches.
- `tests/idr/defunc/force-call.mlir`: the memo sum's dispatch idr-defunctionalize makes, and the stage it sets.
- `tests/idr/defunc/grade-linear-argument.mlir`: the dispatch's printed form, as defunctionalization writes it.
- `tests/idr/defunc/grade-linear-result.mlir`: the dispatch's printed form, as defunctionalization writes it.
- `tests/idr/defunc/grade-plain.mlir`: the dispatch's printed form, as defunctionalization writes it.
- `tests/idr/defunc/growing-lazy.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/growing.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/ioref-closure.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/lazy-choice.mlir`: the memo sum's printed form.
- `tests/idr/defunc/lazy.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/many-labels.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/match-field.mlir`: the sum's printed form and the dispatch.
- `tests/idr/defunc/memo-by-name.mlir`: the memo sum's printed constructors.
- `tests/idr/defunc/memo-forced-join.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/memo-rebuild.mlir`: the memo sum's printed form.
- `tests/idr/defunc/memo-sum.mlir`: the sums' printed forms and the dispatches.
- `tests/idr/defunc/state.mlir`: that each closure of the state transformers' one type has the sum of the labels that reach it, none leading back to @Main.seq.
- `tests/idr/defunc/sum-names.mlir`: the sums' printed forms.
- `tests/idr/defunc/tag-limit.mlir`: that a sum of more than 2^16 constructors is a two-level sum and that the 65,537-label module defunctionalizes within the suite's time bound on both targets.
- `tests/idr/defunc/unreached-cell.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)
- `tests/idr/defunc/untaken-region.mlir`: the dispatch's printed form, as defunctionalization writes it.

## tests/idr/e2e (3)

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

## tests/idr/expect (2)

- `tests/idr/expect/counting.mlir`: how the error names the constructor, by its flat name within its type. (and 2 more marks in the file)
- `tests/idr/expect/in-place.mlir`: that idr::bufferize::copies answers for this copy into a fresh memref.alloc.

## tests/idr/fold (4)

- `tests/idr/fold/closure.mlir`: how a closure constant prints (#idr.closure<@add, [5]>), which the property reads back
- `tests/idr/fold/data.mlir`: how the printer writes a constructor constant (#idr.con), which the property reads back alone, its data type written with its body (and 1 more marks in the file)
- `tests/idr/fold/pending.mlir`: the destination results of idr.con with a hole, and that canonicalize folds the fields given and keeps the read of the hole. (and 1 more marks in the file)
- `tests/idr/fold/strings.mlir`: syntax swept to the data-type-first form

## tests/idr/func (2)

- `tests/idr/func/call-effects.mlir`: that idr.call declares every effect to upstream, so canonicalize keeps every call, and answers move and delay with its callee's effects.
- `tests/idr/func/inline.mlir`: the printed form of each root after the optimizer.

## tests/idr/identity (1)

- `tests/idr/identity/identity.mlir`: that idr-identity, the first step of each function's cleanup, rewrites the calls of each recursive function that gives back its argument, as the identities are solved per component.

## tests/idr/loops (5)

- `tests/idr/loops/accumulate.mlir`: the copies are named <owner>.acc.<16 hex digits> from their keys; check that the patterns match them.
- `tests/idr/loops/invariant-fields.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it. (and 1 more marks in the file)
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
- `tests/idr/lower/force-view.mlir`: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes of a memo sum, and the header words the lowering writes for them.
- `tests/idr/lower/internal-errors.mlir`: the text of the alignment error; check it against idr-lower.
- `tests/idr/lower/layout.mlir`: that each program lowers, as the layout lifts the limits: a cell of more counted references than its header counts holds a count word after the header, and a sum of more constructors than a tag counts is a two-level sum.
- `tests/idr/lower/linear-constant.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/llvm-facts.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/match-lit.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/nat.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/static-thunk.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it. (and 2 more marks in the file)
- `tests/idr/lower/string-build.mlir`: syntax swept to the data-type-first form
- `tests/idr/lower/strings-bigs.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/lower/to-llvm.mlir`: the syntax of idr.memo.enter and idr.memo.settle and the dispatch idr-defunctionalize makes. (and 1 more marks in the file)
- `tests/idr/lower/value-buffers.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it. (and 1 more marks in the file)

## tests/idr/names (2)

- `tests/idr/names/edit.mlir`: that the optimizer makes the specialization nodes here, as the binding-time rule allows.
- `tests/idr/names/reorder.mlir`: that the optimizer makes the specialization nodes here, as the binding-time rule allows.

## tests/idr/narrow (3)

- `tests/idr/narrow/constants.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/narrow/descending.mlir`: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
- `tests/idr/narrow/versioned.mlir`: that a loop whose natural descends through 70 predecessors in one trip, and one that carries a word beside its natural, are each versioned into a loop on words.

## tests/idr/obs (2)

- `tests/idr/obs/debug-counter.mlir`: that skipping the action idr-specialize-clone leaves the call of @pow.
- `tests/idr/obs/stats.mlir`: the statistics' descriptions.

## tests/idr/optimize (7)

- `tests/idr/optimize/caller-cap.mlir`: the chain's sizes against the cap as idr::inlineSize counts them, and the run time of the 24,000-op module.
- `tests/idr/optimize/case-of-case-calls.mlir`: that case-of-case reads a call between a match and its consumer, or in the match, as its callee's effects under idr-optimize, and as anything without the program's table.
- `tests/idr/optimize/constants.mlir`: that the constants summary of the recursive @seven reaches @main.
- `tests/idr/optimize/once.mlir`: how the action log prints the node's function after its tag, as the pinned MLIR's ActionLogger writes an IR unit.
- `tests/idr/optimize/pure-call.mlir`: that idr-pure-calls erases the unread calls of pure callees, one that takes a linear value among them, and merges the identical ones, and keeps every other call; and that counting then releases the linear string the erased call took.
- `tests/idr/optimize/specialize-ends.mlir`: that idr-optimize ends on recursions whose static argument changes at every call: a key that differs from an earlier one only in its scalars is lifted to the key with those scalars as parameters, one with more structure is refused and its call stays a call, and each function is specialized at most one step deep.
- `tests/idr/optimize/totality.mlir`: the run time of the module, whose 1,025 requests make as many copies as the rule over recursive components keys.

## tests/idr/ownership (1)

- `tests/idr/ownership/owned-stage.mlir`: the printed form of idr.take and idr.reuse. (and 1 more marks in the file)

## tests/idr/pipeline (6)

- `tests/idr/pipeline/do-block-forced.mlir`: that the whole chain unfolds in @Main.main, by the memo sums and the optimizer's local loop.
- `tests/idr/pipeline/do-block.mlir`: that the sixteen statements unfold into @Main.main.
- `tests/idr/pipeline/known-label.mlir`: that the specialization on the known constructor is made and @inc inlined into it.
- `tests/idr/pipeline/stages.mlir`: the stages each pass sets and idr-entry taking the program apart.
- `tests/idr/pipeline/steps.mlir`: the tree printer's directory for the module (builtin_module_no-symbol-name) and its file names (<n>_<pass>.mlir), as the pinned MLIR writes them.
- `tests/idr/pipeline/time-trace.mlir`: the zone names of idr-optimize's nodes and of the inner pipeline's passes.

## tests/idr/raise (12)

- `tests/idr/raise/apply.mlir`: that the call of @pick is raised, as a call whose result a dispatch consumes is.
- `tests/idr/raise/branches.mlir`: that each region's dispatch meets the constructors @greet builds once it is inlined, as the inner pipeline folds them. (and 1 more marks in the file)
- `tests/idr/raise/builds-actions.mlir`: that the effects summary gives @actions no effect, so its call is raised across the output.
- `tests/idr/raise/chain.mlir`: that the chain folds in the root, by inlining and the case of a known constructor.
- `tests/idr/raise/closed-world.mlir`: that no specialization of the loop is made on the constructors the literal count builds, as the binding times decide.
- `tests/idr/raise/io-loop.mlir`: that the loop is left as one self tail call with no dispatch over a box, after the sums and the cleanup.
- `tests/idr/raise/not-raised.mlir`: the ops between each kept call and its dispatch, as defunctionalization writes the dispatch; and that @pmk's calls are raised.
- `tests/idr/raise/projection.mlir`: that the projection and dispatch fold in the root once @greet is inlined. (and 1 more marks in the file)
- `tests/idr/raise/shared-key.mlir`: the order of the raised calls in the root, which is the order of the applies.
- `tests/idr/raise/sunk-call-paths.mlir`: that a call that may crash or not return sinks only into every region, past nothing but computing, and that a pure call taking a linear value sinks onto fewer paths, its value released where unused.
- `tests/idr/raise/sunk-call.mlir`: that sinking reads a call's effects as its callee's, so the call of the total @pmk moves into the one region that applies its result and is raised there, while the call of the partial @mk stays before the match.
- `tests/idr/raise/through-linear.mlir`: that the linear enter and use of the action fold away, as the canonicalizer folds a use of an enter.

## tests/idr/rc (17)

- `tests/idr/rc/atom-pairs.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/atom-reuse.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/buffers.mlir`: where idr-rc puts the two boundary ops. (and 1 more marks in the file)
- `tests/idr/rc/consumed.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/counts.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/dies-apart.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/exclusive.mlir`: the copy is named <owner>.excl.<16 hex digits> from its key. (and 2 more marks in the file)
- `tests/idr/rc/kept-fields.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/live.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/loops.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/nested-reuse.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
- `tests/idr/rc/regions-counted.mlir`: idr-rc's counting of region ops and loops, which the owned verifier then holds after the pass.
- `tests/idr/rc/returned.mlir`: syntax swept to the data-type-first form
- `tests/idr/rc/second-redirect.mlir`: that idr-rc follows the exclusive call of @keep to the call its result feeds, so @sum gets its exclusive copy in the same run.
- `tests/idr/rc/statistics.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves. (and 1 more marks in the file)
- `tests/idr/rc/take-at-death.mlir`: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer. (and 1 more marks in the file)
- `tests/idr/rc/verify.mlir`: syntax swept to the data-type-first form

## tests/idr/specialize (11)

- `tests/idr/specialize/binding-times.mlir`: the remark text of each binding time, after defunctionalization made each closure a constructor.
- `tests/idr/specialize/countdown-long.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
- `tests/idr/specialize/countdown.mlir`: the rule over recursive components: a call keys only the positions passed unchanged along the recursion, structurally, and a lone number is never a key position.
- `tests/idr/specialize/dictionary.mlir`: that @sumTo is specialized on the whole record and @plus inlined into the copy.
- `tests/idr/specialize/growing.mlir`: one node for @iter, by the rule over recursive components.
- `tests/idr/specialize/higher-order.mlir`: that @map is specialized on the known constructor of @add with its capture a hole.
- `tests/idr/specialize/partial-list.mlir`: that only the entry copy for [1, 2, n] is made and its recursive call passes the tail as a value (inside a recursive component a call keys only the positions passed unchanged along the recursion).
- `tests/idr/specialize/quantity.mlir`: the order of the copy's parameters, the holes of the key left to right.
- `tests/idr/specialize/shared-key.mlir`: the order of the copies after their owner (by name) and of the root among the functions.
- `tests/idr/specialize/static-table.mlir`: the rule over recursive components: the table passed unchanged along the recursion keys the copy once; the index going down keys nothing. (and 1 more marks in the file)
- `tests/idr/specialize/twice.mlir`: that the call is specialized on both shapes, as the key composes them.

## tests/idr/stack (2)

- `tests/idr/stack/loops.mlir`: syntax swept to the data-type-first form
- `tests/idr/stack/stored.mlir`: syntax swept to the data-type-first form

## tests/idr/structure (5)

- `tests/idr/structure/columns.mlir`: idr-columns' signatures: a tensor of one-constructor records becomes one tensor per field, in the fields' order.
- `tests/idr/structure/never-returns.mlir`: a region ending in ub.unreachable, lowered by idr-structure-loops.
- `tests/idr/structure/ordered.mlir`: the forms idr-structure-loops gives each op from the effects idr-effects finds.
- `tests/idr/structure/tabulate.mlir`: the lowering of idr.tabulate: a region over words that does nothing beyond compute and crash is one linalg.generic.
- `tests/idr/structure/transpose.mlir`: idr.transpose's folds and its lowering to a linalg op.

## tests/idr/tail-calls (4)

- `tests/idr/tail-calls/decided-loops.mlir`: that a call whose path to the return goes round a loop its constants decide, entering a block again with other values, is a guaranteed tail call, and one round a loop an argument decides is none.
- `tests/idr/tail-calls/long-continuation.mlir`: that a call whose path to the return crosses 5,000 blocks is a guaranteed tail call, and one whose path comes back to a block knowing what it knew there before is none.
- `tests/idr/tail-calls/mutual.mlir`: that idr-tail-calls is the pipeline's last module pass, and the tree printer's file names. (and 1 more marks in the file)
- `tests/idr/tail-calls/positions.mlir`: that the tail-calls and convention properties hold where the printed module showed them, and fail at each call that keeps its frame.

## tests/idr/tie-shape (1)

- `tests/idr/tie-shape/verify.mlir`: the verifier's error texts, idr.tie_shape's; check each against it.

## tests/idr/vectorize (3)

- `tests/idr/vectorize/lanes-x86-64.mlir`: the versioned loops' printed form after idr-narrow-lanes on the vectorization schedule's loops, and the tree printer's file names for a function. (and 1 more marks in the file)
- `tests/idr/vectorize/rows-aarch64.mlir`: the vectorized loops' printed form after the vectorization schedule and the tree printer's file names for a function (func_func_<symbol>/<n>_<m>_<pass>.mlir). (and 1 more marks in the file)
- `tests/idr/vectorize/rows-x86-64.mlir`: the vectorized loops' printed form after the vectorization schedule and the tree printer's file names for a function (func_func_<symbol>/<n>_<m>_<pass>.mlir). (and 1 more marks in the file)

## tests/idr/verify (8)

- `tests/idr/verify/attributes.mlir`: the texts of the unknown-attribute errors and of the stack rule, and the data types' syntax.
- `tests/idr/verify/cycle.mlir`: syntax swept to the data-type-first form
- `tests/idr/verify/data.mlir`: the texts of a body's errors, as the type's setBody and parser write them.
- `tests/idr/verify/flow.mlir`: the texts of the flow rule's errors, as verifyFlow and verifyFlowEdges write them.
- `tests/idr/verify/generic.mlir`: the text of a constant naming no constructor of its type. (and 1 more marks in the file)
- `tests/idr/verify/program.mlir`: the texts of the program verifier's errors and the ops they are reported at.
- `tests/idr/verify/roundtrip.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)
- `tests/idr/verify/values.mlir`: syntax swept to the data-type-first form (and 1 more marks in the file)

## tests/programs (12)

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
- `tests/programs/data/shapes/mlir.check`: the identified type's body as the printer writes it (the constructors in tag order with their fields); reconcile the two Shape lines below with that syntax.
- `tests/programs/nat/bits8-past-127/expected`: that a Bits8 of 200, made at run time, is 200 as a Nat and as an Integer, greater than 127 and equal to 200, with no poison from a range put on the tagged word

## tests/registry (3)

- `tests/registry/base-surface/expected`: that Idris loads a fixture's own module named as a base or prelude module under --no-prelude, and the validation refuses each case at its entry (a missing ruled-out definition as found missing)
- `tests/registry/broken-entry/expected`: that Idris loads a fixture's own module named as a prelude module (Builtin, Prelude.IO) under --no-prelude, and the validation refuses each case at its entry
- `tests/registry/string-iterator/expected`: that Idris loads the fixture's own Linear.String.Iterator before the installed package's, and the validation refuses each case at its entry

## tests/reject (6)

- `tests/reject/cycle-array-knot/expected`: where the cycle refusal is now reported. The header keeps line 15 (the definition that makes the array), but the identified-type rule that moved cycle-ioref-knot reports at the first idr.con of a type on the cycle, the Nothing on line 17; set the header to what the compiler says, if it is one of the two
- `tests/reject/cycle-ioref-knot/expected`: that the cycle refusal is reported at the first idr.con the program's own code builds of a type on the cycle (line 18), since an identified data type has no location of its own
- `tests/reject/idris-interface-body/expected`: that a data declaration in an interface body is refused at the declaration, line 12, as an error of Idris and no rule of ours, not at its use
- `tests/reject/idris-totality-depth-pragma/expected`: that %totality_depth is refused by the parser at its line, as an error of Idris and no rule of ours
- `tests/reject/polymorphism-growing-rank/expected`: that the request-chain rule refuses at the recursive call, line 14, as it refuses polymorphism-nested at its own, rather than with the refusal of a shape with no spine
- `tests/reject/polymorphism-nested-data/expected`: that a nested data type is refused at its constructor N, line 11, in the polymorphism category, naming Main.T[Int] and the larger Main.T[Builtin.Pair Int Int] its field needs, and does not hang

## tests/toolchain (1)

- `tests/toolchain/runtime-api/expected`: rc.c gained twelve checks (a new array's slots NULL from birth, and idris_rt_memref_copy on views of boxes and of doubles); confirm every one passes and the total reads 85

## tests/upstream (1)

- `tests/upstream/one-shot-module-function-interface/expected`: written before a toolchain carried the extended patch 24 (upstream's boundary models on FunctionOpInterface and CallOpInterface, the analysis of cycles of calls, results that are not writable and the definite-alias rule, the nearest symbol table) and before idr-bufferize used those models on idr.program: confirm each line below.
