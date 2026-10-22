// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The decide step's reading of one function: its ops numbered, and, in one
// pass over them in order, what each op does with what its operands hold
// (an edge of the flow graph, or a value that must be counted), the cells
// a lifetime may take and the calls whose callee's copy may put into one.
// Where an op stands (the run it is of, whether a slot fits there) is
// carried down from the ops around it as the pass goes, never found by
// walking up.

#include "Plan.h"

#include "idr/IR/Flow.h"
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Grades.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;
using namespace idr;
using namespace idr::lifetimes::decide;

//===----------------------------------------------------------------------===//
// One function, numbered
//===----------------------------------------------------------------------===//

OpOrder::OpOrder(FuncOp fn) {
  SmallVector<std::uint32_t, 16> open;
  fn->walk([&](Operation *op, const WalkStage &stage) {
    if (stage.isBeforeAllRegions()) {
      auto at = static_cast<std::uint32_t>(ops.size());
      open.push_back(at);
      ops.push_back(op);
      ends.push_back(at + 1);
    }
    if (stage.isAfterAllRegions()) {
      ends[open.back()] = static_cast<std::uint32_t>(ops.size());
      open.pop_back();
    }
  });
}

// Past the op itself, each earlier region's ops one after another, each
// with everything in it.
OpAt OpOrder::firstIn(OpAt holder, unsigned number) const {
  std::uint32_t at = holder.index() + 1;
  Operation *op = ops[holder.index()];
  for (unsigned region = 0; region < number; ++region)
    for (Block &block : op->getRegion(region))
      for (Operation &top : block) {
        (void)top;
        at = ends[at];
      }
  return OpAt(at);
}

std::pair<OpAt, OpAt> OpOrder::positions(OpAt start, Block &block, Operation *first,
                                         Operation *last) const {
  std::uint32_t at = start.index();
  std::uint32_t firstAt = at;
  for (Operation &top : block) {
    if (&top == first)
      firstAt = at;
    if (&top == last)
      break;
    at = ends[at];
  }
  return {OpAt(firstAt), OpAt(at)};
}

//===----------------------------------------------------------------------===//
// What a function is decided into
//===----------------------------------------------------------------------===//

LifetimeKind idr::lifetimes::decide::kindOf(CopyMode mode) {
  switch (mode) {
  case CopyMode::Room:
    return LifetimeKind::room();
  case CopyMode::Cursor:
    return LifetimeKind::cursor();
  case CopyMode::Home:
    break;
  }
  return LifetimeKind::home(0);
}

CopyMode idr::lifetimes::decide::modeOf(Opening source) {
  switch (source) {
  case Opening::Block:
    return CopyMode::Room;
  case Opening::Home:
    return CopyMode::Home;
  default:
    break;
  }
  return CopyMode::Cursor;
}

bool idr::lifetimes::decide::holdsLiving(Type type) {
  return holdsReferences(type) && holdOf(type) != Hold::staticData();
}

Type idr::lifetimes::decide::scopedType(Type type) {
  return atHold(type, Hold::scoped(holdOf(type)->claim()));
}

//===----------------------------------------------------------------------===//
// What the IR says, locally
//===----------------------------------------------------------------------===//

namespace {

// Whether region `index` of `op` may run more than once per run of `op`:
// a repeated region of a region branch, or any region of an op that says
// nothing of how its regions run.
bool repeated(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return !branch || branch.isRepetitiveRegion(index);
}

// Whether `op` ends a run of a region that runs again: what it forwards is
// carried into the next run, or out of the repetition.
bool endsRepeatedRun(Operation *op) {
  if (!op->hasTrait<OpTrait::IsTerminator>())
    return false;
  Region *region = op->getParentRegion();
  return region && !isa<FuncOp>(region->getParentOp()) &&
         repeated(region->getParentOp(), region->getRegionNumber());
}

// Whether `op` makes `value`: one of its results, or an argument of a block
// of one of its regions; a terminator gives what its parent makes.
bool makes(Operation *op, Value value) {
  Operation *maker = isa<OpResult>(value)
                         ? cast<OpResult>(value).getOwner()
                         : cast<BlockArgument>(value).getOwner()->getParentOp();
  return maker == op || (op->hasTrait<OpTrait::IsTerminator>() && maker == op->getParentOp());
}

} // namespace

// The op that made a result, or the op whose region binds an argument,
// each stating it in one hop; a function's parameters live where their
// caller says.
StatesLifetimeOpInterface idr::lifetimes::decide::statedBy(Value value) {
  if (auto result = dyn_cast<OpResult>(value))
    return dyn_cast<StatesLifetimeOpInterface>(result.getOwner());
  Operation *binder = cast<BlockArgument>(value).getOwner()->getParentOp();
  return isa<FuncOp>(binder) ? StatesLifetimeOpInterface()
                             : dyn_cast<StatesLifetimeOpInterface>(binder);
}

//===----------------------------------------------------------------------===//
// Reading one function
//===----------------------------------------------------------------------===//

Planner::Planner(FuncOp fn, FunctionId self, const solver::ProgramGraph &graph,
                 const IndexVector<FunctionId, std::optional<Copies>> &copies, Reading reading,
                 solver::Work &work)
    : fn(fn), self(self), graph(graph), copies(copies), reading(reading), work(work), order(fn),
      numbering(fn), count(numbering.size()), flowEdges(count), linkedEdges(count), boxes(count) {
  solver::inWalkOrder(fn, [&](Value value) { values.push_back(value); });
}

