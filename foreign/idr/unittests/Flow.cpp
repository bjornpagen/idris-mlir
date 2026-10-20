// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the flow rule (idr::detail::verifyFlowEdges). An op of ours is
// held to its model by the interface's verifier at every stage, which a
// test op whose model names a value it does not make shows. No interface
// verifier reaches an external model, so each upstream op that holds one is
// asked here, on values that carry a reference.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Parser/Parser.h"

#include "gtest/gtest.h"

#include <set>
#include <string>

using namespace mlir;
using namespace idr;

namespace {

// An op whose model declares its operand, a value some other op or block
// makes, new: an end no op may name.
class NamesAnother : public Op<NamesAnother, OpTrait::ZeroResults, OpTrait::OneOperand,
                               FlowOpInterface::Trait> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NamesAnother)
  using Op::Op;
  static ArrayRef<StringRef> getAttributeNames() { return {}; }
  static StringRef getOperationName() { return "flowtest.names_another"; }
  void getFlowEdges(FlowEdges &edges) { edges.fresh(getOperation()->getOperand(0)); }
};

// Ops shaped as a fold: the region's argument is what an earlier step
// wrote into the result. One reads it from a part of the result, the
// elements, as a fold's accumulator does; the other from the whole result,
// which the op has not made yet: an end no op may name.
template <typename Self>
using ReadsBackBase = Op<Self, OpTrait::OneRegion, OpTrait::OneResult, OpTrait::ZeroOperands,
                         OpTrait::NoTerminator, FlowOpInterface::Trait>;

class ReadsBackPart : public ReadsBackBase<ReadsBackPart> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ReadsBackPart)
  using Op::Op;
  static ArrayRef<StringRef> getAttributeNames() { return {}; }
  static StringRef getOperationName() { return "flowtest.reads_back_part"; }
  void getFlowEdges(FlowEdges &edges) {
    Value result = getOperation()->getResult(0);
    auto shaped = cast<ShapedType>(result.getType());
    edges.flow(FlowPoint::partOf(result, FlowAnchor::elementsOf(shaped.getElementType())),
               FlowPoint::of(getOperation()->getRegion(0).getArgument(0)));
  }
};

class ReadsBackWhole : public ReadsBackBase<ReadsBackWhole> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ReadsBackWhole)
  using Op::Op;
  static ArrayRef<StringRef> getAttributeNames() { return {}; }
  static StringRef getOperationName() { return "flowtest.reads_back_whole"; }
  void getFlowEdges(FlowEdges &edges) {
    edges.flow(FlowPoint::of(getOperation()->getResult(0)),
               FlowPoint::of(getOperation()->getRegion(0).getArgument(0)));
  }
};

// Ops that write a value into the elements of a buffer they are given,
// memory that exists before them: one says the element it replaces is
// released, as memref.store does; the other says nothing of it, which
// would leave a reference in memory no one accounts for.
template <typename Self>
using WritesBase = Op<Self, OpTrait::ZeroResults, OpTrait::NOperands<2>::Impl,
                      FlowOpInterface::Trait>;

template <typename Self, bool released>
void writeEdges(Operation *op, FlowEdges &edges) {
  Value buffer = op->getOperand(1);
  auto shaped = cast<ShapedType>(buffer.getType());
  FlowPoint place = FlowPoint::partOf(buffer, FlowAnchor::elementsOf(shaped.getElementType()));
  edges.flow(FlowPoint::of(op->getOpOperand(0)), place);
  if (released)
    edges.overwrite(place);
}

class WritesOver : public WritesBase<WritesOver> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(WritesOver)
  using Op::Op;
  static ArrayRef<StringRef> getAttributeNames() { return {}; }
  static StringRef getOperationName() { return "flowtest.writes_over"; }
  void getFlowEdges(FlowEdges &edges) { writeEdges<WritesOver, true>(*this, edges); }
};

class WritesUnsaid : public WritesBase<WritesUnsaid> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(WritesUnsaid)
  using Op::Op;
  static ArrayRef<StringRef> getAttributeNames() { return {}; }
  static StringRef getOperationName() { return "flowtest.writes_unsaid"; }
  void getFlowEdges(FlowEdges &edges) { writeEdges<WritesUnsaid, false>(*this, edges); }
};

class FlowTestDialect : public Dialect {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FlowTestDialect)
  static constexpr StringLiteral getDialectNamespace() { return StringLiteral("flowtest"); }
  explicit FlowTestDialect(MLIRContext *context)
      : Dialect(getDialectNamespace(), context, TypeID::get<FlowTestDialect>()) {
    addOperations<NamesAnother, ReadsBackPart, ReadsBackWhole, WritesOver, WritesUnsaid>();
  }
};

// At stage owned, where the function's walk no longer reads a model, the
// interface refuses the op; at the base it verified.
TEST(FlowRule, AModelIsVerifiedAtEveryStage) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, arith::ArithDialect, FlowTestDialect>();
  ParserConfig config(&ctx, /*verifyAfterParse=*/false);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!B = !idr.data<"B">
#types = #idr.types<
  "B" = plain [@K(i64)]
