ECOOP 2024 Paper #58 Reviews and Comments
===========================================================================
Paper #58 Optimizing Layout of Recursive Data Types with Marmoset


Review #58A
===========================================================================

Paper summary
-------------
The paper describes Marmoset, a compiler pass that analyzes the access patterns of fields in (recursive) algebraic datatypes and computes a *dense layout* for the datatype that is tailor to its usage patterns in the program.
Dense layout means that the data structure is allocated in a linear array as much as possible.
Moreover, fields are reordered to enable access patterns as close as possible to a linear scan over memory. The main goal is to avoid arbitrary access patterns to memory as they are detrimental to caching.
The analysis of access patterns comprises the construction of control-flow and data-flow graphs, data dependencies, and the construction of a field access graph which embodies information about the order of field accesses.
The field access graph is the basis for an access cost analysis which is stated as an ILP problem. The solution to this problem is used to fix an order of fields.
Alternatively, a simple greedy algorithm is proposed instead of using an ILP solver.

The analysis is implemented. Several microbenchmarks are conducted and their results are reported in the paper.

Soundness
---------
2. Weak

Justification and comments on soundness
---------------------------------------
Missing related work:
```
Thaïs Baudon, Gabriel Radanne, Laure Gonnord:
Bit-Stealing Made Legal: Compilation for Custom Memory Representations of Algebraic Data Types. Proc. ACM Program. Lang. 7(ICFP): 813-846 (2023)
```

The comparison with GHC is not useful, maybe even meaningless, because...
* GHC is tailored to lazy evaluation, the support for the `-XStrict` flag was added as an afterthought.
* GHC's ADTs are still polymorphic; a fair comparison would be against MLton, a fully monomorphizing ML compiler
* The last sentence of the abstract is generally misleading. At this point, the reader does not yet not that the language supported by Marmoset is strict, so the comparison with GHC suggests an improvement to lazy datastructures.

The paper concentrates on data access and deconstruction, but it does neither mention nor refer to the issues involved in constructing dense datastructures such as suggested by Marmoset. Clearly, a sophisticated allocator is needed, destination passing style may have to be employed, the interface to GC in unclear.

The impact of data layout on modularity is not discussed.

The paper concentrates on a purely functional setting, but it would be good to also discuss the import of reference cells and/or mutable fields as present in natively strict languages like OCaml or ML.

The assessment is largely based on microbenchmarks, some of which are not conclusive.
The impact on any realistic benchmark suite is totally unclear, so it seems premature to draw any conclusions from the presented results.

L90: the speedup numbers are meaningless without reporting the median, too.

L95: /language-based technology/ -> ADTs are an abstraction.

L282-: The description of the CFG is not sufficiently precise. The text suggests (L285) that each subexpression is a separate CFG node, but this is not the case in Fig. 7. The description of the node for a let-binding is incorrect, because is does not take nested lets into account:
```
let x = (let y = e1 in e2) in e3
```
The edges for conditionals should be marked with their local probabilities. Conditional probability only arises on paths. (is it necessary to complicate the model with these probabilities, if they are discarded right away?)

L312: *base cases typically contribute* ... *in our experience*
Here, the reader cannot reproduce this reasoning because there is no experimental data. 
To support these claims, an experiment is necessary.

L326: *only do a transformation when we deem it to be more cost efficient*
This statement is very imprecise and cannot be reproduced.

L334 what is *traversal 2*

L341: *we classify each field* 
It should be clarified upfront that each field can obtain several attributes; that there are dependencies between attributes; and that some attributes derive from the ADT definition, whereas others derive from the code using it.

L393-432: There are two definitions of `List` in play, which is confusing as the text calls both *list* and the constructors have the same names. (The definition of `List` is not shown.) To resolve the confusion, one could rename the constructors of `List'` to `Nil'` and `Cons'`.

L411 *produces a dense output buffer*:
It would be good to clarify the construction of the output in general (see above).
Is there a single representation per datatype or can a single ADT have multiple representations at different places in a program? If not, why not?

L442 - Table 1: If the work per element of the list was significant, then the difference in performance between `List` and `List'` would be neglegible. Here it's 5%, but it's totally unclear what happens on real programs.

L417: *as the work done on the element field increases* 
Why does this impact the efficiency of the traversal?

L482 *temporal relation*  
The preceding sentences says that this relation may have cycles, which contradicts the idea of a temporal relation.

L511 *we tested our hypothesis by ... making an example*
The readers want to see this example and they want to see the data from this experiment, so that they can follow the conclusion that *the layout did not matter as much*.

L518 why restrict to two edges?

L564 Illustrate the cost model with concrete examples.

L631- This paragraph very briefly mentions an alternative to the expensive ILP-based approach. 
It would be good to properly evaluate this greedy approach and quantify its claimed *suboptimality* experimentally.

