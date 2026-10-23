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
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <optional>

namespace idr::families {

// What a case of constructor `tag` of a match on a value of `scrutinee`
// assumes: the scrutinee's indices equal to the constructor's equation over
// its binders.
RegionRefinement caseRefinement(DataType scrutinee, Tag tag);

// The refinements of one function as a walk in program order enters and
// leaves its regions: on a stack, the depth of the scope in each region
// and the equations the regions around it assume, and the refinement they
// make there, the most general unifier of them all, one space of levels
// for the whole scope (a case's constructor's binders are levels after its
// enclosing scope's). What the scope walk checks types against, and what a
// substitution reads to replace the binders a known index fixes. No op
// walks to its ancestors.
class Refinements {
public:
  // The refinements of `function`, its body's region not yet entered.
  explicit Refinements(mlir::Operation *function);
  ~Refinements();
  Refinements(const Refinements &) = delete;
  Refinements &operator=(const Refinements &) = delete;

  // Before the ops of `region`, a region of `op`: its binders and the
  // equation it assumes, if it assumes one, solved with those around it.
  void enter(mlir::Operation *op, mlir::Region &region);
  // After them: the region's own equation goes with it.
  void leave();

  // In the region last entered: the levels bound outside it, by the
  // regions around it and the function; the levels in scope, its own
  // binders the last of them; whether its equations clash, so it is dead;
  // and, where they do not, each level they bind replaced by its term.
  uint32_t depthAtOwner() const;
  uint32_t depth() const;
  Unified unified() const;
  const LevelMap &refinement() const;

  // The levels bound outside the regions of `owner`, where its frame is on
  // the stack; none otherwise.
  std::optional<uint32_t> depthAtOwner(mlir::Operation *owner) const;

private:
  struct State;
  std::unique_ptr<State> state;
};

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
  friend class ScopeQuery;
  struct State;
  std::unique_ptr<State> state;
};

// What an op's own scope rule (ScopeRuleOpInterface) reads of the walk
// where the op stands: whether two types are one under the refinements
// around it, and how many levels an enclosing op's regions start after.
class ScopeQuery {
public:
  explicit ScopeQuery(ScopeWalk &walk) : walk(walk) {}

  // `a` and `b` equal under the refinements here, `a` perhaps a data type
  // refined further where narrowing is allowed.
  bool sameHere(mlir::Type a, mlir::Type b, Narrowing narrowing) const;

  // The levels bound outside the regions of `owner`, an op enclosing the
  // one asked; none where `owner` does not enclose it.
  std::optional<uint32_t> depthAtOwner(mlir::Operation *owner) const;

private:
  ScopeWalk &walk;
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
