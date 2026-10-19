// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules of the frame, read off each op's moves (Lifetimes.h), and the
// function verifier that holds every value of the frame to them.

#include "idr/IR/Lifetimes.h"

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Tail.h"
#include "idr/IR/Verify.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;

namespace idr::lifetimes {

StringRef describe(Escape escape) {
  switch (escape) {
  case Escape::Returned:
    return "returns it, though it dies with the frame";
  case Escape::Stored:
    return "moves it into memory that exists before the op, which outlives the frame";
  case Escape::Repeated:
    return "forwards it out of a region that runs again, whose next run writes the same slots";
  case Escape::TailCalled:
    return "passes it to a self call that becomes the next iteration of a loop in the frame";
  case Escape::Unknown:
    return "uses it in an op that declares none of its moves";
  }
  llvm_unreachable("an escape");
}

namespace {

// Whether `op` makes `value`: one of its results, or an argument of a block
// of one of its regions; a terminator gives what its parent makes. Anything
// else it writes into existed before it.
bool makes(Operation *op, Value value) {
  Operation *maker = isa<OpResult>(value)
                         ? cast<OpResult>(value).getOwner()
                         : cast<BlockArgument>(value).getOwner()->getParentOp();
  return maker == op || (op->hasTrait<OpTrait::IsTerminator>() && maker == op->getParentOp());
}

// Whether `op` ends a run of a region that runs again.
bool endsRepeatedRun(Operation *op) {
  if (!op->hasTrait<OpTrait::IsTerminator>())
    return false;
  auto loop = dyn_cast_or_null<RegionBranchOpInterface>(op->getParentOp());
  return loop && loop.isRepetitiveRegion(op->getParentRegion()->getRegionNumber());
}

} // namespace

bool loopsInFrame(Operation *op) {
  auto call = dyn_cast<CallOp>(op);
  if (!call)
    return false;
  auto fn = call->getParentOfType<FuncOp>();
  return fn && tail::isSelfCall(call, fn) &&
         (tail::inTailPosition(call) || tail::inTailPositionModuloContext(call));
}

void edgesOf(Operation *op, function_ref<void(Value from, const Edge &edge)> each) {
  auto frameable = [](Value value) { return mayBeFrame(value.getType()); };
  if (op->hasTrait<ResultCarriesOperand>()) {
    if (frameable(op->getOperand(0)))
      each(op->getOperand(0), Carries{op->getResult(0)});
    return;
  }
  if (!declaresFlow(op)) {
    for (Value operand : op->getOperands())
      if (frameable(operand))
        each(operand, Escape::Unknown);
    return;
  }
  if (loopsInFrame(op))
    for (Value operand : op->getOperands())
      if (frameable(operand))
        each(operand, Escape::TailCalled);
  bool repeated = endsRepeatedRun(op);
  FlowEdges edges;
  flowEdgesOf(op, edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    const auto *move = std::get_if<FlowEdges::Flow>(&edge.move);
    if (!move)
      continue;
    // What moves: the value, or what a part of it holds; a word or a
    // string read out of a value of the frame reaches no cell of it.
    std::optional<Value> from = move->from.value();
    if (!from || !frameable(*from))
      continue;
    if (std::optional<Type> moved = move->from.type(); moved && !mayBeFrame(*moved))
      continue;
    if (const auto *param = std::get_if<FlowPoint::Parameter>(&move->to.at)) {
      if (auto call = dyn_cast<CallOp>(op))
        each(*from, Passes{call, param->index});
      continue;
    }
    if (std::holds_alternative<FlowPoint::Result>(move->to.at)) {
      each(*from, Escape::Returned);
      continue;
    }
    Value to = *move->to.value();
    if (repeated) {
      each(*from, Escape::Repeated);
      continue;
    }
    if (auto init = dyn_cast<CellInitOp>(op); init && to == init.getResult()) {
      each(*from, Fills{init});
      continue;
    }
    // Memory that exists before the op, or memory the op makes that is no
    // value of the frame (an array's elements, a tensor's): the value is
    // stored where no lifetime follows it. A value of no lifetime made of
    // the value whole (a take's token) holds none of its cells.
    bool intoPart = std::holds_alternative<FlowPoint::Part>(move->to.at);
    if (!makes(op, to) || (intoPart && !frameable(to))) {
      each(*from, Escape::Stored);
      continue;
    }
    if (frameable(to))
      each(*from, Carries{to});
  }
}

} // namespace idr::lifetimes

// Every value an op makes from a value of the frame is of the frame, a cell
// a frame value fills is the frame's, and no frame value escapes; a
// function's results are never of the frame.
LogicalResult idr::verify::lifetimes(FuncOp fn) {
  for (Type result : fn.getResultTypes())
    if (lifetimeOf(result) == Lifetime::Frame)
      return fn.emitOpError("returns a value of the frame, ")
             << result << ", which dies with the frame";
  using namespace lifetimes;
  WalkResult walked = fn.walk([&](Operation *op) {
    LogicalResult held = success();
    edgesOf(op, [&](Value from, const Edge &edge) {
      if (failed(held) || lifetimeOf(from.getType()) != Lifetime::Frame)
        return;
      held = std::visit(
          llvm::makeVisitor(
              [&](const Carries &carries) -> LogicalResult {
                if (lifetimeOf(carries.to.getType()) == Lifetime::Frame)
                  return success();
                InFlightDiagnostic diag = op->emitOpError("makes ")
                                          << carries.to.getType()
                                          << " of a value of the frame, which it reaches";
                diag.attachNote(from.getLoc()) << "the value of the frame is defined here";
                return diag;
              },
              [&](const Fills &fills) -> LogicalResult {
                if (CellInitOp(fills.init).getCell().getType().getLifetime() == Lifetime::Frame)
                  return success();
                InFlightDiagnostic diag =
                    op->emitOpError("moves a value of the frame into a cell of the heap");
                diag.attachNote(from.getLoc()) << "the value of the frame is defined here";
                return diag;
              },
              [](const Passes &) { return success(); },
              [&](Escape escape) -> LogicalResult {
                InFlightDiagnostic diag = op->emitOpError("takes a value of the frame and ")
                                          << describe(escape);
                diag.attachNote(from.getLoc()) << "the value of the frame is defined here";
                return diag;
              }),
          edge);
    });
    return failed(held) ? WalkResult::interrupt() : WalkResult::advance();
  });
  return failure(walked.wasInterrupted());
}
