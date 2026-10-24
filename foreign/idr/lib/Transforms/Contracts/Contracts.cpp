// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// --idr-contracts: what every pass keeps between the module before it and
// the module after it, checked by MLIR's pass instrumentation as the pass
// runs; the promises every compiled program keeps, checked when the
// pipeline ends; and the pass that breaks a contract on purpose for their
// test.
//
// A run is checked when its op is the module or the program: those run on
// the pass manager's own thread, and a pass on each function is checked as
// the nest that runs it on the program. A run on an op another run is on
// is part of that run, and is checked as it: a pass that runs passes
// through its own pipeline runs them on its own op, inside its run, and
// may hold its op half done between them.
//
// The state before a run is a record per function of what the relations
// read, never a copy of the module: each relation is stated over those
// facts, so the contracts on the largest module cost a record per function.
// What a function's row may do is the verifier's to hold to its body after
// every pass; a row widens where a pass adds effects (counting, the arrays'
// buffers), so no relation holds a row to the one before. What no
// function's body shows, the divergence of a cycle of several functions,
// is a relation of the module after the pass alone.

#include "idr/Transforms/Contracts.h"

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Effects/Vocabulary.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Expect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/raw_ostream.h"

#include <concepts>
#include <optional>
#include <variant>

using namespace mlir;

