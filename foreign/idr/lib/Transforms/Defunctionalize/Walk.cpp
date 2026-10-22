// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One function's walk, from the decision alone, in four steps over the
// ops it held when the walk began:
//   - read: each value's key and each operand's move, from the solve,
//     while every value still has the type the solve read;
//   - retype: each value its slot's type, in place, and the function its
//     converted signature;
//   - coerce: before each operand whose move goes between two keys, the
//     match that rebuilds its value in the other family;
//   - replace: each closure op by what it means, and the ops it replaced
//     erased at the end, so no value the solve names is freed while the
//     walk reads the solve.
// Another function is read only through the decision's signatures; what a
// constructor of a family runs is the function its label names.

#include "idr/Analysis/Labels.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// Whether a closure op stands in tail position, read once by the one
// definition before it is replaced.
enum class TailPosition : bool { Within, Tail };

// A call of a function the decision knows, built with a tail fact the one
// definition of tail position rewrites once the function is whole.
CallOp callOf(OpBuilder &b, Location loc, FuncOp callee, IndexArgsAttr indices,
              TypeRange results, ValueRange args) {
  return CallOp::create(b, loc, callee, indices, results, args, TailKind::nontail);
}

// The case of `tag` in `match`, over `scrutinee` of `family`: a block
// binding the scrutinee refined to that constructor, at the constructor's
// binders, and its fields read off it.
struct Case {
  Block *block;
  SmallVector<Value> fields;
  IndexArgsAttr binders;
};
Case caseOf(OpBuilder &b, Location loc, DataMatchOp match, unsigned index, DataType family, Tag tag) {
  Region &region = match.getCaseRegion(index);
  unsigned depth = joins::scopeDepth(&region);
  unsigned count = static_cast<unsigned>(family.binderSorts(tag).size());
  IndexArgsAttr binders = families::levelArgs(b.getContext(), depth, count);
  DataType refined = family.refinedTo(tag, binders.getTerms());
  Block *block = b.createBlock(&region, region.end(), TypeRange(refined), {loc});
  Case out{block, {}, binders};
  for (auto [i, field] : llvm::enumerate(*refined.determinedFields(tag)))
    out.fields.push_back(DataFieldOp::create(b, loc, field, block->getArgument(0), static_cast<unsigned>(i)));
  return out;
}

// A value of a refined type yielded where the match gives its own: the
// cast the enclosing refinements check, or the value where the two are
// one type.
Value reindexed(OpBuilder &b, Location loc, Value value, Type to) {
  if (value.getType() == to)
    return value;
  return DataReindexOp::create(b, loc, to, value);
}

} // namespace

Value coerce(OpBuilder &b, Location loc, Value value, const Key &from, const Key &to,
             const Decision &decision) {
  Type sink = decision.typeOf(atUses(to.carrier, usesOf(value.getType())), to);
  // A move no label reaches never runs: the program's poison.
  if (from.labels.empty() || to.labels.empty())
    return ub::PoisonOp::create(b, loc, sink);
  // A value used once is used once by the match, and the rebuilt one
  // enters the slot at its quantity: the match takes it and gives it.
  DataType source = cast<DataType>(unrestricted(value.getType()));
  DataType target = cast<DataType>(unrestricted(sink));
  SmallVector<int32_t> tags;
  for (unsigned at = 0; at < from.labels.size(); ++at)
    tags.push_back(static_cast<int32_t>(at));
  auto match = DataMatchOp::create(b, loc, TypeRange(sink), value, b.getDenseI32ArrayAttr(tags), ValueRange());
  OpBuilder::InsertionGuard guard(b);
  for (auto [at, label] : llvm::enumerate(from.labels.getAsRange<FlatSymbolRefAttr>())) {
    Case taken = caseOf(b, loc, match, static_cast<unsigned>(at), source, Tag{static_cast<uint32_t>(at)});
    Tag into = decision.tagOf(to, label);
    DataType built = target.refinedTo(into, taken.binders.getTerms());
    SmallVector<Value> held;
    for (auto [field, type] : llvm::zip_equal(taken.fields, *built.determinedFields(into)))
      held.push_back(heldAs(b, loc, field, type));
    Value rebuilt = DataConOp::create(b, loc, built, held);
    YieldOp::create(b, loc, reindexed(b, loc, rebuilt, sink));
  }
  return match->getResult(0);
}

