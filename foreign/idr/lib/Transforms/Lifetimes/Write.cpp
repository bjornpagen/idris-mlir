// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Writing a plan: a copy's lifetime parameter, each run's opener around the
// ops it spans (the one way the pass opens a lifetime, a loan's too), its
// cells as slots or bumped into it, its calls to their callee's copy for
// its kind, and every value that lives in it graded `scoped`, the op that
// makes each stating where.

#include "idr/Transforms/Lifetimes/Plan.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <cstddef>

using namespace mlir;
using namespace idr;
using namespace idr::lifetimes::decide;

// The lifetime parameter goes last, and every scoped result lives in it.
LogicalResult Modes::edit(const Key &key, FuncOp clone) {
  unsigned at = clone.getNumArguments();
  if (failed(clone.insertArgument(at, key.signature.getInputs().back(), DictionaryAttr(),
                                  clone.getLoc())))
    return failure();
  clone.setFunctionType(key.signature);
  SmallVector<LivesIn, 2> results;
  for (auto [index, type] : llvm::enumerate(key.signature.getResults()))
    if (freedBy(type, Release::Scoped))
      results.push_back({static_cast<std::uint32_t>(index), at});
  clone.setLivesInAttr(LivesInAttr::get(clone.getContext(), {}, results, {}));
  return success();
}

namespace {

// `value` lives in `lifetime`: its hold is scoped, with what it claimed of
// its sharing, and the op that makes it states where, each scoped value its
// own entry. Runs are written each before the runs inside it, so a value
// two runs' lifetimes reach is given the inner last, the one its cells of
// both outlive, and an op that passes a scoped value through states its
// operand's lifetime or one that lifetime encloses.
void scope(Value value, Value lifetime) {
  if (!holdOf(value.getType()))
    return;
  value.setType(scopedType(value.getType()));
  if (StatesLifetimeOpInterface states = statedBy(value))
    states.setStatedLifetime(value, lifetime);
}

} // namespace

unsigned Writer::write(FuncOp target, const Plan &plan,
                       std::optional<std::pair<Value, CopyMode>> parameter) {
  // Every op and value the plan names, read before anything is written.
  OpOrder order(target);
  footprint::Vector<Value> values;
  solver::inWalkOrder(target, [&](Value value) { values.push_back(value); });

  std::optional<Resolved> put;
  if (plan.put && parameter)
    put = resolve(order, values, plan.put->sites, plan.put->calls, plan.put->scoped);
  footprint::Vector<Resolved> groups;
  for (const Group &group : plan.groups)
    groups.push_back(resolve(order, values, group.sites, group.calls, group.scoped));

  // The parameter is the outermost lifetime, then each run's, each before
  // the runs inside it. An op the plan replaces (a cell's source, a call
  // that puts) is no op an extent begins or ends at but its own run's,
  // written after its extent is opened. A cursor's run inside another
  // cursor's extent goes on that cursor's stack: the enclosing run was
  // written first, and its extent's positions say it holds this run's op.
  unsigned opened = 0;
  if (put)
    write(*put, parameter->first, Cells::Bumped, parameter->second);
  footprint::Vector<Value> written;
  for (auto [at, group] : llvm::enumerate(plan.groups)) {
    Value lifetime;
    if (!group.extent) {
      lifetime = activationOf(target);
    } else {
      Value base;
      if (group.source == Opening::Cursor && group.run)
        for (std::size_t outer = at; outer-- > 0;)
          if (const Group &around = plan.groups[outer];
              around.source == Opening::Cursor && around.extent &&
              order.within(group.run->first, around.extent->first, around.extent->second)) {
            base = written[outer];
            break;
          }
      lifetime = openLifetime(group.source, order.op(group.extent->first),
                              order.op(group.extent->second), base);
    }
    written.push_back(lifetime);
    ++opened;
    write(groups[at], lifetime, group.cells, modeOf(group.source));
  }
  return opened;
}

// What the plan's positions are in `target`; a put call's results take
// their types from the copy it calls, so they are no values to scope.
Writer::Resolved Writer::resolve(const OpOrder &order, const footprint::Vector<Value> &values,
                                 ArrayRef<OpAt> sites, ArrayRef<PutCall> calls,
                                 ArrayRef<Node> scoped) {
  Resolved out;
  for (OpAt site : sites)
    out.sites.push_back(cast<CellNewOp>(order.op(site)));
  for (const PutCall &call : calls)
    out.calls.emplace_back(cast<FunctionCallOpInterface>(order.op(call.call)), call.callee);
  for (Node n : scoped) {
    Value value = values[n.index()];
    auto result = dyn_cast<OpResult>(value);
    if (result &&
        llvm::any_of(out.calls, [&](std::pair<FunctionCallOpInterface, FunctionId> call) {
          return call.first.getOperation() == result.getOwner();
        }))
      continue;
    out.scoped.push_back(value);
  }
  return out;
}

