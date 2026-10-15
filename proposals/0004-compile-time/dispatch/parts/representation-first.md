## The owner's guideline: representation first

Follow this strictly; it is how every change in this wave is judged.

The biggest lever in programming is the data representation, not the
control flow. When a new case shows up, you can patch the trace of the
computation with another branch, flag or guard, and complexity piles up in
the control flow. Or you can change the data, types and invariants so the
case stops being special, or stops being expressible at all.

- **The data representation determines a program's complexity.** The
  algorithm and the control flow are downstream of it. When complexity
  grows, change the representation before you add to the control flow.
- **Most branches in typical code guard against states a more precise
  representation would make impossible.** Make illegal states
  unrepresentable (Minsky). Parse, don't validate (King): a validator
  checks and throws away what it learned, so every caller checks again; a
  parser returns a type that carries the proof, so the check happens once
  at the boundary. Null is the counterexample: it sits in every type, so it
  forces a check on every use.
- **Most special cases belong to the representation, not the problem.**
  Choose coordinates that dissolve them (Dijkstra's half-open interval,
  homogeneous coordinates, a sentinel node). The ceiling is to turn
  tangled control flow into data and a small evaluator (SICP); Greenspun's
  rule warns that otherwise a complex program grows a bad interpreter by
  accident.
- **A switch on a type tag is a polymorphism not yet named** (Fowler):
  move the variation into data and dispatch.
- **The limit** (Brooks): representation removes accidental complexity,
  not essential complexity. Forcing two genuinely different cases into one
  representation just hides the branching in config flags. Representation
  is globally cheap and locally expensive; a branch is the reverse, free
  now and costly later through drift.

When you reach for a guard, ask instead: what representation would make
this state impossible?
