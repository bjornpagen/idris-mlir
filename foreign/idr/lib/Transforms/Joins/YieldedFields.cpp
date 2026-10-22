// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rule of a match's yielded fields: a result every region
// that yields builds as one constructor, read only through its fields, is
// yielded as the constructor's fields, and the constructor is built once
// after the match. Only while the holds are undecided, so no result it
// touches is scoped yet and the lifetimes the match states are none.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins/Rules.h"

#include "mlir/IR/PatternMatch.h"

#include <cstddef>

// What each stage implies (holdsAt among it), printed from the
// specification.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

// The constructors the regions of `op` that yield give as `result`, when
// the result is one to split: a data value read only through its fields,
// so of a type refined to one constructor, which every region that yields
// builds there of fields of one list of types, for the yield alone.
std::optional<SmallVector<DataConOp>> yieldedConstructors(OpResult result) {
  if (!isMatchable(result.getType()) || result.use_empty() ||
      !llvm::all_of(result.getUsers(), llvm::IsaPred<DataFieldOp>))
    return std::nullopt;
  SmallVector<DataConOp> built;
  for (Region &region : result.getOwner()->getRegions()) {
    if (!yields(region))
      continue;
    auto yield = cast<YieldOp>(region.front().getTerminator());
    Value given = yield->getOperand(result.getResultNumber());
    auto con = given.getDefiningOp<DataConOp>();
    if (!con || con->getBlock() != yield->getBlock() || !given.hasOneUse() ||
        (!built.empty() &&
         !llvm::equal(built.front().getFields().getTypes(), con.getFields().getTypes())))
      return std::nullopt;
    built.push_back(con);
  }
  if (built.empty())
    return std::nullopt;
  return built;
}

// Whether the holds of `op`'s function are still undecided: once they are,
// each field's is fixed at its constructor's, and the constructor stays
// where it was built.
bool holdsUndecided(Operation *op) {
  Stage stage = op->getParentOfType<FuncOp>().getProgram().getStage();
  return holdsAt[static_cast<std::size_t>(stage)] == StageHolds::Undecided;
}

} // namespace

// A result that every region that yields builds as one constructor, and
// that is only ever read through its fields, is yielded as the
// constructor's fields, and the constructor is built once after the match,
// where each read of a field folds to the field the regions gave. A field
// is then the value its region built it of, a linear one the thread it
// was, never a read of a value the match built: a linear array passed back
// beside a value stays the one buffer each region wrote. Only while the
// holds are undecided.
std::optional<Edit> egraph::YieldedFields::decide(MatchOpInterface op, const OperandFacts &) {
  if (!holdsUndecided(op))
    return std::nullopt;
  for (OpResult result : op->getResults())
    if (yieldedConstructors(result))
      return Edit(Rewrite{{result.getResultNumber()}});
  return std::nullopt;
}

void egraph::YieldedFields::rewrite(MatchOpInterface op, const Rewrite &chosen,
                                    RewriterBase &rewriter) {
  unsigned index = chosen.chosen.front();
  if (index >= op->getNumResults())
    return;
  OpResult result = op->getResult(index);
  std::optional<SmallVector<DataConOp>> built = yieldedConstructors(result);
  if (!built)
    return;
  TypeRange fieldTypes = built->front().getFields().getTypes();
  SmallVector<Type> types;
  for (auto [i, type] : llvm::enumerate(op->getResultTypes()))
    if (i != index)
      types.push_back(type);
  unsigned kept = static_cast<unsigned>(types.size());
  llvm::append_range(types, fieldTypes);
  Type type = result.getType();
  Location loc = result.getLoc();
  // Each yield gives its constructor's fields in its place.
  for (DataConOp con : *built) {
    auto yield = cast<YieldOp>(con->getBlock()->getTerminator());
    SmallVector<Value> given;
    for (auto [i, value] : llvm::enumerate(yield.getResults()))
      if (i != index)
        given.push_back(value);
    llvm::append_range(given, con.getFields());
    rewriter.setInsertionPoint(yield);
    rewriter.replaceOpWithNewOp<YieldOp>(yield, given);
    rewriter.eraseOp(con);
  }
  Operation *fresh = withResults(rewriter, op, types);
  rewriter.setInsertionPointAfter(fresh);
  Value rebuilt =
      DataConOp::create(rewriter, loc, type, fresh->getResults().drop_front(kept)).getResult();
  SmallVector<Value> replacements(fresh->getResults().take_front(kept));
  replacements.insert(replacements.begin() + index, rebuilt);
  rewriter.replaceOp(op, replacements);
}

} // namespace idr
