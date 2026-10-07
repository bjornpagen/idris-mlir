// idr.tail:accumulator: a self call whose result a tail position adds
// becomes a tail call that carries the sum.
//
// `length (x :: xs) = S (length xs)` is an addition of the recursive
// result. The addition associates and commutes and its identity is zero,
// so adding on the way down equals adding on the way back: the function
// the program calls seeds a clone with zero, and the clone adds its
// argument before the call, which is then the last thing that tail does.
// idr-tail-loops makes the clone a loop, and the sum is a value of the
// iteration, not a frame. A tail that returns a value adds the sum to it;
// a tail that is already a self call passes the sum on.
//
// A self call in any other position stays a call, and so does one whose
// other operand is itself a self call (`f l + f r`): both results are
// wanted, and the stack grows with them. The addition has to be the tail.
// Counting borrows a call's result and drops it after the addition, so
// this runs first, while the result is still what the tail adds.
export module idr.tail:accumulator;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;

namespace idr {
namespace {

// Whether `value` is the constant natural or integer 0, the identity of
// addition.
bool isZero(Value value) {
  auto constant = value.getDefiningOp<idr::ConstantOp>();
  if (!constant)
    return false;
  auto big = dyn_cast<idr::BigAttr>(constant.getValue());
  return big && big.getValue() == "0";
}

// Whether `value` is computed from a call of `callee`.
bool dependsOnCall(Value value, StringRef callee, DenseSet<Value> &seen) {
  if (!seen.insert(value).second)
    return false;
  Operation *def = value.getDefiningOp();
  if (!def)
    return false;
  if (auto call = dyn_cast<func::CallOp>(def); call && call.getCallee() == callee)
    return true;
  return llvm::any_of(def->getOperands(), [&](Value operand) {
    return dependsOnCall(operand, callee, seen);
  });
}

bool dependsOnCall(Value value, StringRef callee) {
  DenseSet<Value> seen;
  return dependsOnCall(value, callee, seen);
}

// The self call `call` as an accumulator tail of `callee`: the call itself
// is the tail (the sum passes on unchanged), or it is the one operand of
// the addition the tail returns and the other operand does not depend on a
// call of `callee`.
struct Site {
  func::CallOp call;
  idr::BigAddOp add;
  Value addend;
};

std::optional<Site> siteOf(func::CallOp call, StringRef callee) {
  if (call.getCallee() != callee || call.getNumResults() != 1)
    return std::nullopt;
  if (graph::inTailPosition(call))
    return Site{call, idr::BigAddOp(), Value()};
  if (!call->hasOneUse())
    return std::nullopt;
  auto add = dyn_cast<idr::BigAddOp>(*call->user_begin());
  if (!add || !graph::inTailPosition(add) || add->getBlock() != call->getBlock())
    return std::nullopt;
  Value result = call.getResult(0);
  Value addend;
  if (add.getLhs() == result && add.getRhs() != result)
    addend = add.getRhs();
  else if (add.getRhs() == result && add.getLhs() != result)
    addend = add.getLhs();
  else
    return std::nullopt;
  if (dependsOnCall(addend, callee))
    return std::nullopt;
  bool movable = true;
  for (Operation *op = call->getNextNode(); op != add; op = op->getNextNode())
    movable = movable && isMemoryEffectFree(op) && isSpeculatable(op);
  if (!movable)
    return std::nullopt;
  return Site{call, add, addend};
}

// Whether every use of `callee` in `fn` is a call. A reference that is not
// a call would keep calling the function the program calls, which seeds the
// sum at zero.
bool refersOnlyByCall(func::FuncOp fn, StringRef callee) {
  std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody());
  if (!uses)
    return true;
  for (const SymbolTable::SymbolUse &use : *uses) {
    if (use.getSymbolRef().getRootReference() != callee)
      continue;
    if (!isa<func::CallOp>(use.getUser()))
      return false;
  }
  return true;
}

struct Plan {
  SmallVector<Site> sites;
};

// The accumulator tails of `fn`, whose self calls name `callee`, or none
// when a self call is not one or none of them is an addition.
std::optional<Plan> planOf(func::FuncOp fn, StringRef callee) {
  if (fn.isExternal() || fn.getBody().empty() || !fn.getBody().hasOneBlock() || fn.getNumResults() != 1)
    return std::nullopt;
  if (!refersOnlyByCall(fn, callee))
    return std::nullopt;
  Plan plan;
  bool all = true;
  bool anyAdd = false;
  fn.walk([&](func::CallOp call) {
    if (call.getCallee() != callee)
      return;
    if (std::optional<Site> site = siteOf(call, callee)) {
      anyAdd |= static_cast<bool>(site->add);
      plan.sites.push_back(*site);
    } else {
      all = false;
    }
  });
  if (!all || !anyAdd)
    return std::nullopt;
  return plan;
}

// The blocks in tail position of `block`: itself, or through the match in
// tail position, the blocks of its regions.
void forTails(Block &block, function_ref<void(Block &)> f) {
  Operation *terminator = block.getTerminator();
  Operation *prev = terminator->getPrevNode();
  if (graph::passesOnPrevious(terminator) && isa_and_nonnull<idr::MatchOp, idr::MatchLitOp>(prev)) {
    for (Region &region : prev->getRegions())
      if (!region.empty())
        forTails(region.front(), f);
    return;
  }
  f(block);
}

func::CallOp retarget(OpBuilder &b, func::CallOp call, func::FuncOp clone, Value carried) {
  SmallVector<Value> operands(call.getOperands());
  operands.push_back(carried);
  auto neu = func::CallOp::create(b, call.getLoc(), clone, operands);
  neu->setDiscardableAttrs(call->getDiscardableAttrDictionary());
  call.replaceAllUsesWith(neu.getResults());
  call.erase();
  return neu;
}

// The clone's tails: an addition becomes the sum carried into the call,
// which takes the addition's place at the tail, and a tail that returns a
// value adds the sum to it. Zero, the identity, is the sum itself.
void rewriteClone(OpBuilder &b, func::FuncOp clone, StringRef callee, Value acc) {
  Plan plan = *planOf(clone, callee);
  for (Site site : plan.sites) {
    if (site.add) {
      b.setInsertionPoint(site.add);
      auto sum = idr::BigAddOp::create(b, site.add.getLoc(), site.add.getResult().getType(), acc, site.addend);
      b.setInsertionPointAfter(sum);
      SmallVector<Value> operands(site.call.getOperands());
      operands.push_back(sum.getResult());
      auto neu = func::CallOp::create(b, site.call.getLoc(), clone, operands);
      neu->setDiscardableAttrs(site.call->getDiscardableAttrDictionary());
      site.add.getResult().replaceAllUsesWith(neu.getResult(0));
      site.add.erase();
      site.call.erase();
      continue;
    }
    b.setInsertionPoint(site.call);
    retarget(b, site.call, clone, acc);
  }
  forTails(clone.getBody().front(), [&](Block &block) {
    Operation *terminator = block.getTerminator();
    if (!isa<func::ReturnOp, idr::YieldOp>(terminator) || terminator->getNumOperands() != 1)
      return;
    Value value = terminator->getOperand(0);
    if (auto call = value.getDefiningOp<func::CallOp>(); call && call.getCallee() == clone.getSymName())
      return;
    if (isZero(value)) {
      terminator->setOperand(0, acc);
      if (Operation *def = value.getDefiningOp(); def && def->use_empty())
        def->erase();
      return;
    }
    b.setInsertionPoint(terminator);
    auto sum = idr::BigAddOp::create(b, terminator->getLoc(), acc.getType(), acc, value);
    terminator->setOperand(0, sum.getResult());
  });
}

} // namespace

