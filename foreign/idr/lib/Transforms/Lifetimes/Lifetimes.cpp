// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lifetimes: the decide step. Every lifetime is born decided: this step
// writes each opener, its kind, the slots and cells stated in it, the calls
// that put into it, every copy of a function by the kind of lifetime it is
// given and that copy's signature, at once, so no lifetime is ever
// undecided in the IR.
//
// A cell idr.cell.new makes in counted memory is made in a lifetime
// instead, as upstream's promote-buffers-to-stack makes a memref.alloc a
// memref.alloca, when nothing its box reaches must be counted. A value must
// be counted when it goes where no lifetime of the function follows it (it
// is returned, passed to a call, stored into memory that outlives it,
// carried into the next run of a region that runs again), when nothing can
// state where it lives (a parameter, a counted call's result, a value of an
// op with no lifetime operand), and when it is made of such a value or
// made into one: a cell of a lifetime holds no counted field, since a
// lifetime's end frees its memory and drops nothing, and a value merging a
// counted one with a cell of a lifetime would have no one grade. So the
// values that must be counted are everything the flow graph links to those,
// whichever way the link goes: one marking over the function's values,
// never a set per value and never the whole program's graph.
//
// A call puts into a lifetime of its caller what its callee's copy for that
// lifetime's kind gives: a copy is its owner with one more parameter, the
// lifetime, into which it puts each cell whose box reaches only what it
// returns, those results living there. A copy for a room puts a bounded
// amount (each cell once, each callee's copy a room's); one for a cursor or
// a home takes every value it makes there into what it gives back on every
// path, so a caller's lifetime keeps no garbage of it. Each function is
// decided callees first, a component of the call graph from the most every
// member's copy could put, shrinking until none does; then its own body,
// where each call whose results nothing counted reaches is the copy's.
//
// A run (the function's body, or a region that runs again) gets one
// lifetime for its cells and calls: this activation when only slots are
// stated in it and no call of the function continues on a frame; an opener
// with no memory around the ops that use it when only slots are; a block of
// the frame when every call puts a bounded amount; the shard's home when
// the run is the root's body; a cursor otherwise, on the stack of the
// cursor around it where there is one, else its own chain. A lifetime that
// spans a call continuing on a frame is a cursor's, its cells bumped there,
// never slots or a block, which cannot move into a frame. A cursor's or a
// home's calls stand at the top of its region, and each value one gives is
// used again after every allocation that follows it. A run whose lifetime
// would hold a call in tail position, or a jump out of it, keeps its cells
// counted. What the lifetime holds is then graded `scoped`, and the op that
// makes each such value states the lifetime.
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Flow.h"
#include "idr/IR/FlowEdges.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Verify.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Lifetimes.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <utility>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRLIFETIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace idr;
using solver::FunctionId;

namespace {

//===----------------------------------------------------------------------===//
// One function, numbered
//===----------------------------------------------------------------------===//

// One function's values, numbered once by the solver layer's walk.
struct Values {
  using Minter = solver::Numbering<Values>;
};
using Node = Id<Values>;

// One function's ops in pre-order, each with where its subtree ends: a
// position names an op in the function and in every clone of it, which has
// its shape, and the ops from one sibling to a later one, with everything in
// them, are the positions between. The map from an op to its position lives
// as long as the order, one function's.
class OpOrder;
struct OpTag {
  using Minter = OpOrder;
};
using OpAt = Id<OpTag>;

class OpOrder {
public:
  explicit OpOrder(FuncOp fn) {
    SmallVector<std::uint32_t, 16> open;
    fn->walk([&](Operation *op, const WalkStage &stage) {
      if (stage.isBeforeAllRegions()) {
        auto at = static_cast<std::uint32_t>(ops.size());
        open.push_back(at);
        index.try_emplace(op, at);
        ops.push_back(op);
        ends.push_back(at + 1);
      }
      if (stage.isAfterAllRegions()) {
        ends[open.back()] = static_cast<std::uint32_t>(ops.size());
        open.pop_back();
      }
    });
  }

  Operation *op(OpAt at) const { return ops[at.index()]; }
  OpAt at(Operation *op) const { return OpAt(index.find(op)->second); }

