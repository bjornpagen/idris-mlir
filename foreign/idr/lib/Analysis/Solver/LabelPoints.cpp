// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve's points and sinks (LabelPoints.h): laid out, made as the
// reading names them, and found where an answer asks.
#include "idr/Analysis/Solver/LabelPoints.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::labels {

// Each function's parameters, then its results, in label order: a label's
// points are found from its label alone.
Points::Points(const solver::ProgramGraph &graph) : graph(&graph) {
  std::uint32_t space = graph.size().value();
  symbols.assign(space, FlatSymbolRefAttr());
  laid.assign(space, Laid{0, 0, 0});
  for (solver::FunctionId f : graph.functions()) {
    FuncOp fn = graph.op(f);
    symbols[f.index()] = FlatSymbolRefAttr::get(fn.getSymNameAttr());
    Laid &at = laid[f.index()];
    at.parameters = count;
    for (BlockArgument arg : fn.getArguments())
      values.try_emplace(arg, Node(count++));
    at.results = count;
    count += static_cast<std::uint32_t>(fn.getResultTypes().size());
    at.end = count;
  }
}

Node Points::of(Value value) {
  auto [it, made] = values.try_emplace(value, Node(count));
  if (made)
    ++count;
  return it->second;
}

Node Points::of(const FlowAnchor &anchor) {
  auto [it, made] = anchors.try_emplace(anchor, Node(count));
  if (made)
    ++count;
  return it->second;
}

std::optional<Node> Points::find(Value value) const {
  if (auto it = values.find(value); it != values.end())
    return it->second;
  return std::nullopt;
}

std::optional<Node> Points::find(const FlowAnchor &anchor) const {
  if (auto it = anchors.find(anchor); it != anchors.end())
    return it->second;
  return std::nullopt;
}

// The tables hold their points in the addresses' order, so the points are
// sorted by node before anyone reads them.
footprint::Vector<std::pair<Node, PointKey>> Points::described() const {
  footprint::Vector<std::pair<Node, PointKey>> all;
  for (const auto &[value, node] : values)
    all.emplace_back(node, value);
  for (const auto &[anchor, node] : anchors)
    all.emplace_back(node, anchor);
  for (auto [label, symbol] : llvm::enumerate(symbols)) {
    if (!symbol)
      continue;
    const Laid &at = laid[label];
    for (std::uint32_t node = at.results; node < at.end; ++node)
      all.emplace_back(Node(node), FlowSource::Result{symbol, node - at.results});
  }
  llvm::sort(all, [](const auto &a, const auto &b) { return a.first < b.first; });
  return all;
}

std::optional<FlowPlace> Sinks::of(OpOperand &use) const {
  if (auto it = index.find(&use); it != index.end())
    return targets[std::to_underlying(it->second)];
  return std::nullopt;
}

std::optional<FlowPlace> Sinks::meet(OpOperand &use, const FlowPlace &target) {
  auto [it, first] = index.try_emplace(&use, Sink(static_cast<unsigned>(targets.size())));
  if (!first)
    return targets[std::to_underlying(it->second)];
  targets.push_back(target);
  return std::nullopt;
}

} // namespace idr::labels