namespace idr {

namespace {

// The relations checked after a pass, in the order they are checked: the
// rows of their one list (ExpectProperties.inc), printed from their
// records beside idr-expect's properties. The name of each is its error's
// and the test pass's option's.
enum class Relation : std::uint8_t {
#define IDR_CONTRACT_RELATION(name, Enumerator, check, breaker, breaks) Enumerator,
#include "idr/Transforms/ExpectProperties.inc"
#undef IDR_CONTRACT_RELATION
};

struct RelationRow {
  Relation relation;
  llvm::StringLiteral name;
  // How the test pass breaks it, the help of its option's value.
  llvm::StringLiteral breaks;
};

constexpr RelationRow relations[] = {
#define IDR_CONTRACT_RELATION(name, Enumerator, check, breaker, breaks)                           \
  {Relation::Enumerator, name, breaks},
#include "idr/Transforms/ExpectProperties.inc"
#undef IDR_CONTRACT_RELATION
};

constexpr llvm::StringLiteral nameOf(Relation relation) {
  return relations[static_cast<unsigned>(relation)].name;
}

// The pass as MLIR writes it in a pipeline: its argument and options, or,
// for a nest adaptor, which has no argument, the pipeline it runs.
std::string nameOf(Pass *pass) {
  std::string name;
  llvm::raw_string_ostream os(name);
  pass->printAsTextualPipeline(os);
  return name;
}

// Whether a run of `fn` may end by a crash, as its row says.
MayCrash mayCrash(FuncOp fn) {
  return fn.getRow().contains(effects::Atom::crash) ? MayCrash::Yes : MayCrash::No;
}

// What a pass may make of a parameter of `type`: one used once stands, since
// Idris checked that it is used and each pass that drops a dead parameter
// holds it read.
StandsFor parameterStandsFor(Type type) {
  return usesOf(type) == Uses::Once ? StandsFor::Once : StandsFor::Many;
}

// What a pass may make of a result of `type`: one used once by its type (a
// cell, a destination, a package) stands, its one use what fills it or gives
// it back; one used once by its grade alone is the one reference its callee
// hands its caller, which a caller that never reads it leaves unused, so it
// may go.
StandsFor resultStandsFor(Type type) {
  if (isLinearByType(type))
    return StandsFor::Once;
  return usesOf(type) == Uses::Once ? StandsFor::OnceOrNone : StandsFor::Many;
}

// The facts of one function the relations compare.
FunctionRecord recordOf(FuncOp fn) {
  return {fn.getSymNameAttr(), llvm::map_to_vector(fn.getArgumentTypes(), parameterStandsFor),
          llvm::map_to_vector(fn.getResultTypes(), resultStandsFor), mayCrash(fn)};
}

// The record of every idr.func of the module's program. Once lowered, the
// program's functions are upstream's, which carry no grade and no row.
Snapshot snapshotOf(Pass *pass, ModuleOp module) {
  Snapshot snapshot;
  snapshot.pass = pass;
  for (FunctionOpInterface function : expect::functionsOf(module))
    if (auto fn = dyn_cast<FuncOp>(function.getOperation()))
      snapshot.functions.push_back(recordOf(fn));
  return snapshot;
}

// A function the pass kept: the record of a symbol before it, and the
// idr.func of the program that symbol names after it. A function the pass
// made has no record. Of what it holds, quantities-kept holds each binder
// Idris bound to the uses Idris proved, wherever the pass put it; its
// other parameters and its results are what the pass that made it
// derived, which no record states.
struct Kept {
  FuncOp now;
  const FunctionRecord *before;
};

SmallVector<Kept> keptOf(const Snapshot &snapshot, SymbolTable &symbols) {
  SmallVector<Kept> kept;
  for (const FunctionRecord &record : snapshot.functions)
    if (auto fn = symbols.lookup<FuncOp>(record.symbol))
      kept.push_back({fn, &record});
  return kept;
}

// What a relation is checked against after a pass: the pass, as MLIR
// writes it in a pipeline; the module after it, with its analyses and its
// program's symbols; the record of each function it kept; and the uses
// Idris proved of each binder.
struct After {
  StringRef pass;
  ModuleOp module;
  AnalysisManager &analyses;
  SymbolTable &symbols;
  ArrayRef<Kept> kept;
  const expect::ProvedUses &proved;
};

// The error that `relation` is broken by `pass`, at `loc`; a relation that
// says where goes on after a colon.
InFlightDiagnostic broken(Location loc, Relation relation, StringRef pass) {
  return emitError(loc) << "contract " << nameOf(relation) << " broken by " << pass;
}

// quantities-kept: each binder found by its identity has the uses Idris
// proved of it, and each parameter Idris proved used once of a function
// the program still has is found by its identity; each one that does not
// is an error at it, and the contract's at the module.
LogicalResult quantitiesKept(const After &after) {
  ModuleOp module = after.module;
  if (succeeded(expect::usesKept(after.proved, module, after.symbols,
                                 nameOf(Relation::QuantitiesKept))))
    return success();
  broken(module.getLoc(), Relation::QuantitiesKept, after.pass);
  return failure();
}

// What a pass may make of a function it keeps, position by position: each
// position its record holds stands for a run of positions after it, in
// order, each at that position's uses. The run is empty where the pass
// dropped a dead position (Demand, Captures, Results), which only one that
// need not stand can be (StandsFor). It is longer than one where the pass
// holds a value as its parts, each at the whole's grade (idr-columns). No
// pass adds a position to a function it keeps: a stack, a destination or a
// lifetime is a parameter of a function it makes. So a list after the pass
// is compared with the runs its record stands for, whatever its length,
// and where it parts from them is one of three places.

// A position after the pass used many times where its record holds one
// used once: no position of the record before that one is left to stand
// for it.
struct ManyForOnce {
  unsigned now;
  unsigned recorded;
};
// A position after the pass that no position of its record is left to
// stand for.
struct Unrecorded {
  unsigned now;
  Uses is;
};
// A position of the record that must stand, standing for none after the
// pass.
struct Gone {
  unsigned recorded;
};
using Parting = std::variant<ManyForOnce, Unrecorded, Gone>;

// The uses of each position a recorded one stands for.
constexpr Uses usesAt(StandsFor position) {
  return position == StandsFor::Many ? Uses::Many : Uses::Once;
}

// The first position at or after `from` of `before` that `is` holds of, if
// any.
template <std::predicate<StandsFor> Is>
std::optional<unsigned> firstFrom(ArrayRef<StandsFor> before, unsigned from, Is is) {
  const StandsFor *found = llvm::find_if(before.drop_front(from), is);
  if (found == before.end())
    return std::nullopt;
  return static_cast<unsigned>(found - before.begin());
}

constexpr bool usedOnce(StandsFor position) { return usesAt(position) == Uses::Once; }
constexpr bool mustStand(StandsFor position) { return position == StandsFor::Once; }

// Where `now` parts from the runs `before` stands for, or nothing where it
// is those runs. A reading of `now` so far is the count i of before's
// positions whose runs are exactly the positions read, the last of them
// able to stand for more; each next position of `now` goes on the last
// run, or begins the run of a later position, those between standing for
// none, which none of them that must stand may do.
std::optional<Parting> partingOf(ArrayRef<StandsFor> before, ArrayRef<Uses> now) {
  const auto count = static_cast<unsigned>(before.size());
  llvm::BitVector readings(count + 1);
  readings.set(0);
  for (auto [at, is] : llvm::enumerate(now)) {
    llvm::BitVector next(count + 1);
    for (unsigned i : readings.set_bits()) {
      if (i != 0 && usesAt(before[i - 1]) == is)
        next.set(i);
      for (unsigned k = i; k != count; ++k) {
        if (usesAt(before[k]) == is)
          next.set(k + 1);
        if (mustStand(before[k]))
          break;
      }
    }
    if (next.none()) {
      auto position = static_cast<unsigned>(at);
      std::optional<unsigned> once =
          firstFrom(before, static_cast<unsigned>(readings.find_last()), usedOnce);
      if (is == Uses::Many && once)
        return ManyForOnce{position, *once};
      return Unrecorded{position, is};
    }
    readings = std::move(next);
  }
  for (unsigned i : readings.set_bits())
    if (!firstFrom(before, i, mustStand))
      return std::nullopt;
  // Every reading leaves a position that must stand standing for none; the
  // first after the furthest reading is left by every reading.
  return Gone{*firstFrom(before, static_cast<unsigned>(readings.find_last()), mustStand)};
}

// linear-kept: every parameter and every result of a function the pass
// kept stands where its record says, at its uses.
LogicalResult linearKept(const After &after) {
  bool held = true;
  for (Kept k : after.kept) {
    auto compare = [&](StringRef what, ArrayRef<StandsFor> before, TypeRange types) {
      SmallVector<Uses> now = llvm::map_to_vector(types, [](Type t) { return usesOf(t); });
      std::optional<Parting> parting = partingOf(before, now);
      if (!parting)
        return;
      InFlightDiagnostic error = broken(k.now.getLoc(), Relation::LinearKept, after.pass)
                                 << ": " << what << " ";
      StringRef fn = k.now.getSymName();
      idr::match(
          *parting,
          [&](const ManyForOnce &p) {
            error << p.now << " of @" << fn << " is many after it, where its record holds "
                  << what << " " << p.recorded << " used once";
          },
          [&](const Unrecorded &p) {
            error << p.now << " of @" << fn << " is " << stringifyUses(p.is)
                  << " after it, and no " << what << " of its record is left to stand for it";
          },
          [&](const Gone &p) {
            error << p.recorded << " of @" << fn << " was once before it, and no " << what
                  << " after it stands for it";
          });
      held = false;
    };
    compare("parameter", k.before->parameters, k.now.getArgumentTypes());
    compare("result", k.before->results, k.now.getResultTypes());
  }
  return success(held);
}

// crash-sites-not-added: a function the pass kept whose row could not
// crash before it cannot crash after it, as its row says. The verifier,
// which runs before the contracts, holds every row to cover its body, so a
// row that cannot crash leaves no place in the body that may crash, and no
// call of a function that may.
LogicalResult crashSitesNotAdded(const After &after) {
  bool held = true;
  for (Kept k : after.kept) {
    if (k.before->crash == MayCrash::Yes || mayCrash(k.now) == MayCrash::No)
      continue;
    broken(k.now.getLoc(), Relation::CrashSitesNotAdded, after.pass) << ": @" << k.now.getSymName();
    held = false;
  }
  return success(held);
}

// cycle-divergence-kept: every member of a cycle of the program Idris did
// not prove together holds the cycle's divergence. A function's check reads
// its body, where a cycle of several shows only through the calls' copies
// of the other members' rows, so members that all dropped it together pass
// every check. The writer's own addCycles runs over the rows the module
// holds, so the rule is read from its one place, and a member whose row it
// grows lost what its cycle adds. A cycle of one is its function's check's,
// which reads the self call, and the verifier runs before the contracts.
// The program graph, which holds the cycles, indexes a first-order program
// of ours alone.
LogicalResult cycleDivergenceKept(const After &after) {
  ProgramOp program = expect::firstOrderProgram(after.module);
  if (!program)
    return success();
  const auto &graph = after.analyses.nest(program).getAnalysis<solver::ProgramGraph>();
  IndexVector<solver::FunctionId, effects::Row> withCycles = graph.table(effects::Row{});
  for (solver::FunctionId f : graph.functions())
    withCycles[f] = graph.op(f).getRow();
  rows::detail::addCycles(graph, withCycles);
  bool held = true;
  for (solver::FunctionId f : graph.functions()) {
    FuncOp fn = graph.op(f);
    if (fn.getRow() == withCycles[f])
      continue;
    broken(fn.getLoc(), Relation::CycleDivergenceKept, after.pass)
        << ": @" << fn.getSymName()
        << " lies on a cycle Idris did not prove, and its row lacks divergence";
    held = false;
  }
  return success(held);
}

// linear-kept, broken: every function no symbol use names gives back each
// of its results used once by its grade unrestricted and claiming nothing,
// its one use the cast to many at the return: the one reference a callee
// hands its caller, and what it claims, are lost. No call sees the new
// signature; the root is no such function, since the program names it
// outside its body.
void breakLinearKept(ProgramOp program, AnalysisManager) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (fn.isRoot() || !SymbolTable::symbolKnownUseEmpty(fn, program))
      continue;
    SmallVector<Type> results = llvm::to_vector(fn.getResultTypes());
    for (unsigned i = 0; i != results.size(); ++i) {
      if (resultStandsFor(results[i]) != StandsFor::OnceOrNone)
        continue;
      results[i] = shared(atUses(results[i], Uses::Many));
      fn.walk([&](ReturnOp ret) {
        OpBuilder builder(ret);
        ret->setOperand(i, LinCastOp::create(builder, ret.getLoc(), results[i], ret->getOperand(i)));
      });
    }
    fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), results));
  }
}

