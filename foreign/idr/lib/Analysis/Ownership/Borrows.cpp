// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: a parameter the function never needs a reference of
// its own for is borrowed, and its callers keep the reference, which saves
// an idr.dup and an idr.drop per call.
//
// Every parameter starts borrowed and becomes owned when it or a field read
// from it
//   - is taken apart (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor;
//   - is returned, or forwarded on (a match's yield, the value a loop
//     carries round), which owns what it holds;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call. A self call
// whose result a tail position puts in a constructor counts as one:
// idr-trmc makes it a tail call that writes the field, unless a drop sits
// between the call and the constructor. An element read from a buffer
// takes a reference of its own where it is read: it is owned, and owning
// it asks nothing of the buffer.
// The program's root keeps its parameters owned: its caller is not a call
// this analysis sees. A parameter of quantity 1 is owned too: Idris proved
// the function uses it once, so it moves to that use and is never counted.
// A memo cell is never owned: a force writes it while its caller still
// reads it, so the dispatch that forces it reads a view.
//
// What a function's parameters need depends on its own body, on its
// callees' parameters, and through a tail call on what the functions of
// its cycle pass it. Each function is walked once. What a walk cannot
// decide yet it records against the fact it waits on: a call's argument
// needs a reference of its own once its callee's parameter is owned, and a
// tail call within a cycle of calls owns its callee's parameter once the
// value it passes holds a reference of its own, which a parameter comes to
// when it becomes owned, and a field read from one when it needs a
// reference of its own. Each such fact becomes true once, and then what
// waits on it is done, so the work is what changed; the facts are finite,
// so the propagation ends. The least set of owned parameters the rules
// close over does not depend on the order.
//
// The takes of reset/reuse are its decisions, not ops yet: each one owns
// its box where the take will go.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Worklist.h"

#include "mlir/Analysis/CallGraph.h"
#include "llvm/ADT/DenseMapInfoVariant.h"
#include "llvm/ADT/SCCIterator.h"

#include <variant>

using namespace mlir;
using idr::ownership::readFrom;
using idr::ownership::tracked;

namespace idr {

namespace {

// What inference holds of a parameter: owned whatever the function does
// with it (the root's, which its caller outside passes owned; one that
// holds no references; one of quantity 1, which moves to its one use), a
// view whatever it does (a memo cell's), or borrowed until a use needs a
// reference of its own, and then owned.
enum class Holding : uint8_t { Fixed, View, Borrowed, Owned };

// A parameter of a function, by position.
using ParamOf = std::pair<FuncOp, unsigned>;

// What becomes true once: a parameter is owned, or a field read from a
// value needs a reference of its own.
using Fact = std::variant<ParamOf, Value>;

// What waits on a fact: a value that then needs a reference of its own, or
// a parameter then owned.
struct Own {
  Value value;
};
using Action = std::variant<Own, ParamOf>;

class Inference {
public:
  Inference(ProgramOp program, const SymbolTable &symbols, const Reuses &reuses)
      : program(program), symbols(symbols) {
    for (FuncOp fn : program.getOps<FuncOp>())
      for (const Reuses::Site &site : reuses.sites(fn))
        if (const Value *box = std::get_if<Value>(&site.box))
          taken[site.point].push_back(*box);
  }

  void run(DenseMap<FuncOp, SmallVector<Borrows::Param>> &paramsOf, unsigned &borrowed) {
    FuncOp root = program.lookupRoot();
    SmallVector<FuncOp> functions(program.getOps<FuncOp>());
    for (FuncOp fn : functions) {
      SmallVector<Holding> params;
      for (Type type : fn.getArgumentTypes())
        params.push_back(start(fn == root, type));
      holding[fn] = std::move(params);
    }
    // Each function's cycle of calls, named by its first function.
    const CallGraph graph(program);
    for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc) {
      std::optional<FuncOp> first;
      for (const CallGraphNode *node : *scc)
        if (!node->isExternal()) {
          FuncOp fn = functionOf(node);
          first = first.value_or(fn);
          cycleOf[fn] = *first;
        }
    }
    for (FuncOp fn : functions)
      for (Block &block : fn.getBody())
        visit(fn, block);
    while (std::optional<Fact> fact = became.pop())
      if (auto it = waiting.find(*fact); it != waiting.end())
        for (const Action &action : it->second)
          perform(action);
    for (FuncOp fn : functions) {
      SmallVector<Borrows::Param> &params = paramsOf[fn];
      for (auto [type, held] : llvm::zip_equal(fn.getArgumentTypes(), holdingOf(fn))) {
        Borrows::Param param = paramOf(type, held);
        params.push_back(param);
        borrowed += param == Borrows::Param::Borrowed ? 1 : 0;
      }
    }
  }

private:
  static Holding start(bool isRoot, Type type) {
    if (isRoot)
      return Holding::Fixed;
    if (ownership::isMemoCell(type))
      return Holding::View;
    if (!holdsReferences(type) || quantityOf(type) == Quantity::One)
      return Holding::Fixed;
    return Holding::Borrowed;
  }

  static Borrows::Param paramOf(Type type, Holding held) {
    if (!holdsReferences(type))
      return Borrows::Param::Untracked;
    switch (held) {
    case Holding::Fixed:
    case Holding::Owned:
      return Borrows::Param::Owned;
    case Holding::View:
    case Holding::Borrowed:
      return Borrows::Param::Borrowed;
    }
    llvm_unreachable("a holding");
  }

