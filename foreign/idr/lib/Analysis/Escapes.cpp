// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The escape analysis of boxes: which cells can outlive the frame that
// builds them.
//
// The rules, by use, for a value that may hold a cell, read from the
// reference edges of the use's op (idr/IR/Flow.h):
//   - moved or read whole into a value (forwarded by a branch or a region
//     branch, chosen by a select, handed into or out of a linear type):
//     what reaches the value it goes to, in the same way. Linearity has no
//     runtime form, and a value used once may still be used where it
//     escapes;
//   - read out of as a part (a field read, the fields a match binds): what
//     is reachable from it reaches what the read gives; its own reference
//     reaches nothing;
//   - moved into a part of a value (stored in a constructor): everything
//     reachable from it, its own reference too, is reachable from that
//     value. A part of a value this analysis does not follow (an array, a
//     tensor) is memory it cannot see, so the cell escapes;
//   - only read while the op runs (a use its op declares no edge for, as
//     idr.tag's): nothing;
//   - dispatched on by a match of quantity one: the match leaves the cell to
//     build in again, so its own reference goes with it;
//   - passed to a call: it escapes when that parameter's summary does. A
//     cell passed to a parameter that does not escape is live only while
//     the call runs, inside the caller's frame;
//   - returned, given up, or used by an op that declares no flow: it
//     escapes. A returned cell is in a frame that is gone whatever the
//     caller does with it, so the return is never the callers' to decide.
//
// The cell an idr.con builds lives in one stack slot per con, in its
// function's entry block. So it also escapes when the con may run again in
// the same frame while the cell is live: the cell must not be forwarded by
// a terminator of a loop around the con, a region branch whose region
// holding the terminator runs again, which carries values to the next
// iteration or out of the loop. Nor may it be passed to a call in tail
// position of a function on the same cycle of calls: such a call must be a
// tail call (idr-tail-calls) for the cycle to run in constant stack, or the
// next iteration of a loop (idr-tail-loops) when it is a self call, and
// either way the frame is gone when the callee runs. A function off the
// cycle never calls back round to this frame's function, so a call of it in
// tail position may stay a call that keeps the frame. A con counts only in
// a function body of one block whose regions on the way are of one block
// each and belong to region branches whose runs never overlap (none holds
// its region as parallel): a match's case runs at most once, a loop's body
// one iteration at a time. Anywhere else it escapes.
#include "idr/Analysis/EscapesDetail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/IR/Iterators.h"
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

// Whether `a` and `b` are on one cycle of calls: each may call the other,
// through any calls. A function is on one with itself.
bool together(const DenseMap<Operation *, unsigned> &component, Operation *a, Operation *b) {
  if (a == b)
    return true;
  auto at = component.find(a), bt = component.find(b);
  return at != component.end() && bt != component.end() && at->second == bt->second;
}

// The rules above, on upstream's backward base. The base forwards along
// branches and region branches; every other op's uses are what its edges
// say, and a call's are the callee's summaries.
class Solve : public SparseBackwardDataFlowAnalysis<EscapeLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Solve)

  Solve(DataFlowSolver &solver, SymbolTableCollection &unresolved, SymbolTable &symbols,
        const DenseMap<Operation *, unsigned> &component)
      : SparseBackwardDataFlowAnalysis(solver, unresolved), symbols(symbols),
        component(component) {}

  LogicalResult initialize(Operation *top) override;
  LogicalResult visit(ProgramPoint *point) override;
  LogicalResult visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                               ArrayRef<const EscapeLattice *> results) override;
  void visitBranchOperand(OpOperand &operand) override;
  void visitCallOperand(OpOperand &operand) override;
  void visitNonControlFlowArguments(RegionSuccessor &, ArrayRef<BlockArgument>) override {}

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

  SymbolTable &symbols;
  const DenseMap<Operation *, unsigned> &component;
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
  // visit, so that the base never takes an idr.call by its rule.
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
  Operation *op = point->getPrevOp();
  if (auto call = dyn_cast<CallOp>(op)) {
    visitCall(call);
    return success();
  }
  if (failed(AbstractSparseBackwardDataFlowAnalysis::visit(point)))
    return failure();
  // A terminator of a region that runs again carries what it forwards into
  // its loop's next iteration, where a con in the loop writes its slot
  // again, or out of the loop.
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
// it, its own reference as that one's own), into a part of another (all of
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
    update.shallow = std::holds_alternative<FlowPoint::Part>(move.to.at)
                         ? there.deep
                         : part(*target, there, Mode::Shallow);
  reach(lattice, update);
}

LogicalResult Solve::visitOperation(Operation *op, ArrayRef<EscapeLattice *> operands,
                                    ArrayRef<const EscapeLattice *>) {
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
  if (isa<RegionBranchOpInterface>(op) && isBox(value.getType()) &&
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

// Every callee is a function of the program with a body: a call's symbol
// use is verified, and no function is without one.
void Solve::visitCall(CallOp call) {
  auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
  bool ends = tail::inTailPosition(call) &&
              together(component, call->getParentOfType<FuncOp>(), callee);
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
    update.shallow.escapes = part(param, summary, Mode::Shallow).escapes;
    update.deep.escapes = summary.deep.escapes;
    update.shallow.tailCalled = ends;
    update.deep.tailCalled = ends;
    reach(lattice, update);
  }
}

} // namespace

Escapes::Escapes(Operation *op, AnalysisManager &am) : program(op) {
  findCycles(am);
  // One solve over the program: the parameters' summaries, the cons and the
  // loops are one fixpoint, so nothing is solved twice.
  solver.load<Solve>(unresolved, am.getAnalysis<SymbolTable>(), component);
  // MLIR's solver fails only where an analysis's visit does, and every
  // visit of Solve succeeds.
  [[maybe_unused]] LogicalResult ran = solver.initializeAndRun(op);
  assert(succeeded(ran) && "every visit of the escape solve succeeds");
}

} // namespace idr