// crash-sites-not-added, broken: every function whose row could not crash
// crashes instead of returning, at its own location, and the one writer of
// rows writes every row again, so each covers its body and every call its
// callee's. The rows' work counts toward no statistic: the test pass runs
// in no pipeline.
void breakCrashSitesNotAdded(ProgramOp program, AnalysisManager analyses) {
  const auto &graph = analyses.getAnalysis<solver::ProgramGraph>();
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (mayCrash(fn) == MayCrash::Yes)
      continue;
    fn.walk([&](ReturnOp ret) {
      OpBuilder builder(ret);
      CrashCauseOp::create(builder, ret.getLoc(), CrashCause::NoClauseMatched, siteOf(fn.getLoc()));
      ret.erase();
    });
  }
  solver::Work written;
  rows::write(program, graph, written);
}

// quantities-kept, broken: in each function, the first parameter Idris
// proved used once takes the location, and with it the identity, of the
// first it proved used many, each known by its identity. Every type and
// every signature stays as it was, so the module verifies and no relation
// over signatures sees a change; the identity Idris proved used many times
// is now on a binder used once, and the one it proved used once is on no
// binder.
void breakQuantitiesKept(ProgramOp program, AnalysisManager) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    BlockArgument once, many;
    for (BlockArgument arg : fn.getArguments()) {
      if (!expect::identityOf(arg.getLoc()))
        continue;
      BlockArgument &first = usesOf(fn.getArgumentTypes()[arg.getArgNumber()]) == Uses::Once ? once : many;
      if (!first)
        first = arg;
    }
    if (!once || !many)
      continue;
    once.setLoc(many.getLoc());
  }
}

