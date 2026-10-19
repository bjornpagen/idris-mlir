// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize's scheduler: the waves that run the ready set (Optimize.h),
// each component's turn on a worker and what is settled between waves on
// the pass thread. Read by idr-optimize's own units alone.
#ifndef IDR_TRANSFORMS_OPTIMIZESCHEDULER_H
#define IDR_TRANSFORMS_OPTIMIZESCHEDULER_H

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Worklist.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMapInfoVariant.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr::optimize {

// The start of one node's work in idr-optimize, once per node; its IR unit
// is the node's function. Listed by -log-actions-to; idris-mlir-opt's
// debug counter may skip it, and a skipped node stays as it was.
struct NodeAction : support::TaggedAction<NodeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-node";
};

// What a finished component's final bodies say, read by its own turn and
// published between waves: its entry, and each member's constants and
// facts, in member order.
struct Finished {
  struct Member {
    ConstantResults constants;
    inlining::Facts facts;
  };
  idr::Effect effects;
  llvm::SmallVector<Member> members;
};

// What the scheduler reads and writes besides the ready set: the program,
// its symbol table, the node table, the inner pipeline's run, and the pass's
// analysis manager, which nests each function's.
struct Analyses {
  idr::ProgramOp program;
  ReadySet &set;
  mlir::SymbolTable &symbols;
  const specialize::Nodes &nodes;
  const InnerRun &inner;
  mlir::AnalysisManager am;
};

// One component's turn in a wave: the members it takes up and those it
// resumes, and what the turn left for the pass thread to settle.
struct Turn {
  explicit Turn(Scc &scc) : scc(scc) {}

  Scc &scc;
  llvm::SmallVector<Node *> starters, resumed;
  // The nodes of the table this turn built.
  llvm::SmallVector<specialize::Node *> built;
  // Each member it parked, with the batch it asked for and could not have
  // yet, resolved between waves.
  llvm::SmallVector<std::pair<Node *, llvm::SmallVector<specialize::Node *>>> parked;
  // What the component's final bodies say, once every member is done.
  std::optional<Finished> finished;
  uint64_t inlined = 0, capped = 0;
};

// One start or resume of a member: what a wave runs. A member starts once,
// and resumes once per park, a park being named by the first node of the
// batch it waits for, which no later batch holds: a requester asks for
// each node once. So each step enters the worklist of steps once, and they
// are finitely many, as the nodes and their requests are.
using Start = Node *;
using Resume = std::pair<Node *, specialize::Node *>;
using Step = std::variant<Start, Resume>;

// The ready set's scheduler, which idr-optimize alone runs. A wave is every
// step queued: the turn of every component that can go on, its callees
// final and its members waiting on nothing, run in parallel. Between waves, on the pass thread with no turn running, made
// nodes go into the program, finished components become final and publish
// their summaries, requests and the calls of made nodes are recorded as
// waits or merged, and the steps that can go on now are queued. So every
// turn reads a fixed set of final functions, and the output is the same at
// any thread count.
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
  // Adds what each copy of the inner pipeline's cse counted to the run's
  // InnerCounts; once, after the waves (Component.cpp).
  void addInnerStatistics();

private:
  // A turn, on a worker (Component.cpp).
  mlir::LogicalResult turn(Turn &turn);
  // What the members a turn takes up solve.
  void takeUp(llvm::ArrayRef<Node *> starters);
  // One member's loop, which leaves it done or parked.
  mlir::LogicalResult runMember(Node *node, Turn &turn);
  // One inline step, whether it inlined anything; and a round, an inline
  // step and the inner pipeline.
  bool inlineStep(Node *node, Turn &turn);
  mlir::LogicalResult round(Node *node, Turn &turn);
  // Builds the batch a member was given and parks the member when a node of
  // it is not final; whether it parked.
  mlir::FailureOr<bool> parks(Node *node, llvm::SmallVector<specialize::Node *> asked,
                              Turn &turn);
  // Each call in `node`'s body of a callee final now carries the callee's
  // entry: the one place a call takes a final callee's effects.
  void writeCallEffects(const Node &node) const;
  // The inner pipeline on a member, each of its calls of a final callee
  // first given the callee's effects.
  mlir::LogicalResult runInner(Node *node);
  // Builds each requested node this worker claims.
  mlir::LogicalResult build(llvm::ArrayRef<specialize::Node *> requests, Turn &turn);
  Finished finish(const Scc &scc);

  // Between waves, on the pass thread (Waves.cpp).
  void enable(OnceWorklist<Step> &ready);
  llvm::SmallVector<Turn, 0> gather(const Step &first, OnceWorklist<Step> &ready);
  void settle(llvm::MutableArrayRef<Turn> wave);
  void insert(specialize::Node *made);
  bool stepOfRecursion(const specialize::Node &made) const;
  void finalize(Scc &scc, Finished done);
  void want(Node *requester, Node *node);
  void waitOnCalls(Node *node);
  bool reaches(Scc &from, Scc &to);
  void merge(Scc &into, Scc &from);

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

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_OPTIMIZESCHEDULER_H
