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
// The walk leaves how each value is built, what each match's regions
// yield, the returns with the matches around them, and the calls that do
// not only compute. It reads the function's own body, the data types its
// values are of, the entries of the component's members, the callees'
// effects and what `outside` says of every other callee, and writes
// nothing outside the record.
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

bool memoType(Type type) {
  DataType data = dataTypeOf(type);
  return data && data.isMemo();
}

// The tag of the one constructor of the scrutinee's type that no case of
// `match` names, which its default region therefore takes, if there is one.
std::optional<Tag> remaining(MatchOp match) {
  DataType data = match.getDataType();
  auto cases = static_cast<unsigned>(match.getCases().size());
  if (data.getCtors().size() != cases + 1)
    return std::nullopt;
  SmallVector<Tag> named;
  for (unsigned index = 0; index < cases; ++index)
    named.push_back(match.getCaseTag(index));
  for (Tag tag : data.getTags())
    if (!llvm::is_contained(named, tag))
      return tag;
  return std::nullopt;
}

} // namespace

// The one walk, into `out`. It reads the function's own body, the data
// types its values are of, the entries of the component's members and what
// `outside` says of every other callee.
class Record::Walker {
public:
  Walker(FuncOp fn, const Members &members, Outside outside, const CalleeEffects &effects,
         Record &out)
      : fn(fn), members(members), outside(outside), effects(effects), out(out) {}

  bool scan(Region &region);

private:
  Id place(Value value, Build build);
  Id intern(Value value);
  Id internArg(BlockArgument arg);
  Id defineCall(CallOp call);
  Id internJoin(Operation *op, unsigned number);
  Id internResult(OpResult result);
  SmallVector<Arm, 2> armsOf(Operation *op);
  Frames framesAt(Operation *at);
  bool record(ReturnOp ret);
  bool accept(Operation &op);

  FuncOp fn;
  const Members &members;
  Outside outside;
  const CalleeEffects &effects;
  Record &out;
  llvm::DenseMap<Value, Id> ids;
};

std::optional<Record> Record::walk(FuncOp fn, ArrayRef<unsigned> candidates,
                                   const Members &members, Outside outside,
                                   const CalleeEffects &effects) {
  if (candidates.empty())
    return std::nullopt;
  Record out;
  for (unsigned argument : candidates) {
    out.slots.try_emplace(argument, static_cast<unsigned>(out.arguments.size()));
    out.arguments.push_back(argument);
    out.types.push_back(unrestricted(fn.getArgumentTypes()[argument]));
  }
  // A terminator this question cannot keep, or an op that does not only
  // compute, ends the walk: nothing is given back, under any argument and
  // any later assumptions, so the rest of the body is not needed.
  if (!Walker(fn, members, outside, effects, out).scan(fn.getBody()))
    return std::nullopt;
  return out;
}

Record::Id Record::Walker::place(Value value, Build build) {
  auto id = Id(static_cast<unsigned>(out.nodes.size()));
  out.nodes.push_back(std::move(build));
  ids[value] = id;
  return id;
}

Record::Id Record::Walker::intern(Value value) {
  if (auto it = ids.find(value); it != ids.end())
    return it->second;
  if (auto arg = dyn_cast<BlockArgument>(value))
    return internArg(arg);
  return internResult(cast<OpResult>(value));
}

// The entry block's arguments are the function's; a case's are the fields
// of the scrutinee, and the default region's is the scrutinee itself.
Record::Id Record::Walker::internArg(BlockArgument arg) {
  Block *block = arg.getOwner();
  if (block == &fn.getBody().front())
    return place(arg, Entry{arg.getArgNumber()});
  auto match = dyn_cast_or_null<MatchOp>(block->getParentOp());
  if (!match || memoType(match.getScrutinee().getType()))
    return place(arg, Opaque{});
  Id scrutinee = intern(match.getScrutinee());
  Region *region = block->getParent();
  if (region == match.getDefaultRegion())
    return place(arg, Same{scrutinee});
  return place(arg, Field{scrutinee, match.getCaseTag(region->getRegionNumber()),
                          arg.getArgNumber(), arg.getType()});
}

// A callee of the component is known by its own entry; any other by what
// `outside` says of it.
Record::Id Record::Walker::defineCall(CallOp call) {
  for (Value result : call.getResults())
    if (auto it = ids.find(result); it != ids.end())
      return it->second;
  Call made;
  made.callee = call.getCalleeAttr().getAttr();
  if (FuncOp member = members.lookup(made.callee))
    made.returns = !bitEnumContainsAny(member.getEffects(), Effect::diverge);
  else
    made.returns = outside(made.callee).returns;
  for (Value operand : call.getArgs())
    made.args.push_back(intern(operand));
  auto id = Id(static_cast<unsigned>(out.nodes.size()));
  out.nodes.push_back(std::move(made));
  for (Value result : call.getResults())
    ids[result] = id;
  return id;
}

