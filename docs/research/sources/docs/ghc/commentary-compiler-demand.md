# Demand analyser in GHC

This wiki page focuses on information that GHC devs need to know about demand analysis and the corresponding worker/wrapper transformation that feeds on strictness and absence info.

As a first step, it is recommended to get up to speed on demand analysis and notation of demand signatures that is relevant to *users* of GHC, as explained in the [user's guide entry on `-fstrictness`](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/using-optimisation.html#ghc-flag--fstrictness).

Unfortunately, there isn't a single paper (yet) that describes demand analysis as a whole. The relevant sources are:

- The [demand-analyser draft paper (2017)](https://www.microsoft.com/en-us/research/wp-content/uploads/2017/03/demand-jfp-draft.pdf) is as yet unpublished, but gives the most accurate overview of the way GHC's demand analyser works.
- The [cardinality paper (2014)](https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.646.8707&rep=rep1&type=pdf) describes what we call usage analysis today and introduces higher-order call demands. Also described in the demand-analysis draft paper.
- SG wrote a more colloquial [blog post](http://fixpt.de/blog/2017-12-04-strictness-analysis-part-1.html) [series](http://fixpt.de/blog/2018-12-30-strictness-analysis-part-2.html) about strictness analysis. Uses old demand notation, unfortunately.

---

## Demand signatures

See the info in the [user's guide entry on `-fstrictness`](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/using-optimisation.html#ghc-flag--fstrictness).

## Worker-Wrapper split

Demand analysis in GHC drives the *worker-wrapper transformation*,  which exposes specialised calling conventions  to the rest of the compiler.  In particular, the  worker-wrapper transformation implements the unboxing optimisation.

The worker-wrapper transformation splits each 
function `f` into a *wrapper*, with the
ordinary calling convention, and a *worker*, with a specialised
calling convention.  The wrapper serves as an impedance-matcher to the
worker; it simply calls the worker using the specialised calling convention.
The transformation can be expressed directly in GHC's intermediate language.
Suppose that `f` is defined thus:

```hs
f :: (Int,Int) -> Int
f p = <rhs>
```


and that we know that `f` is strict in its argument (the pair, that is),
and uses its components.
What worker-wrapper split shall we make? Here is one
possibility:

```hs
f :: (Int,Int) -> Int
f p = case p of
          (a,b) -> $wf a b

$wf :: Int -> Int -> Int
$wf a b = let p = (a,b) in <rhs>
```


Now the wrapper, `f`, can be inlined at every call site, so that
the caller evaluates `p`, passing only the components to the worker 
`$wf`, thereby implementing the unboxing transformation.


But what if `f` did not use `a`, or `b`?  Then it would be silly to
pass them to the worker `$wf`.  Hence the need for absence
analysis.  Suppose, then, that we know that `b` is not needed. Then
we can transform to:

```hs
f :: (Int,Int) -> Int
f p = case p of (a,b) -> $wf a

$wf :: Int -> Int
$wf a = let p = (a,error "abs") in <rhs>
```


Since `b` is not needed, we can avoid passing it from the wrapper to
the worker; while in the worker, we can use `error "abs"` instead of
`b`.


In short, the worker-wrapper transformation allows the knowledge
gained from strictness and absence analysis to be exposed to the rest
of the compiler simply by performing a local transformation on the
function definition.  Then ordinary inlining and case elimination will
do the rest, transformations the compiler does anyway.

## Discussion


There's ongoing discussion about improvements to the demand analyser.

- Inspired by Call Arity's Co-Call graphs, [this page](commentary/compiler/demand/let-up) discusses how to make the LetUp rule more flow sensitive

## Relevant compiler parts


Multiple parts of GHC are sensitive to changes in the nature of demand signatures and results of the demand analysis, which might cause unexpected errors when hacking into demands. [This list](commentary/compiler/demand/relevant-parts) enumerates the parts of the compiler that are sensitive to demand, with brief summaries of how so.

## Instrumentation


For the [Journal version of the demand analysis paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2017/03/demand-jfp-draft.pdf) we created some instrumentation

- to measure how often a thunk is entered (to see if the update code was useful), and also
- to find out why a thunk is expected to be entered multiple times.


The code adds significant complexity to the demand analyser and the code generator, so we decided not to merge it into master (not even hidden behind flags), but should it ever have to be resurrected, it can be found in the branch `wip/T10613`. Here's the parked [branch](https://gitlab.haskell.org/ghc/ghc/-/tree/wip/T10613).