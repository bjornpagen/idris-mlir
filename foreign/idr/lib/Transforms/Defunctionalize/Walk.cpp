// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One function's edits, made from the decision alone, in four steps:
//   - retype: each value its new type, in place;
//   - coerce: before each operand whose value moves between two keys, the
//     match that rebuilds it in the other family;
//   - replace: each closure op by what it means;
//   - erase: the ops it replaced, at the end.
// Its calls take their tail facts with every call of the program once
// every function is rewritten.
// Every type and attribute an edit builds is the decision's, read through a
// const reference; the walk makes ops and blocks and nothing in the
// context, and reads no other function but through what the decision
// holds of it.

#include "idr/IR/Control/MatchFamily.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// A call of a function the decision knows, its name, index arguments and
// result types the decision's; what it holds of its callee (its row, its
// write part, its lifetimes) copied as the callee states them, as the
// call's own builder would, which makes the rest; a tail fact the one
// definition of tail position rewrites once the program is first order.
CallOp callOf(OpBuilder &b, Location loc, FuncOp callee, FlatSymbolRefAttr name,
              IndexArgsAttr indices, TypeRange results, ValueRange args) {
  CallOp::Properties properties;
  properties.callee = name;
  properties.index_args = indices;
  properties.tail_kind = TailKind::nontail;
  properties.row = callee.getRow();
  properties.untouched = callee.getUntouchedAttr();
  properties.lives_in = callee.getLivesInAttr();
  return CallOp::create(b, loc, results, args, properties);
}

// A match of `value` over `over`'s cases, forwarding nothing and in no
// lifetime: its properties set whole from the decision's attribute of its
// tags, which the match's one builder, from tags, would make on this
// worker; its regions the family's, the default first.
DataMatchOp matchOf(OpBuilder &b, Location loc, TypeRange results, Value value, const Match &over) {
  OperationState state(loc, DataMatchOp::getOperationName());
  state.addOperands(value);
  state.addTypes(results);
  DataMatchOp::Properties &properties = state.getOrAddProperties<DataMatchOp::Properties>();
  properties.cases = over.tags;
  properties.operandSegmentSizes = {1, 0, 0};
  addRegions(state, over.cases.size());
  return cast<DataMatchOp>(b.create(state));
}

// Case `at` of `match`: its block, binding the value refined, and each
// field read off it.
SmallVector<Value> openCase(OpBuilder &b, Location loc, DataMatchOp match, unsigned at,
                            const Case &taken, const Decision &decision) {
  Region &region = match.getCaseRegion(at);
  Block *block = b.createBlock(&region, region.end(), TypeRange(taken.refined), {loc});
  SmallVector<Value> fields;
  for (auto [i, type] : llvm::enumerate(taken.fields))
    fields.push_back(DataFieldOp::create(b, loc, type, block->getArgument(0), ValueRange(),
                                         decision.fieldIndex(static_cast<unsigned>(i))));
  return fields;
}

// `value` moved as `coercion` says: each constructor of its family rebuilt
// in the sink's, or the poison of a move that never runs.
Value coerce(OpBuilder &b, Location loc, Value value, const Coercion &coercion,
             const Decision &decision) {
  return idr::match(
      coercion,
      [&](const NeverRuns &never) -> Value {
        return ub::PoisonOp::create(b, loc, never.sink, decision.poison());
      },
      [&](const Rebuild &rebuild) -> Value {
        const Match &over = decision.match(rebuild.over);
        DataMatchOp match = matchOf(b, loc, TypeRange(rebuild.sink), value, over);
        OpBuilder::InsertionGuard guard(b);
        for (auto [at, taken] : llvm::enumerate(over.cases)) {
          SmallVector<Value> fields =
              openCase(b, loc, match, static_cast<unsigned>(at), taken, decision);
          const Built &into = rebuild.into[at];
          SmallVector<Value> held;
          for (auto [field, type] : llvm::zip_equal(fields, into.fields))
            held.push_back(heldAs(b, loc, field, type));
          Value rebuilt = DataConOp::create(b, loc, into.type, held);
          YieldOp::create(b, loc, givenAs(b, loc, rebuilt, rebuild.sink));
        }
        return match->getResult(0);
      });
}

} // namespace

Value givenAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (unrestricted(value.getType()) == unrestricted(type))
    return heldAs(b, loc, value, type);
  return DataReindexOp::create(b, loc, type, value);
}

