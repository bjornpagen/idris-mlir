Plan for camera ready revision. 
---------------------------------


# Sec 2 (Overview)
- (2a) Add explanation of proof combinator type class trick that allows optional proof argument 
- (2b) Add subsection explaining termination & totality checking & why all refinements should be total
- (2c) Explain why we need the reflect keyword explicitly (for efficiency and because not all Haskell translates to logic, eg type cases, diverging functions)
- (2d) Change Automating Equational Reasoning -> Semi-Automated Equational Reasoning
- (2e?) Add comparison of `swap` using DAFNY (illustrating why PLE != axioms+fuel) https://rise4fun.com/Dafny/ovy6

# Sec 3 (Natural Deduction)
- (3a) Note that it is an embedding, not an isomorphism, since SAT solver is classical
- (3b) Clarify "setting clearer bounds for the expressiveness of SMT-based verifiers" to "Liquid Haskell can express any intuitionistic natural deduction proof"
- (3c?) Put more emphasis on the changes to LH that make the PaT work (we added syntactic sugar for existentials via Abstract Refinement Types)


# Sec 4-5 (Theory)
- (4a?) Delete lambda to SMT encoding since it is trivial, thus it only takes <2 pages and introduces the PLE rule

# Sec 7 (Evaluation)
- (7a)    Add possibility of proof-irrelevance rewrite rule
- (7b?) Add discussions about parallelism benchmarks/run-time and how they introduce no overhead. If they can fit back in ~1pp.

# Sec 8 (Related)
- Add Kuncak et al "Theory of Recursive Definitions" 
- Add comparison to Kuncak et al's "Satisfiability modulo recursive functions" 
- Add comparison to Lean


Extended comments on the reviewers 
-----------------------------------

# Reviewer A 

Q: Induction is not automated here, while it is in tools like Dafny. In practice, this means that the user always has to provide the inductive skeleton. 
A:This is a heuristic in Dafny, we could have it too. 

Q: In my experience, this is also the case with Dafny and F* -- I wonder whether the decidable setting here can simplify debugging.
A: It sure can: compare our local error messages with unpredictable of the above. But, this is a prop if our system.

Q:I like section 3, but is it really that novel? It seems to be an intuitive application of Curry-Howard and natural deduction.
A: Making it work required extending Liquid Types to support existential quantification (429--435). Also the integration of SMT with Propositions as Types is novel (413--415, 481--495).

Q: At the end, isn't the translation from lambdaR to lambdaS similar to axioms in other SMT-based techniques?
That is true, we should clear this section out, but it is already short (<2 pp) (4a)


# Reviewer B

Q: Cons: There is no real formal basis for the soundness claims made in the paper. There is a formal semantics and some stated theorems about it, but no proofs.
But, there are! 

Q: Termination & Totality 
We have solved the termination problem in Refinement Types for Haskell and around this paper we make many references to remind it. In this setting we assume all the proofs and refinements are total,  making our language in practise a terminating language (laziness is not related). We will add a subsection in the overview, summarizing this paper for completeness. (2b)

Q: Can you discuss why the "reflect" keyword is necessary? Can the type checker not figure out which functions should be reflected?
A: For efficiency! The reflect keyword adds a lot of info in the logic, but the logical environments grow. Also, not all Haskell functions can be reflected (eg type cases, diverging, etc). The user directly controls the ones required reflection  (2c)

Q: "Automating Equational Reasoning" - this is a bit misleading. You are proposing to deal with equalities stemming from definitions in this way. But not with equalities that come from previously proven lemmas! So, you are not complete w.r.t. lemmas (which is why they have to be explicitly invoked in proofs in order to be used).
A: Change subtitle to semi-automated Equational Reasoning (2d)

Q: When you invoke lemmas like that in real code (in order to establish a refinement type of a function you actually use in your program (as opposed to a lemma)), is performance affected? For example you may have a lemma "concat_assoc" that states that ++ is associative, which you need to establish the post-condtion of "reverse". So you invoke "concat_assoc" with the right arguments in "reverse". Is reverse strict in that invocation? Does this affect performance? Can those lemma invocations be removed at run-time?
A: Add discussion of performance (7a, b)

Q: When you invoke a lemma that is proved using induction, will it loop if it is invoked on an infinite value?
A: It cannot, under soundness (no disabling termination flag) you cannot generate an infinite list. In ICFP paper, we describe a way to generate a type error in the actual call site. 

Q: Any other static contract checking system (such as e.g. HALO) could be used in the same way you advocate in the paper, which should be discussed in the related work as well. (Of course, your way of dealing with equality may make it more practical.)
A: HALO is already there! 

# Reviewer C

Q: Section 2.3. with the presentation of the various combinators. I actually found the typing of those combinators not making too much sense to me or at least not explained as clear as I had wished.
A: Will do (2a)

Q: Funnily shows only the "easy" direction of the C-H
    correspondence, not that every program corresponds to a proof; is
    that hard or just an application of basic soundness, totality and
    canonical forms?
A: Will clarify that it is not an isomorphism (3a)

Q: Finally, I have one concern about the approach suggested in this work
in general, which is how does the programmer know exactly how to write
a program that exposes all the facts that a proof requires? The
example in 1:4, line 176 highlights this: the programmer
auto-magically just decided to instantiate fib at 0,1,2, because ...??
So, if we were to take an more tactic-based path I would really
recommend more work towards integrating some form of proof state
inspection in an IDE.
A: PLE is exactly this tactic-based path that we are proposing and solves the fib example! 





```haskell
{-@ LIQUID "--higherorder"     @-}
{-@ LIQUID "--automatic-instances=liquidinstances" @-}

module Blank  where

{-@ reflect foo @-}
{-@ foo :: Nat -> Nat @-}
foo :: Int -> Int
foo n = if n <= 0 then 10 else foo (n - 1)

-- LH Fails on the below

{-@ propBad :: n:{ Nat | n < 2 }  -> { foo n == 10 } @-}
propBad :: Int -> ()
propBad n = ()

-- LH succeeds on this however 

{-@ propOK :: n:{ Nat | n < 2 }  -> { foo n == 10 } @-}
propOK :: Int -> ()
propOK 0 = ()
propOK n = propOK (n-1)

-- But DAFNY succeeds because you need to only forcibly unroll upto a depth of 2
-- https://rise4fun.com/Dafny/3cj

{-
function Foo(n:int): int
  decreases n
  {
    if n <= 0 then 10 else Foo(n-1)
  }

 function Prop(n:int): int
   requires (0 <= n && n < 2)
   ensures (Foo(n) == 10)
   {
     0
   }

-}
```



