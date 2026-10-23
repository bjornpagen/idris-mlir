// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The parts of idr-lifetimes' decide step, shared by its units under
// lib/Transforms/Lifetimes: one function's ops numbered, what a function
// is decided into, the planner that decides one function (Read.cpp reads
// it, Decide.cpp decides it), the rule every region the pass opens keeps
// and the one way it opens one, which the loans (Lend.cpp) share, and the
// writer that writes a plan into a function and its copies (Write.cpp).
// The pass is Pass.cpp's.
#ifndef IDR_TRANSFORMS_LIFETIMES_PLAN_H
#define IDR_TRANSFORMS_LIFETIMES_PLAN_H

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Operation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <array>
#include <concepts>
#include <cstdint>
#include <optional>
#include <ranges>
#include <span>
#include <utility>

namespace idr::lifetimes::decide {

using solver::FunctionId;

//===----------------------------------------------------------------------===//
// One function, numbered
//===----------------------------------------------------------------------===//

// One function's values, numbered once by the solver layer's walk.
struct Values {
  using Minter = solver::Numbering<Values>;
};
using Node = Id<Values>;

// One function's ops in pre-order, the function first, each with where its
// subtree ends: a position names an op in the function and in every clone
// of it, which has its shape, and the ops from one sibling to a later one,
// with everything in them, are the positions between. An op is found from
// its position in one load; a position is reached from the function's
// shape (a region's first op, a block's ops one after another), never
// looked up by the op.
class OpOrder;
struct OpTag {
  using Minter = OpOrder;
};
using OpAt = Id<OpTag>;

class OpOrder {
public:
  explicit OpOrder(FuncOp fn);

  Count<OpAt> size() const { return Count<OpAt>(static_cast<std::uint32_t>(ops.size())); }
  mlir::Operation *op(OpAt at) const { return ops[at.index()]; }
  // The position just past `at` and everything in it.
  OpAt end(OpAt at) const { return OpAt(ends[at.index()]); }
  // The function's own position.
  OpAt root() const { return OpAt(0); }

  // The ops from `first` to `last`, siblings in that order, and everything
  // in them.
  llvm::ArrayRef<mlir::Operation *> span(OpAt first, OpAt last) const {
    return llvm::ArrayRef<mlir::Operation *>(ops).slice(first.index(),
                                                        ends[last.index()] - first.index());
  }
  bool within(OpAt at, OpAt first, OpAt last) const {
    return first.index() <= at.index() && at.index() < ends[last.index()];
  }

  // Each op of class `OpT` with its position, in order: MLIR's typed walk,
  // over the function as numbered.
  template <class OpT, std::invocable<OpT, OpAt> Visit>
  void each(Visit &&visit) const {
    for (OpAt at : size().ids())
      if (auto op = llvm::dyn_cast<OpT>(ops[at.index()]))
        visit(op, at);
  }