// Every op in order, each read where it stands: the ops around it, which
// hold it, are those whose subtree has not yet ended.
void Planner::readAll() {
  SmallVector<Around, 16> around;
  for (OpAt at : order.size().ids()) {
    while (!around.empty() && !(at < order.end(around.back().at)))
      around.pop_back();
    Operation *op = order.op(at);
    Where where = around.empty() ? Where{std::nullopt, SlotHere::Fits} : inside(around.back(), op);
    read(op, at, where);
    if (op->getNumRegions() != 0)
      around.push_back({at, where});
  }
}

// Where an op of a region of `holder` stands: in the region's run if it
// runs again, else in the holder's; a slot fits where it fits at the
// holder and the region is one block of a region branch whose runs never
// overlap. The function's body is no run, and a slot fits anywhere in it.
Where Planner::inside(const Around &holder, Operation *op) {
  Region *region = op->getParentRegion();
  Operation *parent = region->getParentOp();
  if (isa<FuncOp>(parent))
    return {std::nullopt, SlotHere::Fits};
  unsigned number = region->getRegionNumber();
  RunAt run = repeated(parent, number) ? RunAt(std::pair(holder.at, number)) : holder.where.run;
  SlotHere slot = holder.where.slot == SlotHere::Fits && isa<RegionBranchOpInterface>(parent) &&
                          region->hasOneBlock() && !parent->hasTrait<OpTrait::HasParallelRegion>()
                      ? SlotHere::Fits
                      : SlotHere::DoesNot;
  return {run, slot};
}

void Planner::mustCount(Value value) {
  if (holdsLiving(value.getType()))
    fixed.push_back(node(value));
}

// What `from` holds goes into `to`.
void Planner::edge(Value from, Value to) {
  links += 3;
  flowEdges.edge(node(from), node(to));
  linkedEdges.edge(node(from), node(to));
  linkedEdges.edge(node(to), node(from));
}

// What `op` does with what its operands hold: each move it declares, an
// edge of the flow graph or a value that must be counted; each value it
// makes that no op can state a lifetime for, one that must; each cell a
// lifetime may take, and each call whose callee's copy may put into one.
void Planner::read(Operation *op, OpAt at, const Where &where) {
  for (Value result : op->getResults())
    if (!statedBy(result))
      mustCount(result);
  for (Region &region : op->getRegions())
    for (Block &block : region)
      for (BlockArgument arg : block.getArguments())
        if (!statedBy(arg))
          mustCount(arg);

  if (auto call = dyn_cast<CallOp>(op)) {
    FunctionId callee = graph.id(call.getCalleeAttr());
    // A call that continues on a frame: on its function's own cycle, not
    // in tail position, so the frames pass moves what follows it into a
    // frame.
    if (call.getTailKind() == TailKind::nontail && graph.onCycle(self) &&
        graph.sccOf(callee) == graph.sccOf(self))
      framed.push_back(at);
    const std::optional<Copies> &theirs = copies[callee];
    Call put{at, callee, {}, where.run};
    for (OpResult result : call->getResults()) {
      if (theirs && llvm::is_contained(theirs->results, result.getResultNumber()))
        put.results.push_back(node(result));
      else
        mustCount(result);
    }
    // One copy is called or none: its results are counted together.
    for (auto [a, b] : llvm::zip(put.results, llvm::drop_begin(put.results)))
      edge(valueOf(a), valueOf(b));
    if (!put.results.empty())
      calls.push_back(std::move(put));
  }

  // A fresh cell whose one use is its init, where a slot fits, a lifetime
  // may take. Its init follows it in the order, so the init reads whether
  // its box is one.
  if (auto cell = dyn_cast<CellNewOp>(op); cell && where.slot == SlotHere::Fits &&
                                           cell.getCell().hasOneUse() &&
                                           isa<CellInitOp>(*cell.getCell().user_begin())) {
    Node box = node(cell.getCell().user_begin()->getResult(0));
    if (boxes.raise(box) == Changed::Yes)
      sites.push_back({at, box, where.run});
  }
  if (auto init = dyn_cast<CellInitOp>(op); init && !boxes.test(node(init.getResult())))
    mustCount(init.getResult());

  if (!declaresFlow(op)) {
    for (Value operand : op->getOperands())
      mustCount(operand);
    return;
  }
  bool repeatedEnd = endsRepeatedRun(op);
  FlowEdges edges;
  flowEdgesOf(op, edges);
  for (const FlowEdges::Edge &each : edges.edges()) {
    const auto *move = std::get_if<FlowEdges::Flow>(&each.move);
    if (!move)
      continue;
    std::optional<Value> from = move->from.value();
    if (!from || !holdsLiving(from->getType()))
      continue;
    // A word read out of a value reaches no cell of it.
    if (std::optional<Type> moved = move->from.type(); moved && !holdsReferences(*moved))
      continue;
    if (std::holds_alternative<FlowPoint::Parameter>(move->to.at) || repeatedEnd) {
      mustCount(*from);
      continue;
    }
    if (const auto *result = std::get_if<FlowPoint::Result>(&move->to.at)) {
      // A copy puts what it returns at a position its copies may put.
      if (reading == Reading::Put && llvm::is_contained(copies[self]->results, result->index))
        returned.push_back(node(*from));
      else
        mustCount(*from);
      continue;
    }
    std::optional<Value> to = move->to.value();
    if (!to) {
      mustCount(*from);
      continue;
    }
    // Memory that exists before the op, or a part of what the op makes
    // that no reference is (an array's elements): stored where no
    // lifetime follows it.
    bool intoPart = std::holds_alternative<FlowPoint::Part>(move->to.at);
    if (!makes(op, *to) || (intoPart && !holdsReferences(to->getType()))) {
      mustCount(*from);
      continue;
    }
    if (holdsLiving(to->getType()))
      edge(*from, *to);
  }
}