>
idr.program @p root(@root) stage(owned) types #types {
  idr.func @f(%b: !idr.own<!idr.box<!B>>) {
    "flowtest.names_another"(%b) : (!idr.own<!idr.box<!B>>) -> ()
    return
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
)mlir",
                                                             config);
  ASSERT_TRUE(module);
  std::string first;
  ScopedDiagnosticHandler handler(&ctx, [&](Diagnostic &diagnostic) {
    if (first.empty())
      first = diagnostic.str();
    return success();
  });
  EXPECT_TRUE(failed(verify(*module)));
  EXPECT_NE(first.find("flow edge"), std::string::npos) << first;
}

// A region may read back a part of its op's result, as a fold's next
// accumulator is what the step before wrote into the result's elements;
// never the whole result.
TEST(FlowRule, ARegionReadsBackAPartOfItsResult) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, func::FuncDialect, FlowTestDialect>();
  ParserConfig config(&ctx, /*verifyAfterParse=*/false);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!B = !idr.data<"B">
func.func @f() {
  %part = "flowtest.reads_back_part"() ({
  ^bb0(%x: !idr.box<!B>):
  }) : () -> tensor<2x!idr.box<!B>>
  %whole = "flowtest.reads_back_whole"() ({
  ^bb0(%y: tensor<2x!idr.box<!B>>):
  }) : () -> tensor<2x!idr.box<!B>>
  return
}
)mlir",
                                                             config);
  ASSERT_TRUE(module);
  ScopedDiagnosticHandler quiet(&ctx, [](Diagnostic &) { return success(); });
  module->walk([&](ReadsBackPart op) { EXPECT_TRUE(succeeded(idr::detail::verifyFlowEdges(op))); });
  module->walk([&](ReadsBackWhole op) { EXPECT_TRUE(failed(idr::detail::verifyFlowEdges(op))); });
}

// A write of a reference into memory that exists before the op says what
// the place held: one that releases it verifies, one that says nothing is
// refused.
TEST(FlowRule, AWriteIntoMemorySaysWhatThePlaceHeld) {
  MLIRContext ctx;
  ctx.loadDialect<IdrDialect, func::FuncDialect, FlowTestDialect>();
  ParserConfig config(&ctx, /*verifyAfterParse=*/false);
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!B = !idr.data<"B">
func.func @f(%e: !idr.box<!B>, %m: memref<2x!idr.box<!B>>) {
  "flowtest.writes_over"(%e, %m) : (!idr.box<!B>, memref<2x!idr.box<!B>>) -> ()
  "flowtest.writes_unsaid"(%e, %m) : (!idr.box<!B>, memref<2x!idr.box<!B>>) -> ()
  return
}
)mlir",
                                                             config);
  ASSERT_TRUE(module);
  ScopedDiagnosticHandler quiet(&ctx, [](Diagnostic &) { return success(); });
  module->walk([&](WritesOver op) { EXPECT_TRUE(succeeded(idr::detail::verifyFlowEdges(op))); });
  module->walk([&](WritesUnsaid op) { EXPECT_TRUE(failed(idr::detail::verifyFlowEdges(op))); });
}

// Each external model names only ends its op may name. The models are read
// from the registry: every registered op of another dialect that holds the
// interface is one, and the fixture must hold an op of each, so a model
// added without a case here fails.
TEST(FlowRule, ExternalModelsKeepTheRule) {
  DialectRegistry registry;
  registerFlowInterfaceExternalModels(registry);
  MLIRContext ctx(registry);
  ctx.loadDialect<IdrDialect, arith::ArithDialect, func::FuncDialect, memref::MemRefDialect,
                  tensor::TensorDialect, ub::UBDialect>();
  std::set<std::string> models;
  for (RegisteredOperationName name : ctx.getRegisteredOperations())
    if (name.getDialectNamespace() != IdrDialect::getDialectNamespace() &&
        name.hasInterface<FlowOpInterface>())
      models.insert(name.getStringRef().str());
  EXPECT_FALSE(models.empty());
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
!B = !idr.data<"B">
func.func @f(%t: tensor<2x!idr.box<!B>>, %m: memref<2x!idr.box<!B>>, %e: !idr.box<!B>,
             %i: index) {
  %inserted = tensor.insert %e into %t[%i] : tensor<2x!idr.box<!B>>
  %extracted = tensor.extract %t[%i] : tensor<2x!idr.box<!B>>
  %made = tensor.from_elements %e, %e : tensor<2x!idr.box<!B>>
  %splat = tensor.splat %e : tensor<2x!idr.box<!B>>
  %generated = tensor.generate {
  ^bb0(%j: index):
    tensor.yield %e : !idr.box<!B>
  } : tensor<2x!idr.box<!B>>
  %loaded = memref.load %m[%i] : memref<2x!idr.box<!B>>
  memref.store %e, %m[%i] : memref<2x!idr.box<!B>>
  %poison = ub.poison : !idr.box<!B>
  return
}
func.func @never() {
  ub.unreachable
}
)mlir",
                                                             &ctx);
  ASSERT_TRUE(module);
  std::set<std::string> exercised;
  module->walk([&](FlowOpInterface op) {
    if (op->getDialect()->getNamespace() == IdrDialect::getDialectNamespace())
      return;
    exercised.insert(op->getName().getStringRef().str());
    EXPECT_TRUE(succeeded(idr::detail::verifyFlowEdges(op))) << op->getName().getStringRef().str();
  });
  EXPECT_EQ(exercised, models);
}

} // namespace
