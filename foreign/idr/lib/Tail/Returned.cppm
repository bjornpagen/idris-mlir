// idr.tail:returned: a result that a function always returns as one of its
// arguments is dropped, and its callers use the argument instead.
//
// A value threaded through a function and given back (a linear array
// through every read and write of it, the state of a recursion or of a
// loop) is, once lowered, the argument itself on every path: through the
// join of an scf.if or scf.index_switch, through a loop whose every
// iteration yields it unchanged (what idr-tail-loops makes of a tail
// recursion, with poison where an exit value has none yet), and through
// the recursive calls, whose result is the argument they pass by the
// hypothesis the analysis refines to a fixpoint from the optimistic start.
// The result is then no information: the caller holds that value already,
// live across the call. Dropping it shrinks every such function's result,
// which the target returns through memory once it has more components than
// registers.
//
// Only a private function every use of which is a direct call changes its
// signature. A result that is an argument on some paths only stays, and so
// does one returned only by calls that never return (unconstrained at the
// fixpoint).
export module idr.tail:returned;

import idr.mlir;
import idr.graph;

using namespace mlir;

namespace {

// What a result is known to be: unconstrained yet (what every result starts
// as), the argument at an index, or no one argument.
struct Returned {
  enum Kind : uint8_t { Unconstrained, Argument, None };
  Kind kind = Unconstrained;
  unsigned argument = 0;

  static Returned arg(unsigned index) { return {Argument, index}; }
  static Returned none() { return {None, 0}; }
  bool operator==(const Returned &) const = default;

  // What two paths agree on.
  Returned meet(Returned other) const {
    if (kind == Unconstrained)
      return other;
    if (other.kind == Unconstrained || *this == other)
      return *this;
    return none();
  }
};

class ReturnedArguments {
public:
  explicit ReturnedArguments(ModuleOp module) : module(module) {
    idr::graph::SymbolUses uses(module);
    for (auto fn : module.getOps<func::FuncOp>())
      if (eligible(fn, uses)) {
        functions.push_back(fn);
        results[fn].assign(fn.getNumResults(), Returned());
      }
  }

  // Refines every function's results until nothing changes: the greatest
  // fixpoint, which the order of visiting does not affect.
  void analyze() {
    bool changed = true;
    while (changed) {
      changed = false;
      for (func::FuncOp fn : functions) {
        SmallVector<Returned> now(fn.getNumResults(), Returned());
        fn.walk([&](func::ReturnOp ret) {
          for (auto [i, operand] : llvm::enumerate(ret.getOperands()))
            now[i] = now[i].meet(argumentOf(fn, operand));
        });
        SmallVector<Returned> &known = results[fn];
        if (now != known) {
          known = std::move(now);
          changed = true;
        }
      }
    }
  }

  // Drops every result known to be an argument; returns how many.
  unsigned rewrite() {
    unsigned dropped = 0;
    for (func::FuncOp fn : functions) {
      ArrayRef<Returned> known = results[fn];
      SmallVector<unsigned> kept;
      for (auto [i, result] : llvm::enumerate(known))
        if (result.kind != Returned::Argument)
          kept.push_back(static_cast<unsigned>(i));
      if (kept.size() == known.size())
        continue;
      dropped += static_cast<unsigned>(known.size() - kept.size());
      SmallVector<Type> types;
      for (unsigned i : kept)
        types.push_back(fn.getResultTypes()[i]);
      for (func::CallOp call : calls[fn]) {
        OpBuilder b(call);
        auto fresh = func::CallOp::create(b, call.getLoc(), call.getCalleeAttr(), types,
                                          call.getOperands());
        fresh->setDiscardableAttrs(call->getDiscardableAttrDictionary());
        unsigned next = 0;
        for (auto [i, result] : llvm::enumerate(known))
          call.getResult(static_cast<unsigned>(i))
              .replaceAllUsesWith(result.kind == Returned::Argument
                                      ? call.getOperand(result.argument)
                                      : fresh.getResult(next++));
        call.erase();
      }
      fn.walk([&](func::ReturnOp ret) {
        SmallVector<Value> operands;
        for (unsigned i : kept)
          operands.push_back(ret.getOperand(i));
        ret->setOperands(operands);
      });
      if (ArrayAttr attrs = fn.getResAttrsAttr()) {
        SmallVector<Attribute> keptAttrs;
        for (unsigned i : kept)
          keptAttrs.push_back(attrs[i]);
        fn.setResAttrsAttr(ArrayAttr::get(fn.getContext(), keptAttrs));
      }
      fn.setType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), types));
    }
    return dropped;
  }

