// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The binding times of the parameters of one component.
//
// The classes are found by abstract interpretation: each function of a
// component on a cycle is interpreted over abstract values (a parameter, a
// proper part of one, or anything), and so is every function of the
// component that it reaches, once for each assignment of abstract values to
// its parameters: an insert-once worklist over finitely many assignments. The calls between the
// component's functions are the only edges: after defunctionalization a
// closure's recursion is a direct call in a dispatch, and a force is a call
// of its memo sum's dispatch function, which calls the label.
#include "idr/Analysis/Specialize.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/STLForwardCompat.h"
#include "llvm/Support/ErrorHandling.h"

#include <map>
#include <optional>
#include <utility>
#include <variant>

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

// What a value is, in terms of the parameters of the function analyzed:
// one of them, a proper part of one, or anything.
struct Same {
  unsigned param;
};
struct Smaller {
  unsigned param;
};
struct Anything {};
using Abstract = std::variant<Anything, Same, Smaller>;

// A proper part of what `of` is.
Abstract partOf(Abstract of) {
  return std::visit(llvm::makeVisitor([](Anything) -> Abstract { return Anything{}; },
                                      [](Same same) -> Abstract { return Smaller{same.param}; },
                                      [](Smaller smaller) -> Abstract { return smaller; }),
                    of);
}

// One number per abstract value, two equal values one number.
unsigned code(Abstract value) {
  return std::visit(llvm::makeVisitor([](Anything) { return 0u; },
                                      [](Same same) { return 2 * same.param + 1; },
                                      [](Smaller smaller) { return 2 * smaller.param + 2; }),
                    value);
}

// What the calls within the component pass at one parameter, joined with
// what one more call passes there: itself is fixed, a proper part of it
// decreasing, both bounded, and anything else other.
BindingTime join(std::optional<BindingTime> seen, BindingTime passed) {
  if (!seen || *seen == passed)
    return passed;
  if (*seen == BindingTime::Other || passed == BindingTime::Other)
    return BindingTime::Other;
  return BindingTime::Bounded;
}

// A tuple of abstract arguments, by its number among the tuples met.
enum class Tuple : unsigned {};
// A function of the component reached with a tuple of abstract arguments.
using Reach = std::pair<Operation *, Tuple>;

// The classes of the parameters of `main`, a function of the component
// `members` on a cycle.
class Interpreter {
public:
  Interpreter(idr::FuncOp main, const Members &members)
      : main(main), members(members), seen(main.getNumArguments()) {}

  SmallVector<BindingTime> run();

private:
  // A function of the component with abstract arguments, the first time it
  // is reached with them.
  void push(idr::FuncOp fn, ArrayRef<Abstract> args);
  void visit(idr::FuncOp fn, ArrayRef<Abstract> args);
  void refer(idr::FuncOp target, ArrayRef<Abstract> args);

  idr::FuncOp main;
  const Members &members;
  // What the calls of `main` read so far pass at each of its parameters;
  // nothing where none passes it.
  SmallVector<std::optional<BindingTime>> seen;
  // The tuples met, numbered as met, found by their codes.
  std::map<SmallVector<unsigned>, Tuple> numbers;
  SmallVector<SmallVector<Abstract>> tuples;
  // Each function of the component with each tuple it is reached with,
  // once: finitely many, as a tuple holds one of finitely many abstract
  // values per parameter.
  OnceWorklist<Reach> work;
};

SmallVector<BindingTime> Interpreter::run() {
  SmallVector<Abstract> identity;
  for (unsigned i = 0; i < main.getNumArguments(); ++i)
    identity.push_back(Same{i});
  push(main, identity);
  while (std::optional<Reach> reach = work.pop()) {
    // Once every parameter is other, nothing read later changes the answer.
    if (llvm::all_of(seen, [](std::optional<BindingTime> time) {
          return time == BindingTime::Other;
        }))
      break;
    // A copy: a push while the body is read may grow the tuples.
    SmallVector<Abstract> args = tuples[llvm::to_underlying(reach->second)];
    visit(cast<idr::FuncOp>(reach->first), args);
  }
  // A parameter no call passes varies as anything may.
  return llvm::map_to_vector(seen, [](std::optional<BindingTime> time) {
    return time.value_or(BindingTime::Other);
  });
}

void Interpreter::push(idr::FuncOp fn, ArrayRef<Abstract> args) {
  SmallVector<unsigned> codes = llvm::map_to_vector(args, code);
  auto [it, made] =
      numbers.try_emplace(std::move(codes), Tuple(static_cast<unsigned>(tuples.size())));
  if (made)
    tuples.emplace_back(args);
  work.push({fn.getOperation(), it->second});
}

void Interpreter::visit(idr::FuncOp fn, ArrayRef<Abstract> args) {
  llvm::DenseMap<Value, Abstract> known;
  auto eval = [&](auto &self, Value value) -> Abstract {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Abstract out = Anything{};
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      Operation *parent = arg.getOwner()->getParentOp();
      // `args` came from a call of `fn` between the component's functions,
      // one per operand, and the component's bodies are ones the verifier
      // checked, whose calls pass one argument per parameter: a pass's
      // input, which idr-optimize reads before a member's turns begin.
      if (parent == fn.getOperation() && arg.getOwner()->isEntryBlock()) {
        out = args[arg.getArgNumber()];
      } else if (auto match = dyn_cast<MatchOp>(parent)) {
        // A case binds the fields of the scrutinee; the default region
        // takes the scrutinee itself back.
        Abstract scrutinee = self(self, match.getScrutinee());
        out = arg.getOwner()->getParent() == match.getDefaultRegion() ? scrutinee
                                                                      : partOf(scrutinee);
      }
    } else if (Operation *def = value.getDefiningOp()) {
      if (auto field = dyn_cast<FieldOp>(def))
        out = partOf(self(self, field.getValue()));
      else if (auto pred = dyn_cast<BigPredOp>(def))
        out = partOf(self(self, pred.getValue()));
      // An integer counted down by a positive step. Unlike a Nat it may
      // pass zero; specialization unrolls only a counter that stays in a
      // small range of naturals, so its specializations stay few either
      // way.
      else if (IntegerAttr step; isa<arith::SubIOp>(def) &&
                                 matchPattern(def->getOperand(1), m_Constant(&step)) &&
                                 step.getValue().isStrictlyPositive())
        out = partOf(self(self, def->getOperand(0)));
    }
    known[value] = out;
    return out;
  };
  fn.walk([&](idr::CallOp call) {
    idr::FuncOp target = members.lookup(call.getCalleeAttr().getAttr());
    if (!target)
      return;
    refer(target, llvm::map_to_vector(call.getArgs(),
                                      [&](Value operand) { return eval(eval, operand); }));
  });
}

void Interpreter::refer(idr::FuncOp target, ArrayRef<Abstract> args) {
  if (target == main)
    for (auto [i, arg] : llvm::enumerate(args)) {
      auto at = static_cast<unsigned>(i);
      BindingTime passed = std::visit(
          llvm::makeVisitor([](Anything) { return BindingTime::Other; },
                            [&](Same s) {
                              return s.param == at ? BindingTime::Fixed : BindingTime::Other;
                            },
                            [&](Smaller s) {
                              return s.param == at ? BindingTime::Decreasing : BindingTime::Other;
                            }),
          arg);
      seen[i] = join(seen[i], passed);
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
