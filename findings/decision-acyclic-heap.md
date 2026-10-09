# Decision: the heap stays acyclic, and a type that could knot it is rejected

The user agreed to this decision on 2026-10-01.

- **Why counting is the right owner here.** Idris 2 is strict, and its data
  is immutable by default. A new object can only point at objects that
  already exist, so the heap is a dag by construction: no cycle collector,
  no write barrier, a release walk that is complete with no marking phase,
  and an exclusivity analysis whose "count 1 means nobody else" is true
  with no deferred-reference caveat. GHC cannot have this (thunk updates
  make old objects point at new ones; recursive `let` makes real cycles),
  and MLton chose tracing in the 1990s with refs everywhere.
- **The one way to make a cycle is a mutable cell:** an array: `IOArray`,
  `Buffer`, and `IORef`, which is the array of rank 0. Measured: `data Node = MkNode
  (IOArray Node)` with `writeArray arr 0 (MkNode arr)` leaves one live
  cell per knot (1000 knots, `idris-rt: live cells 1000`). Chez's
  collector frees them; counting never will.
- **Policy: forbid, not leak, not collect.** A narrow cycle collector is
  the wrong trade when both facts a cycle needs (a mutable cell, and a type
  that reaches it) are static. The check is on the type reachability graph
  after defunctionalization (closure captures are known types then): data
  constructor fields, closure captures and array element types are edges;
  a cycle through a mutable-cell edge is `unsupported (cycle): an array of
  Node can hold a reference to itself through MkNode`, naming the types on
  the cycle. Type-level, so conservative and sound: `IOArray (IOArray
  Int)` passes, `Node` above is rejected, a graph with back-pointers
  through `IORef` is rejected with the reason.
- **Being a subset is fine.** The compiler accepts a subset of Idris 2
  wherever the subset buys an excellent performance or static-analysis
  tradeoff (the user's rule). An acyclic heap is such a tradeoff: it is
  what makes reference counting exact and what the exclusivity work rests
  on. Programs that need cyclic mutable structures are rare, and they are
  told why.
- **Work:** task #102. The knot program is the reject fixture with its
  message; an array-of-arrays program with its expected output is the
  passing one. `IORef` landed as the array of rank 0 (`memref<E>`), so
  the same edge covers it: the knot through an IORef is refused as
  `unsupported (cycle): an IORef of ...` (tests/reject/cycle-ioref-knot).