private:
  // Whether every use of `fn` is a direct call, so that its signature is the
  // pass's to change; the calls are kept.
  bool eligible(func::FuncOp fn, const idr::graph::SymbolUses &symbolUses) {
    if (fn.isExternal() || fn.isPublic() || fn.getNumResults() == 0)
      return false;
    std::optional<ArrayRef<SymbolTable::SymbolUse>> uses = symbolUses.of(fn);
    if (!uses)
      return false;
    SmallVector<func::CallOp> &direct = calls[fn];
    for (const SymbolTable::SymbolUse &use : *uses) {
      auto call = dyn_cast<func::CallOp>(use.getUser());
      if (!call)
        return false;
      direct.push_back(call);
    }
    return true;
  }

  // Which argument of `fn` `value` is, under what is known of the callees
  // and under `assumed`, the hypotheses on the loop arguments being
  // resolved: a loop argument is the function's argument when its initial
  // value is and what the loop yields for it is too, by that hypothesis.
  // A ub.poison is a value of the program, given where nothing reads it (on
  // the path of a loop that does not take it, after a crash): it may be
  // taken to be anything, so it agrees with anything.
  Returned argumentOf(func::FuncOp fn, Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value))
      return argumentOf(fn, arg);
    auto result = cast<OpResult>(value);
    Operation *op = result.getOwner();
    unsigned index = result.getResultNumber();
    if (isa<ub::PoisonOp>(op))
      return Returned();
    if (isa<scf::IfOp, scf::IndexSwitchOp>(op)) {
      Returned joined;
      for (Region &region : op->getRegions()) {
        if (region.empty())
          return Returned::none();
        joined = joined.meet(argumentOf(fn, region.front().getTerminator()->getOperand(index)));
      }
      return joined;
    }
    if (auto select = dyn_cast<arith::SelectOp>(op))
      return argumentOf(fn, select.getTrueValue()).meet(argumentOf(fn, select.getFalseValue()));
    if (auto loop = dyn_cast<scf::WhileOp>(op))
      return argumentOf(fn, loop.getConditionOp().getArgs()[index]);
    if (auto loop = dyn_cast<scf::ForOp>(op))
      return argumentOf(fn, loop.getRegionIterArgs()[index]);
    if (auto call = dyn_cast<func::CallOp>(op)) {
      auto callee = symbols.lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
      auto it = results.find(callee);
      if (it == results.end())
        return Returned::none();
      Returned known = it->second[index];
      if (known.kind == Returned::Argument)
        return argumentOf(fn, call.getOperand(known.argument));
      return known;
    }
    return Returned::none();
  }

  Returned argumentOf(func::FuncOp fn, BlockArgument arg) {
    Block *block = arg.getOwner();
    if (block == &fn.getBody().front())
      return Returned::arg(arg.getArgNumber());
    if (auto it = assumed.find(arg); it != assumed.end())
      return it->second;
    unsigned index = arg.getArgNumber();
    if (auto loop = dyn_cast<scf::WhileOp>(block->getParentOp())) {
      if (block == loop.getAfterBody())
        return argumentOf(fn, loop.getConditionOp().getArgs()[index]);
      return carried(fn, arg, loop.getInits()[index], loop.getYieldOp().getOperand(index));
    }
    if (auto loop = dyn_cast<scf::ForOp>(block->getParentOp())) {
      if (index == 0)
        return Returned::none();
      return carried(fn, arg, loop.getInitArgs()[index - 1],
                     loop.getBody()->getTerminator()->getOperand(index - 1));
    }
    return Returned::none();
  }

  // A loop argument: its initial value, which what the loop yields for it
  // must agree with, under the hypothesis that the argument is that value.
  Returned carried(func::FuncOp fn, BlockArgument arg, Value init, Value yielded) {
    Returned initial = argumentOf(fn, init);
    if (initial.kind != Returned::Argument)
      return initial;
    assumed[arg] = initial;
    Returned joined = initial.meet(argumentOf(fn, yielded));
    assumed.erase(arg);
    return joined;
  }

  ModuleOp module;
  SymbolTableCollection symbols;
  DenseMap<Value, Returned> assumed;
  SmallVector<func::FuncOp> functions;
  DenseMap<Operation *, SmallVector<Returned>> results;
  DenseMap<Operation *, SmallVector<func::CallOp>> calls;
};

} // namespace

namespace idr::tail {

// Drops every result of a function of `module` that it always returns as
// one of its arguments; returns how many.
export unsigned dropReturnedArguments(ModuleOp module) {
  ReturnedArguments returned(module);
  returned.analyze();
  return returned.rewrite();
}

} // namespace idr::tail
