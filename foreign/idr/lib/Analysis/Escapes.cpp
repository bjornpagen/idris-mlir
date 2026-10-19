// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The escape analysis of cells: which cells idr.cell.new makes can outlive
// the frame that makes them.
//
// The rules, by use, for a value that may hold a cell's address, read from
// the reference edges of the use's op (idr/IR/Flow.h):
//   - moved or read whole into a value (forwarded by a branch or a region
//     branch, chosen by a select, a cell made into its box by
//     idr.cell.init): what reaches the value it goes to, in the same way;
//   - handed on by an op whose result is its operand's value at another
//     grade (a view, a share, a linear position): what reaches the result,
//     in the same way. This rule stands in place of the op's reference
//     edges, which say what becomes of a reference, not of an address: a
//     share gives its operand's reference up, but its result is the same
//     cell. Linearity has no runtime form, and a value used once may still
//     be used where it escapes;
//   - read out of as a part (a field read, the fields a match binds): what
//     is reachable from it reaches what the read gives; its own address
//     reaches nothing;
//   - moved into a part of a value (stored in a constructor): everything
//     reachable from it, its own address too, is reachable from that
//     value. A part of a value this analysis does not follow (an array, a
//     tensor) is memory it cannot see, so the cell escapes;
//   - only read while the op runs (a use its op declares no edge for, as
//     idr.tag's): nothing;
//   - dispatched on by a match of quantity one: the match leaves the cell to
//     build in again, so its own address goes with it;
//   - passed to a call: it escapes when that parameter's summary does. A
//     cell passed to a parameter that does not escape is live only while
//     the call runs, inside the caller's frame;
//   - returned, given up, or used by an op that declares no flow: it
//     escapes. A returned cell is in a frame that is gone whatever the
//     caller does with it, so the return is never the callers' to decide.
//
// A cell on the stack lives in one slot per cell op, in its function's
// frame. So it also escapes when the op may run again in the same frame
// while the cell is live: the cell must not be forwarded by a terminator of
// a loop around the op, a region branch whose region holding the terminator
// runs again, which carries values to the next iteration or out of the
// loop. Nor may it be passed to a call in tail position of a function on
// the same cycle of calls: such a call must be a tail call (idr-tail-calls)
// for the cycle to run in constant stack, or the next iteration of a loop
// (idr-tail-loops) when it is a self call, and either way the frame is gone
// when the callee runs. A function off the cycle never calls back round to
// this frame's function, so a call of it in tail position may stay a call
// that keeps the frame. A cell op counts only where the regions on the way
// up to its function's body, which is one block by its type, are of one
// block each and belong to region branches whose runs never overlap (none
// holds its region as parallel): a match's case runs at most once, a loop's
// body one iteration at a time. Anywhere else it escapes.
#include "idr/Analysis/EscapesDetail.h"

#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/IR/Iterators.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <variant>

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {

using namespace detail::escapes;

namespace {

Escape lost() {
  Escape all;
  all.shallow.escapes = true;
  all.deep.escapes = true;
  return all;
}

// The rules above, on upstream's backward base. The base forwards along
// branches and region branches, and hands every call to visitExternalCall,
// since the solver enters no callee; every other op's uses are what its
// edges say, and a call's are the callee's summaries.
class Solve : public SparseBackwardDataFlowAnalysis<EscapeLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Solve)

  Solve(DataFlowSolver &solver, SymbolTableCollection &tables, const CallCycles &cycles)
      : SparseBackwardDataFlowAnalysis(solver, tables), tables(tables), cycles(cycles) {}

  LogicalResult initialize(Operation *top) override;
  LogicalResult visit(ProgramPoint *point) override;
  LogicalResult visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                               ArrayRef<const EscapeLattice *> results) override;
  void visitBranchOperand(OpOperand &operand) override;
  void visitCallOperand(OpOperand &operand) override;
  void visitNonControlFlowArguments(RegionSuccessor &, ArrayRef<BlockArgument>) override {}

  // After defunctionalization every call the base resolves is an idr.call.
  void visitExternalCall(CallOpInterface call, ArrayRef<EscapeLattice *>,
                         ArrayRef<const EscapeLattice *>) override {
    visitCall(cast<CallOp>(call.getOperation()));
  }

  using SparseBackwardDataFlowAnalysis::setToExitState;
  void setToExitState(EscapeLattice *lattice) override { reach(lattice, lost()); }

  // A return lets every cell it returns go, whatever its callers do.
  LogicalResult visitCallableOperation(Operation *, CallableOpInterface,
                                       ArrayRef<AbstractSparseLattice *> operands) override {
    AbstractSparseBackwardDataFlowAnalysis::setAllToExitStates(operands);
    return success();
  }

