// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the two units of exclusivity's solve share, and no other unit reads:
// lib/Analysis/Ownership/Exclusivity.cpp, which runs the solve and keeps
// its answers, and ExclusivityAnalyses.cpp beside it, the solve itself.
// How each call goes, and the captures of each memoizing label, are fixed
// before the solve, which reads them as it marks the program's values.
#ifndef IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
#define IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H

#include "idr/Analysis/Ownership.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <variant>
#include <vector>

namespace idr::detail::exclusivity {

using Sharing = Exclusivity::Sharing;

// How calls go, fixed before the solve. Each function of the program is
// called by its name alone, or, a key of grade specialization and its copy,
// by either name: such a call runs the copy when every value it passes at a
// followed parameter is exclusive, and the original otherwise. A verified
// call names a function of the program, so every name a call holds is
// here. What each function returns from is the idr.return ending its body,
// none when the body ends in ub.unreachable.
class Calls {
public:
  struct Pair {
    FuncOp original;
    FuncOp copy;
  };
  using Callee = std::variant<FuncOp, Pair>;

  Calls(ProgramOp program, const ownership::Copies &copies);

  // What a call of `call`'s callee runs.
  const Callee &calleeOf(CallOp call) const;
  // The functions whose calls may run `fn`.
  llvm::SmallVector<FuncOp, 2> namesOf(FuncOp fn) const;
  // The function `call` runs, `isExclusive` saying which of the values it
  // passes are.
  FuncOp target(CallOp call, llvm::function_ref<bool(mlir::Value)> isExclusive) const;
  // The returns of `fn`, a function of the program.
  llvm::ArrayRef<ReturnOp> returns(FuncOp fn) const { return returnsOf.at(fn); }
  // Whether the program shows every call of `fn`: of every function but
  // its root, which is called from outside. A program is whole and closed:
  // once closures and suspensions are sums, each function runs only where
  // an idr.call names it, and a label's name in a sum's body is a name, no
  // address any op could call through.
  static bool showsEveryCall(FuncOp fn) { return !fn.isRoot(); }

private:
  llvm::DenseMap<mlir::StringAttr, Callee> callees;
  llvm::DenseMap<FuncOp, llvm::SmallVector<ReturnOp>> returnsOf;
};

// The captures of each memoizing label: the memory a cell of a memo sum
// holds a label's fields in, which idr.cell.init writes once, when the
// cell is made, and idr.memo.run moves out at the force, with the cell's
// reference. A capture moved out is exclusive when every value any init
// moved into that field was, and nothing else reaches it while the cell
// holds it: no static memo cell holds the label (static data is no one's
// to take apart), and no read of the field as a view (a match's case
// binding, an idr.field) is used, which is how a second reference to it
// would be taken. Fixed before the solve, which joins the inits into the
// region arguments of the program's memo.run ops of each label. A label is
// made where an op that makes a cell of it runs, as the solve's own
// liveness says (keepMadeIn): a label made only in code that never runs
// is made by nothing, and its captures are shared.
class Captures {
public:
  explicit Captures(ProgramOp program);

  // The forces of the label `tag` of the memo sum `memo`.
  llvm::ArrayRef<MemoRunOp> forcesOf(DataType memo, Tag tag) const;
  // Whether field `index` of that label is shared whatever the inits move
  // into it.
  bool shared(DataType memo, Tag tag, unsigned index) const;
  // Whether a cell of that label is made where the program runs: an init,
  // or static data.
  bool made(DataType memo, Tag tag) const { return makers.contains({memo, tag}); }
  // Keeps as made only the labels an op in a block of `live` makes;
  // whether any label stopped being made.
  bool keepMadeIn(const llvm::DenseSet<mlir::Block *> &live);

private:
  using Label = std::pair<DataType, Tag>;
  llvm::DenseMap<Label, llvm::SmallVector<MemoRunOp>> forces;
  llvm::DenseSet<std::pair<Label, unsigned>> sharedFields;
  // The ops that make a cell of each label.
  llvm::DenseMap<Label, llvm::SmallVector<mlir::Operation *>> makers;
};

// One solve of `program`, whose calls go as `calls` says and whose memo
// captures are as `captures` says: what it found of each value it reached,
// a value absent here being one it never reached (unknown). The solve is
// optimistic: a value is exclusive until a path shares it, and only ever
// shares more, so the marking ends.
llvm::DenseMap<mlir::Value, Sharing> solveOnce(ProgramOp program, const Calls &calls,
                                               const Captures &captures);

// The blocks of `fn` that may run when `fn` runs: those control reaches
// from its entry, every region of a reached op being one it may enter.
// Reachability alone: which region a branch takes on a constant is the
// canonicalizer's to fold, not the solve's to leave ungraded.
void liveBlocksOf(FuncOp fn, llvm::DenseSet<mlir::Block *> &live);

// One writer of values in the solve's graph: an op's results from its
// reference edges, a call's results and its callee's parameters, a region
// successor's inputs (an op's results, or a region's arguments) from its
// predecessors' operands, a block's arguments from its predecessors, or
// the arguments of a region no branch forwards to, which are shared. An
// item reads the values it is a dependent of and runs again when one
// rises or when its function starts to run; it writes nothing from a
// block that may not run.
struct Item {
  enum class Kind : uint8_t { Op, Call, Successor, BlockArgs, EntryArgs };
  Kind kind;
  mlir::Operation *op; // Successor: the branch; BlockArgs: null, block is the item's own
  mlir::Block *block;  // the block that must run for the item to write
  FuncOp fn;           // the function the item is in
  mlir::Region *region; // Successor: the successor region, null for the op successor
  unsigned source;     // Successor: its entry in Graph::successorSources
};

// Where one region successor's inputs come from, read off the branch op
// once: its inputs and the values no predecessor forwards to, each
// predecessor that may go to it as the block control leaves from and the
// operands it forwards, and the blocks control leaves a region from by a
// terminator no interface says the operands of, which prove nothing.
struct SuccessorSources {
  mlir::ValueRange inputs;
  llvm::SmallVector<mlir::Value> unforwarded;
  llvm::SmallVector<std::pair<mlir::Block *, mlir::OperandRange>, 2> from;
  llvm::SmallVector<mlir::Block *, 1> unknownFrom;
};

// The solve's graph of a program, built once: every item, where each
// region successor's inputs come from, the items each value is read by,
// and each function's items. Nothing in it changes as the marking runs.
class Graph {
public:
  Graph(ProgramOp program, const Calls &calls);

  std::vector<Item> items;
  std::vector<SuccessorSources> successorSources;
  llvm::DenseMap<mlir::Value, llvm::SmallVector<unsigned, 2>> dependents;
  llvm::DenseMap<FuncOp, llvm::SmallVector<unsigned>> itemsOf;

private:
  unsigned addItem(Item item);
  void reads(unsigned id, mlir::Value value);
  void readsAll(unsigned id, mlir::ValueRange values);
  void readsReturns(unsigned id, FuncOp callee, const Calls &calls);
  void scan(mlir::Region &region, FuncOp fn, const Calls &calls);
  void scanOp(mlir::Operation *op, FuncOp fn, const Calls &calls);
  void scanBranch(mlir::RegionBranchOpInterface branch, mlir::Block *block, FuncOp fn);
};

} // namespace idr::detail::exclusivity

#endif // IDR_ANALYSIS_OWNERSHIP_EXCLUSIVITYDETAIL_H
