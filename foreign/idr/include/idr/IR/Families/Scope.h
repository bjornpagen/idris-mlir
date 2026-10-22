// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Scopes of index variables, and the refinements regions assume. A scope's
// variables are de Bruijn levels: a function binds levels 0..p-1, and each
// region that binds more (a case, its constructor's binders; a join region,
// its parameters') binds the next ones, so a type prints and is uniqued
// with no context and a value keeps its one type as it flows inward. A
// region may also assume an equation of index terms as it is entered (a
// case, its constructor's equation against its scrutinee's indices; an
// assumed equality), which holds inside it alone. The function's scope
// walk keeps both on a stack as it enters and leaves regions, so no op walks
// its ancestors, and checks every type, every region's entry and every cast
// against them.
#ifndef IDR_IR_FAMILIES_SCOPE_H
#define IDR_IR_FAMILIES_SCOPE_H

#include "idr/IR/Families/Families.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <memory>

namespace idr::families {

// What a case of constructor `tag` of a match on a value of `scrutinee`
// assumes: the scrutinee's indices equal to the constructor's equation over
// its binders.
RegionRefinement caseRefinement(DataType scrutinee, Tag tag);

// The scope rules of one function, as its one walk meets each op and each
// region (the function's verifier drives the walk, the effect row's
// derivation beside it): every value's type names only levels in scope and
// no member of a group by position; every region a refinement leads to that
// clashes is dead (its body unreachable); every value entering a region is
// the operand it comes from at the region's refinement, a case's scrutinee
// perhaps refined to fewer constructors, the binders of its constructor it
// gains there the region's own levels; every idr.data.reindex casts
// between types its enclosing refinements make equal; and every jump passes
// its target's parameters at its terms.
class ScopeWalk {
public:
  // The walk of `function`, its body's region not yet entered.
  explicit ScopeWalk(mlir::Operation *function);
  ~ScopeWalk();
  ScopeWalk(const ScopeWalk &) = delete;
  ScopeWalk &operator=(const ScopeWalk &) = delete;

  // Before the ops of `region`, a region of `op`.
  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region);
  // After them.
  void leave();
  // At `op`, before its regions.
  mlir::LogicalResult check(mlir::Operation *op);

private:
  struct State;
  std::unique_ptr<State> state;
};

// One rule read at every op of a function, as the function's one walk
// meets it: the scope rules, the stage's, a match's, the effect row's
// derivation. The walk is one, so every rule reads each op once, and a rule
// that keeps a stack of what encloses an op (the scopes, the refinements)
// keeps it as the walk enters and leaves regions, never by walking up.
template <class H>
concept FunctionRule = requires(H &rule, mlir::Operation *op, mlir::Region &region) {
  // Before the ops of `region`, a region of `op`.
  { rule.enter(op, region) } -> std::same_as<mlir::LogicalResult>;
  // At `op`, before its regions.
  { rule.check(op) } -> std::same_as<mlir::LogicalResult>;
  // After the ops of the region last entered.
  { rule.leave() } -> std::same_as<void>;
};

// Walks the regions of `function` in order, each op checked by every rule
// before its regions are entered and each region entered and left by every
// rule around its ops, with no recursion: the nesting waits on a stack, as
// deep as the function nests, in the footprint's storage. The first failure
// ends the walk.
template <FunctionRule... Rules>
mlir::LogicalResult walkFunction(mlir::Operation *function, Rules &...rules) {
  struct Level {
    mlir::Operation *owner;
    unsigned region;
    mlir::Region::iterator block;
    mlir::Block::iterator at;
  };
  footprint::Vector<Level> stack;
  auto enter = [&](mlir::Operation *owner, unsigned index) -> mlir::LogicalResult {
    mlir::Region &region = owner->getRegion(index);
    if ((failed(rules.enter(owner, region)) || ...))
      return mlir::failure();
    stack.push_back({owner, index, region.begin(),
                     region.empty() ? mlir::Block::iterator() : region.front().begin()});
    return mlir::success();
  };
  if (function->getNumRegions() > 0 && failed(enter(function, 0)))
    return mlir::failure();
  while (!stack.empty()) {
    Level &level = stack.back();
    mlir::Region &region = level.owner->getRegion(level.region);
    if (level.block != region.end() && level.at == level.block->end()) {
      if (++level.block != region.end())
        level.at = level.block->begin();
      continue;
    }
    if (level.block == region.end()) {
      (rules.leave(), ...);
      mlir::Operation *owner = level.owner;
      unsigned next = level.region + 1;
      stack.pop_back();
      if (next < owner->getNumRegions() && failed(enter(owner, next)))
        return mlir::failure();
      continue;
    }
    mlir::Operation *op = &*level.at++;
    if ((failed(rules.check(op)) || ...))
      return mlir::failure();
    if (op->getNumRegions() > 0 && failed(enter(op, 0)))
      return mlir::failure();
  }
  return mlir::success();
}

} // namespace idr::families

#endif // IDR_IR_FAMILIES_SCOPE_H