private:
  void reach(EscapeLattice *lattice, const Escape &update) {
    propagateIfChanged(lattice, lattice->meet(update));
  }
  void follow(Operation *op, const FlowEdges::Edge &edge);
  void flow(Operation *op, const FlowEdges::Flow &move);
  void visitCall(CallOp call);

  SymbolTableCollection &tables;
  const CallCycles &cycles;
};

LogicalResult Solve::initialize(Operation *top) {
  // The base visits an op only where its block is executable. Every block
  // is: the frame question is asked of every function, called from this
  // program or not, as the rules above read every use.
  top->walk([&](Block *block) {
    auto *live = getOrCreate<Executable>(getProgramPointBefore(block));
    propagateIfChanged(live, live->setToLive());
  });
  // Every op once, users before what they use, through this analysis's own
  // visit, which adds the loop rule to the base's.
  WalkResult walked = top->walk<WalkOrder::PostOrder, ReverseIterator>([&](Operation *op) {
    if (op == top || succeeded(visit(getProgramPointAfter(op))))
      return WalkResult::advance();
    return WalkResult::interrupt();
  });
  return failure(walked.wasInterrupted());
}

LogicalResult Solve::visit(ProgramPoint *point) {
  if (point->isBlockStart())
    return success();
  if (failed(AbstractSparseBackwardDataFlowAnalysis::visit(point)))
    return failure();
  // A terminator of a region that runs again carries what it forwards into
  // its loop's next iteration, where a cell op in the loop writes its slot
  // again, or out of the loop.
  Operation *op = point->getPrevOp();
  auto loop = dyn_cast_or_null<RegionBranchOpInterface>(op->getParentOp());
  if (!loop || !op->hasTrait<OpTrait::IsTerminator>() ||
      !loop.isRepetitiveRegion(op->getParentRegion()->getRegionNumber()))
    return success();
  Escape update;
  update.shallow.loops.push_back(loop.getOperation());
  update.deep.loops.push_back(loop.getOperation());
  forwardedValues(op, [&](OpOperand &use, Value) {
    if (holdsCells(use.get().getType()))
      reach(getLatticeElement(use.get()), update);
  });
  return success();
}

// What one reference edge of `op` makes of the value it moves or reads: a
// flow below; a use given up lets its cell go; a dispatch lets every
// argument go, to whatever runs. A unification, a source and a constant
// are of labels, and a fresh value is reached by its own uses.
void Solve::follow(Operation *op, const FlowEdges::Edge &edge) {
  std::visit(llvm::makeVisitor([&](const FlowEdges::Flow &move) { flow(op, move); },
                               [](const FlowEdges::Unify &) {},
                               [](const FlowEdges::Source &) {},
                               [](const FlowEdges::Fresh &) {},
                               [&](const FlowEdges::Release &move) {
                                 Value given = move.use->get();
                                 if (holdsCells(given.getType()))
                                   setToExitState(getLatticeElement(given));
                               },
                               [](const FlowEdges::Constant &) {},
                               [&](FlowEdges::Dispatch move) {
                                 for (Value arg : move.call.getArgOperands())
                                   if (holdsCells(arg.getType()))
                                     setToExitState(getLatticeElement(arg));
                               }),
             edge.move);
}

// What a flow makes of the value it moves or reads, from the state of where
// it goes. A value goes whole into another (what reaches that one reaches
// it, its own address as that one's own), into a part of another (all of
// it is reachable from that one), or out of a part of it (only what is
// reachable from it reaches what the read gives). Into a parameter or a
// result it goes where this frame does not follow.
void Solve::flow(Operation *op, const FlowEdges::Flow &move) {
  std::optional<Value> source = move.from.value();
  if (!source || !holdsCells(source->getType()))
    return;
  EscapeLattice *lattice = getLatticeElement(*source);
  bool outOfPart = std::holds_alternative<FlowPoint::Part>(move.from.at);
  std::optional<Value> target = move.to.value();
  if (!target)
    return setToExitState(lattice);
  if (!holdsCells(target->getType())) {
    // A word, a string, read out of a part holds no cell; anything moved
    // into what this analysis does not follow is memory it cannot see.
    if (!outOfPart)
      setToExitState(lattice);
    return;
  }
  const Escape &there =
      getOrCreateFor<EscapeLattice>(getProgramPointAfter(op), *target)->getValue();
  Escape update;
  update.deep = there.deep;
  if (!outOfPart)
    update.shallow = std::holds_alternative<FlowPoint::Part>(move.to.at) ? there.deep
                                                                          : own(*target, there);
  reach(lattice, update);
}

