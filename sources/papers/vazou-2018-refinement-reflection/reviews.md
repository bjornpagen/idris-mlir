POPL '18 Paper #2 Reviews and Comments
===========================================================================
Paper #1 Towards Complete Specification and Verification with SMT Solvers


Review #1A
===========================================================================

Overall merit
-------------
4. Weak accept - will not argue for

Reviewer expertise
------------------
Y. Knowledgeable

Paper summary
-------------
This paper introduces (1) _refinement reflection_, which reflects a function definition in its refined type, enabling users to write equational proofs, and (2) _proof by logical evaluation_ (PLE), which completely automates such proofs. The techniques are implemented in Liquid Haskell and evaluated on verifying algebraic laws.

Pros:
- Paper is well-written, polished and relatively accessible, front-loaded with lots of examples. Paper also provides a compelling story about how the techniques fit together.
- PLE is guaranteed to terminate, setting the technique apart from other SMT-based techniques based on axioms.

Cons:
- Induction is not automated here, while it is in tools like Dafny. In practice, this means that the user always has to provide the inductive skeleton.
- As the authors point out in the conclusion, "the increased automation of SMT and proof-search can sometimes make it harder for a user to debug _failed_ proofs". In my experience, this is also the case with Dafny and F* -- I wonder whether the decidable setting here can simplify debugging.

Comments for author
-------------------
I found the paragraph headings mostly very helpful, though it can give a feeling of fragmentation.

The conjunction elimination rule inlined on line 460 page 10 should use /\ not \/.

Confusion:
- I like section 3, but is it really that novel? It seems to be an intuitive application of Curry-Howard and natural deduction.
- At the end, isn't the translation from lambdaR to lambdaS similar to axioms in other SMT-based techniques?



Review #1B
===========================================================================

Overall merit
-------------
3. Weak reject - will not argue against

Reviewer expertise
------------------
X. Expert

Paper summary
-------------
This paper adds "recursive definition reflection" and "proof by logical evaluation" (a way to reason about recursive definitions in the SMT solver) to Liquid Haskell, and shows that the resulting system can be used as an interactive proof assistant (with automation) using the refinement types as dependent types, in the same style as Agda, but with much more automation.

Pros: This is a cool and powerful idea.

Cons: There is no real formal basis for the soundness claims made in the paper. There is a formal semantics and some stated theorems about it, but no proofs.

In particular, I am very worried about the embedding of all of this into a lazy programming language with possibly non-terminating and crashing computations. The paper mentions the need for termination checks here and there (appealing to our intuition), but termination in the context of a lazy higher-order language is very non-trivial to define compositionally.

Also, it is not clear at all how much these termination checks are in the way in practice (even if everything were sound) in a language like Haskell where partial functions (like head) are so common.

I would be much happier if the authors did their development cleanly for a fully terminating total language first, and then carefully showed how to adapt to a non-termatating, partial language. Alternatively, deal with non-termination and crashing primitively (as done in Vytiniotis et al).

More about termination: When you show that a function has a refinement type, what happens when you provide it with a non-terminating computation (e.g. an infinite list)? Will the resulting program not terminate? What does this say about the lemmas you prove? (Also, see below.)

Lastly, the paper feels more like "look what we can do if we allow reasoning about recursive functions in the SMT solver on top of Liquid Haskell!" instead of "look at this carefully designed way of doing interactive proofs with a lot of automation in Haskell (using refinement types)".

At the moment, the paper feels more like a workshop paper with a cool idea than a finished POPL paper.

Comments for author
-------------------
Abstract: "Thus, via, .." - too many commas

I think you should at least add a full section where you explain carefully and in detail how non-termination and crashing is dealt with in every aspect.

For example, partial functions can not occur in refinements at all? (Maybe they can, but they won´t be reflected?) Can we have refinement types for partial functions at all? (If not, what can partial functions be used for, and why is this OK?)

Can you discuss why the "reflect" keyword is necessary? Can the type checker not figure out which functions should be reflected?

"Automating Equational Reasoning" - this is a bit misleading. You are proposing to deal with equalities *stemming from definitions* in this way. But not with equalities that come from previously proven lemmas! So, you are not complete w.r.t. lemmas (which is why they have to be explicitly invoked in proofs in order to be used).

When you invoke lemmas like that in real code (in order to establish a refinement type of a function you actually use in your program (as opposed to a lemma)), is performance affected? For example you may have a lemma "concat_assoc" that states that ++ is associative, which you need to establish the post-condtion of "reverse". So you invoke "concat_assoc" with the right arguments in "reverse". Is reverse strict in that invocation? Does this affect performance? Can those lemma invocations be removed at run-time?

When you invoke a lemma that is proved using induction, will it loop if it is invoked on an infinite value?

Related work: Kuncak et al "Theory of Recursive Definitions" deals with definitions in a similar way to your PLE. You should refer to this.

There are complete ways of reasoning about equality (various methods based on completion), which you should refer to.

Any other static contract checking system (such as e.g. HALO) could be used in the same way you advocate in the paper, which should be discussed in the related work as well. (Of course, your way of dealing with equality may make it more practical.)

Lean (de Moura) also incorporates dependent types, SMT solver automation, and reflection to perform proofs. You should definitely refer to it.
