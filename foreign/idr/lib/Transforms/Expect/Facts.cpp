// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// test-idr-facts: what the dialect answers about each op, reported as a
// remark at the op, which a test expects where it states it
// (`expected-remark`, under -verify-diagnostics), as upstream's
// test-side-effects reports what an op declares. The expectation is the
// test's text at the op's place, not an attribute of the IR under test, so
// an op erased before the report breaks it, and no pass sees the IR
// changed by what the test expects.
//
// Each question is asked as the pass that asks it asks it, of the op's own
// effects, a call's included, which it holds as its callee's: whether an
// unused op is dead and whether two equal ops are one value are upstream's
// dead code removal's and CSE's questions; whether an op may move across
// anything and whether it may be delayed are the dialect's rewrites'.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The questions answered yes about `op`, in a fixed order: whether it is
// dead once nothing reads it, whether it may be moved across anything,
// whether it may be delayed, and whether two equal ones are one value,
// which an op that allocates its result never is: no two cells become one.
std::string answers(Operation *op) {
  std::pair<StringRef, bool> questions[] = {
      {"drop", isOpTriviallyDead(op)},
      {"move", onlyAllocates(op)},
      {"delay", !performsIO(op)},
      {"merge", isMemoryEffectFree(op)},
  };
  std::string out;
  for (auto [question, yes] : questions)
    if (yes)
      out += (out.empty() ? "" : " ") + question.str();
  return out;
}

// Registered in idris-mlir-opt alone: it reports, as a remark at each op of
// every function's body, `facts: [...]`, the answers among `drop move delay
// merge` in that order, bracketed so that one expectation is never a part
// of another; and changes nothing.
struct FactsTest : PassWrapper<FactsTest, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FactsTest)

  StringRef getArgument() const final { return "test-idr-facts"; }
  StringRef getDescription() const final {
    return "Report what the dialect answers about each op of a function's body, as a remark, "
           "for the effects' tests";
  }

  void runOnOperation() override {
    getOperation().walk([](FunctionOpInterface fn) {
      fn.getFunctionBody().walk(
          [](Operation *op) { op->emitRemark() << "facts: [" << answers(op) << "]"; });
    });
    markAllAnalysesPreserved();
  }
};

} // namespace

} // namespace idr::expect

void idr::registerFactsTestPass() { PassRegistration<idr::expect::FactsTest>(); }
