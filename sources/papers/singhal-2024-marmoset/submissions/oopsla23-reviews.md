OOPSLA 2023 Paper #109 Reviews and Comments
===========================================================================
Paper #109 Marmoset : A compiler for automatically optimizing the layout of
Algebraic Data Types


Review #109A
===========================================================================

Overall merit
-------------
D. Reject

Reviewer expertise
------------------
Y. Knowledgeable

Paper summary
-------------
This paper describes a system (Marmoset) for optimizing the layout of ML-style datatypes.  It built on top of another system called Gibbon.  According to the authors, "Gibbon produces dense, packed representations of algebraic data types where unboxed data is accessed directly, without pointer chasing. For example, tree data will be serialized in pre-order into a buffer, and traversing the tree (e.g., to sum all of its elements) will result in, essentially, a linear scan of an array, resulting in no pointer dereferencing and highly-efficient, predictable access patterns."

The key contribution of this paper is an algorithm for inferring the order of datatype fields so that the representation that Gibbon produces matches the traversal order of the functions that use the data.  The authors describe the algorithm and its implementation.  The authors evaluate the algorithm on 2 micro-benchmarks (list reversal and evaluation of an expression tree) and a third benchmark ("blog software case study").

Assessment
----------
The paper tackles an interesting problem (optimization of the layout of data types).  However, the evaluation of the tool is far too limited to be published in a top conference at the moment.  The evaluation does not give the reader any sense of how well the optimization would work if deployed in general in an ML/Haskell compiler.  

The two micro-benchmarks are extremely simple pieces of code (list length, expression evaluation).  I might have expected 20 or so microbenchmarks of this kind.

The blog software case study might also be considered a microbenchmark.  From what I can tell, in the blog benchmark, one defines a list that carries several data items instead of just one (but it is still just a list).  Then 3 simple functions (a filter, a map, and a find) are analyzed *independently of one another* and independently of their use in any larger application context.  My reading of the experiments is that for each function, picks a different representation for the list --- please let me know if I am misinterpreting the experiments.  If this is the case, the blog experiment is essentially three more independent microbenchmarks.  

This reader would like to see how the compiler works on a more substantial application as a whole.  A key challenge is take a large program that uses many data structures, and sometimes uses the same data structure in different ways (different traversal orders) and picks a single representation for each data structure (or having to choose when to use multiple representations of a data structure and having to pay the space cost of replicating it).  The blog case study does not appear to do this.

The paper seems to focus entirely on reading data that has already been allocated. Another question I had was how to arrange for the data to be allocated contiguously (ie, "serialized in preorder in a buffer") in the first place without expensive copying operations.  Data is often shared between structures.  When one functionally updates a balanced binary tree, one typically allocates log n nodes along the path from root to leaf.   How are new nodes are allocated while maintaining the contiguous packed structure?  Does one give up on having a packed structure?   This problem does not seem to be discussed in the paper.

Comments for authors
--------------------
The abstract of the paper states:

"While programmers know that how their data structures are laid out in memory can have significant effects on performance, compiler support to optimize that layout is an under-explored field.  Prior work has either optimized the layout of individual structures without considering how collections of those objects in linked data structures might be laid out, or focused on arranging the placement of linked data structures without considering the internal layout of the constituent objects."

This claim is a bit too broad.  Consider, for example, the work by Peter Hawkins et al on data representation synthesis:

https://dl.acm.org/doi/abs/10.1145/1993498.1993504

The work by Hawkins is clearly different from what is developed here (the input data structure specification language is oriented around relations rather than ML-style data types), but nevertheless, it seems to subvert the broad claim made in the abstract. I would shy away from making such broad claims in the abstract, where there isn't room for explanatory context as there is in the body of the paper.

It is also a good idea to add Hawkins work to the related work section of the paper.

Questions for author response
-----------------------------
In the blogsearch experiment, is the same representation used for all three of the blog functions (FilterBlogs, EmphContent, TagSearch)?  Or is the representation optimized separately for each function?

When one functionally updates a balanced binary tree, one typically allocates log n nodes along the path from root to leaf.   How are new nodes are allocated while maintaining the contiguous packed structure suggested in the paper?  Does one give up on having a packed structure?   In general, how does allocation work?



Review #109B
===========================================================================

Overall merit
-------------
C. Weak reject

