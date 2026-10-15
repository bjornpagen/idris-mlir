## C08 Inline decisions

Producer: U03, alone. Consumers: U04 (a specialization node's `calls` is
one per request, the facts a made node gets), U17 (`largest-function`
reads `idr::inlineSize`, C24; the caller-cap fixture reads the cap), U18
(the D25 record on the owner's machine). Paths are under `foreign/idr/`.
Line numbers are the tree at a3e61f3a.

What decides whether a call is inlined: MLton's per-function rule
(`sources/code/mlton/mlton/ssa/inline.fun:217-295`, its numbers
`control/control-flags.sml:1011-1041`, today's
`lib/Analysis/Inline.cpp:23-25, 42-53`), read once per call on the
callee's final body, plus the per-caller cap (0004 §4 stage 7, D14, D25).
The decision is a pure function of the callee's facts and the caller's
size; nothing in it reads a schedule, a count of rounds or a module.

### The header: `include/idr/Analysis/Inline.h` (replaces today's whole file)

```cpp
// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
#ifndef IDR_ANALYSIS_INLINE_H
#define IDR_ANALYSIS_INLINE_H

#include "idr/IR/IdrDialect.h"

#include <cstdint>

namespace idr {

// How many operations the body of `fn` holds: what a walk of it counts,
// the return and every nested op included, the function itself not.
int64_t inlineSize(idr::FuncOp fn);

namespace inlining {

// MLton's numbers: a leaf of at most kLeafSize ops always inlines; any
// other function when (calls - 1) * (size - kSmall) <= kProduct.
inline constexpr int64_t kLeafSize = 40;
inline constexpr int64_t kSmall = 60;
inline constexpr int64_t kProduct = 320;
// The most ops a caller holds with a callee's body in it.
inline constexpr int64_t kCallerCap = 10000;

// What the rule reads of a callee, all of it fixed once the callee is
// final.
struct Facts {
  // inlineSize of the final body.
  int64_t size = 0;
  // calls(f): the module's idr.call sites naming f when idr-optimize
  // began; 1 for a specialization node, one per request.
  unsigned calls = 0;
  // The final body holds no idr.call.
  bool leaf = false;
  // A member of a final component of two or more, or a final body that
  // calls the function itself.
  bool onCycle = false;
};

// MLton's rule on a final callee: never one on a cycle or one the
// frontend marked `no_inline`; a leaf of at most kLeafSize ops; any other
// when (calls - 1) * (size - kSmall) <= kProduct.
bool worthInlining(const Facts &callee, bool noInline);

// Whether a caller of `callerSize` ops stays at or under kCallerCap with
// the call replaced by a body of `calleeSize` ops.
inline bool fitsCap(int64_t callerSize, int64_t calleeSize) {
  return callerSize - 1 + calleeSize <= kCallerCap;
}

} // namespace inlining
} // namespace idr

#endif // IDR_ANALYSIS_INLINE_H
```

`lib/Analysis/Inline.cpp` defines `inlineSize` (one walk, the count
`References::ops` takes today, `References.cpp:64-65`) and
`worthInlining`, in 64-bit signed arithmetic:

```cpp
bool idr::inlining::worthInlining(const Facts &callee, bool noInline) {
  if (callee.onCycle || noInline)
    return false;
  if (callee.leaf && callee.size <= kLeafSize)
    return true;
  return (static_cast<int64_t>(callee.calls) - 1) * (callee.size - kSmall) <= kProduct;
}
```

### Fixed decisions

- **Deleted:** the class `idr::InlineDecisions`, its analysis, its
  `inlined()`, `inlinable()`, `leaves()` and `inlinableCalls()`, and the
  `Slot` walk over `References` (`Inline.cpp:27-123`). No decision is
  taken for the whole module ahead of inlining: each is taken at the call,
  on the callee's final facts (0004 §3.2: the rule was right, applied
  every round on bodies that grew).
- **Size** is `inlineSize`, the op count of a body walk (0004 §4 stage 7,
  "Size is the op count the formula reads today"). The facts' `size` is
  measured once, when the callee's component becomes final, from its
  final body (Mojo measures the callee after its own pipeline,
  `sources/code/modular/Mojo/lib/Transforms/AutomaticInline.cpp:161-166`).
- **calls(f)** is frozen when idr-optimize begins: the number of `idr.call`
  ops in the module whose callee is `f` (0004 §4 stage 7, D14, as 0007
  D11 decided). A constructor or a dispatch match naming `f` is no call:
  after defunctionalization every apply is a dispatch whose arms are
  direct calls, which are counted (C06 postcondition 3). No count is ever
  re-read: no caller of `f` runs before `f` is final, and a count read
  later would be an arrival count under the pool. A specialization node
  has `calls = 1`, one per request, so it inlines into each requester
  unless it is on a cycle or the requester's cap stops it.
- **Leaf** means the final body holds no `idr.call` (an apply calls
  something today, `Inline.cpp:42`; after defunctionalization there is
  none).
- **On a cycle** is read from the ready set's final component (C07): its
  component has two or more members, or its final body calls itself. A
  member of a cycle is never inlined, MLton's rule
  (`inline.fun:271-295, 319-327`) and today's (`Inline.cpp:100-107`): its
  original could never be deleted.
- **`no_inline`** is the frontend's fact on `idr.func` for a zero-arity
  function whose result is lazy, the one cell of a constant
  (`compiler/src/IdrisMLIR/Emit/Declarations.idr:66-75`): inlining it
  would make a fresh cell at every use. Nothing else writes `no_inline`
  after the cutover (the loop breakers that wrote it are deleted, 0004
  §6). The attribute's declaration is C02's (U01).
- **The cap** (D25): calls are inlined in call-site order while the
  caller, with the callee's final body in, stays at or under 10,000 ops,
  counted as `inlineSize` counts. `fitsCap` counts the call out and the
  callee's whole body in, its return standing for the branch a
  multi-block body becomes. A call past the cap stays a call and its
  callee's original stays with it; reaching the cap stops inlining into
  that caller and never rejects a program. A miss of D25's record changes
  the constant in one commit; it never becomes an option.
- **Who applies it.** Only the ready set's inline step (C07,
  `lib/Transforms/Inline/Inline.cpp`) calls `worthInlining` and
  `fitsCap`. Contification (C07, `idr-contify`) does not: it moves a body
  and copies nothing.
- **Numbers.** 40, 60 and 320 are MLton's (0004 §6, "Kept"); 10,000 is
  D25.

### Invariants

- `worthInlining` and `fitsCap` read nothing but their arguments; the
  facts are written once, when the callee is final, and never change.
- A call into a callee in the caller's own component is never a
  candidate: such a callee is not final while the caller runs (C07).
- A decision never fails: it answers inline or keep.

### Consumers by lane

- U03: the inline step and the ready set (C07).
- U04: a made node's `Facts::calls` is 1; the node's facts are measured
  like any other's when its component is final.
- U17: `largest-function=<n>` reads `idr::inlineSize` (C24); the
  caller-cap fixture names 10,000.
