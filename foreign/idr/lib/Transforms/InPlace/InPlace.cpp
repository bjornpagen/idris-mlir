// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-in-place (idr/Transforms/InPlace.h): the in-place promise decided on
// the program as written (Rule.cpp), then refused or written.
//
// A refusal names the user's call: the first call whose argument cannot be
// shown to pay what its callee is owed, never a call inside a function that
// only passes its own parameter on (that parameter is owed in turn), with a
// note at the cause. The pass rewrites nothing unless every requirement
// holds.
//
// Written, the verdict is types and ops. Every value a requirement reaches
// is graded with its claim, each obligation on its parameter; a call whose
// result must be given back exclusive goes to a version of its callee that
// gives it: the original, where the callee's own obligations already ask
// all the summary needs, else a grade copy made by the specializer's one
// clone-and-key template, keyed by the results it gives and the
// parameters it is owed. Each rebuild site becomes a take of the cell at
// its case's entry, whose fields the case's reads become, and an
// idr.token.rebuild that consumes its linear token in place of the construction
// paired with it. Where a value graded with a claim meets a position that
// takes less, it is shared into it.
#include "idr/Transforms/InPlace.h"

#include "Rule.h"

#include "idr/Analysis/Ownership.h"
#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/GradeCopies.h"
#include "idr/Analysis/Ownership/Meets.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <array>
#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRINPLACE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using namespace idr::inplace;
using idr::BitSet;
using idr::IndexVector;
using idr::solver::FunctionId;

// What a refusal's note says of its cause, by the cause's kind.
constexpr std::array<llvm::StringLiteral, 5> notes{
    "used again here, where the call may still hold it",
    "shared here",
    "made here, by an op that says nothing of what it holds",
    "given back here by a callee that may give it back shared",
    "given to the program from outside",
};
static_assert(static_cast<unsigned>(Why::FromOutside) + 1 == notes.size(),
              "a note per cause, in Why's order");

StringRef noteOf(Why why) { return notes[static_cast<unsigned>(why)]; }

// The family as the user wrote it: its declaration's label.
StringRef labelOf(idr::DataType family) {
  return family ? family.getGroup().label(family.getMember()).getValue() : StringRef("value");
}

void report(const Refusal &refusal) {
  InFlightDiagnostic error = idr::refuse(refusal.at, idr::Rule::Uniqueness);
  StringRef family = labelOf(refusal.family);
  if (refusal.callee)
    error << refusal.caller.getSymName() << " passes a shared " << family << " to "
          << refusal.callee->getSymName() << ", which rebuilds it in place";
  else
    error << refusal.caller.getSymName() << " rebuilds a shared " << family << " in place";
  error.attachNote(refusal.cause.at->getLoc()) << noteOf(refusal.cause.why);
}

// The stronger of two claims asked of one value.
void raise(std::optional<Asks> &held, Asks asks) {
  if (!held || *held < asks)
    held = asks;
}

// A version of a function: what each result gives back (none where nothing
// is asked), what each parameter is owed, and, by their positions in the
// one walk of the body, the claim each value is graded with, what each call
// asks of its callee's results and the version of the callee it goes to.
struct Version {
  llvm::SmallVector<std::optional<Asks>, 1> results;
  llvm::SmallVector<std::optional<Asks>, 4> params;
  std::vector<std::optional<Asks>> grades;
  std::vector<llvm::SmallVector<std::optional<Asks>, 1>> demands;
  std::vector<std::uint32_t> targets;
};

// The one walk of a body, numbered: its values, its calls, and its ops in
// pre-order, each by position. A copy is a clone of its original, so the
// walk numbers both alike.
struct Walk {
  explicit Walk(idr::FuncOp fn) {
    idr::ownership::forEachValue(fn, [&](Value value) { values.push_back(value); });
    idr::ownership::forEachCall(fn, [&](idr::CallOp call) { calls.push_back(call); });
    fn->walk<WalkOrder::PreOrder>([&](Operation *op) { ops.push_back(op); });
  }
  SmallVector<Value> values;
  SmallVector<idr::CallOp> calls;
  SmallVector<Operation *> ops;
};