// What a member of the cycle `cycle` does by its own ops and by the
// functions outside the cycle it calls: a call of a member is read as
// nothing, any other call by its own copy of its callee's row, as the
// function's check reads it. The fold still reads a call of the function
// itself as the cycle of one it closes.
struct OutsideCycle {
  const solver::ProgramGraph &graph;
  solver::SccId cycle;
  rows::CallCopies copies;

  void call(CallOp call, rows::Fold &fold, Runs runs) {
    if (graph.sccOf(graph.id(call.getCalleeAttr())) != cycle)
      copies.call(call, fold, runs);
  }
  rows::Read other(Operation *, rows::Fold &, Runs) { return rows::Read::ByDeclaration; }
};

static_assert(rows::CallReader<OutsideCycle>);

// cycle-divergence-kept, broken: the first cycle, callees first, that Idris
// did not prove together and whose members may run forever by the cycle
// alone loses its divergence, from every member's row and from every call
// of a member. Each member's body then derives none and each call holds
// its callee's row, so every function's check holds, a caller's outside
// the cycle too, whose row now says more than its body does; only the
// program's cycles show what was dropped. A cycle with a member that may
// run forever by itself (a loop, a call of itself, a call outside the
// cycle that may) is passed over: that member's check would refuse the
// dropped row before any relation ran.
void breakCycleDivergenceKept(ProgramOp program, AnalysisManager analyses) {
  const auto &graph = analyses.getAnalysis<solver::ProgramGraph>();
  constexpr effects::Row divergence{effects::Atom::divergence};
  for (solver::SccId component : graph.sccCount().ids()) {
    if (!graph.onCycle(component))
      continue;
    auto members = llvm::map_range(graph.members(component),
                                   [&](solver::FunctionId f) { return graph.op(f); });
    if (rows::provedTogether(members))
      continue;
    OutsideCycle reader{graph, component, {}};
    if (llvm::any_of(members, [&](FuncOp fn) {
          return rows::derive(fn, reader).atoms.contains(effects::Atom::divergence);
        }))
      continue;
    for (FuncOp fn : members)
      fn.setRow(fn.getRow() - divergence);
    program.walk([&](CallOp call) {
      if (graph.sccOf(graph.id(call.getCalleeAttr())) == component)
        call.setRow(call.getRow() - divergence);
    });
    return;
  }
}

