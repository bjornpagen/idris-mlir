// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lifetimes: the decide step. Every lifetime is born decided: this
// step writes each opener, its kind and the slots stated in it at once, so
// no lifetime is ever undecided in the IR.
//
// A cell idr.cell.new makes in counted memory is made in a lifetime
// instead, as upstream's promote-buffers-to-stack makes a memref.alloc a
// memref.alloca, when nothing the cell's box reaches leaves the lifetime:
// no such value is returned, passed to a call, stored into memory that
// outlives it, carried into the next run of a region that runs again, held
// by a counted cell, or made by an op that cannot state where it lives.
// Each function is decided alone, over its own values: a value escapes when
// it reaches an escape along the moves its ops declare, one backward marking
// over the function's flow graph, never a set per value and never the whole
// program's graph. A call's parameters are counted until the borrow marking
// makes them views, so a box passed to a call escapes.
//
// A cell its function makes once per activation becomes a slot of the
// activation's lifetime (`idr.cell.stack in %activation`); one made in a
// region that runs again, a slot of a lifetime opened around each run of
// the innermost such region, its frame-limited proof that count: the slot
// is written once per run, and nothing of a run is carried into the next.
// No slot's lifetime spans a call that continues on a frame (a call on its
// function's own cycle not in tail position): its native frame is gone
// when the frame resumes, so the slot could not survive it. A lifetime of
// one recursion level is a stack or a chain, packed around the push, never
// a slot or a block, whose cells cannot move into a frame.
// What the box reaches is then graded `scoped`, and the op that makes each
// such value states the lifetime. A cell that stays in counted memory is
// the same cell there: this step decides where memory comes from, never
// what compiles.
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Flow.h"
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Lifetimes.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <span>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRLIFETIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace idr;