// The edits are read through a const reference and the IR they name is
// written: each handle is copied out, as an op or a value is passed.
void rewrite(const Edits &edits, const Decision &decision) {
  FuncOp fn = edits.fn;
  OpBuilder b(fn.getContext());

  for (const Retype &each : edits.retypes) {
    Value value = each.value;
    value.setType(each.type);
  }

  for (const Move &move : edits.moves) {
    Operation *owner = move.use->getOwner();
    b.setInsertionPoint(owner);
    move.use->set(
        coerce(b, owner->getLoc(), move.use->get(), decision.coercion(move.coercion), decision));
  }

  SmallVector<Operation *> erased;
  // A constructor's fields are its op's operands. An unforced cell keeps its
  // identity: its constructor is a fresh one, as the family's kind says.
  for (const Construct &each : edits.constructs) {
    Location loc = each.op->getLoc();
    b.setInsertionPoint(each.op);
    SmallVector<Value> held;
    for (auto [operand, type] : llvm::zip_equal(each.op->getOperands(), each.built.fields))
      held.push_back(heldAs(b, loc, operand, type));
    Value result = each.op->getResult(0);
    result.replaceAllUsesWith(
        givenAs(b, loc, DataConOp::create(b, loc, each.built.type, held), result.getType()));
    erased.push_back(each.op);
  }
  // An apply's case calls its label's function with the captures, then the
  // arguments, and yields its results; a family no label reaches is a value
  // the program never has.
  for (const Apply &each : edits.applies)
    idr::match(
        each,
        [&](const Unreached &unreached) {
          FnApplyOp apply = unreached.op;
          b.setInsertionPoint(apply);
          for (Value result : apply.getResults())
            result.replaceAllUsesWith(
                ub::PoisonOp::create(b, apply.getLoc(), result.getType(), decision.poison()));
          erased.push_back(apply);
        },
        [&](const Dispatch &dispatch) {
          FnApplyOp apply = dispatch.op;
          Location loc = apply.getLoc();
          b.setInsertionPoint(apply);
          const Match &over = decision.match(dispatch.match);
          DataMatchOp match = matchOf(b, loc, apply.getResultTypes(), apply.getCallee(), over);
          OpBuilder::InsertionGuard guard(b);
          for (auto [at, taken] : llvm::enumerate(over.cases)) {
            const Callee &callee = over.callees[at];
            const CaseMoves &moves = dispatch.cases[at];
            SmallVector<Value> fields =
                openCase(b, loc, match, static_cast<unsigned>(at), taken, decision);
            // The captures, read at the case's levels, given at the terms
            // the call passes: a reindex before the call where the two
            // differ, so nothing follows the call to relate its results.
            auto captures = static_cast<unsigned>(fields.size());
            SmallVector<Value> args;
            for (auto [field, type] : llvm::zip_equal(fields, callee.bound.getInputs().take_front(captures)))
              args.push_back(givenAs(b, loc, field, type));
            for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
              Value value = arg;
              if (const std::optional<CoercionId> &moved = moves.arguments[i])
                value = coerce(b, loc, value, decision.coercion(*moved), decision);
              args.push_back(
                  givenAs(b, loc, value, callee.bound.getInput(captures + static_cast<unsigned>(i))));
            }
            CallOp call =
                callOf(b, loc, callee.fn, callee.name, taken.given, callee.bound.getResults(), args);
            SmallVector<Value> yields;
            for (auto [j, result] : llvm::enumerate(call.getResults())) {
              Value value = result;
              if (const std::optional<CoercionId> &moved = moves.results[j])
                value = coerce(b, loc, value, decision.coercion(*moved), decision);
              yields.push_back(
                  givenAs(b, loc, value, apply->getResult(static_cast<unsigned>(j)).getType()));
            }
            YieldOp::create(b, loc, yields);
          }
          apply->replaceAllUsesWith(match->getResults());
          erased.push_back(apply);
        });
  // A force is a call of its cell's dispatch function, the value moved out
  // of the forced state's slot into the force's.
  for (const Force &each : edits.forces) {
    LazyForceOp force = each.op;
    Location loc = force.getLoc();
    b.setInsertionPoint(force);
    const Dispatcher &dispatch = decision.family(each.memo).force;
    Value taken = heldAs(b, loc, force.getSuspension(), dispatch.takes);
    CallOp call = callOf(b, loc, dispatch.fn, dispatch.name, dispatch.indices,
                         TypeRange(dispatch.gives), ValueRange(taken));
    Value value = call.getResult(0);
    if (each.moved)
      value = coerce(b, loc, value, decision.coercion(*each.moved), decision);
    force.getResult().replaceAllUsesWith(heldAs(b, loc, value, force.getResult().getType()));
    erased.push_back(force);
  }
  for (const Constant &each : edits.constants) {
    ConstantOp op = each.op;
    b.setInsertionPoint(op);
    op.getResult().replaceAllUsesWith(
        ConstantOp::create(b, op.getLoc(), op.getResult().getType(), each.value));
    erased.push_back(op);
  }

  for (Operation *op : llvm::reverse(erased))
    op->erase();
}

} // namespace idr::defunctionalize