  // The ops from `first` to `last`, siblings in that order, and everything
  // in them.
  ArrayRef<Operation *> span(OpAt first, OpAt last) const {
    return ArrayRef<Operation *>(ops).slice(first.index(), ends[last.index()] - first.index());
  }
  bool within(Operation *op, OpAt first, OpAt last) const {
    std::uint32_t at = index.find(op)->second;
    return first.index() <= at && at < ends[last.index()];
  }

private:
  footprint::Vector<Operation *> ops;
  footprint::Vector<std::uint32_t> ends;
  llvm::DenseMap<Operation *, std::uint32_t> index;
};

//===----------------------------------------------------------------------===//
// What a function is decided into
//===----------------------------------------------------------------------===//

// The kind a copy's lifetime parameter is compiled for, as its caller's
// lifetime is: a room, a cursor, or the shard's home of the root's one site,
// the only home site, so its number is 0.
enum class CopyMode : std::uint8_t { Room, Cursor, Home };

constexpr std::array<CopyMode, 3> everyMode{CopyMode::Room, CopyMode::Cursor, CopyMode::Home};

LifetimeKind kindOf(CopyMode mode) {
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

// The kinds a function's copies may be compiled for.
class CopyModes {
public:
  static constexpr CopyModes none() { return CopyModes(0); }
  static constexpr CopyModes all() { return CopyModes(0b111); }
  constexpr CopyModes with(CopyMode mode) const { return CopyModes(static_cast<std::uint8_t>(bits | bit(mode))); }
  constexpr bool contains(CopyMode mode) const { return (bits & bit(mode)) != 0; }
  constexpr CopyModes without(CopyMode mode) const {
    return CopyModes(static_cast<std::uint8_t>(bits & ~bit(mode)));
  }
  constexpr bool empty() const { return bits == 0; }
  constexpr bool operator==(const CopyModes &) const = default;

private:
  constexpr explicit CopyModes(std::uint8_t bits) : bits(bits) {}
  static constexpr std::uint8_t bit(CopyMode mode) {
    return static_cast<std::uint8_t>(1u << static_cast<unsigned>(mode));
  }
  std::uint8_t bits;
};

// What a caller reads of a callee's copies: the kinds one may be compiled
// for, and which of its results a copy puts into its lifetime.
struct Copies {
  CopyModes modes;
  SmallVector<unsigned, 2> results;
  bool operator==(const Copies &) const = default;
};

// Where a run's lifetime comes from: this activation (no region, a view);
// an opener with no memory, a view; a block of the frame, a room; the
// shard's home; or a cursor's bump, on the stack of the cursor around it
// where there is one, else its own chain.
enum class Opening : std::uint8_t { Activation, NoMemory, Block, Home, Cursor };

// The kind of copy a call into a lifetime of `source` takes.
CopyMode modeOf(Opening source) {
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

// How a run's cells are stated in its lifetime: slots of the frame, or
// bumped into the lifetime, for a lifetime that a frame may carry.
enum class Cells : std::uint8_t { Slots, Bumped };

// A call that puts what it gives into a lifetime: the copy of `callee` for
// that lifetime's kind is called instead.
struct PutCall {
  OpAt call;
  FunctionId callee;
};

// One run's lifetime: the region that runs (none: the function's body), its
// source, how its cells are stated, the cells (their idr.cell.new) and the
// calls it takes, the ops it spans (none for the activation, the rest of
// the body), and the values that live in it, in walk order.
struct Group {
  std::optional<std::pair<OpAt, unsigned>> run;
  Opening source = Opening::Activation;
  Cells cells = Cells::Slots;
  SmallVector<OpAt, 4> sites;
  SmallVector<PutCall, 2> calls;
  std::optional<std::pair<OpAt, OpAt>> extent;
  SmallVector<Node, 8> scoped;
};

// What a copy puts into its lifetime parameter: its cells and calls there,
// the values that live there, the results that do, and the kinds it may be
// compiled for.
struct PutForm {
  SmallVector<OpAt, 4> sites;
  SmallVector<PutCall, 2> calls;
  SmallVector<Node, 8> scoped;
  SmallVector<unsigned, 2> results;
  CopyModes modes = CopyModes::all();
};

// A function decided: its runs' lifetimes, outer runs first, and, for its
// copies, what each puts into its lifetime parameter. Every position is
// the function's as it was read, so the plan writes the function and every
// clone of it alike.
struct Plan {
  SmallVector<Group, 4> groups;
  std::optional<PutForm> put;
};

//===----------------------------------------------------------------------===//
// What the IR says, locally
//===----------------------------------------------------------------------===//

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
// none: the run whose lifetime a cell or a call there is of.
Region *runRegion(Operation *op) {
  for (Region *region = op->getParentRegion(); region && !isa<FuncOp>(region->getParentOp());
       region = region->getParentOp()->getParentRegion())
    if (repeated(region->getParentOp(), region->getRegionNumber()))
      return region;
  return nullptr;
}

unsigned depthOf(Region *region) {
  unsigned depth = 0;
  for (; region; region = region->getParentRegion())
    ++depth;
  return depth;
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

// Whether a value of `type` holds a reference a lifetime could hold:
// static data never needs one, and is linked to nothing.
bool holdsLiving(Type type) {
  return holdsReferences(type) && holdOf(type) != Hold::staticData();
}

// The cell source a cell.init fills, when a lifetime may take it: a fresh
// cell whose one use is its init, where a slot can stand.
CellNewOp candidateSource(Value cell) {
  auto source = cell.getDefiningOp<CellNewOp>();
  return source && cell.hasOneUse() && isa<CellInitOp>(*cell.user_begin()) && placeable(source)
             ? source
             : CellNewOp();
}

//===----------------------------------------------------------------------===//
// Deciding one function
//===----------------------------------------------------------------------===//

// What became of a cell or a call a lifetime might take: still its, or
// counted for good.
enum class Fate : std::uint8_t { Open, Counted };

// Whether the body's own lifetime may be an opener: in a copy that puts
// into its parameter, a region at the top of its body would carry values of
// the parameter out through its yield, where what keeps them would lie
// inside the region, so its body's cells and calls there use the
// activation or stay counted.
enum class BodyOpener : std::uint8_t { Allowed, Refused };

// How a function's returns are read: its own body's, which give its callers
// counted values; or its copies', which put what they give at the result
// positions its copies may put into the lifetime parameter.
enum class Reading : std::uint8_t { Counted, Put };

class Planner {
public:
  Planner(FuncOp fn, FunctionId self, const solver::ProgramGraph &graph,
          const IndexVector<FunctionId, std::optional<Copies>> &copies, Reading reading,
          solver::Work &work)
      : fn(fn), self(self), graph(graph), copies(copies), reading(reading), work(work), order(fn),
        numbering(fn), count(numbering.size()), flowEdges(count), linkedEdges(count) {
    solver::inWalkOrder(fn, [&](Value value) { values.push_back(value); });
  }

  Plan plan() {
    fn->walk<WalkOrder::PreOrder>([&](Operation *op) { read(op); });
    flow.emplace(std::move(flowEdges).finish());
    Csr<Values> linked = std::move(linkedEdges).finish();
    BitSet<Node> reachesReturn = marked<Backward>(*flow, returned);

    footprint::Vector<Fate> siteFates(sites.size(), Fate::Open), callFates(calls.size(), Fate::Open);
    // Each round either makes a cell or a call counted for good or decides
    // every run: it ends after a round per cell and call at most, and in
    // one where nothing more is counted.
    for (;;) {
      footprint::Vector<Node> seeds(fixed.begin(), fixed.end());
      for (auto [at, site] : llvm::enumerate(sites))
        if (siteFates[at] == Fate::Counted)
          seeds.push_back(site.box);
      for (auto [at, call] : llvm::enumerate(calls))
        if (callFates[at] == Fate::Counted)
          llvm::append_range(seeds, call.results);
      BitSet<Node> mustCount = marked<Forward>(linked, seeds);
      for (auto [at, site] : llvm::enumerate(sites))
        if (mustCount.test(site.box))
          siteFates[at] = Fate::Counted;
      for (auto [at, call] : llvm::enumerate(calls))
        if (llvm::any_of(call.results, [&](Node result) { return mustCount.test(result); }))
          callFates[at] = Fate::Counted;

      // Each run's cells and calls that stay in this function; what a copy
      // returns is its parameter's.
      auto putHere = [&](Node node) { return reading == Reading::Put && reachesReturn.test(node); };
      SmallVector<Draft, 4> drafts;
      auto draftOf = [&](Region *run) -> Draft & {
        auto found = llvm::find_if(drafts, [&](const Draft &draft) { return draft.run == run; });
        if (found != drafts.end())
          return *found;
        drafts.push_back({run, {}, {}});
        return drafts.back();
      };
      Draft putDraft{nullptr, {}, {}};
      for (auto [at, site] : llvm::enumerate(sites))
        if (siteFates[at] == Fate::Open)
          (putHere(site.box) ? putDraft : draftOf(site.run)).sites.push_back(at);
      for (auto [at, call] : llvm::enumerate(calls))
        if (callFates[at] == Fate::Open)
          (putHere(call.results.front()) ? putDraft : draftOf(call.run)).calls.push_back(at);
      llvm::stable_sort(drafts, [](const Draft &a, const Draft &b) {
        return depthOf(a.run) < depthOf(b.run);
      });

      BodyOpener opener = putDraft.sites.empty() && putDraft.calls.empty() ? BodyOpener::Allowed
                                                                          : BodyOpener::Refused;
      Plan made;
      bool demoted = false;
      for (const Draft &draft : drafts) {
        std::optional<Group> group = decide(draft, opener, siteFates, callFates);
        if (group)
          made.groups.push_back(std::move(*group));
        else
          demoted = true;
      }
      if (demoted)
        continue;
      if (reading == Reading::Put)
        made.put = putForm(putDraft);
      return made;
    }
  }

private:
  // A cell a lifetime may take: its source, the box its init makes, and the
  // run it is of.
  struct Site {
    OpAt source;
    Node box;
    Region *run;
  };
  // A call whose callee's copy may put its results into a lifetime.
  struct Call {
    OpAt op;
    FunctionId callee;
    SmallVector<Node, 2> results;
    Region *run;
  };
  // One run's cells and calls, as positions in `sites` and `calls`.
  struct Draft {
    Region *run;
    SmallVector<unsigned, 4> sites;
    SmallVector<unsigned, 2> calls;
  };

  Node node(Value value) const { return numbering.at(value); }
  Value valueOf(Node node) const { return values[node.index()]; }

  // One marking of the function's values, its steps counted: each value
  // and each link at most once.
  template <Direction D, class Seeds>
  BitSet<Node> marked(const Csr<Values> &graph, const Seeds &seeds) {
    work.add(std::uint64_t{count.value()} + links);
    return mark<D>(graph, std::span<const Node>(seeds.data(), seeds.size()));
  }

  void mustCount(Value value) {
    if (holdsLiving(value.getType()))
      fixed.push_back(node(value));
  }

  // What `from` holds goes into `to`.
  void edge(Value from, Value to) {
    links += 3;
    flowEdges.edge(node(from), node(to));
    linkedEdges.edge(node(from), node(to));
    linkedEdges.edge(node(to), node(from));
  }

  // What `op` does with what its operands hold: each move it declares, an
  // edge of the flow graph or a value that must be counted; each value it
  // makes that no op can state a lifetime for, one that must; each cell a
  // lifetime may take, and each call whose callee's copy may put into one.
  void read(Operation *op) {
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
        framed.push_back(order.at(op));
      const std::optional<Copies> &theirs = copies[callee];
      Call put{order.at(op), callee, {}, runRegion(op)};
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

    if (auto cell = dyn_cast<CellNewOp>(op); cell && candidateSource(cell.getCell()))
      sites.push_back({order.at(op), node(cell.getCell().user_begin()->getResult(0)), runRegion(op)});
    if (auto init = dyn_cast<CellInitOp>(op); init && !candidateSource(init.getCell()))
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
        if (reading == Reading::Put &&
            llvm::is_contained(copies[self]->results, result->index))
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

  // Whether a lifetime may span the ops from `first` to `last`: it holds no
  // call in tail position, whose return would follow the lifetime's end,
  // and no jump to a join point outside it, which no lifetime lets through.
  bool spannable(OpAt first, OpAt last) const {
    for (Operation *op : order.span(first, last)) {
      if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() != TailKind::nontail)
        return false;
      for (Value operand : op->getOperands())
        if (isa<mlir::TokenType>(operand.getType()))
          if (auto token = dyn_cast<BlockArgument>(operand);
              !token || !order.within(token.getOwner()->getParentOp(), first, last))
            return false;
    }
    return true;
  }

  // One run's lifetime, or none when a cell or a call of it is counted.
  std::optional<Group> decide(const Draft &draft, BodyOpener opener,
                              footprint::Vector<Fate> &siteFates, footprint::Vector<Fate> &callFates) {
    Block &block = draft.run ? draft.run->front() : fn.getBody().front();
    bool body = !draft.run;
    SmallVector<Node, 8> roots;
    for (unsigned at : draft.sites)
      roots.push_back(sites[at].box);
    for (unsigned at : draft.calls)
      llvm::append_range(roots, calls[at].results);
    BitSet<Node> reach = marked<Forward>(*flow, roots);

    // The ops of the run the lifetime spans: from its first cell or call to
    // the last use of a value that lives in it, each seen at the run's top.
    std::optional<OpAt> first, last;
    auto widen = [&](Operation *op) {
      Operation *top = block.findAncestorOpInBlock(*op);
      if (!top)
        return;
      OpAt at = order.at(top);
      if (!first || at < *first)
        first = at;
      if (!last || *last < at)
        last = at;
    };
    for (unsigned at : draft.sites)
      widen(order.op(sites[at].source));
    for (unsigned at : draft.calls)
      widen(order.op(calls[at].op));
    for (Node n : count.ids())
      if (reach.test(n))
        for (Operation *user : valueOf(n).getUsers())
          widen(user);
    bool framedHere = llvm::any_of(framed, [&](OpAt call) {
      return order.within(order.op(call), *first, *last);
    });

    Group group;
    if (draft.run)
      group.run = std::pair(order.at(draft.run->getParentOp()), draft.run->getRegionNumber());
    bool allRooms = llvm::all_of(draft.calls, [&](unsigned at) {
      return copies[calls[at].callee]->modes.contains(CopyMode::Room);
    });
    if (framedHere) {
      group.source = Opening::Cursor;
      group.cells = Cells::Bumped;
    } else if (draft.calls.empty()) {
      group.source = body && framed.empty() ? Opening::Activation : Opening::NoMemory;
    } else if (allRooms) {
      group.source = Opening::Block;
    } else {
      group.source = body && fn.isRoot() ? Opening::Home : Opening::Cursor;
    }
    if (group.source != Opening::Activation) {
      group.extent = std::pair(*first, *last);
      if ((body && opener == BodyOpener::Refused) || !spannable(*first, *last)) {
        for (unsigned at : draft.sites)
          siteFates[at] = Fate::Counted;
        for (unsigned at : draft.calls)
          callFates[at] = Fate::Counted;
        return std::nullopt;
      }
    }

    // A cursor's or a home's call stands at the top of its region, and what
    // it gives is used again after every allocation that follows it there.
    if (group.source == Opening::Cursor || group.source == Opening::Home) {
      bool demoted = false;
      Operation *end = order.op(*last);
      for (unsigned at : draft.calls) {
        const Call &call = calls[at];
        bool holds = copies[call.callee]->modes.contains(modeOf(group.source)) &&
                     order.op(call.op)->getBlock() == &block &&
                     llvm::all_of(call.results, [&](Node result) {
                       return verify::usedAfterEveryAllocation(valueOf(result), end);
                     });
        if (!holds) {
          callFates[at] = Fate::Counted;
          demoted = true;
        }
      }
      if (demoted)
        return std::nullopt;
    }

    for (unsigned at : draft.sites)
      group.sites.push_back(sites[at].source);
    for (unsigned at : draft.calls)
      group.calls.push_back({calls[at].op, calls[at].callee});
    for (Node n : count.ids())
      if (reach.test(n))
        group.scoped.push_back(n);
    return group;
  }

  // What a copy puts into its lifetime parameter: the cells and calls whose
  // values reach what it returns at the positions its copies may put. A
  // room's copy puts each cell once and calls only rooms' copies outside its
  // own component; a cursor's or a home's takes every value it makes there
  // into what it gives back on every path, and calls only copies that do.
  std::optional<PutForm> putForm(const Draft &draft) {
    auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator());
    if (!ret || (draft.sites.empty() && draft.calls.empty()))
      return std::nullopt;
    SmallVector<Node, 8> roots;
    for (unsigned at : draft.sites)
      roots.push_back(sites[at].box);
    for (unsigned at : draft.calls)
      llvm::append_range(roots, calls[at].results);
    BitSet<Node> reach = marked<Forward>(*flow, roots);

    PutForm form;
    for (auto [index, operand] : llvm::enumerate(ret.getOperands()))
      if (holdsLiving(operand.getType()) && reach.test(node(operand)))
        form.results.push_back(static_cast<unsigned>(index));
    if (form.results.empty())
      return std::nullopt;

    auto lives = [&](Value value) { return reach.test(node(value)); };
    auto returnedHere = [&](unsigned result) { return llvm::is_contained(form.results, result); };
    bool bounded = llvm::all_of(draft.calls, [&](unsigned at) {
      FunctionId callee = calls[at].callee;
      return graph.sccOf(callee) != graph.sccOf(self) &&
             copies[callee]->modes.contains(CopyMode::Room);
    });
    bool kept = llvm::all_of(draft.calls,
                             [&](unsigned at) {
                               return copies[calls[at].callee]->modes.contains(CopyMode::Cursor);
                             }) &&
                llvm::all_of(count.ids(), [&](Node n) {
                  Value value = valueOf(n);
                  return !reach.test(n) || !isa<OpResult>(value) ||
                         verify::takenIntoResult(value, lives, returnedHere);
                });
    form.modes = copies[self]->modes;
    if (!bounded)
      form.modes = form.modes.without(CopyMode::Room);
    if (!kept)
      form.modes = form.modes.without(CopyMode::Cursor).without(CopyMode::Home);
    if (form.modes.empty())
      return std::nullopt;

    for (unsigned at : draft.sites)
      form.sites.push_back(sites[at].source);
    for (unsigned at : draft.calls)
      form.calls.push_back({calls[at].op, calls[at].callee});
    for (Node n : count.ids())
      if (reach.test(n))
        form.scoped.push_back(n);
    return form;
  }

  FuncOp fn;
  FunctionId self;
  const solver::ProgramGraph &graph;
  const IndexVector<FunctionId, std::optional<Copies>> &copies;
  Reading reading;
  solver::Work &work;
  OpOrder order;
  solver::Numbering<Values> numbering;
  Count<Node> count;
  footprint::Vector<Value> values;
  CsrBuilder<Values> flowEdges;
  CsrBuilder<Values> linkedEdges;
  std::uint64_t links = 0;
  std::optional<Csr<Values>> flow;
  footprint::Vector<Node> fixed;
  footprint::Vector<Node> returned;
  footprint::Vector<Site> sites;
  footprint::Vector<Call> calls;
  footprint::Vector<OpAt> framed;
};

//===----------------------------------------------------------------------===//
// The copies, by the kind of lifetime they are given
//===----------------------------------------------------------------------===//

// A copy is keyed by its function type, its owner's with one more
// parameter, the lifetime of the kind it is compiled for, and with the
// results it puts there scoped: the type is uniqued, so equal keys are one
// copy, and the name its digest gives is the same on any machine.
struct ModeKey {
  FunctionId owner;
  FunctionType signature;
};

struct Modes {
  using Key = ModeKey;
  using Order = specialize::Equality;
  static constexpr llvm::StringLiteral kind = "mode";
  static FunctionId owner(const Key &key) { return key.owner; }
  static void write(const Key &key, specialize::Bytes &bytes) { bytes.type(key.signature); }
  // The lifetime parameter goes last, and every scoped result lives in it.
  static LogicalResult edit(const Key &key, FuncOp clone) {
    unsigned at = clone.getNumArguments();
    if (failed(clone.insertArgument(at, key.signature.getInputs().back(), DictionaryAttr(),
                                    clone.getLoc())))
      return failure();
    clone.setFunctionType(key.signature);
    SmallVector<LivesIn, 2> results;
    for (auto [index, type] : llvm::enumerate(key.signature.getResults()))
      if (freedBy(type, Release::Scoped))
        results.push_back({static_cast<std::uint32_t>(index), at});
    clone.setLivesInAttr(LivesInAttr::get(clone.getContext(), {}, results, {}));
    return success();
  }
};
static_assert(specialize::KeyAlphabet<Modes>);

// `type` living in a lifetime, with what it claims of its sharing.
Type scopedType(Type type) { return atHold(type, Hold::scoped(holdOf(type)->claim())); }

//===----------------------------------------------------------------------===//
// Writing a plan
//===----------------------------------------------------------------------===//

// `value` lives in `lifetime`: its hold is scoped, with what it claimed of
// its sharing, and the op that makes it states where, each scoped result
// its own. Runs are written outer first, so a value two runs' lifetimes
// reach is given the inner last, the one its cells of both outlive.
void scope(Value value, Value lifetime) {
  if (!holdOf(value.getType()))
    return;
  value.setType(scopedType(value.getType()));
  if (StatesLifetimeOpInterface states = statedBy(value))
    states.setStatedLifetime(value, lifetime);
}

class Writer {
public:
  explicit Writer(const IndexVector<FunctionId, std::array<FuncOp, 3>> &made) : made(made) {}

  // Writes `plan` into `target`, the function it was made of or a clone of
  // it, whose lifetime parameter is `parameter` for a copy; how many
  // lifetimes it opened.
  unsigned write(FuncOp target, const Plan &plan, std::optional<std::pair<Value, CopyMode>> parameter) {
    // Every op and value the plan names, read before anything is written.
    OpOrder order(target);
    footprint::Vector<Value> values;
    solver::inWalkOrder(target, [&](Value value) { values.push_back(value); });

    std::optional<Resolved> put;
    if (plan.put && parameter)
      put = resolve(order, values, plan.put->sites, plan.put->calls, plan.put->scoped);
    SmallVector<std::pair<const Group *, Resolved>, 4> groups;
    for (const Group &group : plan.groups)
      groups.emplace_back(&group, resolve(order, values, group.sites, group.calls, group.scoped));
    SmallVector<std::optional<std::pair<Operation *, Operation *>>, 4> extents;
    for (const Group &group : plan.groups)
      extents.push_back(group.extent ? std::optional(std::pair(order.op(group.extent->first),
                                                               order.op(group.extent->second)))
                                     : std::nullopt);

    // The parameter is the outermost lifetime, then each run's, outer
    // first. An op the plan replaces (a cell's source, a call that puts) is
    // no op an extent begins or ends at but its own run's, written after its
    // extent is opened.
    unsigned opened = 0;
    if (put)
      write(*put, parameter->first, Cells::Bumped, parameter->second);
    for (auto [at, pair] : llvm::enumerate(groups)) {
      auto &[group, resolved] = pair;
      Value lifetime = extents[at] ? open(*group, extents[at]->first, extents[at]->second)
                                   : activation(target);
      ++opened;
      write(resolved, lifetime, group->cells, modeOf(group->source));
    }
    return opened;
  }

private:
  struct Resolved {
    SmallVector<CellNewOp, 4> sites;
    SmallVector<std::pair<CallOp, FunctionId>, 2> calls;
    SmallVector<Value, 8> scoped;
  };

  // What the plan's positions are in `target`; a put call's results take
  // their types from the copy it calls, so they are no values to scope.
  Resolved resolve(const OpOrder &order, const footprint::Vector<Value> &values, ArrayRef<OpAt> sites,
                   ArrayRef<PutCall> calls, ArrayRef<Node> scoped) {
    Resolved out;
    for (OpAt site : sites)
      out.sites.push_back(cast<CellNewOp>(order.op(site)));
    for (const PutCall &call : calls)
      out.calls.emplace_back(cast<CallOp>(order.op(call.call)), call.callee);
    for (Node n : scoped) {
      Value value = values[n.index()];
      auto result = dyn_cast<OpResult>(value);
      if (result && llvm::any_of(out.calls, [&](const auto &call) {
            return call.first.getOperation() == result.getOwner();
          }))
        continue;
      out.scoped.push_back(value);
    }
    return out;
  }

  // This activation's lifetime, opened once at the top of the body.
  static Value activation(FuncOp fn) {
    OpBuilder b = OpBuilder::atBlockBegin(&fn.getBody().front());
    return ActivationOp::create(b, fn.getLoc(),
                                LifetimeType::get(fn.getContext(), LifetimeKind::view()))
        .getLifetime();
  }

  // The innermost cursor lifetime around `op`, an opener's, if any.
  static Value cursorAround(Operation *op) {
    for (Operation *up = op->getParentOp(); up && !isa<FuncOp>(up); up = up->getParentOp())
      if (isa<OpensLifetimeOpInterface>(up) && up->getNumRegions() == 1 &&
          !up->getRegion(0).empty() && up->getRegion(0).front().getNumArguments() != 0)
        if (Value lifetime = up->getRegion(0).front().getArgument(0);
            isCursorLifetime(lifetime.getType()))
          return lifetime;
    return nullptr;
  }

  // The opener of `group` around the ops from `first` to `last`, siblings:
  // they move into its region, which yields each value they make that
  // something after them uses; a yielded value that lives in a lifetime
  // around them keeps that lifetime, its entry of the opener's `outers`.
  Value open(const Group &group, Operation *first, Operation *last) {
    Block *block = first->getBlock();
    Location loc = first->getLoc();
    MLIRContext *ctx = first->getContext();
    auto after = [&](Operation *user) {
      Operation *top = block->findAncestorOpInBlock(*user);
      return top && last->isBeforeInBlock(top);
    };
    SmallVector<Value, 4> out;
    for (Operation *op = first;; op = op->getNextNode()) {
      for (Value result : op->getResults())
        if (llvm::any_of(result.getUsers(), after))
          out.push_back(result);
      if (op == last)
        break;
    }
    SmallVector<Value, 4> outers;
    for (Value value : out)
      if (Value stated = lifetimes::statedLifetime(value))
        outers.push_back(stated);

    OpBuilder b(first);
    SmallVector<Type, 4> types(ValueRange(out).getTypes());
    Operation *opener = nullptr;
    LifetimeKind kind = LifetimeKind::view();
    switch (group.source) {
    case Opening::Activation:
    case Opening::NoMemory:
      opener = LifetimeOp::create(b, loc, types, outers);
      break;
    case Opening::Block:
      opener = LifetimeBlockOp::create(b, loc, types, outers);
      kind = LifetimeKind::room();
      break;
    case Opening::Home:
      opener = LifetimeHomeOp::create(b, loc, types, outers);
      kind = LifetimeKind::home(0);
      break;
    case Opening::Cursor:
      if (Value base = cursorAround(first))
        opener = LifetimeStackOp::create(b, loc, types, base, outers);
      else
        opener = LifetimeChainOp::create(b, loc, types, outers);
      kind = LifetimeKind::cursor();
      break;
    }
    Block *body = new Block();
    opener->getRegion(0).push_back(body);
    Value lifetime = body->addArgument(LifetimeType::get(ctx, kind), loc);
    body->getOperations().splice(body->end(), block->getOperations(), Block::iterator(first),
                                 std::next(Block::iterator(last)));
    OpBuilder inside = OpBuilder::atBlockEnd(body);
    YieldOp::create(inside, loc, out);
    for (auto [value, result] : llvm::zip_equal(out, opener->getResults()))
      value.replaceUsesWithIf(result, [&](OpOperand &use) { return !opener->isAncestor(use.getOwner()); });
    return lifetime;
  }

  // The cells, as slots of the frame or bumped into `lifetime`; the calls,
  // to the copy of their callee for `mode`, given `lifetime`; then every
  // value that lives in it.
  void write(const Resolved &resolved, Value lifetime, Cells cells, CopyMode mode) {
    for (CellNewOp site : resolved.sites) {
      OpBuilder b(site);
      Type cell = site.getCell().getType();
      Value placed = cells == Cells::Slots
                         ? CellStackOp::create(b, site.getLoc(), cell, lifetime).getCell()
                         : CellArenaOp::create(b, site.getLoc(), cell, lifetime).getCell();
      site.getCell().replaceAllUsesWith(placed);
      site.erase();
    }
    for (auto [call, callee] : resolved.calls) {
      FuncOp copy = made[callee][static_cast<unsigned>(mode)];
      OpBuilder b(call);
      SmallVector<Value, 4> args(call.getArgs());
      args.push_back(lifetime);
      auto put = CallOp::create(b, call.getLoc(), copy, call.getIndexArgsAttr(), args,
                                call.getTailKind());
      call->replaceAllUsesWith(put->getResults());
      call.erase();
    }
    for (Value value : resolved.scoped)
      scope(value, lifetime);
  }

  const IndexVector<FunctionId, std::array<FuncOp, 3>> &made;
};

//===----------------------------------------------------------------------===//
// The pass
//===----------------------------------------------------------------------===//

// The most a function's copies could put: every result that holds a
// reference, for every kind. The root's results hold no runtime value.
std::optional<Copies> mostOf(FuncOp fn) {
  if (fn.isRoot())
    return std::nullopt;
  Copies most{CopyModes::all(), {}};
  for (auto [index, type] : llvm::enumerate(fn.getResultTypes()))
    if (holdsLiving(type))
      most.results.push_back(static_cast<unsigned>(index));
  return most.results.empty() ? std::nullopt : std::optional(most);
}

std::optional<Copies> copiesOf(const Plan &plan) {
  if (!plan.put)
    return std::nullopt;
  return Copies{plan.put->modes, plan.put->results};
}

struct IdrLifetimes : impl::IdrLifetimesBase<IdrLifetimes> {
  void runOnProgram(ProgramOp program) {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    solver::Work work;

    // Callees first: a component's copies start at the most each member's
    // could put and shrink to what each member's plan puts, given the
    // others', until none shrinks; each round shrinks one at least, so it
    // ends. Then each member's own body.
    IndexVector<FunctionId, std::optional<Copies>> copies = graph.table(std::optional<Copies>{});
    IndexVector<FunctionId, Plan> copyPlans = graph.table(Plan{});
    IndexVector<FunctionId, Plan> ownPlans = graph.table(Plan{});
    for (solver::SccId component : graph.sccCount().ids()) {
      auto members = graph.members(component);
      for (FunctionId f : members)
        copies[f] = mostOf(graph.op(f));
      for (bool shrank = true; shrank;) {
        shrank = false;
        for (FunctionId f : members)
          if (copies[f])
            copyPlans[f] = Planner(graph.op(f), f, graph, copies, Reading::Put, work).plan();
        for (FunctionId f : members)
          if (copies[f]) {
            std::optional<Copies> now = copiesOf(copyPlans[f]);
            if (now != copies[f]) {
              copies[f] = std::move(now);
              shrank = true;
            }
          }
      }
      for (FunctionId f : members)
        ownPlans[f] = Planner(graph.op(f), f, graph, copies, Reading::Counted, work).plan();
    }

    // The copies the program calls: those its functions' runs call, and
    // those each copy calls in turn, of its own runs' kinds and, for what it
    // puts into its parameter, of its own kind.
    IndexVector<FunctionId, CopyModes> wanted = graph.table(CopyModes::none());
    SmallVector<std::pair<FunctionId, CopyMode>, 8> pending;
    auto want = [&](FunctionId f, CopyMode mode) {
      if (!wanted[f].contains(mode)) {
        wanted[f] = wanted[f].with(mode);
        pending.emplace_back(f, mode);
      }
    };
    auto wantRuns = [&](const Plan &plan) {
      for (const Group &group : plan.groups)
        for (const PutCall &call : group.calls)
          want(call.callee, modeOf(group.source));
    };
    for (FunctionId f : graph.functions())
      wantRuns(ownPlans[f]);
    while (!pending.empty()) {
      auto [f, mode] = pending.pop_back_val();
      wantRuns(copyPlans[f]);
      for (const PutCall &call : copyPlans[f].put->calls)
        want(call.callee, mode);
    }

    // Each copy made from its owner as the plans read it, before anything
    // is written; then every copy written, then every owner.
    IndexVector<FunctionId, std::array<FuncOp, 3>> made = graph.table(std::array<FuncOp, 3>{});
    SmallVector<std::tuple<FunctionId, CopyMode, FuncOp>, 8> written;
    MLIRContext *ctx = program.getContext();
    for (FunctionId f : graph.functions())
      for (CopyMode mode : everyMode) {
        if (!wanted[f].contains(mode))
          continue;
        FuncOp owner = graph.op(f);
        SmallVector<Type, 4> inputs(owner.getArgumentTypes());
        inputs.push_back(LifetimeType::get(ctx, kindOf(mode)));
        SmallVector<Type, 2> results(owner.getResultTypes());
        for (unsigned result : copies[f]->results)
          results[result] = scopedType(results[result]);
        ModeKey key{f, FunctionType::get(ctx, inputs, results)};
        FailureOr<FuncOp> copy = specialize::makeCopy<Modes>(
            owner, key, specialize::nameOf<Modes>(owner.getSymNameAttr(), key));
        if (failed(copy)) {
          owner.emitOpError("internal error: idr-lifetimes could not make a copy of it");
          return signalPassFailure();
        }
        symbols.insert(*copy, std::next(owner->getIterator()));
        made[f][static_cast<unsigned>(mode)] = *copy;
        written.emplace_back(f, mode, *copy);
      }

    Writer writer(made);
    for (auto [f, mode, copy] : written)
      numLifetimes += writer.write(copy, copyPlans[f],
                                   std::pair(copy.getArgument(copy.getNumArguments() - 1), mode));
    SmallVector<std::pair<FunctionId, FuncOp>, 8> edited;
    for (FunctionId f : graph.functions()) {
      const Plan &plan = ownPlans[f];
      if (plan.groups.empty())
        continue;
      numLifetimes += writer.write(graph.op(f), plan, std::nullopt);
      if (llvm::any_of(plan.groups, [](const Group &group) { return !group.calls.empty(); }))
        edited.emplace_back(f, graph.op(f));
    }
    bool wrote = !written.empty() ||
                 llvm::any_of(graph.functions(), [&](FunctionId f) { return !ownPlans[f].groups.empty(); });
    if (!wrote) {
      numWork = work.steps();
      return markAllAnalysesPreserved();
    }

    // The copies join the program graph, every function whose calls changed
    // and every copy with the row its calls now make; then the one writer of
    // rows, since a slot is no heap memory and a copy's row is its own.
    {
      solver::Editor editor = graph.thaw();
      for (auto [f, mode, copy] : written)
        edited.emplace_back(editor.insert(copy), copy);
      for (auto [id, fn] : edited)
        editor.setCallees(id, solver::rowOf(fn, editor));
      std::move(editor).freeze();
    }
    rows::write(program, graph, work);
    numWork = work.steps();
    markAnalysesPreserved<SymbolTable, solver::ProgramGraph>();
  }
};

} // namespace
