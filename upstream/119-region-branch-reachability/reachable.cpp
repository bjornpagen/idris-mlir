// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A region branch op asked whether one of its regions may run after
// another, in each direction: it prints "ok" with the patch, once
// isRegionReachable answers that the op's second region may run after its
// first, that the first never runs after the second, and that neither runs
// again after itself. The order is what insideMutuallyExclusiveRegions
// cannot give, which is false for the two regions either way round. The op
// is this program's, two regions run one after the other (the pin's unit
// test has one too), as the body of an idr.join may enter a join region and
// no join region enters the body. At the pin it does not build: the walk is
// static to ControlFlowInterfaces.cpp.
// Built against the toolchain's MLIR:
//   clang++ -std=c++17 reachable.cpp $(llvm-config --cxxflags --ldflags) libMLIR*.a $(llvm-config --libs --system-libs)
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Parser/Parser.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace reach {

// A terminator that hands nothing on, wherever its op says it goes.
class EndOp : public Op<EndOp, OpTrait::IsTerminator, OpTrait::ZeroResults,
                        OpTrait::ZeroSuccessors, RegionBranchTerminatorOpInterface::Trait> {
public:
  using Op::Op;
  static StringRef getOperationName() { return "reach.end"; }
  static ArrayRef<StringRef> getAttributeNames() { return {}; }

  MutableOperandRange getMutableSuccessorOperands(RegionSuccessor) {
    return MutableOperandRange(getOperation(), 0, 0);
  }
};

// Two regions run one after the other: the first branches to the second,
// and the second has no successor.
class SequentialOp : public Op<SequentialOp, RegionBranchOpInterface::Trait> {
public:
  using Op::Op;
  static StringRef getOperationName() { return "reach.sequential"; }
  static ArrayRef<StringRef> getAttributeNames() { return {}; }

  void getSuccessorRegions(RegionBranchPoint point, SmallVectorImpl<RegionSuccessor> &regions) {
    RegionBranchTerminatorOpInterface end = point.getTerminatorPredecessorOrNull();
    if (end && end->getParentRegion() == &getOperation()->getRegion(0))
      regions.push_back(RegionSuccessor(&getOperation()->getRegion(1)));
  }
  using RegionBranchOpInterface::Trait<SequentialOp>::getSuccessorRegions;
};

class ReachDialect : public Dialect {
public:
  explicit ReachDialect(MLIRContext *context)
      : Dialect(getDialectNamespace(), context, TypeID::get<ReachDialect>()) {
    addOperations<EndOp, SequentialOp>();
  }
  static StringRef getDialectNamespace() { return "reach"; }
};

} // namespace reach

static const char *source = R"mlir(
"reach.sequential"() ({
  "reach.end"() : () -> ()
}, {
  "reach.end"() : () -> ()
}) : () -> ()
)mlir";

int main() {
  DialectRegistry registry;
  registry.insert<reach::ReachDialect>();
  MLIRContext context(registry);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(source, &context);
  if (!module) {
    llvm::outs() << "the module does not parse\n";
    return 1;
  }
  auto branch = cast<RegionBranchOpInterface>(&module->getBody()->front());

  bool held = true;
  auto expect = [&](StringRef what, bool answer, bool expected) {
    if (answer == expected)
      return;
    held = false;
    llvm::outs() << what << ": " << (answer ? "true" : "false") << "\n";
  };
  expect("isRegionReachable(0, 1)", branch.isRegionReachable(0, 1), true);
  expect("isRegionReachable(1, 0)", branch.isRegionReachable(1, 0), false);
  expect("isRegionReachable(0, 0)", branch.isRegionReachable(0, 0), false);
  expect("isRegionReachable(1, 1)", branch.isRegionReachable(1, 1), false);

  if (held)
    llvm::outs() << "ok\n";
  return held ? 0 : 1;
}
