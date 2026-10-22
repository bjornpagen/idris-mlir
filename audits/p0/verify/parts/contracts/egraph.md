<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Contract: what idr-simplify reads (L14, 2026-10-21)

Declared in `foreign/idr/include/idr/Transforms/EGraph.h`.

## 1. Rule tables

specgen prints `Spec.Core.Rewrite`'s records into
`idr/IR/Generated/Rewrites.h.inc`, inside namespace
`idr::egraph::generated`, using the types in `idr::egraph::table`:
- **`inline constexpr table::PatternNode patterns[]`**, in preorder. Each
  node's kind is `Var`, `Node` or `Literal`:
  - a `Node` has `op` (its position in `Kinds`), `result` and `arity`;
  - a `Var` has `var`;
  - a `Literal` has `literal`.
- **`inline constexpr table::Condition conditions[]`**, each on a `var`:
  `IsConstant`, `PowerOfTwo`, `InRange{lo,hi}` or `Clean`.
- **`inline constexpr table::Rule rules[]`**, sorted by root kind. Each
  rule is `{vars, lhs, lhsSize, rhs, rhsSize, conditions, conditionCount}`.
  Every rule is one-way (D106); the `direction` field and the `Equal`
  path are deleted (L14, 7d39d9bb; L03 drops them from `Spec/Core/Rewrite`).
- **`inline constexpr std::uint32_t rulesOfKind[]`**: `Kinds::size + 1`
  offsets into `rules`.
- **`using Kinds = table::OpList<...>`**: the op classes a pattern names.
- **`using SkeletonRules = table::RuleList<::idr::egraph::<Name>...>`**.
- **`inline constexpr std::uint32_t nodesPerOp`**: C156's B.

An `UpstreamNode` pattern prints as a `Node`, with the admitted op's class
in `Kinds`.

## 2. A skeleton rule class

A skeleton rule (L09's in `IR/Control/Control.h`, L13's in their headers)
meets the concept `idr::egraph::SkeletonRule`:
- `using Root = <op class or interface>;`
- `static std::optional<idr::egraph::Edit> decide(Root, const idr::egraph::OperandFacts &);`
- `static void rewrite(Root, const idr::egraph::Rewrite &, mlir::RewriterBase &);`

`Edit` is a closed sum:
- **`Forward{operandOfResult}`**: each result becomes an operand.
- **`Take{region, operandOfArgument}`**: a region op becomes one of its
  regions, with the block arguments bound to operands and the yields as
  the results. The engine writes the region's ops back in place.
- **`Rewrite{chosen}`**: `struct Rewrite { llvm::SmallVector<unsigned, 4> chosen; };`
  carries the choice the rule made while it could read the e-graph (for
  example, the arm indices), so `rewrite` need not recompute it. The
  engine calls `R::rewrite(root, rewrite, rewriter)` between the two
  rounds.

`OperandFacts` answers by `Value`, for any value of the function, not by
operand position (L14, revised 2026-10-21):
- `constant(Value)`;
- `range(Value)`;
- `origin(Value)`: the input op of the chosen form, for example an
  `idr.data.con`;
- `cost(Value) -> idr::egraph::Cost`: the extraction cost of the value's
  chosen form, its operands included. `Cost` has `<=>` and `+`.

`decide` reads the e-graph after extraction, so a rule chooses per arm
(C157). `CaseOfCase::decide`, for example, reads each producer arm's
yielded value through `origin`, `constant` and `cost`, and returns
`Rewrite`. Root stays one op class or interface per rule; a rule over
several ops uses an interface root, in the style of
`DataMatchOpInterface`.

**At most two rounds per function.**
- Round 1 builds and extracts the e-graph; then every skeleton rule
  decides.
- If any rule decided `Rewrite`, the engine runs those
  `R::rewrite(root, rewrite, rewriter)` on the input, region by region in walk
  order, with the insertion point at the root. A root that an earlier
  rewrite erased is skipped, so `rewrite` re-checks its own condition on
  the root as it now is.
- Round 2 builds the e-graph again over the result. A `Rewrite`
  decision is kept as is, and that round's `Forward` and `Take` edits
  are written back.

So a rule may restructure its root's regions freely, and the e-graph then
simplifies what it made: a copied dispatch, for example, folds by
`TakenRegion`'s `Take` in round 2.

A rule header includes `idr/Transforms/EGraph.h`.

## 3. The identity rule (C18)

`idr-simplify` replaces a floating call by the argument its callee gives
back whole, reading `idr::egraph::CalleeFacts`. Only L18's optimizer
builds those facts, through `createIdrSimplify(const CalleeFacts &)` for
its inner pipeline. The pipeline's plain `createIdrSimplify()` reads
none, since the optimizer has already rewritten those calls.

## Found during the cutover (L14, 2026-10-21)

The engine replaces a node when a rule fires and never unions, so every
class holds one node and `OperandFacts::cost` has no reader; case-of-case
uses its own unit costs. Whether it becomes a true e-graph or is named a
hash-consed rewrite graph is the owner's question queued in P0 §4. Until
then, `cost` is unread, and a replaced node's facts are carried to its
replacement.