class Writer {
public:
  Writer(idr::ProgramOp program, idr::solver::ProgramGraph &graph, const Summaries &summaries,
         const Keeps &keeps, const Verdict &verdict, SymbolTable &symbols)
      : program(program), graph(graph), summaries(summaries), keeps(keeps), verdict(verdict),
        symbols(symbols), versions(graph.table<std::vector<Version>>()),
        positions(graph.table<std::optional<Positions>>()), bodies(graph.table<Version>()) {}

  LogicalResult write() {
    for (FunctionId fn : graph.functions())
      readBody(fn);
    for (FunctionId fn : graph.functions())
      if (!versions[fn].empty())
        resolve(fn, 0);
    while (!pending.empty()) {
      auto [fn, version] = pending.pop_back_val();
      traceReturns(fn, version);
    }
    return materialize();
  }

private:
  // Where each value, call and op of a function's original body stands in
  // the walk, read before anything changes it: the numbering's maps, which
  // go with the pass.
  struct Positions {
    llvm::DenseMap<Value, std::uint32_t> values;
    llvm::DenseMap<Operation *, std::uint32_t> calls;
    llvm::DenseMap<Operation *, std::uint32_t> ops;
  };

  Positions &positionsOf(FunctionId fn) {
    std::optional<Positions> &at = positions[fn];
    if (!at) {
      at.emplace();
      Walk walk(graph.op(fn));
      for (auto [index, value] : llvm::enumerate(walk.values))
        at->values.try_emplace(value, static_cast<std::uint32_t>(index));
      for (auto [index, call] : llvm::enumerate(walk.calls))
        at->calls.try_emplace(call, static_cast<std::uint32_t>(index));
      for (auto [index, op] : llvm::enumerate(walk.ops))
        at->ops.try_emplace(op, static_cast<std::uint32_t>(index));
    }
    return *at;
  }

  Version blank(FunctionId fn) {
    idr::FuncOp op = graph.op(fn);
    Positions &at = positionsOf(fn);
    Version version;
    version.results.assign(op.getNumResults(), std::nullopt);
    version.params.assign(verdict.obligations[fn].begin(), verdict.obligations[fn].end());
    version.grades.assign(at.values.size(), std::nullopt);
    version.demands.assign(at.calls.size(), {});
    version.targets.assign(at.calls.size(), 0);
    return version;
  }

  // What a body's own starts reach: each rebuild site's cell, and each
  // argument its callee is owed. Every version of the body holds it. A
  // body none of whose values the verdict reaches, and which no call asks a
  // version of, has no version: nothing of it changes but the results of
  // the calls it makes.
  void readBody(FunctionId fn) {
    idr::FuncOp op = graph.op(fn);
    Chains chains(op, graph, summaries, keeps);
    Chains::Reached reached;
    for (const RebuildSite &site : verdict.sites[fn])
      chains.trace(site.taken, Asks::Self, reached);
    idr::ownership::forEachCall(op, [&](idr::CallOp call) {
      FunctionId callee = graph.id(call.getCalleeAttr());
      for (auto [param, arg] : llvm::enumerate(call.getArgOperands()))
        if (std::optional<Asks> owed = verdict.obligations[callee][param])
          chains.trace(arg, *owed, reached);
    });
    if (reached.values.empty() && llvm::none_of(verdict.obligations[fn], [](auto owed) {
          return owed.has_value();
        }))
      return;
    ensure(fn);
    record(fn, bodies[fn], reached);
    versions[fn].front() = bodies[fn];
  }

  // `fn`'s original version, made where a call first asks one of it.
  void ensure(FunctionId fn) {
    if (!versions[fn].empty())
      return;
    bodies[fn] = blank(fn);
    versions[fn].push_back(bodies[fn]);
  }

