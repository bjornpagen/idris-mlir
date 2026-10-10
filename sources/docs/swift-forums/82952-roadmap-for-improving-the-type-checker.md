# Roadmap for improving the type checker

In the past, we've released various "manifestos" and "roadmaps" to discuss planned improvements to the language. This post is also a roadmap of sorts, but instead, the focus is on the implementation rather than user-visible language changes (however, I will briefly mention a few potential language changes at the very end).

Specifically, I'm going to talk about some work we are doing to improve expression type checking in the Swift compiler. This includes changes that have already shipped in Swift 6.2, changes that are on the `main` development branch, changes that we plan on working on next, and more tentative longer-term plans.

Before talking about specific improvements, I'm going to start with a rather long explanation of this part of the compiler implementation, which to my knowledge has not been summarized in one place yet.

## Introduction

This is all, of course, about the dreaded `the compiler is unable to type-check this expression in reasonable time` error. This error can appear with both valid and invalid code, and the various workarounds are unsatisfactory, to say the least. Splitting up an expression into smaller pieces, introducing type annotations, or attempting other refactorings will sometimes allow valid code to type check, or in the invalid case, surface an actionable diagnostic. However, this breaks flow and becomes a frustrating process of trial and error "shotgun debugging" even for the most experienced Swift programmers. The compiler doesn't even _tell you_ if your expression is valid or not!

### Type-based overloading

Swift supports _overloading_, where multiple declarations in the same scope can share the same name. Swift allows two forms of overloading: by argument labels, or by type. The former case is ultimately handled by name lookup, because argument labels are specified at the call site. Argument label lookup does not introduce any algorithmic complexity in the type checker, so I won't discuss it further. Type-based overloading, on the other hand, requires the type checker to reason about the types of expressions before it can decide the correct overload to pick, which is a more difficult problem. So in the rest of this post, when I talk about overloading, I'm specifically referring to overloading based on types---either parameter or result types.

### Constraint solving

The Swift compiler implements overload resolution by transforming expression type checking into a _constraint solving_ problem.  The compiler always looks at a single expression at a time (with some exceptions, such as multi-statement closures), and proceeds to type-check each expression in turn.

First, we introduce _type variables_ to represent the unknown type of each sub-expression in the syntax tree. Next, we generate _constraints_ to describe relationships among type variables. Examples of constraints include "type `X` is a subtype of type `Y`", "type `X` is the result of calling function type `Y` with arguments `Z`", and crucially for overload resolution, what are called _disjunction constraints_. A disjunction constraint has the form "type `X` is either `Y1`, or `Y2`, or `Y3`, ... or `Yn`", where each `Yn` is the type of an overloaded declaration with the same name.

Once we have our type variables and constraints, we proceed to _solve_ the constraint system by attempting to assign a concrete type to each type variable, in a manner that is consistent with the set of constraints. A set of such assignments is called a _solution_. The constraint solving process can produce zero, one, or many solutions. If no solution was found, the expression is erroneous. If one solution was found, we're done; if multiple solutions were found, we first attempt to _rank_ the solutions in case one of them is clearly "better" than the others. If this ranking fails to produce a winner, we diagnose an ambiguity error.

### Algorithmic complexity

The algorithmic complexity in constraint solving arises as a result of these disjunction constraints, because in the worst case, there is no better approach to solving such a constraint system except to attempt each combination of disjunction choices.

This is somewhat like solving a Sudoku. You can write down a number in a blank square, and then check that the result is a valid board. If it is, you try to fill in another square, and so on. On the other hand, if you get stuck, you _backtrack_ by erasing a previously filled in square, and attempt to place a number somewhere else. If you're lucky and make perfect a guess at each step, you can fill in the whole board without backtracking. At the other extreme, you might end up attempting every possible path to a solution, which can take a long time.