Reviewer expertise
------------------
X. Expert

Paper summary
-------------
This paper builds on Gibbon (ECOOP'17), which compiles functions over
tree-structured data to work on a flattened representation of that
data, instead of over the usual representation of tree nodes as
records and tree edges as pointers. The extension reported here
extends Gibbon to infer an order of values within nodes (i.e., fields
within cases of an abstract datatype) to optimize run-time performance
for a given function, where the choice is based on a static analysis
of the function.

Assessment
----------
Strengths:

 * demonstrates that a static analysis is practical

 * demonstrates that the analysis can produce good results, finding
   the optimal ordering for each of a set of benchmarks

 * clear and complete presentation of the analysis and experiments

Weaknesses:

 * missing context for a reader unfamiliar with the motivation behind
   Gibbon

 * substantial gap between the experiments and practical application

Comments for authors
--------------------
Overall, this looks like solid technical work. In the context of
Gibbon, the rationale for the analysis is clear, and while the
analysis approach makes sense, it is not obvious that it would work on
real code and provide measurable benefits.

Still, I had trouble getting started with this paper, because I had
too many questions about how allocation and reclamation would work,
how sharing would work, whether data alignment would be an issue, and
generally how flattening abstract-datatype trees could be a good idea
at all. Reading the Gibbon paper cleared up those questions ---
particularly on the point that a flat representation only makes sense
in some applications. Repeating the whole Gibbon paper here isn't
necessary, but spending a page or so on that context and motivation
could make the Marmoset paper much more accessible.
I still struggle to picture a practical application of Marmoset. Even
if we take Gibbon's practicality as a given, the benchmarks here show
improvements for individual functions, where the representation choice
is tuned to that function. A realistic application seems most likely
to involve multiple functions that all need to work on the same
representation, and so the question becomes one of picking the best
order across a set of functions. It seems straightforward to adapt the
analysis in this paper to merge contributions from multiple
functions, but a single choice will dilute the performance benefit.
The experiments here do not speak to the end-to-end benefit for such
an application. Finally, while the blog benchmark programs seem like
kinds of tasks that sometimes needs to be done, it takes some
imagination to picture these kinds of computations as the bottleneck
for a blog-hosting service.

Small editing comments:

Line 379: Is this just saying it's a directed graph (with weights on
the edges), as opposed to a multigraph?
 
Line 498: The second "j" should be "i".

Table 1: Why isn't the Marmoset column exactly the same as List'
column? Isn't Marmoset just picking an order, so it should match
exactly one or the other?

Tables 2-4: It seems like using milliseconds instead of seconds would
be a better choice for all tables, especially since you can avoid
scientific notation (i.e., e-2 and e-3).

Table 5: There must be a better way here. First, a reader has to flip
between tables 3 and 5 to figure out which numbers should be expected
as blue and which should be expected as red; it seems like some
summary of table 3 should be integrated into table 5. Meanwhile,
numbers written as "1.03e7" and "1.31e6" at first look about the same,
until you remember that "e7" is 10 times as large as "e6"; it would be
better to pick a single exponent for all cells in the table. The
"instructions" rows are total instruction counts, not
instruction-cache hits or misses, right? (But the table description
talks about blue and red as related to cache misses.)

Questions for author response
-----------------------------
I would be interested to hear more thoughts on applications and how
specializing to individual functions would play out end-to-end.



Review #109C
===========================================================================

Overall merit
-------------
C. Weak reject

Reviewer expertise
------------------
Y. Knowledgeable

Paper summary
-------------
The paper extend the compilation technique in Gibbon that realized a serialized data layout for user defined algebraic data types in a functional language. The extension optimizes data layout with respect to a function that accesses the data so that the function will access the data almost sequentially. The optimization algorithm creates a model of a given function that represents cost of field accesses that vary in different order of fields in the memory layout, and finds the field ordering that gives the minimum cost by using an ILP solver. The idea was evaluated by comparing execution times of the programs that are optimized by the proposed algorithm and that are created by reordering fields by hand. The evaluation used two micro benchmarking programs (element counting functions and a logical expression interpreter) and the three functions that traverses a list of Blog articles in different ways. The evaluation showed that the proposed algorithm can find the layout that give the same performance as the best hand-reordered layouts.

Assessment
----------
The idea to find optimal data layout by analyzing a function that accesses the data is original. The approach transform the optimization problem into an ILP is promising.

