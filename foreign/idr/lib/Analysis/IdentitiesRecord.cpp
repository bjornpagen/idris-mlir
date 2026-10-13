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
// (a call as its own effects say), or is a match whose regions only
// compute, or a call assumed to give back what it is passed that it may
// rely on. A region that ends in ub.unreachable and does nothing else on
// the way is one Idris proved is never taken. In the owned stage, where a
// value holds or borrows a reference, nothing gives back anything: a
// counted value cannot stand for a fresh one.
//
// The walk leaves the part each value is of every candidate argument, and
// the calls whose result is an operand while the callee is assumed to give
// that operand back. It reads the function's own body, the symbol table and
// the declarations, and writes nothing outside the record, so the walks of
// a module's functions run at once.
#include "idr/Analysis/Identities.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

namespace {

bool isOne(Value value) {
  Attribute constant;
  auto big = matchPattern(value, m_Constant(&constant)) ? dyn_cast<BigAttr>(constant) : BigAttr();
  return big && big.getValue() == "1";
}

StringAttr caseCtor(MatchOp match, unsigned region) {
  return cast<FlatSymbolRefAttr>(match.getCases()[region]).getAttr();
}

} // namespace

Identities::Record::Record(FuncOp fn, ArrayRef<unsigned> candidates, SymbolTable &symbols)
    : fn(fn), symbols(symbols) {
  for (unsigned argument : candidates) {
    index.try_emplace(argument, static_cast<unsigned>(arguments.size()));
    arguments.push_back(argument);
    parts.emplace_back(fn.getArgumentTypes()[argument]);
  }
  // Walk the body once. An owned value, a terminator this question cannot
  // keep, or an op that does not only allocate ends it: nothing is given
  // back, under any argument and any later assumptions, so the rest of the
  // body is not needed and is not walked again.
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

bool Identities::Record::memoType(Type type) {
  DataOp data = lookupData(symbols, type);
  return data && isMemo(data);
}

// The one constructor of the scrutinee's type that no case of `match`
// names, which its default region therefore takes, if there is one.
StringAttr Identities::Record::remaining(MatchOp match) {
  DataOp data = lookupData(symbols, match.getScrutinee().getType());
  if (!data)
    return {};
  SmallVector<CtorOp> ctors = data.getCtors();
  if (ctors.size() != match.getCases().size() + 1)
    return {};
  for (CtorOp ctor : ctors)
    if (llvm::none_of(match.getCases(), [&](Attribute named) {
          return cast<FlatSymbolRefAttr>(named).getAttr() == ctor.getSymNameAttr();
        }))
      return ctor.getSymNameAttr();
  return {};
}

int Identities::Record::place(Value value, Node node) {
  int id = static_cast<int>(nodes.size());
  nodes.push_back(std::move(node));
  memo.emplace_back();
  ids[value] = id;
  return id;
}

int Identities::Record::intern(Value value) {
  if (auto it = ids.find(value); it != ids.end())
    return it->second;
  if (auto arg = dyn_cast<BlockArgument>(value))
    return internArg(arg);
  return internResult(cast<OpResult>(value));
}

int Identities::Record::internArg(BlockArgument arg) {
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
    unsigned region = block->getParent()->getRegionNumber();
    if (region >= match.getCases().size())
      node.deflt = true;
    else
      node.ctor = caseCtor(match, region);
  }
  return place(arg, std::move(node));
}

