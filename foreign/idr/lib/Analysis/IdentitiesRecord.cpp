// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one walk of a function whose arguments might be given back.
//
// A return gives back the argument x when its value is x rebuilt: x
// itself, or a part of x where x is that part; a constructor where x is
// known to be that constructor, each field the same field of x rebuilt; a
// constant where x is known to be that literal, or that constructor when
// it has no fields; the successor of x's predecessor; a match whose every
// region that returns yields x rebuilt; a value held at another quantity;
// or a call assumed to give back what it is passed, passed x. What x is
// known to be at a return is what the matches around it say (a case binds
// its constructor or its literal), or the one constructor its type has;
// values never change, so it holds of every read of x, wherever the read
// is.
//
// The function must also only compute: each op only allocates its results
// (a call as its callee's effects say), or is a match whose regions only
// compute, or a call assumed to give back what it is passed that it may
// rely on. A region that ends in ub.unreachable and does nothing else on
// the way is one Idris proved is never taken. A function of a program in
// the owned stage has no candidates, so no value walked here holds or
// borrows a reference.
//
// The walk leaves the part each value is of every candidate argument, and
// the calls whose result is an operand while the callee is assumed to give
// that operand back. It reads the function's own body, the data types its
// values are of, the entries of the component's members and what `outside`
// says of every other callee, and writes nothing outside the record.
#include "idr/Analysis/Identities.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::identities {

namespace {

// A big or natural constant one: what a successor adds.
bool isOne(Value value) {
  BigAttr big;
  return matchPattern(value, m_Constant(&big)) && big.getValue().isOne();
}

} // namespace

Record::Record(FuncOp fn, ArrayRef<unsigned> candidates, const Members &members, Outside outside)
    : fn(fn), members(members), outside(outside) {
  for (unsigned argument : candidates) {
    index.try_emplace(argument, static_cast<unsigned>(arguments.size()));
    arguments.push_back(argument);
    parts.emplace_back(fn.getArgumentTypes()[argument]);
  }
  // Walk the body once. A terminator this question cannot keep, or an op
  // that does not only allocate, ends it: nothing is given back, under any
  // argument and any later assumptions, so the rest of the body is not
  // needed and is not walked again.
  if (arguments.empty() || !scan(fn.getBody())) {
    possible = false;
    nodes.clear();
    memo.clear();
    ids.clear();
    rets.clear();
    reliant.clear();
    joins.clear();
  }
}

bool Record::memoType(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.isMemo();
}

// The tag of the one constructor of the scrutinee's type that no case of
// `match` names, which its default region therefore takes, if there is one.
std::optional<unsigned> Record::remaining(MatchOp match) {
  DataType data = match.getDataType();
  auto cases = static_cast<unsigned>(match.getCases().size());
  if (data.getCtors().size() != cases + 1)
    return std::nullopt;
  SmallVector<bool> named(cases + 1, false);
  for (unsigned index = 0; index < cases; ++index)
    named[match.getCaseTag(index)] = true;
  return static_cast<unsigned>(llvm::find(named, false) - named.begin());
}

int Record::place(Value value, Node node) {
  int id = static_cast<int>(nodes.size());
  nodes.push_back(std::move(node));
  memo.emplace_back();
  ids[value] = id;
  return id;
}

int Record::intern(Value value) {
  if (auto it = ids.find(value); it != ids.end())
    return it->second;
  if (auto arg = dyn_cast<BlockArgument>(value))
    return internArg(arg);
  return internResult(cast<OpResult>(value));
}

int Record::internArg(BlockArgument arg) {
  Node node;
  Block *block = arg.getOwner();
  if (block == &fn.getBody().front()) {
    node.kind = Node::Entry;
    node.arg = arg.getArgNumber();
  } else if (auto match = dyn_cast_or_null<MatchOp>(block->getParentOp())) {
    node.kind = Node::MatchArg;
    node.src = intern(match.getScrutinee());
    node.arg = arg.getArgNumber();
    node.type = arg.getType();
    node.memo = memoType(match.getScrutinee().getType());
    Region *region = block->getParent();
    if (region == match.getDefaultRegion())
      node.deflt = true;
    else
      node.tag = match.getCaseTag(region->getRegionNumber());
  }
  return place(arg, std::move(node));
}

int Record::defineCall(CallOp call) {
  for (Value result : call.getResults())
    if (auto it = ids.find(result); it != ids.end())
      return it->second;
  Node node;
  node.kind = Node::Call;
  node.callee = call.getCalleeAttr().getAttr();
  // A callee of the component is known by its own entry; any other by what
  // `outside` says of it.
  if (FuncOp member = members.lookup(node.callee))
    node.returns = !bitEnumContainsAny(entryOf(member), Effect::diverge);
  else
    node.returns = outside(node.callee).returns;
  node.allocates = onlyAllocates(call);
  for (Value operand : call.getArgs())
    node.ops.push_back(intern(operand));
  int id = static_cast<int>(nodes.size());
  nodes.push_back(std::move(node));
  memo.emplace_back();
  for (Value result : call.getResults())
    ids[result] = id;
  return id;
}

void Record::encodeConst(Node &node, Value value, Attribute constant) {
  node.kind = Node::Const;
  node.attr = constant;
  node.type = value.getType();
  auto con = dyn_cast<ConAttr>(constant);
  if (!con)
    return;
  node.isCon = true;
  node.conRun = con.isRun();
  if (node.conRun)
    return;
  node.tag = con.getTag();
  node.fieldless = con.getData().getCtor(node.tag).fields.empty();
}