L650 *subsequently typecheck*
why does that matter?

L687-Table 2:
Something is weird with these numbers. Potentially, nine runs is not enough to yield a meaningful result.
The point is: Both Mgreedy and Msolver choose `List'` as the layout (and the text should say so).
The code generated by Marmoset runs through the same Gibbon backend as the two left columns (at least, that's how the implementation is described). Hence, the numbers in the `List'`, Mgreedy, Msolver column should be identical in the limit.

L736-Table 3:
Same issue again. Why is Gibbon-LR slower than Mgreedy and Msolver.

L785-Table 4:
* misaligned-pre should not be reported using scientific notation
* it should be highlighted that Aligned-Post, MGreedy, and MSolver are most likely very similar.
Frankly, these three benchmarks have the same access characteristics.
Their qualitative difference is unclear and hence the question, why is it not sufficient to concentrate on one of them?

L834-Table 5:
Why scientific notation? 

L845-Table 6:
* it would be good to explain the abbreviation scheme for, e.g., hiadctb
* it would also be good to give the abbreviation for the layouts computed by MGreedy and MSolver as well as having columns for Gibbon that match these layout exactly. Right now, this is not the case.
* only for `TagSearch` there is a difference in performance between MGreedy and MSolver. This is interesting! But there is no analysis as to why MGreedy is weaker on this benchmark.

L963-Figure 9: This diagram is not explained and it is too small.

L981-Table 8: The rows lack explanation.

L1011-Figure 10: It's not clear what these diagrams are good for. Moreover, it looks like they contain a lot of repetition. Are these bars for single runs?

L1065 *structure of arrays* There should be references for this. One might be:
```
Ben L. Titzer, Jens Palsberg:
Vertical object layout and compression for fixed heaps. CASES 2007: 170-178
```

Significance
------------
3. Acceptable

Justification and comments on significance
------------------------------------------
There is potential in this work, but more experiments on significant benchmarks are needed to fully evaluate its impact. 
In addition, there should be experiments to evaluate the cost/benefit ratio of using the (expensive) ILP-solver vs using the simple greedy approach. 
The paper should also offer a conclusion from the experiments.

Presentation
------------
3. Acceptable

Justification and comments on presentation
------------------------------------------
The paper contains some typos that would be caught by a spell checker.

Some incomplete sentences: L187, L192, and a couple more.

Reviewer expertise
------------------
3. Knowledgeable



Review #58B
===========================================================================

Paper summary
-------------
This paper builds on earlier work on Gibbon, a compiler for packed, serialized data layouts; the extension is to analyse the code under a cost model, and use a linear solver to identify a good layout. The story is nicely told, but the technical content is only informally presented rather than made precise - in this day and age, surely we have better techniques for presenting algorithms and data transformations?

Soundness
---------
3. Acceptable

Justification and comments on soundness
---------------------------------------
I don't really have any grounds to doubt soundness; but neither is there strong evidence to believe it, in the form of precise descriptions and formalisms. In particular, S3 is really rather disappointingly handwavy.

Concretely, I find it difficult to determine from the paper what the possible layouts are for tree-structured data, whereas it is not difficult to guess about linear data. The (rightly informal) sketch in S2 shows only the easy linear case; already at this point I am wondering whether Marmoset can handle trees at all (presumably not graphs, since they're not an algebraic datatype?). Does the "structure of arrays" idea (l433) work also for binary trees, with separate arrays of left-child-pointers and right-child-pointers? S5.3 asserts that it works for binary trees, but gives no hint as to precisely what it does - it would be helpful to see the packed layout possibilities Marmoset offers for these two tree datatypes.

## Minor comments

* 57: Of course code with unfavourable access patterns will be slower than with favourable. The more important question is surely whether code with unfavourable access patterns will be worse off after your "optimization" than it would have been with naive pointer representations.
* 310-315: Also, a fixed weighting on constructors generally does not give a very interesting distribution over data structures. For example, lists with weight alpha for Nil and beta=(1-alpha) for Cons give you length N with weight beta^N*alpha, with exponential decay. That is a priori unlikely to match the weights of your input data. The same problem occurs with random data generation for testing purposes. 
* 554-556: This is a convoluted way of saying that the constraints capture permutations.
* 693: M_Greedy and M_Solver are undefined. Presumably these are the algorithms sketched in S3.6.4 and S3.7?

Significance
------------
4. Strong

Justification and comments on significance
------------------------------------------
There's quite a lot of recent work on approaches to separating algorithmic structure from data layout - of course, it's really rather an old problem (also the essence of relational databases). So this is an important area; and finding the right way to synthesize layouts used by program transformers like Gibbon seems like the right approach. But I think it would be difficult for anyone else to build on anything more detailed than the high-level ideas reported here, because the presentation is so imprecise.

Presentation
------------
4. Strong

Justification and comments on presentation
------------------------------------------
The paper structure is clear, and the writing too. But there are quite a few typos and grammatical errors, listed below.

## Minor comments

* 9: "how collections [...] are laid out"
* 61: I think you mean "slogan" ("battle-cry") - a motto is more philosophical. Though I guess the point could be debated!
* 126: Stray double space in "heap using"? Also l186
* 187: "unneeded data requires"
* 192: "detects that it has"
* 274: "in a polymorphic"
* 325: "we do such a transformation only when"
* 330: It's a stretch to call S2 a "description": illustrated? sketched?
* 390: "whether or not to do"
* 395: "For instance, a function"
* 460: Typeface for "foo" - cf l399, l410
* 418: "representation, because"
* 432: "We argue that"
* 514: "and the start addresses"
* 518: "allow a maximum of two", or better, "allow at most two"
* 547: "where $n$ is the number of fields"
* 604: "if not, we"
* 639: "layout; however,"
* 646: "but we leave"
* 658: The punctuation is confusing in "a LoCal program, which has regions and locations, essentially, buffers and pointer arithmetic". The parentheses on l279 were much better; or use a long dash here before "essentially". But also, aren't you repeating yourself?
* 659: Use a proper arrow.
* 677: "affects cache behaviour (S5.5) and compile times (S6.6)"
* 693: Wrong font for the subscripts in M_Greedy and M_Solver? cf l575-587
* 719: "memory address is"
* 719: "In contrast, if"
* 751: "As can be seen"
* 758: "performance, which matches"
* 779: "increments the values"
* 819: "Rightmost"
* 821: "lower than"
* 839-842: Format this scientific notation properly: that's not a subtraction. Why not write "*10^{-7}"?
* 879: "The last two columns"
* 1066: "where the performance"
* Bib: is unusually carefully done - thank you! But "fuer" should have an umlaut (l1278).

Reviewer expertise
------------------
2. Some familiarity



Review #58C
===========================================================================

Paper summary
-------------
The paper introduces MARMOSET an extension to GIBBON to analyse and optimize the layout of algebraic data types (ADTs). MARMOSET works by transforming the layout of ADTs, such that it matches their data access pattern. In the context of Gibbon, this eliminates most of the pointer chasing when accessing ADT fields. To achieve this goal, a function's control flow graph as well as its data flow graph are combined into a field-access graph. This graph represents the temporal ordering of accesses among an ADTs fields for a given function. The field-access graph is then used to encode an Integer Linear Program, which finds the optimal data layout for an ADT. 
The authors have implemented MARMOSET in the Gibbon compiler and benchmarked two versions of their implementation (MSolver and MGreedy) against Gibbon (without MARMOSET extension) and GHC (when possible). Besides two micro-benchmarks, they could also show a performance improvement for a larger case study. The subsequent discussion goes into details about the compile times and cache behaviour at run time.

Soundness
---------
4. Strong

Justification and comments on soundness
---------------------------------------
The paper includes two micro-benchmark and one case study to empirically show that MARMOSET indeed improves performance for recursive ADT definitions compared to Gibbon and GHC. The authors clearly explain the expected and observed performance results and discuss them in detail. Furthermore, the paper shows, that the compile time overhead of their greedy approach is on par with Gibbon. 

I think an additional case study could make this paper even stronger by focusing on different aspects of the optimization. For example, the authors mention that their implementation performs a global optimization of the ADT layout based on all functions of the program. 
I would like to know how the performance changes, if two or more functions in the same program require different access pattern? What are the tradeoffs involved here? 
Additionally, I would also like to know if there are data structures for which the optimization delivers poorer results or even impairs the performance?

Significance
------------
4. Strong

Justification and comments on significance
------------------------------------------
Recursive algebraic data types are commonly used in functional programming languages. As such, a need for efficient, automatic optimizations for ADTs exists. The authors show that their automatic rewriting of ADT layout using MARMOSET achieves this goal.
Prior work already tackles similar problems, although most of the approaches rely on user provided annotations. MARMOSET seems unique in the way, that they provide an automatic approach for rewriting layouts of ADTs based on static analysis results, that might even be refined by run time information.  
It would be interesting to see to which extend the optimization improves with additional run time information.

Questions for the authors: 
How hard would it be to integrate your optimization into GHC?

Presentation
------------
5. Very strong

Justification and comments on presentation
------------------------------------------
Overall, the paper was well written and easy to follow. The general ideas are clearly stated in the Introduction and Section 2 provides a good example to get an intuition for the optimization. 
Some small things I noticed during reading: 

- Figure 3: Figure 3 could profit from a little more explaining: 
    + I think it is not explained, that the numbers on each arrow correspond to the order in which fields are accessed
    + Line 123: It is never explained what a tag of a constructor is
- Line 910: I think either "chooses" or "places" is redundant here

Reviewer expertise
------------------
2. Some familiarity