For a more detailed overview of constraint solving in the Swift type checker, see https://github.com/swiftlang/swift/blob/main/docs/TypeChecker.md. For an explanation of why overload resolution is inherently hard, and why every known approach has exponential running time in the _worst_ case, see https://forums.swift.org/t/how-does-compiler-compile-swiftui-code/78483/4 and https://learn.microsoft.com/en-us/archive/blogs/ericlippert/lambda-expressions-vs-anonymous-methods-part-five.

### What does `reasonable time` mean?

Since constraint solving with disjunctions takes exponential time in the worst case, it will always be possible to write down a short program that would require an inordinate amount of time to type check, so the type checker must limit the total amount of work that it does, and fail if this limit is reached.

The Swift type checker imposes two such limits:
- Every time we attempt a disjunction choice, we increment a counter. The counter is reset to zero at the start of each expression, and if the value exceeds one million, we give up.
- The constraint solver also allocates various data structures in a per-expression _arena_, which is then torn down in one shot once type checking this expression ends. If the total size of the arena exceeds 512 megabytes, we give up.

In the past, Swift also had a wall-clock time limit, but this is no longer enabled by default, because it is non-deterministic across machines. Counting operations is a better approach, and most "too complex" expressions don't take longer than 4 seconds on a typical machine in practice.

### Invalid expressions, salvage mode, and diagnostics

In ordinary type checking, the solver stops and backtracks immediately when a constraint fails, but this does not in itself produce precise error messages.

To get good diagnostics after a failure, we restart the solving process again, this time with an expanded search space. This is called "salvage mode." In salvage mode, a failure to solve a constraint is handled differently. Instead of simply failing the constraint and stopping the solver, we proceed as if the failed constraint succeeded, but we also record a _fix_.

For example, if an expression does not type-check because `Int` does not conform to `Sequence`, then this conformance constraint will fail on the first attempt. We then restart type checking in salvage mode. When the bogus constraint comes up again, we pretend that `Int` actually _does_ conform to `Sequence`, but we record a fix, and continue solving more constraints until we're done.

Once we finish solving the constraint system in salvage mode, the collected fixes are then analyzed to produce a diagnostic. Finally, if salvage mode fails but no fixes are recorded, we emit the `failed to produce diagnostic` error.

For more details about the diagnostic architecture, see https://www.swift.org/blog/new-diagnostic-arch-overview/.

# Goals and non-goals

