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
// buffers), so no relation holds a row to the one before.

#include "idr/Transforms/Contracts.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Effects/Vocabulary.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
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
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/raw_ostream.h"

#include <concepts>

using namespace mlir;

namespace idr {

namespace {

// The relations checked after a pass, in the order they are checked; the
// name of each is its error's and the test pass's option's.
enum class Relation : std::uint8_t { QuantitiesKept, LinearKept, CrashSitesNotAdded };

struct RelationRow {
  Relation relation;
  llvm::StringLiteral name;
  // How the test pass breaks it, the help of its option's value.
  llvm::StringLiteral breaks;
};

// The one table of the relations: each one's name, and how the test pass
// breaks it.
constexpr RelationRow relations[] = {
    {Relation::QuantitiesKept, "quantities-kept",
     "trade the identities of two binders of other uses"},
    {Relation::LinearKept, "linear-kept", "give a linear result back unrestricted"},
    {Relation::CrashSitesNotAdded, "crash-sites-not-added",
     "make every function that could not crash crash"},
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

// The facts of one function the relations compare.
FunctionRecord recordOf(FuncOp fn) {
  auto uses = [](TypeRange types) { return llvm::map_to_vector(types, [](Type t) { return usesOf(t); }); };
  return {fn.getSymNameAttr(), uses(fn.getArgumentTypes()), uses(fn.getResultTypes()),
          fn.getRow().contains(effects::Atom::crash) ? MayCrash::Yes : MayCrash::No};
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
// made or erased is compared with nothing: a copy's signature is derived
// from its source's by the one derivation the copying passes share.
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

// The error that `relation` is broken by `pass`, at `loc`; a relation that
// says where goes on after a colon.
InFlightDiagnostic broken(Location loc, Relation relation, StringRef pass) {
  return emitError(loc) << "contract " << nameOf(relation) << " broken by " << pass;
}

// linear-kept: every parameter and every result of a function the pass
// kept has the uses it had. A pass may drop a parameter or a result (a
// dead one), after which a position names another value, so a list is
// compared where its length is unchanged; a changed one is a signature the
// pass derived, by the derivation the copying passes share.
bool linearKept(StringRef pass, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    auto compare = [&](StringRef what, ArrayRef<Uses> before, TypeRange now) {
      if (before.size() != now.size())
        return;
      for (auto [i, was, type] : llvm::enumerate(before, now)) {
        Uses is = usesOf(type);
        if (is == was)
          continue;
        broken(k.now.getLoc(), Relation::LinearKept, pass)
            << ": " << what << " " << i << " of @" << k.now.getSymName() << " is "
            << stringifyUses(is) << " after it, and was " << stringifyUses(was) << " before it";
        held = false;
      }
    };
    compare("parameter", k.before->parameters, k.now.getArgumentTypes());
    compare("result", k.before->results, k.now.getResultTypes());
  }
  return held;
}

// crash-sites-not-added: a function the pass kept whose row could not
// crash before it has no place that may crash after it, counted as
// idr-expect's crash-sites counts them, of that function alone.
bool crashSitesNotAdded(StringRef pass, SymbolTable &symbols, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    if (k.before->crash == MayCrash::Yes || expect::crashSitesOf(k.now, symbols) == 0)
      continue;
    broken(k.now.getLoc(), Relation::CrashSitesNotAdded, pass) << ": @" << k.now.getSymName();
    held = false;
  }
  return held;
}

// linear-kept, broken: every function no symbol use names gives back each
// of its linear results unrestricted, its one use the cast to many at the
// return. No call sees the new type; the root is no such function, since
// the program names it outside its body.
void unrestrictResults(ProgramOp program) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (fn.isRoot() || !SymbolTable::symbolKnownUseEmpty(fn, program))
      continue;
    SmallVector<Type> results = llvm::to_vector(fn.getResultTypes());
    for (unsigned i = 0; i != results.size(); ++i) {
      if (!isLinear(results[i]))
        continue;
      results[i] = atUses(results[i], Uses::Many);
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
void addCrashSites(ProgramOp program, const solver::ProgramGraph &graph) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (fn.getRow().contains(effects::Atom::crash))
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
// proved used once and the first it proved used many, each known by its
// identity, trade locations, and with them identities. Every type and
// every signature stays as it was, so the module verifies and no relation
// over signatures sees a change; each binder Idris proved is now at the
// other's uses.
void tradeIdentities(ProgramOp program) {
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
    Location onceAt = once.getLoc();
    once.setLoc(many.getLoc());
    many.setLoc(onceAt);
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

  void runOnOperation() override {
    ProgramOp program = getOperation();
    switch (relation.getValue()) {
    case Relation::QuantitiesKept:
      return tradeIdentities(program);
    case Relation::LinearKept:
      return unrestrictResults(program);
    case Relation::CrashSitesNotAdded:
      return addCrashSites(program, getAnalysis<solver::ProgramGraph>());
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

  // Every relation is checked, in this order, each reporting every place
  // it fails.
  bool held = true;
  if (failed(expect::usesKept(*proved, module, nameOf(Relation::QuantitiesKept)))) {
    broken(module.getLoc(), Relation::QuantitiesKept, name);
    held = false;
  }
  held = linearKept(name, kept) && held;
  held = crashSitesNotAdded(name, symbols, kept) && held;
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