namespace {

// What the rewrite of each kind of closure op reads of the solve, read
// before any type changes: the keys of its operands and results.
template <class Op>
struct Read {
  Op op;
  SmallVector<Slot, 2> keys;
};

template <class Op>
SmallVector<Read<Op>> readAll(FuncOp fn, const Decision &decision) {
  SmallVector<Read<Op>> out;
  fn.walk([&](Op op) {
    Read<Op> &read = out.emplace_back(Read<Op>{op, {}});
    for (Value operand : op->getOperands())
      read.keys.push_back(decision.keyOf(operand));
    for (Value result : op->getResults())
      read.keys.push_back(decision.keyOf(result));
  });
  return out;
}

// What the rewrite builds of a constructor op: its family's constructor
// for the label, the captures held as its fields.
Value construct(OpBuilder &b, Location loc, Value result, Tag tag, ValueRange captures) {
  DataType family = cast<DataType>(unrestricted(result.getType()));
  DataType built = family.refinedTo(tag, {});
  SmallVector<Value> held;
  for (auto [capture, type] : llvm::zip_equal(captures, *built.determinedFields(tag)))
    held.push_back(heldAs(b, loc, capture, type));
  return DataConOp::create(b, loc, built, held);
}

} // namespace

LogicalResult rewrite(FuncOp fn, const Decision &decision) {
  OpBuilder b(fn.getContext());
  const Signature &sig = decision.signature(fn.getSymNameAttr());

  // Read: each value's new type, each move that goes between two keys, and
  // each closure op's keys, before any type changes.
  struct Move {
    OpOperand *use;
    Key from, to;
  };
  struct Retype {
    Value value;
    Type type;
  };
  SmallVector<Move> moves;
  SmallVector<Retype> retypes;
  fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (OpOperand &use : op->getOpOperands()) {
      Slot from = decision.keyOf(use.get()), to = decision.sinkOf(use);
      if (from && to && *from != *to)
        moves.push_back({&use, *from, *to});
    }
    for (Value result : op->getResults())
      retypes.push_back({result, decision.typeOf(result.getType(), decision.keyOf(result))});
    if (op == fn.getOperation())
      return;
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Value arg : block.getArguments())
          retypes.push_back({arg, decision.typeOf(arg.getType(), decision.keyOf(arg))});
  });
  SmallVector<Read<FnClosureOp>> closures = readAll<FnClosureOp>(fn, decision);
  SmallVector<Read<LazySuspendOp>> suspensions = readAll<LazySuspendOp>(fn, decision);
  SmallVector<Read<LazyDelayOp>> delays = readAll<LazyDelayOp>(fn, decision);
  SmallVector<Read<FnApplyOp>> applies = readAll<FnApplyOp>(fn, decision);
  SmallVector<Read<LazyForceOp>> forces = readAll<LazyForceOp>(fn, decision);
  SmallVector<Read<ConstantOp>> constants = readAll<ConstantOp>(fn, decision);

  // Retype: the function's signature and entry block, then every value.
  fn.setFunctionType(sig.converted);
  for (auto [arg, type] : llvm::zip_equal(fn.getArguments(), sig.converted.getInputs()))
    arg.setType(type);
  for (const Retype &each : retypes)
    each.value.setType(each.type);

  // Coerce: before the op that moves it, each value rebuilt in its sink's
  // family.
  for (const Move &move : moves) {
    Operation *owner = move.use->getOwner();
    b.setInsertionPoint(owner);
    move.use->set(coerce(b, owner->getLoc(), move.use->get(), move.from, move.to, decision));
  }

  // Replace: each closure op by what it means, each kind by its own rule.
  SmallVector<Operation *> erased;
  SmallVector<CallOp> made;
  for (const Read<FnClosureOp> &read : closures) {
    b.setInsertionPoint(read.op);
    Tag tag = decision.tagOf(*read.keys.back(), read.op.getCalleeAttr());
    read.op.getResult().replaceAllUsesWith(
        construct(b, read.op.getLoc(), read.op.getResult(), tag, read.op.getCaptures()));
    erased.push_back(read.op);
  }
  // An unforced cell keeps its identity: its constructor is a fresh one,
  // as the family's kind says, and nothing merges or folds it.
  for (const Read<LazySuspendOp> &read : suspensions) {
    b.setInsertionPoint(read.op);
    Tag tag = decision.tagOf(*read.keys.back(), read.op.getCalleeAttr());
    read.op.getResult().replaceAllUsesWith(
        construct(b, read.op.getLoc(), read.op.getResult(), tag, read.op.getCaptures()));
    erased.push_back(read.op);
  }
  // An evaluated suspension is its memo family's forced state.
  for (const Read<LazyDelayOp> &read : delays) {
    b.setInsertionPoint(read.op);
    DataType family = cast<DataType>(unrestricted(read.op.getResult().getType()));
    read.op.getResult().replaceAllUsesWith(construct(b, read.op.getLoc(), read.op.getResult(),
                                                     family.memo()->forced(), read.op.getValue()));
    erased.push_back(read.op);
  }
  // An apply is a match over its callee's family, each case calling the
  // function its label names with the captures, then the arguments; a
  // family no label reaches is a value the program never has.
  for (const Read<FnApplyOp> &read : applies) {
    FnApplyOp apply = read.op;
    Location loc = apply.getLoc();
    b.setInsertionPoint(apply);
    const Key &key = *read.keys.front();
    SmallVector<Type> types(apply.getResultTypes());
    if (key.labels.empty()) {
      for (Value result : apply.getResults())
        result.replaceAllUsesWith(ub::PoisonOp::create(b, loc, result.getType()));
      erased.push_back(apply);
      continue;
    }
    // A tail apply's dispatch is in tail position, and so is each case's
    // call, unless a result is rebuilt after it.
    TailPosition tail = tail::inTailPosition(apply) ? TailPosition::Tail : TailPosition::Within;
    Value callee = apply.getCallee();
    DataType family = cast<DataType>(unrestricted(callee.getType()));
    SmallVector<int32_t> tags;
    for (unsigned at = 0; at < key.labels.size(); ++at)
      tags.push_back(static_cast<int32_t>(at));
    auto match = DataMatchOp::create(b, loc, types, callee, b.getDenseI32ArrayAttr(tags), ValueRange());
    OpBuilder::InsertionGuard guard(b);
    for (auto [at, label] : llvm::enumerate(key.labels.getAsRange<FlatSymbolRefAttr>())) {
      Case taken = caseOf(b, loc, match, static_cast<unsigned>(at), family, Tag{static_cast<uint32_t>(at)});
      const Signature &run = decision.signature(label.getAttr());
      auto target = SymbolTable::lookupNearestSymbolFrom<FuncOp>(apply, label);
      auto captures = static_cast<unsigned>(taken.fields.size());
      SmallVector<Value> args;
      for (auto [field, type] : llvm::zip_equal(taken.fields, run.converted.getInputs().take_front(captures)))
        args.push_back(heldAs(b, loc, field, type));
      for (auto [i, arg] : llvm::enumerate(apply.getArgs())) {
        Value value = arg;
        const Slot &into = run.arguments[captures + i];
        if (const Slot &own = read.keys[1 + i]; own && into && *own != *into)
          value = coerce(b, loc, value, *own, *into, decision);
        args.push_back(heldAs(b, loc, value, run.converted.getInput(captures + i)));
      }
      CallOp call = callOf(b, loc, target, taken.binders, run.converted.getResults(), args);
      made.push_back(call);
      SmallVector<Value> yields;
      for (auto [j, result] : llvm::enumerate(call.getResults())) {
        Value value = result;
        const Slot &own = read.keys[1 + apply.getArgs().size() + j];
        if (const Slot &out = run.results[j]; own && out && *own != *out) {
          if (tail == TailPosition::Tail)
            return apply.emitError("internal error: idr-defunctionalize: the label ")
                   << label << " of a tail apply gives a closure of other labels than the "
                   << "apply's, rebuilt after the call";
          value = coerce(b, loc, value, *out, *own, decision);
        }
        yields.push_back(reindexed(b, loc, value, types[j]));
      }
      YieldOp::create(b, loc, yields);
    }
    apply->replaceAllUsesWith(match->getResults());
    erased.push_back(apply);
  }
  // A force is a call of its cell's dispatch function, the value moved out
  // of the forced state's slot into the force's.
  for (const Read<LazyForceOp> &read : forces) {
    LazyForceOp force = read.op;
    Location loc = force.getLoc();
    b.setInsertionPoint(force);
    const Family &memo = decision.familyOf(*read.keys.front());
    auto dispatch = SymbolTable::lookupNearestSymbolFrom<FuncOp>(force, memo.force);
    DataType cell = cast<DataType>(unrestricted(force.getSuspension().getType()));
    Value taken = heldAs(b, loc, force.getSuspension(), dispatch.getArgumentTypes().front());
    CallOp call = callOf(b, loc, dispatch, IndexArgsAttr::get(b.getContext(), cell.getIndices()),
                         dispatch.getResultTypes(), ValueRange(taken));
    made.push_back(call);
    Value value = call.getResult(0);
    const Slot &forced = decision.signature(memo.force.getAttr()).results.front();
    if (const Slot &own = read.keys.back(); own && forced && *own != *forced)
      value = coerce(b, loc, value, *forced, *own, decision);
    force.getResult().replaceAllUsesWith(heldAs(b, loc, value, force.getResult().getType()));
    erased.push_back(force);
  }
  // A constant holding a closure, each closure in it its label's
  // constructor in its slot's family.
  for (const Read<ConstantOp> &read : constants) {
    Attribute value = decision.constantOf(read.op.getValue(), read.keys.back());
    if (value == read.op.getValue())
      continue;
    b.setInsertionPoint(read.op);
    read.op.getResult().replaceAllUsesWith(
        ConstantOp::create(b, read.op.getLoc(), read.op.getResult().getType(), value));
    erased.push_back(read.op);
  }
  for (Operation *op : llvm::reverse(erased))
    op->erase();
  // Each call this walk made, its tail fact read where it now stands.
  for (CallOp call : made)
    call.setTailKind(tail::decide(call));
  return success();
}

} // namespace idr::defunctionalize