int Identities::Record::defineCall(CallOp call) {
  for (Value result : call.getResults())
    if (auto it = ids.find(result); it != ids.end())
      return it->second;
  Node node;
  node.kind = Node::Call;
  node.callee = call.getCalleeAttr().getAttr();
  // A function the module lacks, one without a body, or one without effects
  // may do anything, so it is not known to return.
  auto callee = symbols.lookup<FuncOp>(node.callee);
  std::optional<Effect> effects =
      callee && !callee.isExternal() ? callee.getEffects() : std::optional<Effect>();
  node.returns = effects && !bitEnumContainsAny(*effects, Effect::diverge);
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

void Identities::Record::encodeConst(Node &node, Value value, Attribute constant) {
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
  node.ctor = con.getCtor().getLeafReference();
  CtorOp ctor = lookupCtor(symbols, con.getCtor());
  node.fieldless = ctor && ctor.getFieldTypes().empty();
}

int Identities::Record::internJoin(Operation *op, unsigned number) {
  unsigned side = static_cast<unsigned>(joins.size());
  joins.push_back(armsOf(op));
  int found = -1;
  for (OpResult result : op->getResults()) {
    Node node;
    node.kind = Node::Join;
    node.arg = result.getResultNumber();
    node.side = side;
    int id = place(result, std::move(node));
    if (result.getResultNumber() == number)
      found = id;
  }
  return found;
}

SmallVector<Identities::Record::Arm, 2> Identities::Record::armsOf(Operation *op) {
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

int Identities::Record::internResult(OpResult result) {
  Operation *op = result.getOwner();
  if (isa<MatchOp, MatchLitOp>(op))
    return internJoin(op, result.getResultNumber());
  if (auto call = dyn_cast<CallOp>(op))
    return defineCall(call);
  Node node;
  if (isa<LinEnterOp, LinUseOp>(op)) {
    node.kind = Node::Copy;
    node.src = intern(op->getOperand(0));
  } else if (auto read = dyn_cast<FieldOp>(op)) {
    node.kind = Node::Field;
    node.src = intern(read.getValue());
    node.ctor = read.getCtorAttr().getAttr();
    node.arg = static_cast<unsigned>(read.getIndex());
    node.type = read.getType();
    node.memo = memoType(read.getValue().getType());
  } else if (auto pred = dyn_cast<BigPredOp>(op)) {
    node.kind = Node::Pred;
    node.src = intern(pred.getValue());
  } else if (auto con = dyn_cast<ConOp>(op)) {
    node.kind = Node::Con;
    node.ctor = con.getCtor().getLeafReference();
    node.type = con.getType();
    node.memo = memoType(con.getType());
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

SmallVector<Identities::Record::Frame, 2> Identities::Record::framesAt(Operation *at) {
  SmallVector<Frame, 2> frames;
  for (Region *region = at->getParentRegion(); region; region = region->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (parent == fn.getOperation())
      break;
    unsigned regionNumber = region->getRegionNumber();
    if (auto match = dyn_cast<MatchOp>(parent)) {
      Frame frame;
      frame.scrutinee = intern(match.getScrutinee());
      if (regionNumber < match.getCases().size()) {
        frame.named = true;
        frame.ctor = caseCtor(match, regionNumber);
      } else if (StringAttr rest = remaining(match)) {
        frame.named = true;
        frame.ctor = rest;
      }
      frames.push_back(frame);
    } else if (auto literal = dyn_cast<MatchLitOp>(parent)) {
      Frame frame;
      frame.lit = true;
      frame.scrutinee = intern(literal.getScrutinee());
      if (regionNumber < literal.getCases().size()) {
        frame.named = true;
        frame.literal = literal.getCases()[regionNumber];
      }
      frames.push_back(frame);
    }
  }
  return frames;
}

bool Identities::Record::record(ReturnOp ret) {
  if (ret.getNumOperands() != 1)
    return false;
  rets.push_back({intern(ret.getOperand(0)), framesAt(ret.getOperation())});
  return true;
}

// The one descent. Match regions are part of what only computes; a call
// that does not only allocate is kept to be justified from the record; any
// other op must only allocate, and is not opened again.
bool Identities::Record::scan(Region &region) {
  for (Block &block : region) {
    if (llvm::any_of(block.getArgumentTypes(), owns))
      return false;
    for (BlockArgument arg : block.getArguments())
      intern(arg);
    for (Operation &op : block)
      if (!accept(op))
        return false;
  }
  return true;
}

bool Identities::Record::accept(Operation &op) {
  if (llvm::any_of(op.getResultTypes(), owns))
    return false;
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

} // namespace idr
