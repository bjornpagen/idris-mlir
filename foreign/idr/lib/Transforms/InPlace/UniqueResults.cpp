// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-unique-results (idr/Transforms/InPlace.h): the local rule solved
// (Unique.cpp), then written into the types.
//
// A value is raised only where its claim is kept: by a result raised, by an
// op that infers its results from it (a read, a take, which reads the
// claim), and by a kept value it moves, is read or is built into, so a
// value whose only use takes less is left as it is and no share is made
// for it. Every signature is written first; then each body in the one
// walk's order, so a value's sources are written before it: its raised
// values, each call's results its callee's again, each kept position that
// keeps its operand's value and flows on linearly at its operand's claim
// (one copied keeps its own, which may forget it), and each op of ours
// that infers its results inferred again where an operand changed or a
// step before the rule graded one. Last, wherever a value now claiming
// more meets a use that takes less, it is shared into it: at a call, a
// return, a forward or an op of upstream's as every pass that raises a
// claim meets them, and before any other op that would read a type it does
// not take.
#include "idr/Transforms/InPlace.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Meets.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/InPlace/Unique.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRUNIQUERESULTS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using namespace idr::unique;
using idr::FuncOp;
using idr::Unique;
using idr::ownership::Term;
using idr::ownership::Via;

enum class Kept : std::uint8_t { No, Yes };
enum class Touched : std::uint8_t { No, Yes };

// The values of `body` whose claims are kept, from `seeds`, back along each
// raised or read value's terms to what it is moved, read or built from, and
// from a position that keeps its operand's value to the operand.
idr::footprint::Vector<Kept> keptOf(const Body &body, llvm::ArrayRef<Local> seeds) {
  idr::footprint::Vector<Kept> kept(body.nodes.size(), Kept::No);
  idr::footprint::Vector<Local> work;
  auto keep = [&](Local at) {
    if (at != noLocal && kept[at] == Kept::No) {
      kept[at] = Kept::Yes;
      work.push_back(at);
    }
  };
  for (Local seed : seeds)
    keep(seed);
  while (!work.empty()) {
    Local at = work.back();
    work.pop_back();
    const Node &node = body.nodes[at];
    if (node.role == Role::Same)
      keep(node.first);
    if (node.role != Role::Raised && node.role != Role::Read)
      continue;
    for (std::uint32_t term = node.first; term != node.last; ++term) {
      const Term<Local> &each = body.terms[term];
      if (each.via == Via::Moved || each.via == Via::ReadOut || each.via == Via::Built)
        keep(each.from);
    }
  }
  return kept;
}

// Whether `use`, of a value now claiming more, takes it as it is: a
// position the meeting of positions settles (a call's argument, a return,
// a forwarded value, an operand of an op of upstream's, met at the bare
// grade), an op of ours whose results follow its operands (one that keeps
// its operand's value, one that infers its results), a field moved into a
// value the op builds, which any claim fills, or an op that moves nothing
// of the value.
bool takesRaised(OpOperand &use) {
  Operation *user = use.getOwner();
  if (idr::ownership::carriersOnly(user) || isa<CallOpInterface, InferTypeOpInterface>(user) ||
      user->hasTrait<OpTrait::ReturnLike>() || user->hasTrait<idr::SameValue>())
    return true;
  bool forwarded = false;
  idr::forwardedValues(user, [&](OpOperand &operand, Value) { forwarded |= &operand == &use; });
  if (forwarded)
    return true;
  auto declared = dyn_cast<idr::FlowOpInterface>(user);
  if (!declared)
    return false;
  idr::FlowEdges edges;
  declared.getFlowEdges(edges);
  bool built = false;
  bool named = false;
  auto names = [&](const idr::FlowSource &source) {
    return source.taken() == &use || source.value() == use.get();
  };
  auto namesPlace = [&](const idr::FlowPlace &place) { return place.value() == use.get(); };
  for (const idr::FlowEdges::Edge &edge : edges.edges())
    idr::match(
        edge.move,
        [&](const idr::FlowEdges::Flow &flow) {
          if (!names(flow.from) && !namesPlace(flow.to))
            return;
          named = true;
          bool moved = idr::match(
              flow.from.at, [&](const idr::FlowSource::Taken &taken) { return taken.use == &use; },
              [](const idr::ownership::NotTaken auto &) { return false; });
          bool intoBuilt = idr::match(
              flow.to.at, [](const idr::FlowPlace::Part &) { return true; },
              [](const idr::ownership::WholePlace auto &) { return false; });
          built |= moved && intoBuilt;
        },
        [&](const idr::FlowEdges::Release &release) { named |= release.use == &use; },
        [&](const idr::FlowEdges::Unify &unify) {
          named |= namesPlace(unify.a) || namesPlace(unify.b);
        },
        [&](const idr::FlowEdges::Overwrite &overwrite) {
          named |= overwrite.place.of == use.get();
        },
        [&](const idr::FlowEdges::Fill &fill) { named |= fill.place.of == use.get(); },
        [](const idr::OneOf<idr::FlowEdges::Source, idr::FlowEdges::Fresh, idr::FlowEdges::Constant,
                            idr::FlowEdges::Dispatch> auto &) {});
  return built || !named;
}

