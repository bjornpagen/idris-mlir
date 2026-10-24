// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-simplify: one function's e-graph per run, in two turns at most
// (EGraph.h), each admitted by its arena, and what the optimizer reads of
// it.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/Analysis/Solver/Trace.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"
#include "idr/Support/Memory.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <span>

#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::egraph {

using detail::Function;
using detail::Kinds;
using detail::Turn;

// Per result, the constant op the final body's return reads, as it holds
// it; none where the return reads anything else. A body that ends without
// returning (its one block ends in a crash) reaches no caller, and returns
// nothing to know.
void CalleeFacts::publish(solver::FunctionId f, identities::Facts given, FuncOp final) {
  if (f.index() >= facts.size().value()) {
    IndexVector<solver::FunctionId, Published> old = std::move(facts);
    facts = IndexVector<solver::FunctionId, Published>(names->size(), [&](solver::FunctionId g) {
      return g.index() < old.size().value() ? std::move(old[g]) : Published();
    });
  }
  Published out{std::move(given), {}};
  out.returned.resize(final.getResultTypes().size());
  if (auto ret = dyn_cast<ReturnOp>(final.getBody().front().getTerminator()))
    for (auto [returned, operand] : llvm::zip_equal(out.returned, ret.getOperands())) {
      Attribute constant;
      if (matchPattern(operand, m_Constant(&constant)))
        returned = ReturnedConstant{constant, operand.getDefiningOp()->getDialect(),
                                    operand.getType()};
    }
  facts[f] = std::move(out);
}

const CalleeFacts::Published *CalleeFacts::find(FlatSymbolRefAttr callee) const {
  std::optional<solver::FunctionId> f = names->find(callee);
  if (!f || f->index() >= facts.size().value())
    return nullptr;
  return &facts[*f];
}

identities::FactsView CalleeFacts::of(FlatSymbolRefAttr callee) const {
  const Published *known = find(callee);
  return known ? known->given.view() : identities::FactsView();
}

llvm::ArrayRef<std::optional<ReturnedConstant>>
CalleeFacts::returns(FlatSymbolRefAttr callee) const {
  const Published *known = find(callee);
  return known ? llvm::ArrayRef<std::optional<ReturnedConstant>>(known->returned)
               : llvm::ArrayRef<std::optional<ReturnedConstant>>();
}

} // namespace idr::egraph

namespace {

// The host's memory, which the arena of every function's e-graph in flight
// takes from, whichever pass runs it: the pipeline's points under MLIR's
// pass manager, upstream's inliner from its workers, the optimizer from
// its waves. A process runs on one host, so this is one ledger for the
// process's life, its budget read once. A run enters holding no other
// arena, so the run in flight always finishes and no wait lasts for ever.
class HostArenas {
public:
  static HostArenas &ofProcess() {
    static HostArenas host(idr::support::hostMemoryBytes());
    return host;
  }

  // An arena alone larger than the host ends the compiler through its one
  // out-of-memory handler, a crash of the machine, never a refusal; any
  // other enters once it fits beside those in flight, or when none is.
  void enter(std::uint64_t bytes) {
    if (bytes > budget)
      llvm::report_bad_alloc_error("a function's e-graph needs more memory than the host has");
    std::unique_lock lock(mutex);
    freed.wait(lock, [&] { return inFlight == 0 || inFlight + bytes <= budget; });
    inFlight += bytes;
  }

  void leave(std::uint64_t bytes) {
    {
      std::lock_guard lock(mutex);
      inFlight -= bytes;
    }
    freed.notify_all();
  }

private:
  explicit HostArenas(std::uint64_t budget) : budget(budget) {}

  std::uint64_t budget;
  std::uint64_t inFlight = 0;
  std::mutex mutex;
  std::condition_variable freed;
};

// One function's arena, in flight while it is held: entered before the
// search starts, left when the e-graph it was admitted for is gone.
class Admitted {
public:
  explicit Admitted(const idr::egraph::Function &function) : bytes(function.arena()) {
    HostArenas::ofProcess().enter(bytes);
  }
  ~Admitted() { HostArenas::ofProcess().leave(bytes); }
  Admitted(const Admitted &) = delete;
  Admitted &operator=(const Admitted &) = delete;

private:
  std::uint64_t bytes;
};

class Erasures;
struct RootTag {
  using Minter = Erasures;
};
// A root of the rewrites between the two turns, by the order they run in.
using Root = idr::Id<RootTag>;

// Which roots the rewrites before them erased, so that each is skipped:
// MLIR reports an erasure by its op's address alone, which the roots'
// table, built once from the rewrites, turns into a root's number.
class Erasures : public RewriterBase::Listener {
public:
  explicit Erasures(std::span<const idr::egraph::Function::Pending> pending)
      : count(static_cast<std::uint32_t>(pending.size())), erased(count) {
    for (auto [at, each] : llvm::enumerate(pending))
      roots.try_emplace(each.root, Root(static_cast<std::uint32_t>(at)));
  }

  void notifyOperationErased(Operation *op) override {
    if (auto root = roots.find(op); root != roots.end())
      (void)erased.raise(root->second);
  }

  idr::Count<Root> size() const { return count; }
  bool wasErased(Root root) const { return erased.test(root); }

private:
  idr::Count<Root> count;
  idr::footprint::DenseMap<Operation *, Root> roots;
  idr::BitSet<Root> erased;
};

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  Simplify() = default;
  explicit Simplify(const idr::egraph::CalleeFacts &callees) : callees(&callees) {}

  // The generated kinds' op names, found once per pass instance: which op
  // an Operation * is is the one fact MLIR's open op set leaves to run time.
  LogicalResult initialize(MLIRContext *context) override {
    kinds = std::make_shared<const idr::egraph::Kinds>(idr::egraph::detail::makeKinds(context));
    return success();
  }

  // Each turn's e-graph is admitted alone and gone before the next is
  // made, so a run holds one arena at a time.
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    idr::solver::SolveUnit unit("idr-simplify", fn.getSymName());
    idr::footprint::Vector<idr::egraph::Function::Pending> rewrites;
    {
      idr::egraph::Function first(fn, *kinds, callees);
      Admitted admitted(first);
      first.build();
      first.extract();
      first.decide(idr::egraph::Turn::First);
      rewrites = first.rewrites();
      if (rewrites.empty()) {
        IRRewriter rewriter(&getContext());
        first.elaborate(rewriter);
      }
      numWork += first.work();
    }
    if (rewrites.empty())
      return;
    Erasures erasures(rewrites);
    IRRewriter rewriter(&getContext(), &erasures);
    for (Root root : erasures.size().ids()) {
      if (erasures.wasErased(root))
        continue;
      const idr::egraph::Function::Pending &pending = rewrites[root.index()];
      rewriter.setInsertionPoint(pending.root);
      idr::egraph::Function::rewriteSkeleton(pending, rewriter);
    }
    idr::egraph::Function second(fn, *kinds, callees);
    Admitted admitted(second);
    second.build();
    second.extract();
    second.decide(idr::egraph::Turn::Second);
    IRRewriter writer(&getContext());
    second.elaborate(writer);
    numWork += second.work();
  }

  std::shared_ptr<const idr::egraph::Kinds> kinds;
  const idr::egraph::CalleeFacts *callees = nullptr;
};

} // namespace

// createIdrSimplify() is the generated constructor; this is the
// optimizer's, for its inner pipeline.
std::unique_ptr<Pass> idr::createIdrSimplify(const egraph::CalleeFacts &callees) {
  return std::make_unique<Simplify>(callees);
}
