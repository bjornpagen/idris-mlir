// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize, the first-order optimizer: one bottom-up ready set over the
// components of the call graph, run in waves. A function is taken up once
// every component it calls into is final; it inlines its calls into final
// callees, runs the inner pipeline once, and runs both again only for
// what its cleanup and its specialization requests exposed. And
// idr-contify, which runs before it. (The ready set is Mojo's
// AutomaticInline design rebuilt on Scc.h and MLIR's thread pool.)
#ifndef IDR_TRANSFORMS_OPTIMIZE_H
#define IDR_TRANSFORMS_OPTIMIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Inline.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDROPTIMIZE
#define GEN_PASS_DECL_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"

class BindingTimes;
class ConstantSummaries;
class Holds;
class Identities;

namespace optimize {

struct Scc;

// The start of one node's work in idr-optimize, once per node; its IR unit
// is the node's function. Listed by -log-actions-to; idris-mlir-opt's
// debug counter may skip it, and a skipped node stays as it was.
struct NodeAction : support::TaggedAction<NodeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-node";
};

// One function of the ready set: a function the module held when
// idr-optimize began, or a specialization node it made.
class Node {
public:
  // The function; for a made node, null until the node table builds it.
  idr::FuncOp fn;
  // The node table's node this one is; null for a function the module
  // held.
  specialize::Node *made = nullptr;
  // What the inline rule reads: `calls` when the node is made, the rest
  // when its component is final.
  inlining::Facts facts;

  // Whether its component is final: its facts are written and nothing
  // writes the function again. Set between waves only, so it is the same
  // for every reader of a wave.
  bool isFinal() const { return final; }

private:
  friend class ReadySet;
  friend class Scheduler;

  // A made node not yet built, then (as every node starts) one not taken
  // up, one parked on the nodes in `waitsOn`, or one done. A member's turn
  // writes its state; the rest changes between waves.
  enum class State : uint8_t { Unbuilt, Waiting, Parked, Done };

  bool final = false;
  Scc *scc = nullptr;
  State state = State::Waiting;
  bool inModule = true;
  llvm::SmallVector<Node *> waitsOn, waiters;
  // What its last turn requested and could not have yet, resolved between
  // waves.
  llvm::SmallVector<specialize::Node *> asked;
};

// A component of the ready set's graph, callees first. A component of made
// nodes grows when a request would park a node on itself.
struct Scc {
  // Module order; a merge appends the merged members.
  llvm::SmallVector<Node *> members;
  // The components with a call or a force into this one.
  llvm::SmallVector<Scc *> callers;
  unsigned unfinishedCallees = 0;
  Scc *mergedInto = nullptr;
  // What this component is after every merge.
  Scc &leader();
};

// The ready set of a module as idr-optimize drives it, and the node
// table's view of the schedule. Its maps change only between waves, so
// lookup and isFinal may be called from any worker of a wave.
class ReadySet final : public specialize::Schedule {
public:
  ReadySet(mlir::Operation *module, mlir::AnalysisManager &am);
  ~ReadySet() override;
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<ReadySet>();
  }

  // The node of the function named `name` the module holds; null for none.
  Node *nodeOf(mlir::StringAttr name) const { return byName.lookup(name); }
  // How many nodes it holds: the module's functions and the made nodes.
  size_t nodeCount() const { return all.size(); }
  idr::FuncOp lookup(mlir::StringAttr name) const override;
  bool isFinal(idr::FuncOp fn) const override;

private:
  friend class Scheduler;
  std::vector<std::unique_ptr<Node>> all;
  std::vector<std::unique_ptr<Scc>> sccs;
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
  llvm::DenseMap<specialize::Node *, Node *> byMade;
};

// The inner per-function pipeline, run once per node and again by the
// bounded local loop, into `pm`, a manager on idr.func.
void buildInnerPipeline(mlir::OpPassManager &pm);

// What the scheduler reads and writes besides the ready set: the module's
// symbol table and the analyses the pass took before any task, so that
// the inner pipeline's passes find them cached.
struct Analyses {
  mlir::ModuleOp module;
  ReadySet &set;
  mlir::SymbolTable &symbols;
  const Holds &holds;
  ConstantSummaries &summaries;
  BindingTimes &times;
  Identities &identities;
  const specialize::Nodes &nodes;
  mlir::AnalysisManager am;
};

// One component's turn in a wave: the members it takes up and those it
// resumes, and what the turn left for the pass thread to settle.
struct Turn {
  Scc *scc = nullptr;
  llvm::SmallVector<Node *> starters, resumed;
  // The nodes of the table this turn built, each with what its build
  // requested.
  llvm::SmallVector<std::pair<specialize::Node *, llvm::SmallVector<specialize::Node *>>> built;
  bool finished = false;
  uint64_t inlined = 0, capped = 0;
};

// The ready set's scheduler, which idr-optimize alone runs. A wave is the
// turn of every component that can go on: its callees final, its members
// in the module and parked on nothing, run in parallel. Between waves, on
// the pass thread with no turn running, made nodes go into the module,
// finished components become final, requests are recorded or merged, and
// the next wave is read off what is final. So every turn reads a fixed
// set of final functions, and the output is the same at any thread count.
class Scheduler {
public:
  using RunPipeline = std::function<mlir::LogicalResult(mlir::OpPassManager &, mlir::Operation *)>;

  Scheduler(Analyses in, RunPipeline run);

  // Runs the waves. Failure when a turn failed, having emitted its
  // diagnostic, or when a node was left not final.
  mlir::LogicalResult run();

  uint64_t inlined() const { return numInlined; }
  uint64_t capped() const { return numCapped; }
  uint64_t made() const { return numMade; }

private:
  // A turn, on a worker (Component.cpp).
  mlir::LogicalResult turn(Turn &turn);
  // One member's loop from its next inline step: whether it was parked.
  mlir::FailureOr<bool> runMember(Node *node, bool resumed, Turn &turn);
  mlir::LogicalResult runInner(idr::FuncOp fn);
  // Builds each requested node this worker claims, and what its build
  // requests in turn.
  mlir::LogicalResult build(llvm::ArrayRef<specialize::Node *> requests, Turn &turn);
  void finish(Scc &scc);

  // Between waves, on the pass thread (Waves.cpp).
  llvm::SmallVector<Turn> nextWave();
  mlir::LogicalResult settle(llvm::MutableArrayRef<Turn> wave);
  mlir::LogicalResult insert(Node *node);
  void finalize(Scc &scc);
  Node *nodeOfMade(specialize::Node *made);
  mlir::LogicalResult want(Node *requester, Node *node);
  bool reaches(Scc &from, Scc &to);
  mlir::LogicalResult merge(Scc &into, Scc &from);

  Analyses analyses;
  RunPipeline runPipeline;

  // Copies of the inner pipeline, one per worker that runs one; a copy is
  // made when every copy is in use.
  mlir::OpPassManager inner;
  std::mutex pipelinesMutex;
  std::vector<std::unique_ptr<mlir::OpPassManager>> pipelines;
  llvm::SmallVector<mlir::OpPassManager *> idle;

  uint64_t numInlined = 0, numCapped = 0, numMade = 0, numFinal = 0;
};

} // namespace optimize
} // namespace idr

#endif // IDR_TRANSFORMS_OPTIMIZE_H
