
Thanks for your comments. 

We would like to correct #B's misconception that 
"there is no real formal basis ... no proofs". 
The supplementary materials have 20+ pages of 
proofs of all the theorems claimed in the paper.
Furthermore, the issue of laziness has been 
studied extensively by [Vazou et al.ICFP14]
on which we build directly, and which shows 
laziness is orthogonal to our contributions here.

We hope the reviewer will revisit the paper 
in light of these facts.

## 1A

> I wonder whether the decidable setting here can simplify debugging.

Yes, we believe it can, hence our emphasis on a decidable means of
reasoning about functions / performing "computation" at the refinement level.
However, we think of this as a *Pro* of our work, not a *Con*.

> I like section 3 ... is it that novel?

As you and we note, Section 3 is a straightforward application of Propositions as Types.
But it was not obvious in prospect, only in retrospect; the section was the
result of trying to determine whether our technique was as powerful as natural
deduction. Making it work required extending Liquid Types to support existential
quantification (429--435). Also the integration of SMT with Propositions as
Types is novel (413--415, 481--495).

## 1B

> Cons: There is no real formal basis for the soundness claims made in the paper... no proofs

The submitted supplementary material (as cited in 761) has 20+ pages of detailed proofs
of _all_ the theorems stated in the paper, i.e., about the soundness
of the type system, the embedding of ND and the completeness and
termination of the PLE algorithm.

>  I am very worried about the embedding of all of this into a lazy programming language

We have studied the issue of embedding refinements into a lazy language
extensively, in [Vazou et al. ICFP 2014] as cited in (145-149, 249 and 641), 
where we develop the meta-theory _and_ present an empirical evaluation on 
10KLOC of Haskell libraries.

> "how much these termination checks are in the way in practice"

Briefly, with careful defaults and SMT reasoning, less than a single 
line of annotations per 100 LOC, i.e. minimal.

> what happens when you provide it with a non-terminating computation (e.g. an infinite list)?

By default the refinement type checker _rejects_ such programs.
The user can tell the type checker to mark such values as "lazy"
(i.e. potentially diverging) in which case, no refinements are
associated with the potentially diverging value. This yields a
sound system as formalized at length in the ICFP 2014 paper.
We will add further clarification in our current paper. 

> When you invoke a lemma that is proved using
> induction, will it loop if it is invoked on
> an infinite value?

Again, as described in the ICFP 2014 paper, the
type (termination) checker ensures you cannot
invoke a lemma on an infinite value (i.e. the
program is rejected unless lemmas/functions
are invoked on finite values.)

> When you invoke lemmas like ... is performance affected?

No, there is no overhead as all proof terms are just unit
values that are "irrelevant" for the computation.
That is, the proofs need _never_ be executed and
can be eliminated by GHC using the following rewrite rule

{-# RULE "proofs are irrelevant" forall (p :: Proof). p = () #-}

We validate this claim by including detailed
performance measurements (Fig 18, 19 in Appendix J of
supplementary materials) which demonstrates to quote
the paper:

  "we compare the verified and unverified versions of
   our implementation to observe no appreciable
   difference in performance."