namespace tail {

// What `accumulate` rewrote: the functions, and the additions that became
// the carried sum.
export struct Accumulated {
  uint64_t functions = 0;
  uint64_t tails = 0;
};

// Rewrites every tail that adds its own result in `module` to carry the
// sum into a clone.
export Accumulated accumulate(ModuleOp module) {
  Accumulated accumulated;
  MLIRContext *ctx = module.getContext();
  SymbolTable symbols(module);
  OpBuilder b(ctx);
  for (auto fn : llvm::make_early_inc_range(module.getOps<func::FuncOp>())) {
    StringRef callee = fn.getSymName();
    std::optional<Plan> plan = planOf(fn, callee);
    if (!plan)
      continue;
    Type result = fn.getResultTypes()[0];
    b.setInsertionPointAfter(fn);
    auto clone = cast<func::FuncOp>(b.clone(*fn));
    clone.setSymName((callee + "$acc").str());
    clone.setPrivate();
    clone->removeAttr("idr.clone");
    (void)clone.insertArgument(clone.getNumArguments(), result, DictionaryAttr(), fn.getLoc());
    clone.setFunctionType(FunctionType::get(ctx, clone.getArgumentTypes(), fn.getResultTypes()));
    symbols.insert(clone);
    rewriteClone(b, clone, callee, clone.getArgument(clone.getNumArguments() - 1));

    uint64_t tails = 0;
    for (Site site : plan->sites)
      if (site.add)
        ++tails;

    // The old body computed the sum on the way back. Drop it after the
    // clone exists: its values still name each other until their uses go.
    Block &entry = fn.getBody().front();
    entry.dropAllDefinedValueUses();
    while (!entry.empty())
      entry.front().erase();
    b.setInsertionPointToStart(&entry);
    Value zero = idr::ConstantOp::create(b, fn.getLoc(), result, idr::BigAttr::get(ctx, "0"));
    SmallVector<Value> args(entry.getArguments());
    args.push_back(zero);
    auto call = func::CallOp::create(b, fn.getLoc(), clone, args);
    func::ReturnOp::create(b, fn.getLoc(), call.getResults());

    ++accumulated.functions;
    accumulated.tails += tails;
  }
  return accumulated;
}

} // namespace tail
} // namespace idr