// The values of one body whose types changed: [from, to) of the writer's.
struct Run {
  std::size_t from = 0;
  std::size_t to = 0;
};

class Writer {
public:
  Writer(const idr::solver::ProgramGraph &graph, Solution &solution)
      : graph(graph), solution(solution), resultsChanged(graph.table<Touched>(Touched::No)),
        runs(graph.table<Run>()) {}

  // Every signature, then every body, then every body that changed met;
  // the results raised.
  unsigned write() {
    unsigned count = 0;
    for (FunctionId f : graph.functions())
      count += writeSignature(f);
    for (FunctionId f : graph.functions())
      writeBody(f);
    for (FunctionId f : graph.functions())
      if (runs[f].from != runs[f].to)
        meet(f);
    return count;
  }

private:
  unsigned writeSignature(FunctionId f) {
    FuncOp fn = graph.op(f);
    llvm::SmallVector<Type> results(fn.getResultTypes());
    unsigned count = 0;
    for (auto [index, type] : llvm::enumerate(results)) {
      Unique given = solution.results[f][index];
      if (idr::ownership::covers(idr::ownership::claimOf(type), given))
        continue;
      type = idr::ownership::claiming(type, given);
      ++count;
    }
    if (count == 0)
      return 0;
    resultsChanged[f] = Touched::Yes;
    fn.setFunctionType(FunctionType::get(
        fn.getContext(), llvm::to_vector(fn.getBody().front().getArgumentTypes()), results));
    return count;
  }