  void record(FunctionId fn, Version &version, const Chains::Reached &reached) {
    Positions &at = positionsOf(fn);
    for (auto [value, asks] : reached.values)
      raise(version.grades[at.values.lookup(value)], asks);
    for (const Chains::Demand &demand : reached.demands) {
      auto &asked = version.demands[at.calls.lookup(demand.call)];
      if (asked.empty())
        asked.assign(demand.call->getNumResults(), std::nullopt);
      raise(asked[demand.result], demand.asks);
    }
  }

  // What a version that gives back `results` is owed: its function's
  // obligations, and what the summaries of those results need, which may
  // ask no more than the obligations do.
  enum class Beyond : std::uint8_t { Nothing, More };
  struct Owed {
    llvm::SmallVector<std::optional<Asks>, 4> params;
    Beyond beyond = Beyond::Nothing;
  };
  Owed owedFor(FunctionId fn, llvm::ArrayRef<std::optional<Asks>> results) {
    Owed owed{{verdict.obligations[fn].begin(), verdict.obligations[fn].end()}, Beyond::Nothing};
    for (auto [result, asks] : llvm::enumerate(results)) {
      if (!asks)
        continue;
      // Every requirement the verdict reached was met, so its summary is.
      const Need &need = summaries.of(fn, static_cast<unsigned>(result), *asks);
      for (auto [param, strength] : *need)
        if (!owed.params[param] || *owed.params[param] < strength) {
          raise(owed.params[param], strength);
          owed.beyond = Beyond::More;
        }
    }
    return owed;
  }

  // Each call of a version goes to the version of its callee that gives
  // back what the call asks: the original, merged with what it asks, where
  // the callee's obligations cover what that needs; else a copy keyed by
  // its results.
  void resolve(FunctionId fn, std::uint32_t at) {
    Walk walk(graph.op(fn));
    for (auto [index, call] : llvm::enumerate(walk.calls)) {
      // Copied: making a version may move the one it is read from.
      llvm::SmallVector<std::optional<Asks>, 1> asked = versions[fn][at].demands[index];
      if (asked.empty())
        continue;
      FunctionId callee = graph.id(call.getCalleeAttr());
      ensure(callee);
      Owed owed = owedFor(callee, asked);
      std::uint32_t target = 0;
      if (owed.beyond == Beyond::Nothing) {
        Version &original = versions[callee].front();
        bool grew = false;
        for (auto [held, asks] : llvm::zip_equal(original.results, asked))
          if (asks && (!held || *held < *asks)) {
            held = asks;
            grew = true;
          }
        if (grew)
          pending.push_back({callee, 0});
      } else {
        auto same = llvm::find_if(versions[callee], [&](const Version &other) {
          return llvm::equal(other.results, asked);
        });
        target = static_cast<std::uint32_t>(same - versions[callee].begin());
        if (same == versions[callee].end()) {
          Version copy = bodies[callee];
          copy.results.assign(asked.begin(), asked.end());
          copy.params = std::move(owed.params);
          versions[callee].push_back(std::move(copy));
          pending.push_back({callee, target});
        }
      }
      versions[fn][at].targets[index] = target;
    }
  }

  // What a version's results reach, given back at their claims.
  void traceReturns(FunctionId fn, std::uint32_t at) {
    idr::FuncOp op = graph.op(fn);
    auto ret = dyn_cast<idr::ReturnOp>(op.getBody().front().getTerminator());
    if (!ret)
      return;
    Chains chains(op, graph, summaries, keeps);
    Chains::Reached reached;
    for (auto [result, asks] : llvm::enumerate(versions[fn][at].results))
      if (asks)
        chains.trace(ret.getOperand(static_cast<unsigned>(result)), *asks, reached);
    record(fn, versions[fn][at], reached);
    resolve(fn, at);
  }