  static FuncOp functionOf(const CallGraphNode *node) {
    return cast<FuncOp>(node->getCallableRegion()->getParentOp());
  }

  // The parameter `value` is, if it is one: an argument of its function's
  // entry block, which has one argument for each parameter.
  static std::optional<ParamOf> parameter(Value value) {
    auto arg = dyn_cast<BlockArgument>(value);
    if (!arg || !arg.getOwner()->isEntryBlock())
      return std::nullopt;
    auto fn = dyn_cast<FuncOp>(arg.getOwner()->getParentOp());
    if (!fn)
      return std::nullopt;
    return ParamOf{fn, arg.getArgNumber()};
  }

  // Every function of the program is entered before any is walked, and a
  // call's callee is one of them, with a parameter for each argument, as
  // the call's verifier holds.
  MutableArrayRef<Holding> holdingOf(FuncOp fn) { return holding.find(fn)->second; }

  void perform(const Action &action) {
    std::visit([&](const auto &what) { performOne(what); }, action);
  }
  void performOne(const Own &what) { own(what.value); }
  void performOne(const ParamOf &param) { ownParam(param); }

  // A borrowed parameter becomes owned, once.
  void ownParam(ParamOf param) {
    Holding &held = holdingOf(param.first)[param.second];
    if (held != Holding::Borrowed)
      return;
    held = Holding::Owned;
    (void)became.push(param);
  }

  // `value` needs a reference of its own. An element has one already; a
  // field takes one, and so does what it was read from. Each step is to the
  // value read from, defined before it.
  void own(Value value) {
    if (!tracked(value) || ownership::isCountedElement(value))
      return;
    if (std::optional<ParamOf> param = parameter(value))
      return ownParam(*param);
    Value from = readFrom(value);
    if (!from || !ownedFields.insert(value).second)
      return;
    (void)became.push(value);
    own(from);
  }

  // Does `action` once `param` is owned: now when it is, never for a view.
  void whenOwned(ParamOf param, Action action) {
    switch (holdingOf(param.first)[param.second]) {
    case Holding::Fixed:
    case Holding::Owned:
      return perform(action);
    case Holding::Borrowed:
      waiting[param].push_back(action);
      return;
    case Holding::View:
      return;
    }
  }

  // Does `action` once `value` holds a reference of its own: now when it
  // does (an element, or a value no read gives), never when it holds no
  // reference, and once the parameter it is, or a field on its way up to
  // one, comes to. The way up is the chain of what each was read from.
  void whenHolds(Value value, Action action) {
    for (Value at : definitionChain(value, readThrough)) {
      if (!tracked(at))
        return;
      if (std::optional<ParamOf> param = parameter(at))
        return whenOwned(*param, action);
      if (ownership::isCountedElement(at) || !readFrom(at) || ownedFields.contains(at))
        return perform(action);
      waiting[at].push_back(action);
    }
  }

  // What `value` was read from, when it was read.
  static std::optional<Value> readThrough(Value value) {
    if (Value from = readFrom(value))
      return from;
    return std::nullopt;
  }

  // The ops of `block` of `fn` as a post-order walk meets them, with each
  // take where it will go.
  void visit(FuncOp fn, Block &block) {
    for (Value box : taken.lookup(ownership::BlockStart{&block}))
      own(box);
    for (Operation &op : block) {
      for (Region &region : op.getRegions())
        for (Block &inner : region)
          visit(fn, inner);
      collectOp(fn, &op);
      for (Value box : taken.lookup(ownership::After{&op}))
        own(box);
    }
  }

  void collectOp(FuncOp fn, Operation *op) {
    if (auto call = dyn_cast<CallOp>(op)) {
      auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
      bool tail = cycleOf.lookup(callee) == cycleOf.lookup(fn) &&
                  (tail::inTailPosition(call) || tail::inTailPositionModuloConstructor(call));
      for (auto [index, arg] : llvm::enumerate(call.getArgOperands())) {
        ParamOf param{callee, static_cast<unsigned>(index)};
        whenOwned(param, Own{arg});
        if (tail)
          whenHolds(arg, param);
      }
      return;
    }
    if (isa<ConOp>(op)) {
      for (Value operand : op->getOperands())
        if (parameter(operand))
          own(operand);
      return;
    }
    // Borrowed, a returned or forwarded parameter would need a reference
    // of its own to move on with, and the caller's value would be shared
    // from then on.
    if (isa<ReturnOp>(op))
      for (Value operand : op->getOperands())
        own(operand);
    forwardedValues(op, [&](OpOperand &operand, Value) { own(operand.get()); });
  }

  ProgramOp program;
  const SymbolTable &symbols;
  // The boxes the takes own, by where each take will go.
  DenseMap<ownership::Point, SmallVector<Value>> taken;
  DenseMap<FuncOp, SmallVector<Holding>> holding;
  DenseMap<FuncOp, FuncOp> cycleOf;
  // The fields that need a reference of its own.
  DenseSet<Value> ownedFields;
  // The facts that became true, each once, and what waits on each.
  OnceWorklist<Fact> became;
  DenseMap<Fact, SmallVector<Action>> waiting;
};

} // namespace

Borrows::Borrows(ProgramOp program, const SymbolTable &symbols, const Reuses &reuses) {
  Inference(program, symbols, reuses).run(paramsOf, numBorrowed);
}

} // namespace idr