While the worst case behavior is unavoidable, it does not have to be the case that type checking must take exponential time on _all_ expressions, even when complex overload sets are involved. In fact, _most_ expressions do type-check rather quickly, even today. It is also true that for any given single "hard" expression, it is possible to devise a heuristic that will solve it quickly, because in the extreme case, you can hard-code knowledge of that _specific_ problem instance in the constraint solver (of course, we won't do that).

The main goal then, is to devise sufficiently-general heuristics which can quickly solve most realistic problem instances, without hard-coding too many special cases, so that hopefully, the exponential running time only appears with pathological examples which are unlikely to occur in practice. The primary way to accomplish this is to **attempt disjunction choices in the right order**---this includes both choosing the next disjunction to attempt, and the next choice within a disjunction to attempt. Also, we can **avoid considering disjunction choices that lead to contradictions**. By doing this, we can find the valid solutions more quickly, and spend less time exploring long "dead ends."

A secondary goal is to **improve the auxiliary data structures and algorithms** used in the constraint solver, so that even if an exhaustive search must be attempted on a given expression, as will sometimes be the case, we burn less CPU time while considering the same search space.

There are also two non-goals worth mentioning:

1. **Removing overloading from the language.** Without disjunction constraints, a constraint system can almost always be solved very quickly. However, this would be such a major change to the language, and break so many existing APIs, that it is not feasible to attempt at this point, even as a new language mode.

2. **Removing bidirectional inference.** We can also imagine a language design where expressions are type-checked in a strictly bottom-up fashion, starting from the leaves, like in many other C-family languages. This is another drastic simplification that essentially trivializes the whole problem. However, this would require giving up on language features such as polymorphic literals, leading-dot member syntax, closures with inferred types, and parts of generics. All of these are features that make Swift into the expressive language it is today.

# Recent improvements

## Swift 6.2

In Swift 6.2, we spent time profiling the type checker with various larger projects, as well as individual slow expressions, both valid and invalid. This uncovered some bottlenecks, including with the backtracking implementation, various graph algorithms such as computing connected components, and other miscellaneous algorithms.

The first example is an invalid expression where we can see a small improvement. Consider the last line of the below code listing, which appeared in this [blog post](https://danielchasehooper.com/posts/why-swift-is-slow/):

```
let address = "127.0.0.1"
let username = "steve"
let password = "1234"
let channel = 11

let url = "http://" + username 
            + ":" + password 
            + "@" + address 
            + "/api/" + channel 
            + "/picture"
```

The expression is invalid as written, because there is no overload of `+` taking an `Int` and a `String`. On my machine, Swift 6.1 spends 10 seconds to produce an `unable to type-check` error, while in Swift 6.2, we get the same error in 6 seconds. Of course, this is not the desired end state, since we should instead produce a meaningful diagnostic. However, this example specifically illustrates that the type checker is able to do the same amount of work in less time.

For a more realistic example, I measured a project that makes heavy use of overloading and generics, and saw that total type checking time improved from 42 seconds in Swift 6.1, down to 34 seconds in Swift 6.2.

## Swift 6.3

### Optimized disjunction selection

Recent `main` development snapshots introduced a large set of changes that @xedin has been working on for several years now, to improve disjunction selection, by collecting more information to decide what disjunction should be attempted next. Unlike the targeted optimizations in Swift 6.2 which offered incremental wins without reducing the fundamental complexity of the problem, the disjunction selection changes allow the type checker to quickly solve many expressions that we were formerly unable to type-check. The new algorithm can also drastically speed up expressions that would type check, but were just under the limit and thus slow.

These changes replace some older optimizations that would look at the entire expression before solving begins, to attempt "pre-solving" certain sub-expressions. These hacks were rather brittle in practice, so a small change to an expression could defeat the entire hack.

The optimized disjunction selection algorithm instead runs as part of the constraint solver, making it more robust and predictable. The biggest wins can be seen with expressions that involve math operators and literals. Here is a typical example. The Swift 6.2 compiler was unable to type check the below expression, but the compiler from `main` type checks this successfully, in 4 milliseconds:
```
func test(n: Int) -> Int {
  return n == 0 ? 0 : (0..<n).reduce(0) { x, y in
    (x > 0 && y % 2 == 0) ? (((x + y) - (x + y)) / (y - x)) + ((x + y) / (y - x)) : x
  }
}
```

The invalid expression from above, where `+` was applied to `String` and `Int`, is still rejected, however with the new algorithm, it only takes the compiler 2 seconds to reach the limit.

Finally, on the same project I mentioned in the Swift 6.2 summary above, the new algorithm yields a further reduction in total type checking time, down to 12 seconds.

(If you find an expression that type checks on a released version of Swift but fails on a `main` development snapshot, please file a GitHub issue.)

### Optimized constraint solver arena usage

Recent `main` development snapshots also introduce an optimization which eliminates a source of exponential _space_ usage in the constraint solver. This optimization is still disabled by default, but we hope to enable it [soon](https://github.com/swiftlang/swift/pull/84993). (You can enable it with the `-solver-enable-prepared-overloads` frontend flag on a `main` development snapshot if you'd like to test it now.)

This optimization works as follows. Previously, when attempting a disjunction choice for a generic overload, the solver would generate new type variables and constraints corresponding to the generic parameters and `where` clause requirements of the generic overload. If the same overload had to be attempted multiple times, in combination with other overload choices, the same type variables and constraints would be generated every time. These type variables and constraints are allocated in the constraint solver's arena. This space optimization instead allocates these structures once, the first time a disjunction choice is attempted.

For many expressions, this leads to a drastic reduction in constraint solver arena usage. In some instances, it will transform an exponential _space_ problem into a polynomial _space_ problem, even if it still requires exponential _time_. Furthermore, since less space also means less time, the primary benefit here is again a reduction in total type checking time. In the future, pre-generating these structures will also enable further improvements to the disjunction choice algorithm.

On the invalid expression from earlier, where `+` was applied to `String` and `Int`, the constraint solver arena space optimization further reduces the time to reach the limit, down to 1.7 seconds. (That's a more than 5x improvement since Swift 6.1.)

Finally, with the same test project I mentioned twice above, this optimization decreases total type checking time from 12 seconds, down to 10 seconds. (That's a more than 4x improvement since Swift 6.1.)

### Expanding our test suite to cover more fast and slow expressions

To help prevent performance regressions in the future, and to track progress on solving the problem, we have added more test cases to our suite. These have been reduced from user-reported slow expressions in GitHub issues for the Swift project.

Some of the test cases also use our `scale-test` tool, which repeats a common element of an expression (think adding `+ 1 + 1 + 1 ...`), measures the performance of each instance, and then attempts to guess if the resulting problem scales in polynomial or exponential time. This helps catch more subtle issues where a given expression might still appear to be "fast", but becomes slow if you make it just a little bit longer.

These test cases are found in the [validation-test/Sema/type_checker_perf](https://github.com/swiftlang/swift/tree/main/validation-test/Sema/type_checker_perf) directory in the Swift repo. The recently added test cases are in https://github.com/swiftlang/swift/pull/84450, with a few more in https://github.com/swiftlang/swift/pull/84890. We hope to continue expanding the type checker performance test suite over time.

# Future improvements

**Disclaimer:** all of the below is subject to change as our plans evolve.

## Optimizing bindings

Imagine we're solving a constraint system, and we're left with a single unsolved constraint, a conversion from a type variable `T0` to `Optional<Int>`. At this point, in order to proceed, we must "guess" the concrete type to bind to `T0`. While `T0` might just be `Optional<Int>`, another valid choice is `Int`, because `Int` converts to `Optional<Int>`. The _bindings_ subsystem in the constraint solver is responsible for tracking the potential bindings for each type variable by considering unsolved conversion constraints, and ultimately, attempting various potential bindings until a solution is found.

The book-keeping for bindings is rather complicated, and must be updated incrementally as constraints are solved and new constraints are introduced. Another complication is that to choose the next binding to attempt, we must consider all type variables and all of their potential bindings, and rank them according to a heuristic.

Today, this ranking process indeed considers all type variables and all bindings, and ultimately picks just one type variable and just one binding to attempt. This must be repeated for each unbound type variable, which of course results in a _quadratic time_ algorithm.

Thus, even in a constraint system without a large number of complex overloads, it is sometimes possible to observe algorithmic complexity due to bindings. Now, most expressions do not involve a large number of type variables---it is far more common to see a large number of disjunction choices instead. But one situation where a large number of type variables are generated is if you write an **array or dictionary literal** with a large number of elements.

We plan on overhauling the data structures for tracking potential bindings, both to eliminate some duplicate bookkeeping (`BindingSet` and `PotentialBindings` in the implementation) and to make the _choice_ of the next binding to attempt something that can be done in constant or logarithmic time, instead of the current situation where it is linear in the number of type variables. This will radically speed up the type checking of large array and dictionary literals.

Since solving constraints can introduce new bindings, an important decision problem is whether a binding set is "complete". Today, this check is very conservative, so we often don't attempt bindings until we've gone far down a path of disjunction choices. More accurate computation of when a binding set is complete would allow bindings to be attempted sooner, which would reduce algorithmic complexity of type-checking many common expressions.

Another improvement to the bindings logic would allow the solver to reach a contradiction by considering contradictory bindings. Today, if a type variable `T0` is subject to two conversion constraints, for example to `Optional<Int>` and `Optional<String>`, we don't reach a contradiction until we attempt every possible concrete type for `T0`. But in this case, there is no concrete type that converts to both `Optional<Int>` and `Optional<String>`, and so a contradiction could be reached faster, avoiding wasting time exploring dead ends.

These improvements to the binding logic should speed up many expressions, including long collection literals as I mentioned, and also the aforesaid invalid expression where `+` was applied to `String` and `Int`, where we should finally be able to quickly produce an actionable diagnostic.

## Removing more performance hacks

While the new disjunction selection algorithm subsumed many old performance hacks, some hacks remain. Once again, these hacks tend to be applicable in narrow cases only, which introduces performance cliffs when small changes are made to an expression, and they also have "load-bearing" semantic effects which complicate the language model. These will be generalized or subsumed by existing optimizations over time.

It's worth noting that fixing some of these might be source-breaking in extreme edge cases, but we think this is worth the small inconvenience it may cause. Aside from improving performance, this will make the language semantics easier to reason about, and also improve diagnostics.

To make this more concrete, here are a few random examples of hacks that we hope to eliminate:

- Subscripting of `Array` and `Dictionary` types is handled in a special way, with a narrow optimization that dates back all the way to Swift 1.0 (`inferCollectionSubscriptResultType()`). It can result in strange overload resolution behavior in some cases, and of course it doesn't generalize to subscripts on user-defined types.
- When simplifying a function call constraint, we look for the case where all overloads have a common return type (`simplifyAppliedOverloadsImpl()`). This does not handle generic return types at all, and has some strange edge-case behaviors.
- There is an optimization that kicks in when a generic overload set has exactly two overloads (`tryOptimizeGenericDisjunction()`). This is an obvious performance cliff if a third overload is added, even if its not used in the expression.
- A set of optimizations attempt to skip some disjunction choices entirely, and "partition" overload sets for math operators into generic, concrete, and SIMD overloads. This is too specific to math operators, and again leads to strange behavior where a concrete overload is chosen even though a generic overload would result in better solutions or diagnostics.

## Optimizing the handling of partial solutions

One of the steps in our constraint solver algorithm constructs a _constraint graph_, where the vertices are type variables, and the edges relate each pair of type variables that appear in the same constraint. An important optimization detects a situation where this graph has more than one connected component, in which case each component can be solved independently. The "partial solutions" that we obtain from solving each component are then merged to form a solution for the overall constraint system.

In many situations, this can avoid exponential behavior. However, in other situations where a large number of partial solutions are produced, building the data structures representing these partial solutions, and the merging algorithm itself, can dominate type checking time for a given expression.

By building upon the "trail" data structure for speeding up backtracking that was introduced in Swift 6.2, we hope to reduce the overhead caused by partial solutions in those pathological cases. A specific class of expression where this tends to arise is when you have a large collection literal and each element is itself a complex expression.

## Improving salvage mode

While not strictly performance-related, we would also like to eliminate more cases where salvage mode fails to record any fixes, which as I mentioned above, results in the unhelpful `failed to produce diagnostic` error.

In fact, another odd situation can arise with salvage mode today: there are known examples where normal type checking fails, but salvage mode then _succeeds_, in which case we accept the expression. This is a performance problem right off the bat, because such an expression must essentially be type checked twice before a solution is found, even though it is valid.

This is also not intended by design, and it involves certain corners of the language which are not well-understood or tested. Fixing these situations will improve performance in pathological cases, while also cleaning up these edge cases in the language, and improving test coverage. Ultimately, if salvage succeeds in this way, we plan to have the solver emit another "fallback diagnostic" instead of silently proceeding.

Finally, if normal type-checking produces multiple valid solutions, we still enter salvage mode today, before we generate an ambiguity diagnostic. This should not be necessary, and addressing this will speed up diagnostics for certain invalid ambiguous expressions. This will also reduce the probability that salvage mode, which must do more work by design, will then fail with an "unable to type-check" error, instead of emitting an actionable diagnostic using information already gleaned from normal type checking.

# Longer-term future improvements

I'm going to end this post with more tentative ideas, that while not fully fleshed out, have the potential drastically improve type checking performance.

## Changes to operator lookup

So far, I've only talked about changes which are (mostly) source-compatible, and this has been our main focus to date. However, while we've ruled out drastic solutions such as removing overloading or bidirectional inference entirely, we are considering some more targeted language changes, which would be rolled out with upcoming features or language modes.

Consider the `==` operator. This operator is heavily-overloaded, but most overloads are implementations of the `Equatable`  protocol's `==` requirement. In principle, we could avoid attempting each one in turn, simplifying the constraint system that we generate for any expression that involves `==`.

We plan to investigate a scheme where we prune overload sets to hide overloads that witness a protocol requirement, which will simplify overload sets for `==` as well as many other (but not all) operators.

This will require changing the rules for solution ranking, which today always prefer concrete overloads; however, we will need to prefer the generic `Equatable.==` overload in many instances as well. For this reason, such a change might be slightly source breaking, at least in pathological cases, but it might be possible to stage in a way that avoids disruption for realistic programs.

## Changes to polymorphic literals

A common misconception is that polymorphic literals, like integers and strings, themselves introduce overloads, where every concrete type conforming to an `ExpressibleBy*` protocol adds a disjunction choice to the literal. This isn't quite right; a literal such as `"hello world"` will type check if a concrete type is known from the surrounding code, and if that fails, via a default type, which is `String` in this case. So while this acts as a disjunction of sorts, in this case the disjunction only has two choices, and often the default is not attempted at all.

However, an integer literal such as `123` actually has two default types, `Int` and `Double`, and the resulting disjunction has three choices. It might be worth considering a language change where floating point literals must be spelled with a decimal point. Today, expressions involving mixed integer and double literals can be particularly tricky to type check, for this reason.

## Improved constraint solving techniques

Once we are further along with various refactorings and cleanups described above, we will be in a position to implement more advanced constraint solving techniques, such as those commonly used in SAT solvers today. "SAT," or Boolean formula satisfiability, is a related problem to operator overloading. (Like overload resolution, SAT takes exponential time to solve in the worst case, but unlike overload resolution, the "domain" of each type variable is a true or false value. Instead of "constraints", the problem instance consists of a Boolean formula built up from "and", "or", and "not" operations.) Many of the techniques used to speed up SAT solvers can be applied to constraint solving.

A solver that supports **non-chronological backtracking** can jump back over more than one disjunction choice once it detects a contradiction. This avoids the exploration of more dead-ends that necessarily fail, because some constraint further up is already unsatisfiable.

Another technique is **clause learning**. The "naive" approach to constraint solving will discard all state changes when backtracking after a contradiction is discovered. In a solver with clause learning, the algorithm will, roughly speaking, "learn" facts as it goes, recording new constraints that result from backtracking. This ensures that if the same situation arises again, the contradiction can be detected sooner because of the "learned" constraint.

(For those curious to learn more about SAT solvers, here is a blog post I saw the other day with a good summary: https://vaibhavsagar.com/blog/2025/10/22/satisfying-solutions/. A book with a decent introduction is "The Satisfiability Problem" by Schóning and Torán. An in-depth treatment appears in Knuth Volume 4B. Finally, a recent academic paper titled [The simple essence of overloading](https://se.cs.uni-tuebingen.de/publications/benes2025overloading.pdf) by Beneš and Brachthäuser, outlines an interesting approach to overload resolution where the problem is reduced to a [binary decision diagram](https://en.wikipedia.org/wiki/Binary_decision_diagram). Some of the ideas here may apply to Swift type checking as well.)

# Conclusion

There are quite a number of interesting improvements that can be made to the Swift type checker, and we look forward to sharing more updates as we make progress in this area.