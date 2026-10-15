// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The binding times of the parameters of one component.
//
// The classes are found by abstract interpretation: each function of a
// component on a cycle is interpreted over abstract values (a parameter, a
// proper part of one, or anything), and so is every function of the
// component that it reaches, once for each assignment of abstract values to
// its parameters, so the interpretation ends. The calls between the
// component's functions are the only edges: after defunctionalization a
// closure's recursion is a direct call in a dispatch, and a force is a call
// of its memo sum's dispatch function, which calls the label.
#include "idr/Analysis/Specialize.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <set>
#include <utility>

using namespace mlir;

namespace idr {

llvm::StringRef nameOf(BindingTime time) {
  switch (time) {
  case BindingTime::Free:
    return "free";
  case BindingTime::Fixed:
    return "fixed";
  case BindingTime::Decreasing:
    return "decreasing";
  case BindingTime::Bounded:
    return "bounded";
  case BindingTime::Other:
    return "other";
  }
  llvm_unreachable("unknown binding time");
}

namespace {

// The functions of a component, by name.
using Members = llvm::DenseMap<StringAttr, idr::FuncOp>;

// What a value is, in terms of the parameters of the function analyzed.
struct Abstract {
  enum class Kind : uint8_t { Top, Same, Smaller };
  Kind kind = Kind::Top;
  unsigned param = 0;

  static Abstract same(unsigned param) { return {Kind::Same, param}; }

  // One number per abstract value: anything is anything, whatever
  // parameter it was last seen as.
  unsigned code() const {
    return kind == Kind::Top ? 0 : 2 * param + (kind == Kind::Same ? 1 : 2);
  }

  // A proper part of what `of` is.
  static Abstract partOf(Abstract of) {
    return of.kind == Kind::Top ? of : Abstract{Kind::Smaller, of.param};
  }
};

// The classes of the parameters of `main`, a function of the component
// `members` on a cycle.
class Interpreter {
public:
  Interpreter(idr::FuncOp main, const Members &members)
      : main(main), members(members), same(main.getNumArguments(), false),
        smaller(main.getNumArguments(), false), other(main.getNumArguments(), false) {}

  SmallVector<BindingTime> run();

private:
  // A function of the component with abstract arguments, the first time it
  // is reached with them.
  void push(idr::FuncOp fn, ArrayRef<Abstract> args);
  void visit(idr::FuncOp fn, ArrayRef<Abstract> args);
  void refer(idr::FuncOp target, ArrayRef<Abstract> args);

  idr::FuncOp main;
  const Members &members;
  SmallVector<bool> same, smaller, other;
  // Each function of the component with the arguments it was reached with.
  std::set<std::pair<Operation *, SmallVector<unsigned>>> visited;
  SmallVector<std::pair<idr::FuncOp, SmallVector<Abstract>>> work;
};

SmallVector<BindingTime> Interpreter::run() {
  SmallVector<Abstract> identity;
  for (unsigned i = 0; i < main.getNumArguments(); ++i)
    identity.push_back(Abstract::same(i));
  push(main, identity);
  while (!work.empty() && !llvm::all_of(other, [](bool b) { return b; })) {
    auto [fn, args] = work.pop_back_val();
    visit(fn, args);
  }
  SmallVector<BindingTime> out;
  for (unsigned i = 0; i < main.getNumArguments(); ++i) {
    if (other[i] || (!same[i] && !smaller[i]))
      out.push_back(BindingTime::Other);
    else if (same[i] && smaller[i])
      out.push_back(BindingTime::Bounded);
    else
      out.push_back(same[i] ? BindingTime::Fixed : BindingTime::Decreasing);
  }
  return out;
}

void Interpreter::push(idr::FuncOp fn, ArrayRef<Abstract> args) {
  SmallVector<unsigned> codes =
      llvm::map_to_vector(args, [](const Abstract &arg) { return arg.code(); });
  if (visited.emplace(fn.getOperation(), std::move(codes)).second)
    work.emplace_back(fn, SmallVector<Abstract>(args));
}

void Interpreter::visit(idr::FuncOp fn, ArrayRef<Abstract> args) {
  llvm::DenseMap<Value, Abstract> known;
  auto eval = [&](auto &self, Value value) -> Abstract {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Abstract out;
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      Operation *parent = arg.getOwner()->getParentOp();
      if (parent == fn.getOperation() && arg.getOwner()->isEntryBlock()) {
        if (arg.getArgNumber() < args.size())
          out = args[arg.getArgNumber()];
      } else if (auto match = dyn_cast<MatchOp>(parent)) {
        // A case binds the fields of the scrutinee; the default region
        // takes the scrutinee itself back.
        Abstract scrutinee = self(self, match.getScrutinee());
        out = arg.getOwner()->getParent() == match.getDefaultRegion() ? scrutinee
                                                                      : Abstract::partOf(scrutinee);
      }
    } else if (Operation *def = value.getDefiningOp()) {
      if (auto field = dyn_cast<FieldOp>(def))
        out = Abstract::partOf(self(self, field.getValue()));
      else if (auto pred = dyn_cast<BigPredOp>(def))
        out = Abstract::partOf(self(self, pred.getValue()));
      // An integer counted down by a positive step. Unlike a Nat it may
      // pass zero; specialization unrolls only a counter that stays in a
      // small range of naturals, so its specializations stay few either
      // way.
      else if (IntegerAttr step; isa<arith::SubIOp>(def) &&
                                 matchPattern(def->getOperand(1), m_Constant(&step)) &&
                                 step.getValue().isStrictlyPositive())
        out = Abstract::partOf(self(self, def->getOperand(0)));
    }
    known[value] = out;
    return out;
  };
  fn.walk([&](idr::CallOp call) {
    idr::FuncOp target = members.lookup(call.getCalleeAttr().getAttr());
    if (!target)
      return;
    SmallVector<Abstract> passed(target.getNumArguments());
    for (auto [i, operand] : llvm::enumerate(call.getArgs()))
      if (i < passed.size())
        passed[i] = eval(eval, operand);
    refer(target, passed);
  });
}

void Interpreter::refer(idr::FuncOp target, ArrayRef<Abstract> args) {
  if (target == main)
    for (auto [i, arg] : llvm::enumerate(args)) {
      if (arg.kind == Abstract::Kind::Same && arg.param == i)
        same[i] = true;
      else if (arg.kind == Abstract::Kind::Smaller && arg.param == i)
        smaller[i] = true;
      else
        other[i] = true;
    }
  push(target, args);
}

// Whether `fn` calls itself anywhere in its body.
bool callsItself(idr::FuncOp fn) {
  StringAttr name = fn.getSymNameAttr();
  return fn.walk([&](idr::CallOp call) {
             return call.getCalleeAttr().getAttr() == name ? WalkResult::interrupt()
                                                           : WalkResult::advance();
           }).wasInterrupted();
}

} // namespace

SmallVector<SmallVector<BindingTime>> bindingTimesOf(ArrayRef<idr::FuncOp> component) {
  Members members;
  for (idr::FuncOp fn : component)
    members[fn.getSymNameAttr()] = fn;
  bool cycle = component.size() > 1 || llvm::any_of(component, callsItself);
  SmallVector<SmallVector<BindingTime>> out;
  for (idr::FuncOp fn : component) {
    if (!cycle)
      out.emplace_back(fn.getNumArguments(), BindingTime::Free);
    else
      out.push_back(Interpreter(fn, members).run());
  }
  return out;
}

} // namespace idr