int Record::internJoin(Operation *op, unsigned number) {
  unsigned side = static_cast<unsigned>(joins.size());
  joins.push_back(armsOf(op));
  int wanted = -1;
  for (OpResult result : op->getResults()) {
    Node node;
    node.kind = Node::Join;
    node.arg = result.getResultNumber();
    node.side = side;
    int id = place(result, std::move(node));
    if (result.getResultNumber() == number)
      wanted = id;
  }
  return wanted;
}

SmallVector<Record::Arm, 2> Record::armsOf(Operation *op) {
  SmallVector<Arm, 2> arms;
  for (Region &region : op->getRegions()) {
    Arm arm;
    if (region.empty()) {
      arm.empty = true;
      arms.push_back(std::move(arm));
      continue;
    }
    Operation *end = region.front().getTerminator();
    if (isa<ub::UnreachableOp>(end)) {
      arm.unreachable = true;
    } else if (isa<YieldOp>(end)) {
      arm.yield = true;
      arm.frames = framesAt(end);
      for (Value operand : end->getOperands())
        arm.values.push_back(intern(operand));
    } else {
      arm.empty = true;
    }
    arms.push_back(std::move(arm));
  }
  return arms;
}

int Record::internResult(OpResult result) {
  Operation *op = result.getOwner();
  if (isa<MatchOp, MatchLitOp>(op))
    return internJoin(op, result.getResultNumber());
  if (auto call = dyn_cast<CallOp>(op))
    return defineCall(call);
  Node node;
  if (op->hasTrait<ResultCarriesOperand>()) {
    node.kind = Node::Copy;
    node.src = intern(op->getOperand(0));
  } else if (auto read = dyn_cast<FieldOp>(op)) {
    node.kind = Node::Field;
    node.src = intern(read.getValue());
    node.tag = static_cast<unsigned>(read.getTag());
    node.arg = static_cast<unsigned>(read.getIndex());
    node.type = read.getType();
    node.memo = memoType(read.getValue().getType());
  } else if (auto pred = dyn_cast<BigPredOp>(op)) {
    node.kind = Node::Pred;
    node.src = intern(pred.getValue());
  } else if (auto con = dyn_cast<ConOp>(op)) {
    node.kind = Node::Con;
    node.tag = static_cast<unsigned>(con.getTag());
    node.type = con.getResult().getType();
    node.memo = memoType(node.type);
    for (Value field : con.getFields()) {
      node.ops.push_back(intern(field));
      node.types.push_back(field.getType());
    }
  } else if (auto add = dyn_cast<BigAddOp>(op)) {
    node.kind = Node::Add;
    Value lhs = add.getLhs();
    Value rhs = add.getRhs();
    Value rest = isOne(rhs) ? lhs : isOne(lhs) ? rhs : Value();
    node.src = rest ? intern(rest) : -1;
  } else {
    Attribute constant;
    if (matchPattern(result, m_Constant(&constant)))
      encodeConst(node, result, constant);
  }
  return place(result, std::move(node));
}

SmallVector<Record::Frame, 2> Record::framesAt(Operation *at) {
  SmallVector<Frame, 2> frames;
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (parent == fn.getOperation())
      break;
    if (auto match = dyn_cast<MatchOp>(parent)) {
      Frame frame;
      frame.scrutinee = intern(match.getScrutinee());
      frame.tag = region == match.getDefaultRegion()
                      ? remaining(match)
                      : std::optional<unsigned>(match.getCaseTag(region->getRegionNumber()));
      frames.push_back(frame);
    } else if (auto literal = dyn_cast<MatchLitOp>(parent)) {
      Frame frame;
      frame.lit = true;
      frame.scrutinee = intern(literal.getScrutinee());
      if (region != literal.getDefaultRegion())
        frame.literal = literal.getCases()[region->getRegionNumber()];
      frames.push_back(frame);
    }
  }
  return frames;
}

bool Record::record(ReturnOp ret) {
  if (ret.getNumOperands() != 1)
    return false;
  rets.push_back({intern(ret.getOperand(0)), framesAt(ret.getOperation())});
  return true;
}

// The one descent. Match regions are part of what only computes; a call
// that does not only allocate is kept to be justified from the record; any
// other op must only allocate, and is not opened again.
bool Record::scan(Region &region) {
  for (Block &block : region) {
    for (BlockArgument arg : block.getArguments())
      intern(arg);
    for (Operation &op : block)
      if (!accept(op))
        return false;
  }
  return true;
}

bool Record::accept(Operation &op) {
  if (op.hasTrait<OpTrait::IsTerminator>()) {
    if (auto ret = dyn_cast<ReturnOp>(op))
      return record(ret);
    return isa<YieldOp, ub::UnreachableOp>(op);
  }
  if (isa<MatchOp, MatchLitOp>(op)) {
    for (Region &region : op.getRegions())
      if (!scan(region))
        return false;
    if (op.getNumResults())
      intern(op.getResult(0));
    return true;
  }
  if (auto call = dyn_cast<CallOp>(op)) {
    int id = defineCall(call);
    if (!nodes[static_cast<std::size_t>(id)].allocates)
      reliant.push_back(id);
    return true;
  }
  // An op with regions that only allocates holds no return: idr.return is
  // only ever in the function's own body.
  if (!onlyAllocates(&op))
    return false;
  for (Value result : op.getResults())
    intern(result);
  return true;
}

} // namespace idr::identities
