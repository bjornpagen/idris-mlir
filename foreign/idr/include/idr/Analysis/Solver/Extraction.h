// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one walk order of a function's values, and their numbering in it. A
// solve whose facts are per value reads each body's values into arrays
// that name no MLIR, and its answer is written back by a walk in the same
// order: both visit the values through inWalkOrder, one template, so the
// i-th value of one is the i-th value of the other.
//
// The one map keyed by an IR handle is a Numbering's, while one function,
// or one region compared with others, is numbered; it is gone when the
// numbering finishes. It and every other table here are the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_EXTRACTION_H
#define IDR_ANALYSIS_SOLVER_EXTRACTION_H

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Value.h"
#include "mlir/IR/Visitors.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <utility>

namespace idr::solver {

// The one walk order of a region's values: its entry arguments; then, op by
// op, each nested region's block arguments as the walk enters it, and the
// op's results once its regions are done. Every region holds one block
// until the lowering, so a value comes after every value of the region it
// is made from: an operand before the op that reads it, and a region's
// yielded values before the results they become.
template <class Visit>
  requires std::invocable<Visit &, mlir::Value>
void inWalkOrder(mlir::Region &body, Visit &&visit) {
  for (mlir::BlockArgument arg : body.getArguments())
    visit(mlir::Value(arg));
  for (mlir::Operation &top : body.front())
    top.walk([&](mlir::Operation *op, const mlir::WalkStage &stage) {
      if (stage.isAfterAllRegions()) {
        for (mlir::Value result : op->getResults())
          visit(result);
        return;
      }
      // A stage counts regions as MLIR's int; a region's index is unsigned.
      for (mlir::Block &block : op->getRegion(static_cast<unsigned>(stage.getNextRegion())))
        for (mlir::BlockArgument arg : block.getArguments())
          visit(mlir::Value(arg));
    });
}

// A function's walk is its body's, so a function and a region inside one
// are numbered in the one order.
template <class Visit>
  requires std::invocable<Visit &, mlir::Value>
void inWalkOrder(idr::FuncOp fn, Visit &&visit) {
  inWalkOrder(fn.getBody(), std::forward<Visit>(visit));
}

// What a numbering spans. A function is isolated from above, so every
// value it reads is its own and has an id. A region inside a function also
// reads values the ops around it made, which are not its own and get none:
// a region's body compared with another's (two cases of one match) holds
// both kinds, its own matched to the other body's and those from around it
// matched to themselves, and the two kinds are the problem's.
enum class Scope : std::uint8_t { Isolated, Nested };

// One function's, or one nested region's, values numbered in walk order: a
// value's id is above the id of every value of the scope it is made from,
// so a loop over ids ascending is a topological order of the scope's
// dataflow.
template <class Tag, Scope S = Scope::Isolated>
class Numbering {
public:
  using Node = Id<Tag>;
  struct Done {
    Count<Node> count;
    IndexVector<Node, mlir::Value> values;
  };

  explicit Numbering(idr::FuncOp fn)
    requires(S == Scope::Isolated)
  {
    number(fn.getBody());
  }

  explicit Numbering(mlir::Region &body)
    requires(S == Scope::Nested)
  {
    number(body);
  }

  // The id of a value of the function: verified IR defines every operand
  // inside the function before its use, so every value asked has one.
  Node at(mlir::Value value) const
    requires(S == Scope::Isolated)
  {
    return Node(index.find(value)->second);
  }

  // The id of a value the region made; none for one made around it.
  std::optional<Node> find(mlir::Value value) const
    requires(S == Scope::Nested)
  {
    auto it = index.find(value);
    if (it == index.end())
      return std::nullopt;
    return Node(it->second);
  }

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
  void number(mlir::Region &body) {
    inWalkOrder(body, [&](mlir::Value value) {
      index.try_emplace(value, static_cast<std::uint32_t>(values.size()));
      values.push_back(value);
    });
  }

  footprint::DenseMap<mlir::Value, std::uint32_t> index;
  footprint::Vector<mlir::Value> values;
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_EXTRACTION_H