  void writeBody(FunctionId f) {
    Body &body = *solution.bodies[f];
    FuncOp fn = body.fn;
    // A result its signature now raises keeps what it returns.
    llvm::SmallVector<Local> seeds;
    if (body.returns == Returns::Yes)
      for (auto [index, type] : llvm::enumerate(fn.getResultTypes()))
        if (!idr::ownership::covers(body.nodes[body.returned[index]].typed,
                                    idr::ownership::claimOf(type)))
          seeds.push_back(body.returned[index]);
    for (Local read : body.inferring)
      if (!idr::ownership::covers(body.nodes[read].typed, body.claims[read]))
        seeds.push_back(read);
    idr::footprint::Vector<Kept> kept = keptOf(body, seeds);

    // The body numbered again, as the solve read it, for the operands of an
    // op whose results follow them: the solver's numbering, whose one map
    // goes with the body.
    Locals numbering(fn);
    auto local = [&](Value value) -> Local { return numbering.at(value).index(); };
    idr::footprint::Vector<Touched> touched(body.nodes.size(), Touched::No);
    auto change = [&](Value value, Type type) {
      if (value.getType() == type)
        return;
      changed.emplace_back(value, value.getType());
      value.setType(type);
      touched[local(value)] = Touched::Yes;
    };
    auto anyTouched = [&](Operation *op) {
      return llvm::any_of(op->getOperands(),
                          [&](Value operand) { return touched[local(operand)] == Touched::Yes; });
    };
    // A result read out of an operand a step before the rule graded (a
    // parameter graded at the boundary), which the solve proves claims more
    // than its type: its op was inferred before that grade.
    auto stale = [&](Operation *op) {
      return llvm::any_of(op->getResults(), [&](Value result) {
        Local at = local(result);
        return body.nodes[at].role == Role::Read && body.claims[at] != body.nodes[at].typed;
      });
    };
    auto raise = [&](Value value) {
      Local at = local(value);
      if (body.nodes[at].role == Role::Raised && kept[at] == Kept::Yes &&
          !idr::ownership::covers(body.nodes[at].typed, body.claims[at]))
        change(value, idr::ownership::claiming(value.getType(), body.claims[at]));
    };
    runs[f].from = changed.size();
    fn->walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        raise(arg);
      for (Operation &op : *block) {
        if (auto call = dyn_cast<idr::CallOp>(&op)) {
          FunctionId callee = graph.id(call.getCalleeAttr());
          if (resultsChanged[callee] == Touched::No)
            continue;
          llvm::SmallVector<Type> before(call->getResultTypes());
          call.copyCallee(graph.op(callee));
          for (auto [result, type] : llvm::zip_equal(call->getResults(), before)) {
            Type now = result.getType();
            result.setType(type);
            change(result, now);
          }
        } else if (op.hasTrait<idr::SameValue>()) {
          // A result kept as its operand, where its claim is kept, claims
          // what its operand now does; one copied keeps its own grade.
          Unique operand = idr::ownership::claimOf(op.getOperand(0).getType());
          for (Value result : op.getResults()) {
            Local at = local(result);
            if (body.nodes[at].role == Role::Same && kept[at] == Kept::Yes &&
                !idr::ownership::covers(idr::ownership::claimOf(result.getType()), operand))
              change(result, idr::ownership::claiming(result.getType(), operand));
          }
        } else if (auto infer = dyn_cast<InferTypeOpInterface>(&op);
                   infer && !idr::ownership::carriersOnly(&op)) {
          if (anyTouched(&op) || stale(&op))
            reinfer(infer, change);
        } else {
          for (Value result : op.getResults())
            raise(result);
        }
      }
    });
    runs[f].to = changed.size();
  }

  // `infer`'s results inferred again from its operands as now written: what
  // it gives is a fact of what it reads. An op that admits its results at
  // more grades than it infers keeps them. An op of upstream's is never
  // inferred again: it reads its operands at the bare grade, met after.
  template <class Change>
  void reinfer(InferTypeOpInterface infer, Change &&change) {
    Operation *op = infer.getOperation();
    llvm::SmallVector<Type> inferred;
    if (failed(infer.inferReturnTypes(op->getContext(), op->getLoc(), op->getOperands(),
                                      op->getRawDictionaryAttrs(), op->getPropertiesStorage(),
                                      op->getRegions(), inferred)) ||
        infer.isCompatibleReturnTypes(inferred, op->getResultTypes()))
      return;
    for (auto [result, type] : llvm::zip_equal(op->getResults(), inferred))
      change(result, type);
  }

  // Each use of a value of `f`'s body now claiming more, met: shared into
  // an op that would read a type it does not take, then every position.
  void meet(FunctionId f) {
    llvm::SmallVector<std::pair<OpOperand *, Type>> unmet;
    for (std::size_t each = runs[f].from; each != runs[f].to; ++each)
      for (OpOperand &use : changed[each].first.getUses())
        if (!takesRaised(use))
          unmet.emplace_back(&use, changed[each].second);
    for (auto [use, before] : unmet) {
      Operation *user = use->getOwner();
      OpBuilder builder(user);
      Value shared = idr::CountShareOp::create(builder, user->getLoc(), before, use->get());
      use->set(shared);
    }
    idr::ownership::shareIntoPositions(graph.op(f), [&](idr::CallOp call) {
      return graph.op(graph.id(call.getCalleeAttr()));
    });
    idr::ownership::shareIntoCarriers(graph.op(f));
  }

  const idr::solver::ProgramGraph &graph;
  Solution &solution;
  idr::IndexVector<FunctionId, Touched> resultsChanged;
  // Each value whose type changed, with its type before, each body's its
  // run.
  idr::footprint::Vector<std::pair<Value, Type>> changed;
  idr::IndexVector<FunctionId, Run> runs;
};

struct UniqueResults : idr::impl::IdrUniqueResultsBase<UniqueResults> {
  void runOnProgram(idr::ProgramOp program) {
    const idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::solver::Work work;
    numUnique += idr::unique::raiseClaims(graph, *program.getContext(), work);
    numWork += work.steps();
    // No call changed callee or kind, and no symbol changed.
    markAnalysesPreserved<idr::solver::ProgramGraph, SymbolTable>();
  }
};

} // namespace

unsigned idr::unique::raiseClaims(const idr::solver::ProgramGraph &graph, MLIRContext &context,
                                  idr::solver::Work &work) {
  Solution solution = solve(graph, context, work);
  return Writer(graph, solution).write();
}
