// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// upstream/79-operation-equivalence-symbol-hook, checked on the pinned
// MLIR: OperationEquivalence compares and hashes operations with every
// symbol reference mapped through the caller's hook, in their attributes
// and in the types of their results and operands. With @b in @a's class,
// two operations that differ only in naming @a or @b, in an attribute or
// inside a result's or an operand's type, are equivalent and hash alike;
// without the hook they are not equivalent, and neither is one naming @c,
// of a class of its own. Prints `ok` when every check holds, and a line
// for each that does not.
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/OperationSupport.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace {

// What each check gave against what it should, a line for each that
// differs.
struct Tally {
  unsigned wrong = 0;
  void expect(const char *check, bool got, bool want) {
    if (got == want)
      return;
    llvm::outs() << check << ": " << (got ? "holds" : "does not hold") << "\n";
    ++wrong;
  }
};

} // namespace

int main() {
  MLIRContext context;
  context.allowUnregisteredDialects();
  Builder builder(&context);
  Location loc = builder.getUnknownLoc();
  auto symbol = [&](StringRef name) { return FlatSymbolRefAttr::get(&context, name); };
  // @a and @b are one class, which @a stands for; @c is its own.
  auto classOf = [&](SymbolRefAttr ref) -> Attribute {
    return ref.getRootReference() == "b" ? Attribute(symbol("a")) : Attribute(ref);
  };
  auto flags = OperationEquivalence::IgnoreLocations;

  // A call naming its callee in an attribute.
  auto call = [&](StringRef callee) {
    OperationState state(loc, "test.call");
    state.addAttribute("callee", symbol(callee));
    return Operation::create(state);
  };
  // An operation whose result's type names a symbol: a tensor's encoding
  // may be any attribute.
  auto tensorOf = [&](StringRef name) -> Type {
    return RankedTensorType::get({4}, builder.getF32Type(), symbol(name));
  };
  auto make = [&](StringRef name) {
    OperationState state(loc, "test.make");
    state.addTypes(tensorOf(name));
    return Operation::create(state);
  };
  // An operation whose operand's type names the symbol of `of`'s result.
  auto use = [&](Operation *of) {
    OperationState state(loc, "test.use");
    state.addOperands(of->getResult(0));
    return Operation::create(state);
  };

  Tally tally;
  auto exact = OperationEquivalence::exactValueMatch;
  auto anyValue = OperationEquivalence::ignoreValueEquivalence;
  auto equivalent = [&](Operation *lhs, Operation *rhs, auto values, OperationEquivalence::MapSymbolRefFn map) {
    return OperationEquivalence::isEquivalentTo(lhs, rhs, values, nullptr, flags, nullptr, map);
  };
  auto hash = [&](Operation *op) {
    return OperationEquivalence::computeHash(op, OperationEquivalence::ignoreHashValue,
                                             OperationEquivalence::ignoreHashValue, flags, classOf);
  };

  Operation *callA = call("a"), *callB = call("b"), *callC = call("c");
  tally.expect("attributes, without the hook", equivalent(callA, callB, exact, nullptr), false);
  tally.expect("attributes, one class", equivalent(callA, callB, exact, classOf), true);
  tally.expect("attributes, two classes", equivalent(callA, callC, exact, classOf), false);
  tally.expect("attributes, one class, one hash", hash(callA) == hash(callB), true);

  Operation *makeA = make("a"), *makeB = make("b"), *makeC = make("c");
  tally.expect("result types, without the hook", equivalent(makeA, makeB, anyValue, nullptr), false);
  tally.expect("result types, one class", equivalent(makeA, makeB, anyValue, classOf), true);
  tally.expect("result types, two classes", equivalent(makeA, makeC, anyValue, classOf), false);
  tally.expect("result types, one class, one hash", hash(makeA) == hash(makeB), true);

  Operation *useA = use(makeA), *useB = use(makeB);
  tally.expect("operand types, without the hook", equivalent(useA, useB, anyValue, nullptr), false);
  tally.expect("operand types, one class", equivalent(useA, useB, anyValue, classOf), true);

  for (Operation *op : {useA, useB, makeA, makeB, makeC, callA, callB, callC})
    op->destroy();
  if (tally.wrong != 0)
    return 1;
  llvm::outs() << "ok\n";
  return 0;
}