// An option whose parser reads a relation.
template <class Opt>
concept RelationOption = requires(Opt &option) {
  { option.getParser() } -> std::convertible_to<llvm::cl::parser<Relation> &>;
};

// The option's values, one per row of the table: a modifier as
// `llvm::cl::values` is, reading the rows where that one takes a list of
// its own.
struct EachRelation {
  template <RelationOption Opt>
  void apply(Opt &option) const {
    for (const RelationRow &row : relations)
      option.getParser().addLiteralOption(row.name, row.relation, row.breaks);
  }
};

// The pass the contracts' own test runs, registered in idris-mlir-opt
// alone: it breaks one relation on purpose and leaves a module that
// verifies, so that what fails is the contract checked after it.
struct BreakContract : PassWrapper<BreakContract, OperationPass<ProgramOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(BreakContract)

  BreakContract() = default;
  // The manager clones a pass with an option through its copy, then copies
  // the option's value.
  BreakContract(const BreakContract &other) : PassWrapper(other) {}

  StringRef getArgument() const final { return "test-idr-break-contract"; }
  StringRef getDescription() const final {
    return "Break one contract on purpose, keeping the module valid, for the contracts' own "
           "test: --idr-contracts must name this pass";
  }
  Option<Relation> relation{*this, "relation", llvm::cl::desc("The contract to break"),
                            llvm::cl::init(Relation::LinearKept), EachRelation{}};

  // Each relation's breaker, by its row: what it reads of the program it
  // asks of the pass's analyses.
  void runOnOperation() override {
    ProgramOp program = getOperation();
    AnalysisManager analyses = getAnalysisManager();
    switch (relation.getValue()) {
#define IDR_CONTRACT_RELATION(name, Enumerator, check, breaker, breaks)                           \
  case Relation::Enumerator:                                                                      \
    return breaker(program, analyses);
#include "idr/Transforms/ExpectProperties.inc"
#undef IDR_CONTRACT_RELATION
    }
  }
};

} // namespace

void ContractInstrumentation::runBeforePass(Pass *pass, Operation *op) {
  ModuleOp module = expect::checkedModule(op);
  // A run inside the run under way is part of it, and takes no record.
  if (!module || before)
    return;
  // The module the frontend emitted, before the first pass: what Idris
  // proved of its binders, read once. A module Emit gave two binders one
  // identity says so here, at that binder.
  if (!proved) {
    FailureOr<expect::ProvedUses> read = expect::provedUses(module);
    proved = succeeded(read) ? std::move(*read) : expect::ProvedUses();
  }
  before = snapshotOf(pass, module);
}

void ContractInstrumentation::runAfterPass(Pass *pass, Operation *op) {
  ModuleOp module = expect::checkedModule(op);
  if (!module || !before || before->pass != pass)
    return;
  Snapshot snapshot = std::move(*before);
  before.reset();

  std::string name = nameOf(pass);
  ModuleAnalysisManager mam(module, /*passInstrumentor=*/nullptr);
  AnalysisManager analyses = mam;
  SymbolTable &symbols = expect::symbolsOf(module, analyses);
  SmallVector<Kept> kept = keptOf(snapshot, symbols);

  // Every relation is checked, in the order of their rows, each reporting
  // every place it fails.
  After after{name, module, analyses, symbols, kept, *proved};
  bool held = true;
#define IDR_CONTRACT_RELATION(name, Enumerator, check, breaker, breaks)                           \
  held = succeeded(check(after)) && held;
#include "idr/Transforms/ExpectProperties.inc"
#undef IDR_CONTRACT_RELATION
  if (!held)
    signalPassFailure(pass);
}

void ContractInstrumentation::runAfterPassFailed(Pass *pass, Operation *op) {
  if (expect::checkedModule(op) && before && before->pass == pass)
    before.reset();
}

LogicalResult ContractInstrumentation::finish(ModuleOp module) {
  ModuleAnalysisManager mam(module, /*passInstrumentor=*/nullptr);
  AnalysisManager analyses = mam;
  return expect::universal(module, analyses);
}

void registerContractTestPass() { PassRegistration<BreakContract>(); }

} // namespace idr
