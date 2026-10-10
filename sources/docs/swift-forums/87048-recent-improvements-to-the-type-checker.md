With the Swift 6.4 release converging, I thought it would be a good time to detail some of the type checker performance improvements we worked on since I shared the [type checker performance roadmap](https://forums.swift.org/t/roadmap-for-improving-the-type-checker/82952) last year. I'm also going to outline a couple of things we plan on looking at next.

## Swift 6.4

The disjunction selection and favoring algorithms in Swift 6.3 allowed us to phase out some older, less principled performance optimizations.

The work in Swift 6.4 can be seen as a continuation of this trend. We looked at various instances of slow expression type checking and came up with some simple but effective optimizations which improve performance in a variety of situations. As with last year's work, these new improvements have rendered obsolete certain older, more narrowly targeted heuristics, which makes the compiler easier to maintain and test.

All of the changes I will describe below can be found in the latest Swift 6.4 development snapshots. Please test and report any issues you find!

### Disjunction pruning

A quick reminder about terminology. Each reference to an overloaded function name generates a "disjunction constraint", which presents the type checker with a choice between one or more overloaded declarations that share the same name but have different types.

The type checker's goal is to find a compatible set of overload choices from each disjunction. In the "main loop" of the constraint solver, we look at all remaining unsolved disjunctions, together with the currently known type of each argument and result at the call site. These types from the call site are compared against the declared type of each overload in the disjunction.

In Swift 6.3, we only differentiated between overload choices that were "favored" vs. not. Here, "favored" roughly means "likely to succeed and lead to the best overall solution". Disjunctions with favored choices were bumped to the front of the line, and the favored choices in each disjunction were attempted first. If a favored choice succeeds, we then skip everything else.

Favoring works well when each guess is correct, because the solver can avoid backtracking entirely in those situations. Many situations involving arithmetic operators are now solved very quickly in Swift 6.3 thanks to favoring. But favoring cannot make a correct guess _every_ time, because we cannot solve _every_ instance without backtracking; and when favoring makes a wrong guess, we often end up with mismatched types at call sites which result in _nothing_ being favored. The solver then has to attempt each overload in turn, and it may very well turn out that they all fail.

Swift 6.4 introduces what we call **disjunction pruning**. When we evaluate an overload choice against the call site, we further differentiate between "favored", "not favored", and a third state, "cannot possibly succeed". Once we know an overload choice cannot possibly succeed, the choice is disabled, and disabled overload choices do not need to be attempted, regardless of whether any other overload choice succeeds.

The immediate consequence is to shorten some dead-ends in the search space. However, it becomes more effective in two special situations where it gives the type checker a "guaranteed winning move":
1. If at any point we find that we have a disjunction where all overload choices _except for one_ are disabled, we can attack this disjunction next, simply by binding that remaining overload choice. Previously, favoring alone would not be sufficient to ensure that this disjunction was always chosen. This has the effect of propagating more type information in the constraint system at no "cost". The resulting constraint simplification might then disable more choices, and so on.
2. Similarly, if any remaining disjunction has _all_ overload choices disabled, we can attempt it next. There is no benefit to any further exploration, because we're at a dead end.

The second case can come up even when type checking a _valid_ expression. Suppose that favoring makes an incorrect guess, so the current combination of overload choices is inconsistent, but you just don't know it yet. You may still have to explore a bit further, but often you will quickly get to a point where _at least one_ remaining disjunction has all choices disabled. Favoring alone has no reason to pick this disjunction next, so you could get a combinatorial search that was doomed to fail. Now, the solver recognizes that it is in this situation, and backtracks immediately.

### Improved binding inference

All of the type checker's overload-related optimizations rely on being able to compare the declared type of each overload choice, against the "currently known" contextual type information at each call site in your expression. If nothing is yet known about the types at a call site---that is, all of the argument and result types are unbound type variables---we postpone considering that disjunction, hoping that binding some other overload first can propagate more type information later. For this to work, types must effectively "flow through" the constraint system as we gradually bind overloads.

The main complication we face here is that Swift has implicit conversions. In general, if you have an expression like `f(g())`, you cannot simply assume that the result type of `g()` is going to be _exactly_ the parameter type of `f()`. There might be a conversion involved--erasing a concrete type to an existential, wrapping a value of type `T` in an optional of type `T?`, and certain more exotic conversions. If either `f()` or `g()` is overloaded, we might have to consider each overload to ascertain the exact concrete types and implicit conversions that are involved.

All of these situations are modeled by creating new type variables, and joining them with _conversion constraints_. (Recall that a "type variable" is the type checker's lingo for an unknown type that must be inferred. You can read more about the design of the type checker in [TypeChecker.md](https://github.com/swiftlang/swift/commits/main/docs/TypeChecker.md).)

The part of the type checker that is responsible for this is known as **binding inference**. In Swift 6.3, the basic design for binding inference was the following. The type checker looked at each type variable that hasn't been bound yet, collecting all subtyping constraints that are adjacent to this type variable. If the other side of one of those conversion constraints was a concrete type, like `$T conv Int`, we add `Int` to the list of _potential bindings_ of our type variable `$T`. Each potential binding was seen as a "candidate type" for `$T`.

Suppose our constraint system contains these two constraints:
```
Int conv $T
$T conv Optional<Any>
```
We would record two potential bindings for `$T`: `Int`, and `Optional<Any>`. However, notice how this list is not exhaustive from a conceptual point of view; `Any`, for instance, happens to be a third type that also satisfies both constraints, because it is a supertype of `Int` and a subtype of `Optional<Any>`. So is `Optional<Int>`. But neither one was directly mentioned by the constraint system, so it is not recorded as a potential binding.

On the other hand, this list of potential bindings might contain _too many_ types. Suppose we add a _third_ constraint in our constraint system:
```
$T conforms Equatable
```
Now, `Optional<Any>` does not conform to `Equatable`, so it's not a valid potential binding at all, but `Optional<Int>`, which again was not in the list, remains a candidate.

To deal with this uncertainty, the type checker would delay binding a type variable on the other side of a conversion constraint until it felt sure the set of potential bindings was complete. It would then attempt each potential binding in turn, and solve the rest of the constraint system. If that fails, it would attempt the next binding, and so on.

This design had several problems:
1. In constraint systems with a large number of conversion constraints, such as expressions involving generics and closures, this "delay" effect meant that disjunction favoring and pruning were not able to make good deductions, resulting in a combinatorial search.
2. Doomed binding attempts that consider invalid potential bindings could introduce unnecessary backtracking, even when an expression does not call any overloaded functions.
3. It can sometimes happen that _more than one_ potential binding succeeds. The type checker would then find multiple solutions with identical overload choices that only differ in bindings, and often be unable to disambiguate the results, rejecting otherwise valid code with a confusing diagnostic.

Swift 6.4 takes binding inference in a new direction. Instead of just collecting a list of potential bindings, we try to more precisely reason about the type variable's _domain_, which is the set of all possible fixed types that it could be bound to. Just like disjunction pruning, this requires introducing some new "algebraic operations" for reasoning about Swift's subtype relation, and in fact the code for these operations is shared between the two optimizations.

I'll walk through some simple examples to give you an idea of exactly what this all means. These won't cover all possibilities, and also the types in real programs will tend to be more complicated; so these optimizations are of course not specific to the case of simple conversions to and from `Int`.

The simplest form of this optimization was partially implemented in the Swift 6.3 binding inference logic already, but it is now more precise. Suppose you have a conversion constraint where a type variable `$T` is converted _to_ an `Int`:

```
$T conv Int
```
How does `Int` behave under implicit conversions? While `Int` is declared in the standard library, as far as the type checker is concerned it is just a plain old struct. Structs don't have arbitrary subtypes in the Swift language, in fact the only subtype of `Int` is `Int` itself. So in this situation, we can, indeed, just bind `$T` to `Int` without delaying the conversion constraint at all.

Now, suppose that instead we have this pair of constraints:
```
Int conv $T
$T conv Optional<String>
```
Considered in isolation, neither one can be solved right away, because some ambiguity remains:
1. The first constraint tells us that `$T` is a _supertype_ of `Int`. While `Int` has no proper subtypes, it does have supertypes: `Optional<Int>`, various existential types, etc.
2. The second constraint tells us that `$T` is a _subtype_ of `Optional<String>`, but `Optional<String>` has a proper subtype now; `String`.

However, let's instead consider the implication of both constraints simultaneously. Notice that the set of supertypes of `Int` has _an empty intersection_ with the set of all subtypes of `Optional<String>`.

We don't have to delay binding `$T` until we discover more constraints involving `$T`. We don't have to attempt both bindings. We don't have to look at any other disjunctions first. There is no possible type you can bind to `$T` at this point. We just backtrack immediately.

Here is another common situation involving a supertype relationship:
```
Int conv $T
$T conforms BinaryInteger
```
Once again, neither constraint can be solved in isolation, but we can look at the intersection of the two sets. Let's think about what `$T` could be:
1. `Int` itself.
2. `Optional<Int>`.
3. Various existential types.
4. `AnyHashable`.

While `Int` itself conforms to `BinaryInteger`, in fact none of the other choices do. This is something you can directly check for 1, 2, and 4. For 3, we can't enumerate all existentials, but we can still check if `BinaryInteger` is a self-conforming protocol. Since it isn't, that option is ruled out. So `Int` is provably the only type in the domain of `$T`, and it can be bound without delay.

Finally, you can imagine the analogous situation where either the original expression was invalid, or we've taken a wrong turn while considering overloads:
```
Int conv $T
$T conforms Sequence
```
Once again, neither constraint can be solved in isolation, but we can still conclude that none of the possible supertypes of `Int` conform to `Sequence`, so in fact `$T` has an empty domain, and we need to backtrack to reconsider an earlier overload choice. Previously, we would simply delay binding `$T` until we learned enough to solve either constraint; this could require exploring a large search space, all of which would ultimately lead to a dead end as soon as any type was bound to `$T`.

These are all heuristics in the end; no algorithm will give us an exact description of a type variable's domain in every situation (unless you believe that P = NP). However, these simple checks I described radically speed up certain expressions.

### Other optimizations

There were many other smaller improvements.

If you recall, back in the Swift 6.2 days, we spent some time optimizing the solver's fundamental data structures and primitive operations, locking in some constant-time performance wins by considering the same number of combinations of choices while spending less time on each choice.

Swift 6.4 adds a couple of optimizations of this nature as well. Something I talked about before is scalability on constraint systems having a large number of type variables. While it is somewhat unusual compared to having a large number of overloads, it still comes up with large collection literals for example. For now, binding inference still visits each type variable on each step of the solver's main loop, the work of re-generating binding sets is now done incrementally, avoiding wasted re-computation when nothing has changed.

### Code cleanups

The type checker in Swift 6.4 can quickly solve certain expressions which stumped Swift 6.3. The new optimizations also solve some _old_ expressions quickly, by which I mean some older, less-general optimizations have been subsumed. For example, the type checker previously had some hard-coded knowledge of SIMD overloads of standard library math operators, but this no longer makes a measurable difference in performance with the tests we've run, so this and a few other special cases are now hidden behind frontend flags. Assuming no issues, these code paths will be removed entirely on the `main` branch soon.

### Testing

The suite of type checker-related tests in the compiler's test suite has grown considerably. This includes correctness tests for overload resolution and binding inference, as well as a collection of "fast" and "slow" expressions. The performance tests now all have a precise operation count expectation, the goal being that even small regressions in type checking performance can be identified quickly.

Swift 6.3 had 157 files in the "fast" directory, and 47 in "slow". Now, we have 213 in "fast" and 65 in "slow". The numbers are of course meaningless in isolation, but they represent a steady turnover: the curated "slow" examples move to "fast" as the type checker improves, and the "slow" set is gradually replenished with new, even harder, expressions. Sometimes, we come across an old bug report that has already been fixed, and the test case goes straight to "fast", but in any case, everything that is now in "fast" is a representative of a user-reported example expression that at some point in the past was slow to type check.

## Examples

Here are a few assorted examples, to demonstrate some common coding patterns which should now type check more efficiently with the above optimizations.

Here is an example using bitwise integer arithmetic. It was too complex to type check in Swift 6.3, and type checks instantly in Swift 6.4:
```swift
func f(word: UInt64, offset: Int, numBits: Int) -> UInt {
    return UInt((word >> offset) & ((1 << numBits) - 1) & ((1 << numBits) - 1) & ((1 << numBits) - 1))
}
```

This example uses the standard library's SIMD types and their overloaded math operators. It was too complex to type check in Swift 6.3, but it now type checks instantly in Swift 6.4:
```swift
func f() {
  let u = SIMD2<Float>(0, 1)
  let v = SIMD2<Float>(1, 2)
  let r = [2*u + 3*v, 4*u + 5*v, 5*u + 6*v, 6*u + 7*v]
}
```

A reference to an implicitly-unwrapped optional `T!` generates a disjunction in the type checker, because the value can then either be used as a `T?` without unwrapping, or force-unwrapped to a `T`. Here, we have a dictionary literal constructed keys and values that are implicitly unwrapped optionals (in a real situation, the keys and values would of course be different values, but the type checker only cares about their types, so the test case ends up looking a bit contrived).

This was too complex to type check in Swift 6.3. Thanks to disjunction pruning, it type checks instantly in Swift 6.4:
```swift
func f(str: CFString!) {
  let _ = [
    str: String(str),
    str: String(str),
    str: String(str),
    str: String(str),
    str: String(str),
    str: String(str),
    str: String(str),
    str: String(str)
  ]
}
```

The next three examples demonstrate progress, and show there is more room for improvement, because ideally they would all type check instantly. These kinds of expressions, with a mix of generics, closures with inferred types, and overloaded APIs, lean heavily on binding inference.

The first example was too complex to type check in Swift 6.3, and now type checks in 10 milliseconds in Swift 6.4:
```swift
func f() {
  let _ = (0...1).lazy.flatMap {
    a in (1...2).lazy.map { b in (a, b) }
  }.filter {
    1 < $0 && $0 < $1 && $0 + $1 < 3
  }
}
```
This second example took 300 milliseconds to type check in Swift 6.3, and now type checks in 4 milliseconds in Swift 6.4:
```swift
func f() {
  print(Array(1...5).filter({ $0 < 3 }).map({ $0 * 10 }).reduce(0, +))
}
```
The third example took almost 300 milliseconds to type check in Swift 6.3, and now clocks in at around 7 milliseconds:
```swift
func f(n: Int, a: [Int]) {
  let _ = [(0 ..< n + a.count).map { Int8($0) }] +
          [(0 ..< n + a.count).map { Int8($0) }.reversed()]
}
```

## Next steps

As always, future plans are tentative and subject to change. For example, in last year's post, there was no mention of disjunction pruning at all, because we only got the idea to try it after I wrote the post. No doubt there will be more surprises ahead.

### Binding inference

I am currently working on the next set of improvements to extend the domain analysis optimizations to more situations. This will help with expressions that contain complex overloads and closures. An important part of this change also generalizes the so-called "type join" operation to those types that contain type variables. This will improve type checker performance with large collection literals.

### Diagnostics

I haven't said anything about diagnostics yet. Remember how upon encountering an error, we restart type checking in a so-called "diagnostic mode". In diagnostic mode, the type checker considers more overload choices and bindings, even if they are invalid, in the hope of finding some set of "fixes" which can be stitched together to present the user with a meaningful set of diagnostic errors. Unfortunately, because diagnostic mode explores more choices than normal mode, this can result in a "cannot type check in reasonable time" error when the input expression is invalid, instead of a proper diagnostic.

While the new optimizations I described above do not run in diagnostic mode just yet, we plan to generalize the binding inference optimizations to handle the case where we are emitting fixes as well, which should greatly improve the performance of diagnostic mode type checking.

### Investigating language changes

Finally, last time I raised the possibility of targeted changes to the semantics of the language. So far, we've tried and (mostly) succeeded in maintaining source compatibility while improving the performance of the type checker, but it's worth mentioning one possibility.

Looking ahead, we think that binding inference can become more effective if we could eliminate a certain form of inference from the language. In our internal testing, we've only come across a handful of projects that rely on the behavior in question, but enough that it warrants some discussion. This post is already a bit long though, so I will explain this all in a separate thread soon.