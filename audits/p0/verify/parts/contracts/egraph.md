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
  rule is `{vars, lhs, lhsSize, rhs, rhsSize, conditions, conditionCount,
  direction}`, where `direction` is `Simplify` or `Equal`.
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
- `static void rewrite(Root, mlir::RewriterBase &);`

`Edit` is a closed sum:
- **`Forward{operandOfResult}`**: each result becomes an operand.
- **`Take{region, operandOfArgument}`**: a region op becomes one of its
  regions, with the block arguments bound to operands and the yields as
  the results. The engine writes the region's ops back in place.
- **`Rewrite`**: the engine calls `R::rewrite` once the root's operands
  are written back, with the insertion point at the root, before its
  regions.

`OperandFacts` answers by operand position:
- `constant(i)`: null if there is none;
- `range(i)`: an optional `ConstantIntRanges`;
- `origin(i)`: the input op that made the chosen form, for example an
  `idr.con`; null otherwise.

A rule header includes `idr/Transforms/EGraph.h`.

## 3. The identity rule (C18)

`idr-simplify` replaces a floating call by the argument its callee gives
back whole, reading `idr::egraph::CalleeFacts`. Only L18's optimizer
builds those facts, through `createIdrSimplify(const CalleeFacts &)` for
its inner pipeline. The pipeline's plain `createIdrSimplify()` reads
none, since the optimizer has already rewritten those calls.