  // The position of the first op of region `number` of the op at `holder`.
  OpAt firstIn(OpAt holder, unsigned number) const;
  // The positions of `first` and `last`, ops of `block` in that order, the
  // block's first op at `start`.
  std::pair<OpAt, OpAt> positions(OpAt start, mlir::Block &block, mlir::Operation *first,
                                  mlir::Operation *last) const;

private:
  footprint::Vector<mlir::Operation *> ops;
  footprint::Vector<std::uint32_t> ends;
};

//===----------------------------------------------------------------------===//
// What a function is decided into
//===----------------------------------------------------------------------===//

// The kind a copy's lifetime parameter is compiled for, as its caller's
// lifetime is: a room, a cursor, or the shard's home of the root's one site,
// the only home site, so its number is 0.
enum class CopyMode : std::uint8_t { Room, Cursor, Home };

inline constexpr std::array<CopyMode, 3> everyMode{CopyMode::Room, CopyMode::Cursor,
                                                   CopyMode::Home};

LifetimeKind kindOf(CopyMode mode);

// The kinds a function's copies may be compiled for.
class CopyModes {
public:
  static constexpr CopyModes none() { return CopyModes(0); }
  static constexpr CopyModes all() { return CopyModes(0b111); }
  constexpr CopyModes with(CopyMode mode) const {
    return CopyModes(static_cast<std::uint8_t>(bits | bit(mode)));
  }
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
  llvm::SmallVector<unsigned, 2> results;
  bool operator==(const Copies &) const = default;
};

// Where a run's lifetime comes from: this activation (no region, a view);
// an opener with no memory, a view; a block of the frame, a room; the
// shard's home; or a cursor's bump, on the stack of the cursor around it
// where there is one, else its own chain.
enum class Opening : std::uint8_t { Activation, NoMemory, Block, Home, Cursor };

// The kind of copy a call into a lifetime of `source` takes.
CopyMode modeOf(Opening source);

// How a run's cells are stated in its lifetime: slots of the frame, or
// bumped into the lifetime, for a lifetime that a frame may carry.
enum class Cells : std::uint8_t { Slots, Bumped };

// The run a cell or a call is of: the innermost region around it that runs
// again within its function, by its op's position and its number; none for
// the function's body.
using RunAt = std::optional<std::pair<OpAt, unsigned>>;

// A call that puts what it gives into a lifetime: the copy of `callee` for
// that lifetime's kind is called instead.
struct PutCall {
  OpAt call;
  FunctionId callee;
};

// One run's lifetime: the run, its source, how its cells are stated, the
// cells (their idr.cell.new) and the calls it takes, the ops it spans (none
// for the activation, the rest of the body), and the values that live in
// it, in walk order.
struct Group {
  RunAt run;
  Opening source = Opening::Activation;
  Cells cells = Cells::Slots;
  footprint::Vector<OpAt> sites;
  footprint::Vector<PutCall> calls;
  std::optional<std::pair<OpAt, OpAt>> extent;
  footprint::Vector<Node> scoped;
};

// What a copy puts into its lifetime parameter: its cells and calls there,
// the values that live there, the results that do, and the kinds it may be
// compiled for.
struct PutForm {
  footprint::Vector<OpAt> sites;
  footprint::Vector<PutCall> calls;
  footprint::Vector<Node> scoped;
  llvm::SmallVector<unsigned, 2> results;
  CopyModes modes = CopyModes::all();
};

// A function decided: its runs' lifetimes, every run before the runs inside
// it, and, for its copies, what each puts into its lifetime parameter.
// Every position is the function's as it was read, so the plan writes the
// function and every clone of it alike.
struct Plan {
  footprint::Vector<Group> groups;
  std::optional<PutForm> put;
};

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

// Whether a function's component of the call graph runs a call on a frame:
// a member calls a member, not in tail position. A frame holds no
// lifetime, so every function on such a component's stack takes the
// component's lifetimes in one arrangement and passes them on: its members
// reach one another only through the lifetime parameter their copies
// share, never through a lifetime one of them opens.
enum class Framing : std::uint8_t { Unframed, Framed };

// Whether a slot can stand where an op is: every region from it up to its
// function's body is the one block of a region branch whose runs never
// overlap, so the slot is written once per run of the region around it.
enum class SlotHere : std::uint8_t { Fits, DoesNot };

// Where an op stands: the run it is of, and whether a slot fits there.
struct Where {
  RunAt run;
  SlotHere slot;
};

class Planner {
public:
  Planner(FuncOp fn, FunctionId self, const solver::ProgramGraph &graph,
          const IndexVector<FunctionId, std::optional<Copies>> &copies, Reading reading,
          Framing framing, solver::Work &work);

  Plan plan();

private:
  // A cell a lifetime may take: its source, the box its init makes, and the
  // run it is of.
  struct Site {
    OpAt source;
    Node box;
    RunAt run;
  };
  // A call whose callee's copy may put its results into a lifetime.
  struct Call {
    OpAt op;
    FunctionId callee;
    llvm::SmallVector<Node, 2> results;
    RunAt run;
  };
  // One run's cells and calls, as positions in `sites` and `calls`.
  struct Draft {
    RunAt run;
    footprint::Vector<unsigned> sites;
    footprint::Vector<unsigned> calls;
  };
  // An op whose regions hold the ops being read, and where it stands.
  struct Around {
    OpAt at;
    Where where;
  };

  Node node(mlir::Value value) const { return numbering.at(value); }
  mlir::Value valueOf(Node n) const { return values[n.index()]; }

  // One marking of the function's values, its steps counted: each value
  // and each link at most once.
  template <Direction D, class Seeds>
  BitSet<Node> marked(const Csr<Values> &g, const Seeds &seeds) {
    work.add(std::uint64_t{count.value()} + links);
    return mark<D>(g, std::span<const Node>(seeds.data(), seeds.size()));
  }

  // Reading (Read.cpp).
  void readAll();
  static Where inside(const Around &holder, mlir::Operation *op);
  void readMoves(mlir::Operation *op);
  void read(CallOp call, OpAt at, const Where &where);
  void read(CellNewOp cell, OpAt at, const Where &where);
  void read(CellInitOp init);
  void mustCount(mlir::Value value);
  void edge(mlir::Value from, mlir::Value to);

  // Deciding (Decide.cpp).
  bool spannable(mlir::Block &block, OpAt first, OpAt last) const;
  std::optional<Group> decide(const Draft &draft, BodyOpener opener,
                              footprint::Vector<Fate> &siteFates,
                              footprint::Vector<Fate> &callFates);
  std::optional<PutForm> putForm(const Draft &draft);