// The body's one activation: the run's lifetime and a loan of static data
// both stand in it, so whichever is written second finds it at the top.
Value idr::lifetimes::decide::activationOf(FuncOp fn) {
  Block &entry = fn.getBody().front();
  if (auto held = entry.getOps<ActivationOp>(); !held.empty())
    return (*held.begin()).getLifetime();
  OpBuilder b = OpBuilder::atBlockBegin(&entry);
  return ActivationOp::create(b, fn.getLoc(),
                              LifetimeType::get(fn.getContext(), LifetimeKind::view()))
      .getLifetime();
}

Value idr::lifetimes::decide::openLifetime(Opening source, Operation *first, Operation *last,
                                           Value base) {
  Block *block = first->getBlock();
  Location loc = first->getLoc();
  MLIRContext *ctx = first->getContext();
  auto after = [&](Operation *user) {
    Operation *top = block->findAncestorOpInBlock(*user);
    return top && last->isBeforeInBlock(top);
  };
  SmallVector<Value, 4> out;
  for (Operation *op = first;; op = op->getNextNode()) {
    for (Value result : op->getResults())
      if (llvm::any_of(result.getUsers(), after))
        out.push_back(result);
    if (op == last)
      break;
  }
  SmallVector<Value, 4> outers;
  for (Value value : out)
    if (Value stated = lifetimes::statedLifetime(value))
      outers.push_back(stated);

  OpBuilder b(first);
  SmallVector<Type, 4> types(ValueRange(out).getTypes());
  Operation *opener = nullptr;
  LifetimeKind kind = LifetimeKind::view();
  switch (source) {
  case Opening::Activation:
  case Opening::NoMemory:
    opener = LifetimeOp::create(b, loc, types, outers);
    break;
  case Opening::Block:
    opener = LifetimeBlockOp::create(b, loc, types, outers);
    kind = LifetimeKind::room();
    break;
  case Opening::Home:
    opener = LifetimeHomeOp::create(b, loc, types, outers);
    kind = LifetimeKind::home(0);
    break;
  case Opening::Cursor:
    opener = base ? LifetimeStackOp::create(b, loc, types, base, outers).getOperation()
                  : LifetimeChainOp::create(b, loc, types, outers).getOperation();
    kind = LifetimeKind::cursor();
    break;
  }
  Block *body = new Block();
  opener->getRegion(0).push_back(body);
  Value lifetime = body->addArgument(LifetimeType::get(ctx, kind), loc);
  body->getOperations().splice(body->end(), block->getOperations(), Block::iterator(first),
                               std::next(Block::iterator(last)));
  OpBuilder inside = OpBuilder::atBlockEnd(body);
  YieldOp::create(inside, loc, out);
  for (auto [value, result] : llvm::zip_equal(out, opener->getResults()))
    value.replaceUsesWithIf(result,
                            [&](OpOperand &use) { return !opener->isAncestor(use.getOwner()); });
  return lifetime;
}

// The cells, as slots of the frame or bumped into `lifetime`; the calls,
// to the copy of their callee for `mode`, given `lifetime`, each standing
// where the call it replaces stood; then every value that lives in it.
void Writer::write(const Resolved &resolved, Value lifetime, Cells cells, CopyMode mode) {
  for (CellNewOp site : resolved.sites) {
    OpBuilder b(site);
    Type cell = site.getCell().getType();
    Value placed = cells == Cells::Slots
                       ? CellStackOp::create(b, site.getLoc(), cell, lifetime).getCell()
                       : CellArenaOp::create(b, site.getLoc(), cell, lifetime).getCell();
    site.getCell().replaceAllUsesWith(placed);
    site.erase();
  }
  for (auto [call, callee] : resolved.calls) {
    FuncOp copy = made[callee][static_cast<unsigned>(mode)];
    IRRewriter rewriter(call.getContext());
    rewriter.setInsertionPoint(call);
    SmallVector<Value, 4> args(call.getArgs());
    args.push_back(lifetime);
    auto put = CallOp::create(rewriter, call.getLoc(), copy, call.getIndexArgsAttr(), args);
    CallStanding standing = call.getStanding();
    call->replaceAllUsesWith(put->getResults());
    call->erase();
    (void)tail::restand(rewriter, put, standing);
  }
  for (Value value : resolved.scoped)
    scope(value, lifetime);
}