  idr::ownership::PromiseCopies::Key keyOf(FunctionId owner, idr::FuncOp fn,
                                         const Version &version) {
    idr::ownership::PromiseCopies::Key key{owner, {}, {}};
    for (auto [param, type] : llvm::enumerate(fn.getArgumentTypes()))
      key.params.push_back(version.params[param] ? idr::ownership::claimFor(*version.params[param])
                                                 : idr::ownership::claimOf(type));
    for (auto [result, type] : llvm::enumerate(fn.getResultTypes()))
      key.results.push_back(version.results[result]
                                ? idr::ownership::claimFor(*version.results[result])
                                : idr::ownership::claimOf(type));
    return key;
  }

  // `type` raised to the claim `asks`, where its sharing is still open
  // below it.
  static Type claimed(Type type, Asks asks) {
    idr::Unique claim = idr::ownership::claimFor(asks);
    return idr::ownership::leavesOpen(type, claim) ? idr::ownership::claiming(type, claim) : type;
  }

  // A version's values graded, its parameters with what they are owed, its
  // signature with them.
  static void grade(idr::FuncOp op, const Version &version) {
    Walk walk(op);
    for (auto [value, asks] : llvm::zip_equal(walk.values, version.grades))
      if (asks)
        value.setType(claimed(value.getType(), *asks));
    for (auto [param, asks] : llvm::zip_equal(op.getBody().front().getArguments(), version.params))
      if (asks)
        param.setType(claimed(param.getType(), *asks));
    SmallVector<Type> results(op.getResultTypes());
    for (auto [type, asks] : llvm::zip_equal(results, version.results))
      if (asks)
        type = claimed(type, *asks);
    op.setFunctionType(FunctionType::get(
        op.getContext(), llvm::to_vector(op.getBody().front().getArgumentTypes()), results));
  }

  // Each rebuild site of `op`, a version of `fn`, rewritten: the take of
  // the cell at the case's entry, its fields the case's reads, and the
  // rebuild that consumes its token in place of the construction.
  void rebuild(FunctionId fn, const Walk &walk) {
    Positions &at = positionsOf(fn);
    for (const RebuildSite &site : verdict.sites[fn]) {
      auto match = cast<idr::DataMatchOp>(walk.ops[at.ops.lookup(site.match)]);
      auto construction = cast<idr::DataConOp>(walk.ops[at.ops.lookup(site.construction)]);
      Block &entry = match->getRegion(site.caseIndex).front();
      BlockArgument taken = entry.getArgument(site.taken.getArgNumber());
      OpBuilder builder = OpBuilder::atBlockBegin(&entry);
      auto take = idr::CountTakeOp::create(builder, match.getLoc(), taken);
      for (OpOperand &use : llvm::make_early_inc_range(taken.getUses()))
        if (auto field = dyn_cast<idr::DataFieldOp>(use.getOwner())) {
          field.getResult().replaceAllUsesWith(
              take.getFields()[static_cast<unsigned>(field.getIndex())]);
          field.erase();
        }
      builder.setInsertionPoint(construction);
      auto rebuilt = idr::TokenRebuildOp::create(builder, construction.getLoc(),
                                                 construction.getResult().getType(),
                                                 take.getToken(), construction.getFields());
      construction.getResult().replaceAllUsesWith(rebuilt.getResult());
      construction.erase();
    }
  }

