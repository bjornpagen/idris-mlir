// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The binding times of the parameters of one function of a component.
//
// They are found by abstract interpretation: the function is interpreted
// over abstract values (one of its parameters, unchanged, or anything), and
// so is every function of the component that it reaches, once for each
// assignment of abstract values to its parameters: an insert-once worklist
// over finitely many assignments. The calls between the component's
// functions are the only edges: after defunctionalization a closure's
// recursion is a direct call in a dispatch, and a force is a call of its
// memo sum's dispatch function, which calls the label.
#include "idr/Analysis/BindingTimes.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <algorithm>
#include <map>
#include <utility>
#include <variant>

using namespace mlir;

namespace idr {

llvm::StringRef nameOf(BindingTime time) {
  switch (time) {
  case BindingTime::Fixed:
    return "fixed";
  case BindingTime::Varies:
    return "varies";
  }
  llvm_unreachable("unknown binding time");
}

namespace {

// The functions of a component, by name.
using Members = llvm::DenseMap<StringAttr, idr::FuncOp>;

// What a value is, in terms of the parameters of the function analyzed:
// one of them, unchanged, or anything.
namespace abstract {
struct Anything {};
struct Same {
  unsigned param;
};
} // namespace abstract
using Abstract = std::variant<abstract::Anything, abstract::Same>;

// One number per abstract value, two equal values one number.
unsigned code(Abstract value) {
  return std::visit(llvm::makeVisitor([](abstract::Anything) { return 0u; },
                                      [](abstract::Same same) { return same.param + 1; }),
                    value);
}

// What `value` is in `fn`, whose parameters are `args`: an argument of its
// body is its parameter's; what idr::sourceOf finds the same value is what
// that value is; anything else is anything.
Abstract eval(Value value, idr::FuncOp fn, ArrayRef<Abstract> args) {
  // `args` came from a call of `fn` between the component's functions, one
  // per operand, and the component's bodies are ones the verifier checked,
  // whose calls pass one argument per parameter: a pass's input, which
  // idr-optimize reads before a member's turns begin.
  if (auto arg = dyn_cast<BlockArgument>(value); arg && arg.getParentRegion() == &fn.getBody())
    return args[arg.getArgNumber()];
  return std::visit(
      llvm::makeVisitor([&](idr::Same same) { return eval(same.value, fn, args); },
                        [](idr::Made) -> Abstract { return abstract::Anything{}; },
                        [](const idr::Field &) -> Abstract { return abstract::Anything{}; }),
      sourceOf(value));
}

// A tuple of abstract arguments, by its number among the tuples met.
enum class Tuple : unsigned {};
// A function of the component reached with a tuple of abstract arguments.
using Reach = std::pair<Operation *, Tuple>;

// The binding times of the parameters of `main`, a function of the
// component `members`.
class Interpreter {
public:
  Interpreter(idr::FuncOp main, const Members &members)
      : main(main), members(members), seen(main.getNumArguments(), BindingTime::Fixed) {}

  SmallVector<BindingTime> run();

private:
  // A function of the component with abstract arguments, the first time it
  // is reached with them.
  void push(idr::FuncOp fn, ArrayRef<Abstract> args);
  void visit(idr::FuncOp fn, ArrayRef<Abstract> args);
  void refer(idr::FuncOp target, ArrayRef<Abstract> args);

  idr::FuncOp main;
  const Members &members;
  // The join of what the calls of `main` read so far pass at each of its
  // parameters.
  SmallVector<BindingTime> seen;
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
    identity.push_back(abstract::Same{i});
  push(main, identity);
  while (auto reach = work.pop()) {
    // Once every parameter varies, nothing read later changes the answer.
    if (llvm::all_of(seen, [](BindingTime time) { return time == BindingTime::Varies; }))
      break;
    // A copy: a push while the body is read may grow the tuples.
    SmallVector<Abstract> args = tuples[llvm::to_underlying(reach->second)];
    visit(cast<idr::FuncOp>(reach->first), args);
  }
  return seen;
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
  fn.walk([&](idr::CallOp call) {
    idr::FuncOp target = members.lookup(call.getCalleeAttr().getAttr());
    if (!target)
      return;
    refer(target, llvm::map_to_vector(call.getArgs(),
                                      [&](Value operand) { return eval(operand, fn, args); }));
  });
}

// A call of `main` passes each parameter on unchanged in its own position,
// or makes it vary.
void Interpreter::refer(idr::FuncOp target, ArrayRef<Abstract> args) {
  if (target == main)
    for (auto [i, arg] : llvm::enumerate(args)) {
      auto at = static_cast<unsigned>(i);
      BindingTime passed = std::visit(
          llvm::makeVisitor([](abstract::Anything) { return BindingTime::Varies; },
                            [&](abstract::Same same) {
                              return same.param == at ? BindingTime::Fixed : BindingTime::Varies;
                            }),
          arg);
      seen[i] = std::max(seen[i], passed);
    }
  push(target, args);
}

} // namespace

SmallVector<BindingTime> bindingTimesOf(idr::FuncOp fn, ArrayRef<idr::FuncOp> component) {
  Members members;
  for (idr::FuncOp member : component)
    members[member.getSymNameAttr()] = member;
  return Interpreter(fn, members).run();
}

} // namespace idr
