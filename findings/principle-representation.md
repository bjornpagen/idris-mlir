# The principle: the representation is the lever

The user's guiding document, condensed. It applies twice here: to how
idris-mlir itself is written, and to the representations it chooses for Idris
programs. The user's standard for the dialect follows from it:

> Every single thing in our MLIR dialect must be load-bearing. We have to keep
> as much richness in our type system as we can, so we can whole-program
> optimize extremely aggressively, far more than MLton.

## Purpose

The biggest lever in programming is the data representation, not the
control flow. When a new case shows up, you can patch the trace of the
computation with another branch, flag or guard, and complexity piles up in
the control flow. Or you can change the data, types and invariants, so the
case stops being special or stops being expressible at all. Brooks, Pike,
Raymond and Torvalds said this in almost the same words across fifty years,
and type theory explains why it works.

## Spiky points of view

1. **The data representation determines a program's complexity.** The
   algorithm and the control flow are downstream of it. When complexity
   grows, change the representation before adding to the control flow.
2. **Most branches in typical code do not handle the problem.** They guard
   against states that a more precise representation would have made
   impossible.
   - Three flags give eight states, and a four-case sum gives four
     (Minsky: "make illegal states unrepresentable").
   - Validation throws away what it learned, while parsing returns a type
     that carries the proof (King: "parse, don't validate").
   - Null sits in every type, so it forces a check on every use (Hoare).
3. **Most special cases belong to the representation, not the problem.**
   Change the representation and they are gone rather than handled.
   - Dijkstra's half-open interval.
   - Homogeneous coordinates.
   - Sentinel nodes.
   - At the ceiling, control flow reified as data with a small evaluator
     (SICP ch. 4). Greenspun's rule is the warning.

## Insights

- **Two ways to absorb a new case.** Patch the trace, or change the
  structure: the same problem on two surfaces, with opposite cost profiles.
- **The lineage.**
  - Brooks (1975): "Show me your tables, and I won't usually need your
    flowcharts; they'll be obvious." Representation is the essence of
    programming.
  - Pike (1989), Rule 5, "data dominates", citing Brooks p. 102.
  - Raymond (1997): "smart data structures and dumb code", citing Brooks.
  - Torvalds (2006): "good programmers worry about data structures and
    their relationships". Git's object model is his proof.
- **Types remove branches.** Illegal states are the hidden source of
  branching.
  - A parser moves the tested information into the type, so the check
    happens once, at the boundary.
  - A polymorphic signature is an enforced specification. Reynolds'
    abstraction theorem and Wadler's free theorems: code cannot branch on
    a representation it cannot see.
- **Techniques that remove branches.**
  - Polymorphic dispatch (Fowler), in place of a switch on a type tag.
  - A null object (Woolf) or a sentinel (CLRS), in place of boundary
    checks.
  - Choosing coordinates (Dijkstra, homogeneous coordinates).
  - Control flow as data (tables, state machines, an AST and an evaluator).
- **The limit.**
  - Representation is globally cheap and locally expensive, and a branch
    is the reverse. That cost structure is why the branch is the reflex.
  - Representation removes accidental complexity, not essential
    complexity (Brooks, "No Silver Bullet"). Forcing two genuinely
    different cases into one representation only hides the branching in
    flags.
  - The right representation often shows only after the imperative
    version exposes the pattern.

## What it means here

- Every type, op, attribute and verifier rule of `idr` carries information
  that a pass consumes, or rules out states. Nothing is decorative, and
  nothing is accepted without meaning (see review-external.md: the dead
  `quantities` attribute).
- Facts Idris proves are kept in types all the way down, where no pass can
  drop them: quantities, erasure, uniqueness, totality, indices and ranges.
  A fact kept as a guard or a discardable attribute is a representation
  not yet chosen.
- When a pass grows a special case, the question is what representation
  would make that case impossible.

Sources: Brooks, *The Mythical Man-Month* ch. 9 and "No Silver Bullet";
Pike, "Notes on Programming in C"; Raymond, "The Cathedral and the Bazaar"
§6; Torvalds, git list 2006-07-27; Minsky, "Effective ML"; King, "Parse,
don't validate"; Hoare, "Null References"; Wadler, "Theorems for Free!";
Reynolds, "Types, Abstraction and Parametric Polymorphism"; Fowler,
*Refactoring*; Woolf, "Null Object"; Dijkstra, EWD831; CLRS §10.2; Foley et
al. ch. 5; SICP ch. 4; Greenspun's tenth rule.