namespace {

// One function's values, numbered once by the solver layer's walk.
struct Values {
  using Minter = solver::Numbering<Values>;
};
using Node = Id<Values>;

// Whether region `index` of `op` may run more than once per run of `op`:
// a repeated region of a region branch, or any region of an op that says
// nothing of how its regions run.
bool repeated(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return !branch || branch.isRepetitiveRegion(index);
}

// Whether a slot can stand where `op` is: every region from it up to its
// function's body is the one block of a region branch whose runs never
// overlap, so the slot is written once per run of the region around it.
bool placeable(Operation *op) {
  for (Region *region = op->getParentRegion(); region;
       region = region->getParentOp()->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (isa<FuncOp>(parent))
      return true;
    if (!isa<RegionBranchOpInterface>(parent) || !region->hasOneBlock() ||
        parent->hasTrait<OpTrait::HasParallelRegion>())
      return false;
  }
  return false;
}

// The innermost region around `op` that runs again within its function, or
// none: the lifetime a slot there is per run of.
Region *runRegion(Operation *op) {
  for (Region *region = op->getParentRegion(); region && !isa<FuncOp>(region->getParentOp());
       region = region->getParentOp()->getParentRegion())
    if (repeated(region->getParentOp(), region->getRegionNumber()))
      return region;
  return nullptr;
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

// The op that would state where `value` lives, if it can: the op that made
// a result, or the op whose region binds an argument; a function's
// parameters live where their caller says.
StatesLifetimeOpInterface statedBy(Value value) {
  if (auto result = dyn_cast<OpResult>(value))
    return dyn_cast<StatesLifetimeOpInterface>(result.getOwner());
  Operation *binder = cast<BlockArgument>(value).getOwner()->getParentOp();
  return isa<FuncOp>(binder) ? nullptr : dyn_cast<StatesLifetimeOpInterface>(binder);
}

// A cell of the function to decide: its source, the box its init makes,
// and the run of the region it would be a slot of (none: the activation).
struct Candidate {
  CellNewOp cell;
  Node box;
  Region *run;
};

// One function's decision: its flow graph over its values, the values that
// escape, and the cells that stay in a lifetime.
class Decision {
public:
  Decision(FuncOp fn, const solver::ProgramGraph &calls)
      : fn(fn), calls(calls), self(calls.id(fn)), numbering(fn), count(numbering.size()),
        graph(count) {}

  // Decides and writes the function; how many lifetimes it opened. Every
  // fact is read before the first write: the numbering's map is gone once
  // it hands back the function's values.
  unsigned run() {
    SmallVector<Node> seeds;
    fn->walk([&](Operation *op) { read(op, seeds); });
    IndexVector<Node, Value> values = std::move(numbering).finish().values;
    Csr<Values> flow = std::move(graph).finish();
    BitSet<Node> escaping = mark<Backward>(flow, std::span<const Node>(seeds));

    // Each placed cell's box, grouped by the run it is a slot of: the
    // activation's group first, then the regions that run again, outer
    // ones first, so a value an inner run's box reaches is stated in the
    // inner lifetime, the one it cannot outlive.
    SmallVector<std::pair<Region *, SmallVector<Candidate>>> groups;
    for (const Candidate &candidate : candidates)
      if (!escaping.test(candidate.box) && !spansFramedCall(candidate.run)) {
        auto group = llvm::find_if(groups, [&](const auto &g) { return g.first == candidate.run; });
        if (group == groups.end()) {
          groups.push_back({candidate.run, {}});
          group = std::prev(groups.end());
        }
        group->second.push_back(candidate);
      }
    llvm::stable_sort(groups, [](const auto &a, const auto &b) {
      return depthOf(a.first) < depthOf(b.first);
    });

    for (auto &[run, placed] : groups) {
      Value lifetime = run ? openRun(*run) : activation();
      SmallVector<Node> boxes;
      for (const Candidate &candidate : placed)
        boxes.push_back(candidate.box);
      BitSet<Node> reached = mark<Forward>(flow, std::span<const Node>(boxes));
      for (Node node : count.ids())
        if (reached.test(node))
          scope(values[node], lifetime);
      for (Candidate &candidate : placed) {
        OpBuilder b(candidate.cell);
        auto slot = CellStackOp::create(b, candidate.cell.getLoc(), candidate.cell.getCell().getType(),
                                        lifetime);
        candidate.cell.getCell().replaceAllUsesWith(slot.getCell());
        candidate.cell.erase();
      }
    }
    return static_cast<unsigned>(groups.size());
  }

private:
  static unsigned depthOf(Region *region) {
    unsigned depth = 0;
    for (; region; region = region->getParentRegion())
      ++depth;
    return depth;
  }

  // Whether the lifetime a slot in `run` would be (the activation, for
  // none) holds a call that continues on a frame.
  bool spansFramedCall(Region *run) const {
    return llvm::any_of(framed, [&](Operation *call) {
      return !run || run->isAncestor(call->getParentRegion());
    });
  }

  // An escape: `value` goes where no lifetime of this function follows it.
  void escape(Value value, SmallVectorImpl<Node> &seeds) {
    if (holdsReferences(value.getType()))
      seeds.push_back(numbering.at(value));
  }

  // What `op` does with what its operands hold: each move it declares, an
  // edge of the flow graph or an escape; each value it makes that no op
  // can state a lifetime for, an escape; and each candidate cell.
  void read(Operation *op, SmallVectorImpl<Node> &seeds) {
    for (Value result : op->getResults())
      if (holdsReferences(result.getType()) && !statedBy(result))
        escape(result, seeds);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          if (holdsReferences(arg.getType()) && !statedBy(arg))
            escape(arg, seeds);

    // A call that continues on a frame: on its function's own cycle, not in
    // tail position, so the frames pass moves what follows it into a frame.
    if (auto call = dyn_cast<CallOp>(op); call && call.getTail() == TailKind::NonTail &&
                                          calls.onCycle(self) &&
                                          calls.sccOf(calls.id(call.getCalleeAttr())) ==
                                              calls.sccOf(self))
      framed.push_back(op);

    if (auto cell = dyn_cast<CellNewOp>(op)) {
      Value value = cell.getCell();
      if (placeable(op) && value.hasOneUse())
        if (Operation *init = *value.user_begin(); init->getNumResults() != 0)
          candidates.push_back({cell, numbering.at(init->getResult(0)), runRegion(op)});
    }
    // A box made in a cell no lifetime takes is counted, and so is what it
    // holds.
    if (auto init = dyn_cast<CellInitOp>(op); init && !init.getCell().getDefiningOp<CellNewOp>())
      escape(init.getResult(), seeds);

    if (!declaresFlow(op)) {
      for (Value operand : op->getOperands())
        escape(operand, seeds);
      return;
    }
    bool repeatedEnd = endsRepeatedRun(op);
    FlowEdges edges;
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges()) {
      const auto *move = std::get_if<FlowEdges::Flow>(&edge.move);
      if (!move)
        continue;
      std::optional<Value> from = move->from.value();
      if (!from || !holdsReferences(from->getType()))
        continue;
      // A word read out of a value reaches no cell of it.
      if (std::optional<Type> moved = move->from.type(); moved && !holdsReferences(*moved))
        continue;
      if (std::holds_alternative<FlowPoint::Parameter>(move->to.at) ||
          std::holds_alternative<FlowPoint::Result>(move->to.at) || repeatedEnd) {
        escape(*from, seeds);
        continue;
      }
      std::optional<Value> to = move->to.value();
      if (!to) {
        escape(*from, seeds);
        continue;
      }
      // Memory that exists before the op, or a part of what the op makes
      // that no reference is (an array's elements): stored where no
      // lifetime follows it.
      bool intoPart = std::holds_alternative<FlowPoint::Part>(move->to.at);
      if (!makes(op, *to) || (intoPart && !holdsReferences(to->getType()))) {
        escape(*from, seeds);
        continue;
      }
      if (holdsReferences(to->getType()))
        graph.edge(numbering.at(*from), numbering.at(*to));
    }
  }

  // The function's activation lifetime, opened once at the top of its
  // body.
  Value activation() {
    OpBuilder b = OpBuilder::atBlockBegin(&fn.getBody().front());
    return ActivationOp::create(b, fn.getLoc(),
                                LifetimeType::get(fn.getContext(), LifetimeKind::view()))
        .getLifetime();
  }

  // A lifetime around each run of `run`'s one block: every op but its
  // terminator moves into an `idr.lifetime`, which yields what the
  // terminator gave on. What a terminator of a run gives on escapes every
  // lifetime, so no yielded value is scoped and the opener states no outer
  // lifetime.
  Value openRun(Region &run) {
    Block &block = run.front();
    Operation *terminator = block.getTerminator();
    OpBuilder b(terminator);
    Location loc = terminator->getLoc();
    auto opener = LifetimeOp::create(b, loc, terminator->getOperandTypes(), /*outer=*/Value());
    Block *body = new Block();
    opener.getBody().push_back(body);
    Value lifetime = body->addArgument(LifetimeType::get(fn.getContext(), LifetimeKind::view()), loc);
    body->getOperations().splice(body->end(), block.getOperations(), block.begin(),
                                 Block::iterator(opener));
    OpBuilder inside = OpBuilder::atBlockEnd(body);
    YieldOp::create(inside, loc, terminator->getOperands());
    terminator->setOperands(opener.getResults());
    return lifetime;
  }

  // `value` lives in `lifetime`: its hold is scoped, with what it claimed
  // of its sharing, and the op that makes it states where.
  static void scope(Value value, Value lifetime) {
    std::optional<Hold> hold = holdOf(value.getType());
    if (!hold)
      return;
    value.setType(atHold(value.getType(), Hold::scoped(hold->claim())));
    statedBy(value).setStatedLifetime(value, lifetime);
  }

  FuncOp fn;
  const solver::ProgramGraph &calls;
  solver::FunctionId self;
  solver::Numbering<Values> numbering;
  Count<Node> count;
  CsrBuilder<Values> graph;
  SmallVector<Candidate> candidates;
  SmallVector<Operation *> framed;
};

// The decide step, then the one writer of rows: a lifetime's end drops its
// cells' owned fields, an effect on counts the functions did not have.
struct IdrLifetimes : impl::IdrLifetimesBase<IdrLifetimes> {
  void runOnProgram(ProgramOp program) override {
    const solver::ProgramGraph &calls = getAnalysis<solver::ProgramGraph>();
    for (FuncOp fn : program.getOps<FuncOp>())
      numLifetimes += Decision(fn, calls).run();
    rows::write(program, calls);
  }
};

} // namespace