  LogicalResult materialize() {
    // The copies, cloned from their originals before any original changes,
    // each right after its original.
    IndexVector<FunctionId, SmallVector<idr::FuncOp, 1>> ops =
        graph.table<SmallVector<idr::FuncOp, 1>>();
    SmallVector<FunctionId> functions(graph.functions().begin(), graph.functions().end());
    for (FunctionId fn : functions) {
      idr::FuncOp original = graph.op(fn);
      ops[fn].push_back(original);
      for (const Version &version : llvm::drop_begin(versions[fn])) {
        FailureOr<idr::FuncOp> copy = idr::ownership::gradeCopy<idr::ownership::PromiseCopies>(
            original, keyOf(fn, original, version), symbols);
        if (failed(copy))
          return failure();
        ops[fn].push_back(*copy);
      }
    }
    // Every version graded before any call reads a callee's signature.
    for (FunctionId fn : functions)
      for (auto [version, op] : llvm::zip(versions[fn], ops[fn]))
        grade(op, version);
    // Each call to the version it asks for; then the results of every call
    // of a function whose signature changed are its callee's again, and
    // every position of a function that changed or calls one is met.
    BitSet<FunctionId> touched(graph.size());
    for (FunctionId fn : functions)
      for (auto [version, op] : llvm::zip(versions[fn], ops[fn])) {
        (void)touched.raise(fn);
        for (FunctionId caller : graph.callers(fn))
          (void)touched.raise(caller);
        Walk walk(op);
        for (auto [index, call] : llvm::enumerate(walk.calls))
          if (!version.demands[index].empty()) {
            FunctionId callee = graph.id(call.getCalleeAttr());
            call.setCalleeAttr(
                FlatSymbolRefAttr::get(ops[callee][version.targets[index]].getSymNameAttr()));
          }
        rebuild(fn, walk);
      }
    auto calleeOf = [&](idr::CallOp call) {
      return symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
    };
    for (FunctionId fn : functions) {
      if (!touched.test(fn))
        continue;
      for (idr::FuncOp op : ops[fn]) {
        op.walk([&](idr::CallOp call) {
          for (auto [result, type] :
               llvm::zip_equal(call->getResults(), calleeOf(call).getResultTypes()))
            result.setType(type);
        });
        idr::ownership::shareIntoPositions(op, calleeOf);
      }
    }
    // The copies join the program graph, every version's row what its
    // calls now name, and every row its derivation again.
    idr::solver::Editor editor = graph.thaw();
    SmallVector<std::pair<FunctionId, idr::FuncOp>> edited;
    for (FunctionId fn : functions) {
      if (versions[fn].empty())
        continue;
      edited.emplace_back(fn, ops[fn].front());
      for (idr::FuncOp copy : llvm::drop_begin(ops[fn]))
        edited.emplace_back(editor.insert(copy), copy);
    }
    for (auto [id, op] : edited)
      editor.setCallees(id, idr::solver::rowOf(op, editor));
    std::move(editor).freeze();
    idr::rows::write(program, graph);
    return success();
  }

  idr::ProgramOp program;
  idr::solver::ProgramGraph &graph;
  const Summaries &summaries;
  const Keeps &keeps;
  const Verdict &verdict;
  SymbolTable &symbols;
  IndexVector<FunctionId, std::vector<Version>> versions;
  IndexVector<FunctionId, std::optional<Positions>> positions;
  IndexVector<FunctionId, Version> bodies;
  SmallVector<std::pair<FunctionId, std::uint32_t>> pending;
};

struct InPlace : idr::impl::IdrInPlaceBase<InPlace> {
  void runOnProgram(idr::ProgramOp program) {
    idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    Keeps keeps = keepsOf(graph);
    Summaries summaries = summariesOf(graph, keeps);
    Verdict verdict = decide(graph, summaries, keeps);
    if (!verdict.refusals.empty()) {
      for (const Refusal &refusal : verdict.refusals)
        report(refusal);
      return signalPassFailure();
    }
    bool promised = llvm::any_of(graph.functions(),
                                 [&](FunctionId fn) { return !verdict.sites[fn].empty(); });
    if (!promised) {
      markAllAnalysesPreserved();
      return;
    }
    if (failed(Writer(program, graph, summaries, keeps, verdict, getAnalysis<SymbolTable>()).write()))
      return signalPassFailure();
    markAnalysesPreserved<idr::solver::ProgramGraph, SymbolTable>();
  }
};

} // namespace
