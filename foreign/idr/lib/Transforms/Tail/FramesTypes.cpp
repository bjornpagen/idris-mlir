// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' data types: a component's stack and its answer, and a
// member's result into and out of the answer (Frames.cpp rewrites the
// bodies and the rests).

#include "idr/Transforms/Tail.h"

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;

namespace idr::tail {

// The stack's data type: `empty`, then each frame, holding what its rest
// reads and the stack under it.
FailureOr<DataType> stackTypeOf(Declarations &declarations, FramesPlan &plan) {
  MLIRContext *ctx = declarations.getProgram().getContext();
  SmallVector<SmallVector<Type>> fields;
  fields.reserve(plan.frames.size());
  return declarations.define(plan.stack.getValue(), [&](DataType self) {
    Type below = BoxType::get(ctx, self);
    DataType::Body body;
    body.ctors.push_back({StringAttr::get(ctx, "empty"), {}, role::Plain{}});
    for (auto [index, frame] : llvm::enumerate(plan.frames)) {
      SmallVector<Type> &each = fields.emplace_back();
      for (Value held : frame.held)
        each.push_back(held.getType());
      each.push_back(below);
      body.ctors.push_back(
          {StringAttr::get(ctx, "frame" + std::to_string(index)), each, role::Plain{}});
    }
    return FailureOr<DataType::Body>(std::move(body));
  });
}

// The answer's data type, when the members give more than one result
// type: one constructor per result type, holding a value of it, in the
// plan's tag order.
FailureOr<DataType> answerTypeOf(Declarations &declarations, FramesPlan &plan) {
  MLIRContext *ctx = declarations.getProgram().getContext();
  // A constructor's fields are a reference into storage the caller
  // keeps, as the stack's are.
  SmallVector<SmallVector<Type>> fields;
  fields.reserve(plan.results.size());
  for (Type result : plan.results)
    fields.push_back({result});
  return declarations.define(plan.answer.getValue(), [&](DataType) {
    DataType::Body body;
    for (auto [index, each] : llvm::enumerate(fields))
      body.ctors.push_back(
          {StringAttr::get(ctx, "answer" + std::to_string(index)), each, role::Plain{}});
    return FailureOr<DataType::Body>(std::move(body));
  });
}

Value FramesMade::asAnswer(RewriterBase &rewriter, Location loc, const FramesPlan &plan,
                           Value value) const {
  if (!sum)
    return value;
  auto tag = Tag{static_cast<uint32_t>(llvm::find(plan.results, value.getType()) -
                                       plan.results.begin())};
  return ConOp::create(rewriter, loc, answer, tag, ValueRange{value});
}

// A member's own result out of the answer its run gave: the answer
// itself when there is no sum, and otherwise the one case of the sum that
// holds this member's result type, the only one a run that started in
// this member on the empty stack can give.
Value fromAnswer(RewriterBase &rewriter, const FramesPlan &plan, const FramesMade &made, FuncOp fn,
                 Value given) {
  if (!made.sum)
    return given;
  Location loc = fn.getLoc();
  Type result = fn.getResultTypes()[0];
  auto tags = llvm::to_vector(made.sum->getTags());
  auto match = MatchOp::create(rewriter, loc, TypeRange(result), given, ArrayRef<Tag>(tags));
  for (auto [index, each] : llvm::enumerate(plan.results)) {
    Region &region = match.getCaseRegion(static_cast<unsigned>(index));
    const Ctor &ctor = made.sum->getCtor(Tag{static_cast<uint32_t>(index)});
    Block *block = rewriter.createBlock(&region, region.end(),
                                        {fieldType(made.answer, ctor.fields[0])},
                                        {passBinder(loc, "answer")});
    if (each == result)
      YieldOp::create(rewriter, loc, heldAs(rewriter, loc, block->getArgument(0), result));
    else
      ub::UnreachableOp::create(rewriter, loc);
  }
  rewriter.setInsertionPointAfter(match);
  return match.getResult(0);
}

} // namespace idr::tail
