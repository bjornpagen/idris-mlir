// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Extract, solve, write back: the solve shape of a problem whose facts are
// per value across functions (the label solve, exclusivity, borrows, the
// stack inference, deduplication). Each function is read in parallel into
// arrays at its own base offset, the bases a prefix sum of the functions'
// counts, so a node's id is its function's base plus its position in the
// function's walk; the solve runs over those arrays, which name no MLIR;
// the answer is written back by a walk in the same order. Extraction and
// write-back both visit a function's values through inWalkOrder, one
// template, so the i-th value of one is the i-th value of the other.
//
// A solver's domain is a type: an extractor takes only Open values, which
// only a question's filter makes from a value whose type leaves the
// question open. A node for a value whose type settles it (a quantity-1
// parameter for a borrow, an erased thing anywhere) cannot be written.
//
// The one map keyed by an IR handle is a Numbering's, while one function
// is numbered; it is gone when the numbering finishes. Every other table
// here is the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_EXTRACTION_H
#define IDR_ANALYSIS_SOLVER_EXTRACTION_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Threading.h"
#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"
#include "llvm/ADT/DenseMap.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <optional>
#include <utility>

namespace idr::solver {

// The one walk order of a function's values: its entry arguments; then, op
// by op, each region's block arguments as the walk enters it, and the op's
// results once its regions are done. Every region holds one block until the
// lowering, so a value comes after every value it is made from: an operand
// before the op that reads it, and a region's yielded values before the
// results they become.
template <class Visit>
  requires std::invocable<Visit &, mlir::Value>
void inWalkOrder(idr::FuncOp fn, Visit &&visit) {
  for (mlir::BlockArgument arg : fn.getBody().getArguments())
    visit(mlir::Value(arg));
  for (mlir::Operation &top : fn.getBody().front())
    top.walk([&](mlir::Operation *op, const mlir::WalkStage &stage) {
      if (stage.isAfterAllRegions()) {
        for (mlir::Value result : op->getResults())
          visit(result);
        return;
      }
      for (mlir::Block &block : op->getRegion(stage.getNextRegion()))
        for (mlir::BlockArgument arg : block.getArguments())
          visit(mlir::Value(arg));
    });
}

// One function's values numbered in walk order: a value's id is above the
// id of every value it is made from, so a loop over ids ascending is a
// topological order of the function's dataflow.
template <class Tag>
class Numbering {
public:
  using Node = Id<Tag>;
  struct Done {
    Count<Node> count;
    IndexVector<Node, mlir::Value> values;
  };

  explicit Numbering(idr::FuncOp fn) {
    inWalkOrder(fn, [&](mlir::Value value) {
      index.try_emplace(value, static_cast<std::uint32_t>(values.size()));
      values.push_back(value);
    });
  }

  // The id of a value of the function: verified IR defines every operand
  // inside the function before its use, so every value asked has one.
  Node at(mlir::Value value) const { return Node(index.find(value)->second); }
  Count<Node> size() const { return Count<Node>(static_cast<std::uint32_t>(values.size())); }

  // The numbering's answer; the map is gone after this.
  Done finish() && {
    Count<Node> count(static_cast<std::uint32_t>(values.size()));
    IndexVector<Node, mlir::Value> out(count, mlir::Value());
    for (std::uint32_t at = 0; at < values.size(); ++at)
      out[Node(at)] = values[at];
    return {count, std::move(out)};
  }

private:
  llvm::DenseMap<mlir::Value, std::uint32_t> index;
  footprint::Vector<mlir::Value> values;
};

// Where each function's nodes start in the program's arrays.
template <class Tag>
class Offsets {
public:
  using Node = Id<Tag>;

  Count<Node> size() const { return count; }
  // The node of the `local`-th item of `f`'s extraction.
  Node node(FunctionId f, std::uint32_t local) const { return Node(base[f] + local); }
  std::uint32_t local(FunctionId f, Node n) const { return n.index() - base[f]; }
  std::uint32_t itemsOf(FunctionId f) const { return items[f]; }

private:
  template <class T, class C, class F>
  friend Offsets<T> extract(const ProgramGraph &g, mlir::MLIRContext &context, C &&countOf,
                            F &&fill);
  Offsets(IndexVector<FunctionId, std::uint32_t> base, IndexVector<FunctionId, std::uint32_t> items,
          std::uint32_t total)
      : base(std::move(base)), items(std::move(items)), count(total) {}

  IndexVector<FunctionId, std::uint32_t> base;
  IndexVector<FunctionId, std::uint32_t> items;
  Count<Node> count;
};

// Two parallel passes over the program's functions. `countOf(f, fn)` says
// how many items `f` extracts; then, the bases laid out, `fill(f, fn,
// offsets)` writes `f`'s items at its base into the client's arrays, which
// it sizes by `offsets.size()` beforehand, and may name another function's
// nodes through the offsets (a call's edge into its callee's parameters).
// Each pass writes only its own function's slots; the bases are a prefix
// sum in id order, so the layout does not depend on the schedule.
template <class Tag, class C, class F>
Offsets<Tag> extract(const ProgramGraph &g, mlir::MLIRContext &context, C &&countOf, F &&fill) {
  IndexVector<FunctionId, std::uint32_t> items = g.table<std::uint32_t>(0);
  IdRange<FunctionId> functions = g.functions();
  mlir::parallelFor(&context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    items[f] = countOf(f, g.op(f));
  });
  IndexVector<FunctionId, std::uint32_t> base = g.table<std::uint32_t>(0);
  std::uint32_t total = 0;
  for (FunctionId f : functions) {
    base[f] = total;
    total += items[f];
  }
  Offsets<Tag> offsets(std::move(base), std::move(items), total);
  mlir::parallelFor(&context, 0, functions.size(), [&](std::size_t at) {
    FunctionId f = functions[at];
    fill(f, g.op(f), static_cast<const Offsets<Tag> &>(offsets));
  });
  return offsets;
}

// Whether a value's type leaves a question open; a choice, never a flag.
enum class Openness : std::uint8_t { Settled, Open };

template <class Q>
concept Question = requires(mlir::Type type) {
  { Q::openness(type) } -> std::same_as<Openness>;
};

// A value whose type leaves `Q` open: the only input an extractor of `Q`
// takes, made only by `Q`'s filter.
template <Question Q>
class Open {
public:
  static std::optional<Open> of(mlir::Value value) {
    if (Q::openness(value.getType()) == Openness::Settled)
      return std::nullopt;
    return Open(value);
  }
  mlir::Value value() const { return v; }

private:
  explicit Open(mlir::Value value) : v(value) {}
  mlir::Value v;
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_EXTRACTION_H