LogicalResult Solve::visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                                    ArrayRef<const EscapeLattice *>) {
  // The address of the operand is the result's, whatever the op does with
  // the reference (the rule above): one whole flow, in place of the edges.
  if (op->hasTrait<ResultCarriesOperand>()) {
    flow(op, {FlowPoint::of(op->getOperand(0)), FlowPoint::of(op->getResult(0))});
    return success();
  }
  if (!declaresFlow(op)) {
    for (auto [operand, lattice] : llvm::zip(op->getOperands(), operands))
      if (holdsCells(operand.getType()))
        setToExitState(lattice);
    return success();
  }
  FlowEdges edges;
  flowEdgesOf(op, edges);
  for (const FlowEdges::Edge &edge : edges.edges())
    if (edge.carries(Carrier::Reference))
      follow(op, edge);
  return success();
}

// An operand of a region branch, or of a terminator of one, that the base
// does not forward: what the op's edges say of it, as of any use. A box of
// quantity one a region branch dispatches on dies there, and its cell is
// left to build in again.
void Solve::visitBranchOperand(OpOperand &operand) {
  Value value = operand.get();
  if (!holdsCells(value.getType()))
    return;
  Operation *op = operand.getOwner();
  auto flow = dyn_cast<FlowOpInterface>(op);
  if (!flow)
    return setToExitState(getLatticeElement(value));
  // Whether `edge` moves or reads `value`: a flow from it, or its use
  // given up. The other edges move no operand's value.
  auto from = [&](const FlowEdges::Edge &edge) {
    return std::visit(
        llvm::makeVisitor(
            [&](const FlowEdges::Flow &move) { return move.from.value() == value; },
            [](const FlowEdges::Unify &) { return false; },
            [](const FlowEdges::Source &) { return false; },
            [](const FlowEdges::Fresh &) { return false; },
            [&](const FlowEdges::Release &move) { return move.use->get() == value; },
            [](const FlowEdges::Constant &) { return false; },
            [](const FlowEdges::Dispatch &) { return false; }),
        edge.move);
  };
  FlowEdges edges;
  flow.getFlowEdges(edges);
  for (const FlowEdges::Edge &edge : edges.edges())
    if (edge.carries(Carrier::Reference) && from(edge))
      follow(op, edge);
  if (isa<RegionBranchOpInterface>(op) && holdsOwnAddress(value.getType()) &&
      quantityOf(value.getType()) == Quantity::One) {
    Escape update;
    update.shallow.escapes = true;
    reach(getLatticeElement(value), update);
  }
}

void Solve::visitCallOperand(OpOperand &operand) {
  if (holdsCells(operand.get().getType()))
    setToExitState(getLatticeElement(operand.get()));
}

// Every callee is a function of the program with a body, found through the
// table the base resolved the call by: a call's symbol use is verified, and
// no function is without one.
void Solve::visitCall(CallOp call) {
  auto callee = cast<FuncOp>(call.resolveCallableInTable(&tables));
  // A call in tail position ends the frame, and so does one in tail
  // position but for the context its result goes into: idr-trmc makes it
  // the next iteration of a loop in the same frame, writing the hole.
  bool ends = (tail::inTailPosition(call) || tail::inTailPositionModuloContext(call)) &&
              cycles.together(call->getParentOfType<FuncOp>(), callee);
  ProgramPoint *after = getProgramPointAfter(call);
  for (auto [index, operand] : llvm::enumerate(call.getArgs())) {
    if (!holdsCells(operand.getType()))
      continue;
    EscapeLattice *lattice = getLatticeElement(operand);
    // The parameter's state is its summary; the solver visits the call
    // again when it grows.
    BlockArgument param = callee.getArgument(static_cast<unsigned>(index));
    const Escape &summary = getOrCreateFor<EscapeLattice>(after, param)->getValue();
    Escape update;
    update.shallow.escapes = own(param, summary).escapes;
    update.deep.escapes = summary.deep.escapes;
    update.shallow.tailCalled = ends;
    update.deep.tailCalled = ends;
    reach(lattice, update);
  }
}

} // namespace

Escapes::Escapes(Operation *op, AnalysisManager &am) : program(op) {
  const CallCycles &cycles = am.getAnalysis<CallCycles>();
  findCycles(cycles);
  // One solve over the program: the parameters' summaries, the cell ops and
  // the loops are one fixpoint, so nothing is solved twice.
  solver.load<Solve>(tables, cycles);
  // MLIR's solver fails only where an analysis's visit does, and every
  // visit of Solve succeeds.
  [[maybe_unused]] LogicalResult ran = solver.initializeAndRun(op);
  assert(succeeded(ran) && "every visit of the escape solve succeeds");
}

} // namespace idr