  FuncOp fn;
  FunctionId self;
  const solver::ProgramGraph &graph;
  const IndexVector<FunctionId, std::optional<Copies>> &copies;
  Reading reading;
  Framing framing;
  solver::Work &work;
  OpOrder order;
  solver::Numbering<Values> numbering;
  Count<Node> count;
  footprint::Vector<mlir::Value> values;
  CsrBuilder<Values> flowEdges;
  CsrBuilder<Values> linkedEdges;
  std::uint64_t links = 0;
  std::optional<Csr<Values>> flow;
  footprint::Vector<Node> fixed;
  footprint::Vector<Node> returned;
  footprint::Vector<Site> sites;
  footprint::Vector<Call> calls;
  footprint::Vector<OpAt> framed;
  footprint::Vector<OpAt> tails;
  // The boxes of the cells a lifetime may take, so an init reads whether
  // its cell is one in one load.
  BitSet<Node> boxes;
};

// Whether a lifetime's region may hold the ops of `block` from `first` to
// `last`, siblings in that order, `ops` being those ops and everything in
// them: no call in tail position, whose return would follow the region's
// end, and no jump to a join point outside them, which no region lets
// through. The one rule every region this pass opens is held to, a run's
// and a loan's.
template <std::ranges::input_range Ops>
  requires std::convertible_to<std::ranges::range_reference_t<Ops>, mlir::Operation *>
bool regionMayHold(mlir::Block &block, mlir::Operation *first, mlir::Operation *last, Ops &&ops) {
  auto inside = [&](mlir::Operation *op) {
    mlir::Operation *top = block.findAncestorOpInBlock(*op);
    return top && !top->isBeforeInBlock(first) && !last->isBeforeInBlock(top);
  };
  for (mlir::Operation *op : ops) {
    if (lastActOf(op))
      return false;
    for (mlir::Value operand : op->getOperands())
      if (llvm::isa<mlir::TokenType>(operand.getType()))
        if (auto token = llvm::dyn_cast<mlir::BlockArgument>(operand);
            !token || !inside(token.getOwner()->getParentOp()))
          return false;
  }
  return true;
}

// Whether `call`, in function `self`, continues on a frame: it returns to
// its caller, and its callee is on `self`'s own cycle, so the frames pass
// moves what follows it into a frame of its own.
inline bool continuesOnFrame(const solver::ProgramGraph &graph, FunctionId self, CallOp call) {
  return !lastActOf(call) && graph.sccOf(graph.id(call.getCalleeAttr())) == graph.sccOf(self);
}

// Opens a lifetime from `source` around the ops from `first` to `last`,
// siblings: they move into its region, which yields each value they make
// that something after them uses, a yielded value that lives in a lifetime
// around them keeping that lifetime as its entry of the opener's `outers`.
// A cursor's opener is on the stack of `base` where one is given, else its
// own chain. The lifetime the region binds.
mlir::Value openLifetime(Opening source, mlir::Operation *first, mlir::Operation *last,
                         mlir::Value base);

// This activation's lifetime of `fn`, opened once at the top of its body.
mlir::Value activationOf(FuncOp fn);

// Whether a value of `type` holds a reference a lifetime could hold:
// static data never needs one, and is linked to nothing.
bool holdsLiving(mlir::Type type);

// `type` living in a lifetime, with what it claims of its sharing.
mlir::Type scopedType(mlir::Type type);

// The op that would state where `value` lives, if one can.
StatesLifetimeOpInterface statedBy(mlir::Value value);

//===----------------------------------------------------------------------===//
// The copies, and writing a plan
//===----------------------------------------------------------------------===//

// A copy is keyed by its function type, its owner's with one more
// parameter, the lifetime of the kind it is compiled for, and with the
// results it puts there scoped: the type is uniqued, so equal keys are one
// copy, and the name its digest gives is the same on any machine.
struct ModeKey {
  FunctionId owner;
  mlir::FunctionType signature;
};

struct Modes {
  using Key = ModeKey;
  using Order = specialize::Equality;
  static constexpr llvm::StringLiteral kind = "mode";
  static FunctionId owner(const Key &key) { return key.owner; }
  static void write(const Key &key, specialize::Bytes &bytes) { bytes.type(key.signature); }
  static mlir::LogicalResult edit(const Key &key, FuncOp clone);
};
static_assert(specialize::KeyAlphabet<Modes>);

// Each function's copies by kind, as the pass made them.
using Made = IndexVector<FunctionId, std::array<FuncOp, 3>>;

class Writer {
public:
  explicit Writer(const Made &made) : made(made) {}

  // Writes `plan` into `target`, the function it was made of or a clone of
  // it, whose lifetime parameter is `parameter` for a copy; how many
  // lifetimes it opened.
  unsigned write(FuncOp target, const Plan &plan,
                 std::optional<std::pair<mlir::Value, CopyMode>> parameter);

private:
  struct Resolved {
    footprint::Vector<CellNewOp> sites;
    footprint::Vector<std::pair<CallOp, FunctionId>> calls;
    footprint::Vector<mlir::Value> scoped;
  };

  Resolved resolve(const OpOrder &order, const footprint::Vector<mlir::Value> &values,
                   llvm::ArrayRef<OpAt> sites, llvm::ArrayRef<PutCall> calls,
                   llvm::ArrayRef<Node> scoped);
  void write(const Resolved &resolved, mlir::Value lifetime, Cells cells, CopyMode mode);

  const Made &made;
};

} // namespace idr::lifetimes::decide

#endif // IDR_TRANSFORMS_LIFETIMES_PLAN_H