// Every result of a match at once, after its arms: the arms are made
// first, so a match inside one has its own side before this one takes its
// own.
Record::Id Record::Walker::internJoin(Operation *op, unsigned number) {
  SmallVector<Arm, 2> arms = armsOf(op);
  auto side = static_cast<unsigned>(out.joins.size());
  out.joins.push_back(std::move(arms));
  std::optional<Id> wanted;
  for (OpResult result : op->getResults()) {
    Id id = place(result, Join{side, result.getResultNumber()});
    if (result.getResultNumber() == number)
      wanted = id;
  }
  return *wanted;
}

SmallVector<Record::Arm, 2> Record::Walker::armsOf(Operation *op) {
  SmallVector<Arm, 2> arms;
  for (Region &region : op->getRegions()) {
    if (region.empty()) {
      arms.push_back(Fails{});
      continue;
    }
    Operation *end = region.front().getTerminator();
    if (isa<ub::UnreachableOp>(end)) {
      arms.push_back(Unreachable{});
    } else if (isa<YieldOp>(end)) {
      Yields yields;
      yields.frames = framesAt(end);
      for (Value operand : end->getOperands())
        yields.values.push_back(intern(operand));
      arms.push_back(std::move(yields));
    } else {
      arms.push_back(Fails{});
    }
  }
  return arms;
}

Record::Id Record::Walker::internResult(OpResult result) {
  Operation *op = result.getOwner();
  if (isa<MatchOp, MatchLitOp>(op))
    return internJoin(op, result.getResultNumber());
  if (auto call = dyn_cast<CallOp>(op))
    return defineCall(call);
  if (op->hasTrait<ResultCarriesOperand>())
    return place(result, Same{intern(op->getOperand(0))});
  if (auto read = dyn_cast<FieldOp>(op)) {
    if (memoType(read.getValue().getType()))
      return place(result, Opaque{});
    return place(result, Field{intern(read.getValue()), read.getTag(),
                               static_cast<unsigned>(read.getIndex()), read.getType()});
  }
  if (auto pred = dyn_cast<BigPredOp>(op))
    return place(result, Pred{intern(pred.getValue())});
  if (auto con = dyn_cast<ConOp>(op)) {
    Type type = con.getResult().getType();
    if (memoType(type))
      return place(result, Opaque{});
    Con made{con.getTag(), type, {}, {}};
    for (Value field : con.getFields()) {
      made.fields.push_back(intern(field));
      made.types.push_back(field.getType());
    }
    return place(result, std::move(made));
  }
  if (auto add = dyn_cast<BigAddOp>(op)) {
    Value lhs = add.getLhs();
    Value rhs = add.getRhs();
    Value rest = isOne(rhs) ? lhs : isOne(lhs) ? rhs : Value();
    if (!rest)
      return place(result, Opaque{});
    return place(result, Successor{intern(rest)});
  }
  Attribute constant;
  if (!matchPattern(result, m_Constant(&constant)))
    return place(result, Opaque{});
  std::optional<Tag> fieldless;
  if (auto con = dyn_cast<ConAttr>(constant);
      con && !con.isRun() && con.getData().getCtor(con.getTag()).fields.empty())
    fieldless = con.getTag();
  return place(result, Constant{constant, result.getType(), fieldless});
}

// The matches around `at`, inner first, each where its region says what
// its scrutinee is: a case its constructor's tag, a default region the
// one constructor no case names, a literal case its literal.
Record::Frames Record::Walker::framesAt(Operation *at) {
  Frames frames;
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (parent == fn.getOperation())
      break;
    if (auto match = dyn_cast<MatchOp>(parent)) {
      std::optional<Tag> tag =
          region == match.getDefaultRegion()
              ? remaining(match)
              : std::optional<Tag>(match.getCaseTag(region->getRegionNumber()));
      if (tag)
        frames.push_back({intern(match.getScrutinee()), KnownTag{*tag}});
    } else if (auto literal = dyn_cast<MatchLitOp>(parent)) {
      if (region != literal.getDefaultRegion())
        frames.push_back({intern(literal.getScrutinee()),
                          KnownLiteral{literal.getCases()[region->getRegionNumber()]}});
    }
  }
  return frames;
}

bool Record::Walker::record(ReturnOp ret) {
  if (ret.getNumOperands() != 1)
    return false;
  Id value = intern(ret.getOperand(0));
  out.rets.push_back({value, framesAt(ret.getOperation())});
  return true;
}

// The one descent. Match regions are part of what only computes; a call
// that does not only compute is kept to be justified from the record; any
// other op must only compute, and is not opened again.
bool Record::Walker::scan(Region &region) {
  for (Block &block : region) {
    for (BlockArgument arg : block.getArguments())
      intern(arg);
    for (Operation &op : block)
      if (!accept(op))
        return false;
  }
  return true;
}

bool Record::Walker::accept(Operation &op) {
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
    Id id = defineCall(call);
    if (!onlyAllocates(call, &effects))
      out.reliant.push_back(id);
    return true;
  }
  // An op with regions that only computes holds no return: idr.return is
  // only ever in the function's own body.
  if (!onlyAllocates(&op, &effects))
    return false;
  for (Value result : op.getResults())
    intern(result);
  return true;
}

} // namespace idr::identities