I see however a couple of weaknesses in the proposed approach and the evaluation.

As for the approach, it optimizes a data layout to one function. When a program manipulates a data with more than one functions each of which works best with a different layout from the others, we cannot simply apply the proposed approach.  We maybe apply the optimization algorithm to the whole program that consists of those functions. But it is not clear if the algorithm can work well such a function (as the paper says that the algorithm does not inline function calls inside a function) in terms of analysis times and effectiveness of optimization. We maybe apply the optimization to each function, which however requires conversion of data from one function to another. Such a conversion might degrade the speedup obtain from the optimal layout.

As for the evaluation, it only concerns only a few number of programs.  Even thought the paper says "realistic", it uses functions extracted from one hypothetical Blog application.  In order convince ourselves that the approach would work for variety of algebraic datatypes and variety of functions, we would like to see more programs used in the evaluation.



R2 Response by Author [Vidush Singhal <singhav@purdue.edu>]
---------------------------------------------------------------------------
======================================================================

We would like to thank the reviewers for their detailed reviews and comments about the shortcomings of our paper and how we can improve upon these shortcomings. 

These comments are very insightful and will help us in improving this paper in future iterations to be the best version of itself. 

We would like to provide answers to some of the questions as best as possible. 

Reviewer A: 

In the blogsearch experiment, is the same representation used for all three of the blog functions (FilterBlogs, EmphContent, TagSearch)?  Or is the representation optimized separately for each function?

Currently, Marmoset optimises each function and layout mutually and the optimization is not inter-procedural. It only optimises one function and an algebraic data type pair at a time (intra-procedural). Hence, for each of the functions (FilterBlogs, EmphContent, TagSearch), Marmoset generates a different representation for each function that is the most optimal and provides the best performance for that specific function. In addition these functions are separate programs in the benchmarking methodlogy. 

When one functionally updates a balanced binary tree, one typically allocates log n nodes along the path from root to leaf. How are new nodes are allocated while maintaining the contiguous packed structure suggested in the paper?  Does one give up on having a packed structure?   In general, how does allocation work?

When new nodes are allocated, those nodes occupy a new memory region. This new memory region is connected to the old tree by adding an Indirection pointer in the representation of the old tree. This indirection pointer points to the newly allocated nodes of the tree. Hence, the representation contains a mix of packed serialised data and pointers making the representation "mostly serial". This breaks the contiguous representation of the tree, which can only be maintained if we were doing in-place updates. However, if we have to add extra nodes to the tree, having a mostly serial representation ensures that we still get some of the benefits of the packed serialised representation while also having the ability to update the tree. 

Reviewer B:

I would be interested to hear more thoughts on applications and how
specialising to individual functions would play out end-to-end.

We agree that the current version of Marmoset is lacking in optimising the representation across multiple functions. The per-function analysis will have to be extended to work across multiple functions in order to support function composition, that is, inter-procedural analysis. 

There are two ways that this can happen

We would optimise each function and ADT intra procedurally. We think that each ADT's optimization would be independent of any other ADT and hence we can evaluate each (function, ADT) pair independently. 

Once marmoset provides the optimal representation of each ADT, we generate copies of the ADTs and change the function signature to use the respective optimal ADT suggested by marmoset. 

Copy functions would need to be inserted to make sure that each function would get the correct representation of the ADT that optimises the performance of that function. 
This may generate some slow downs when it comes to copying. 

Another approach would be to update the cost function to be global and take into account the cost of executing each function (This would have to be a static analysis to figure out the cost using some heuristic). Based on this global cost function, one particular representation of the ADT would be chosen that minimizes the total cost of executing the pipeline of functions in the program. This would mean that all functions would use the same representation of the ADT. This would avoid adding copy calls for the ADT between function boundaries.  

In terms of applications, we would include some more realistic programs that would benefit from this layout optimization. This would involve finding ADTs where field order has an impact on the performance. We will work on finding such benchmarks and make sure that we have a rich variety in subsequent submissions.



Comment @A1 by Administrator
---------------------------------------------------------------------------
Dear authors,

Thank you for your response. Overall, the reviewers felt that more work is needed for this paper to make it a competitive submission. From your response, it seems that you have a good plan for extending your work and producing a substantially different and improved paper for a future submission.
