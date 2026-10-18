// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// --idr-contracts: what every pass keeps between the module before it and
// the module after it, checked by MLIR's pass instrumentation as the pass
// runs; and the pass that breaks a contract on purpose for their test.
//
// A run is checked when its op is the module or the program: those run on
// the pass manager's own thread, and a pass on each function is checked as
// the nest that runs it on the program. A run on an op another run is on
// is part of that run, and is checked as it. A nest adaptor runs its passes
// on the ops its op holds, never on its own, so such a run comes only from
// a pass that runs passes through its own pipeline (MLIR's runPipeline,
// which Pass.cpp's dynamic pipeline callback instruments as any other),
// and every one of ours runs them on its own op. Between them the pass may
// hold its op half done: idr-rc-exclusive writes the exclusive grades of
// the whole program, then commits them function by function in such a
// run. A contract is a relation at a pass's boundary, so the pass is
// checked whole.
//
// The state before a run is a clone of the module, which the relations
// read as they read the module after it: idr-expect's typed checks take it
// as their module of reference, and each function the pass kept is
// compared with the clone's function of its symbol.

#include "idr/Transforms/Contracts.h"

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <cassert>

using namespace mlir;

namespace idr {

namespace {

// The relations checked after a pass, in the order they are checked; the
// name of each is its error's and the test pass's option's.
enum class Relation {
  QuantitiesKept,
  LinearKept,
  EffectsNotWidened,
  CrashSitesNotAdded,
  FoldsBalanced,
};

StringRef nameOf(Relation relation) {
  switch (relation) {
  case Relation::QuantitiesKept:
    return "quantities-kept";
  case Relation::LinearKept:
    return "linear-kept";
  case Relation::EffectsNotWidened:
    return "effects-not-widened";
  case Relation::CrashSitesNotAdded:
    return "crash-sites-not-added";
  case Relation::FoldsBalanced:
    return "folds-balanced";
  }
  llvm_unreachable("a relation the contracts check");
}

// The relations the test pass breaks, each with its relation's value, so
// its name is the relation's: quantities-kept and folds-balanced are
// idr-expect's properties, which idr-expect's own tests make fail.
enum class Breakable {
  LinearKept = static_cast<int>(Relation::LinearKept),
  EffectsNotWidened = static_cast<int>(Relation::EffectsNotWidened),
  CrashSitesNotAdded = static_cast<int>(Relation::CrashSitesNotAdded),
};

// Whether a run of a pass on `op` is checked: one on the module or on its
// program. A run inside the program comes from a worker thread and touches
// nothing here.
bool checked(Operation *op) { return isa<ModuleOp, ProgramOp>(op); }

// The module a check reads: the one checked, or the one that holds the
// program checked.
ModuleOp moduleOf(Operation *op) {
  if (auto module = dyn_cast<ModuleOp>(op))
    return module;
  return op->getParentOfType<ModuleOp>();
}

// The pass as MLIR writes it in a pipeline: its argument and options, or,
// for a nest adaptor, which has no argument, the pipeline it runs.
std::string nameOf(Pass *pass) {
  std::string name;
  llvm::raw_string_ostream os(name);
  pass->printAsTextualPipeline(os);
  return name;
}

// A function the pass kept: an idr.func of the program after it, and the
// function of its symbol in the copy before it. A function the pass made or
// erased is compared with nothing: a copy it makes (a specialization's
// raise node, a trmc clone) has no predecessor with its contract. Once
// lowered, the program's functions are upstream's, which declare none of
// it.
struct Kept {
  FuncOp now;
  FuncOp before;
};

// The error that `relation` is broken by `pass`, at `loc`; a relation that
// says where goes on after a colon.
InFlightDiagnostic broken(Location loc, Relation relation, StringRef pass) {
  return emitError(loc) << "contract " << nameOf(relation) << " broken by " << pass;
}

// A relation idr-expect states of the module: its check, which reports
// each place it fails, then the contract's error at the module.
bool stated(Relation relation, LogicalResult property, StringRef pass, ModuleOp module) {
  if (succeeded(property))
    return true;
  broken(module.getLoc(), relation, pass);
  return false;
}

// linear-kept: every parameter and every result of a function the pass
// kept has the quantity it had. A pass may drop a parameter or a result (a
// dead one, a returned argument), after which a position names another
// value, so a list is compared only where its length is unchanged.
bool linearKept(StringRef pass, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    auto compare = [&](StringRef what, ArrayRef<Type> before, ArrayRef<Type> now) {
      if (before.size() != now.size())
        return;
      for (auto [i, then, type] : llvm::enumerate(before, now)) {
        Quantity was = quantityOf(then), is = quantityOf(type);
        if (is == was)
          continue;
        broken(k.now.getLoc(), Relation::LinearKept, pass)
            << ": " << what << " " << i << " of @" << k.now.getSymName() << " has quantity "
            << stringifyQuantity(is) << " after it, and had " << stringifyQuantity(was)
            << " before it";
        held = false;
      }
    };
    compare("parameter", k.before.getArgumentTypes(), k.now.getArgumentTypes());
    compare("result", k.before.getResultTypes(), k.now.getResultTypes());
  }
  return held;
}

// effects-not-widened: what a function the pass kept may do after it is
// among what it might do before.
bool effectsNotWidened(StringRef pass, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    Effect now = k.now.getEffects(), before = k.before.getEffects();
    if (bitEnumContainsAll(before, now))
      continue;
    broken(k.now.getLoc(), Relation::EffectsNotWidened, pass)
        << ": @" << k.now.getSymName() << " may do " << stringifyEffect(now)
        << " after it, and did " << stringifyEffect(before) << " before it";
    held = false;
  }
  return held;
}

// crash-sites-not-added: a function the pass kept that could not crash
// before it has no place that may crash after it, counted as idr-expect's
// crash-sites counts them, of that function alone.
bool crashSitesNotAdded(StringRef pass, SymbolTable &symbols, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    if (bitEnumContainsAny(k.before.getEffects(), Effect::crash) ||
        expect::crashSitesOf(k.now, symbols) == 0)
      continue;
    broken(k.now.getLoc(), Relation::CrashSitesNotAdded, pass) << ": @" << k.now.getSymName();
    held = false;
  }
  return held;
}

// effects-not-widened, broken: every function may do IO, written with
// every call of it (writeEffects), so a call holds its callee's effects and
// every caller, which covered its callees', still covers them.
void widenEffects(ProgramOp program) {
  SymbolTableCollection tables;
  SymbolUserMap users(tables, program);
  for (FuncOp fn : program.getOps<FuncOp>())
    writeEffects(fn, fn.getEffects() | Effect::io, users);
}

// linear-kept, broken: every function no symbol use names gives back each
// of its linear results unrestricted, its one use moved to the return. No
// call sees the new type; the root is no such function, since the program
// names it outside its body. Only a result linear by its grade has an
// unrestricted form: one linear by its type (the world, a destination)
// takes no grade, so isLinear, which reads the grade, leaves it as it is.
void unrestrictResults(ProgramOp program) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (fn.isRoot() || !SymbolTable::symbolKnownUseEmpty(fn, program))
      continue;
    SmallVector<Type> results = llvm::to_vector(fn.getResultTypes());
    for (unsigned i = 0; i != results.size(); ++i) {
      if (!isLinear(results[i]))
        continue;
      results[i] = atQuantity(results[i], Quantity::Many);
      fn.walk([&](ReturnOp ret) {
        OpBuilder builder(ret);
        ret->setOperand(i, LinUseOp::create(builder, ret.getLoc(), ret->getOperand(i)));
      });
    }
    fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), results));
  }
}

// crash-sites-not-added, broken: every function that could not crash
// crashes instead of returning, and then every function, with every call of
// it, may crash, so each covers its body and its calls.
void addCrashSites(ProgramOp program) {
  for (FuncOp fn : program.getOps<FuncOp>()) {
    if (bitEnumContainsAny(fn.getEffects(), Effect::crash))
      continue;
    fn.walk([&](ReturnOp ret) {
      OpBuilder builder(ret);
      CrashOp::create(builder, ret.getLoc(), "contract broken");
      ub::UnreachableOp::create(builder, ret.getLoc());
      ret.erase();
    });
  }
  SymbolTableCollection tables;
  SymbolUserMap users(tables, program);
  for (FuncOp fn : program.getOps<FuncOp>())
    writeEffects(fn, fn.getEffects() | Effect::crash, users);
}

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
  void getDependentDialects(DialectRegistry &registry) const final {
    registry.insert<ub::UBDialect>();
  }

  // The option's values are the relations' names; unnamed, the first.
  Option<Breakable> relation{
      *this, "relation", llvm::cl::desc("The contract to break"),
      llvm::cl::init(Breakable::LinearKept),
      llvm::cl::values(
          clEnumValN(Breakable::LinearKept, nameOf(Relation::LinearKept),
                     "give a linear result back unrestricted"),
          clEnumValN(Breakable::EffectsNotWidened, nameOf(Relation::EffectsNotWidened),
                     "let every function do IO"),
          clEnumValN(Breakable::CrashSitesNotAdded, nameOf(Relation::CrashSitesNotAdded),
                     "make every function that could not crash crash"))};

  void runOnOperation() override {
    ProgramOp program = getOperation();
    switch (relation.getValue()) {
    case Breakable::LinearKept:
      return unrestrictResults(program);
    case Breakable::EffectsNotWidened:
      return widenEffects(program);
    case Breakable::CrashSitesNotAdded:
      return addCrashSites(program);
    }
  }
};

} // namespace

void ContractInstrumentation::runBeforePass(Pass *pass, Operation *op) {
  if (!checked(op))
    return;
  std::lock_guard<std::mutex> lock(mutex);
  // The insert decides: an op another run is on already has its entry,
  // and this run, part of that one, takes no snapshot.
  auto [at, outermost] = before.try_emplace(op);
  if (!outermost)
    return;
  at->second.pass = pass;
  at->second.before.op = moduleOf(op).clone();
}

void ContractInstrumentation::runAfterPass(Pass *pass, Operation *op) {
  if (!checked(op))
    return;
  Snapshot snapshot;
  {
    std::lock_guard<std::mutex> lock(mutex);
    // Every run on a checked op finds an entry: its own, or that of the run
    // it is part of, which that run checks.
    auto at = before.find(op);
    assert(at != before.end() && "a run on the module or the program has its entry");
    if (at->second.pass != pass)
      return;
    snapshot = std::move(at->second);
    before.erase(at);
  }

  ModuleOp module = moduleOf(op);
  std::string name = nameOf(pass);
  ModuleAnalysisManager mam(module, /*passInstrumentor=*/nullptr);
  AnalysisManager analyses = mam;
  SymbolTable was(expect::programOf(*snapshot.before.op));
  SmallVector<Kept> kept;
  for (FunctionOpInterface function : expect::functionsOf(module))
    if (auto fn = dyn_cast<FuncOp>(function.getOperation()))
      if (auto then = was.lookup<FuncOp>(fn.getSymNameAttr()))
        kept.push_back({fn, then});

  // Every relation is checked, in this order, each reporting every place
  // it fails.
  bool held = stated(Relation::QuantitiesKept,
                     expect::quantitiesKept({module, analyses, nameOf(Relation::QuantitiesKept),
                                             snapshot.before}),
                     name, module);
  held = linearKept(name, kept) && held;
  held = effectsNotWidened(name, kept) && held;
  held = crashSitesNotAdded(name, expect::symbolsOf(module, analyses), kept) && held;
  held = stated(Relation::FoldsBalanced,
                expect::foldsBalanced(
                    {module, analyses, nameOf(Relation::FoldsBalanced), expect::Nothing{}}),
                name, module) &&
         held;
  if (!held)
    signalPassFailure(pass);
}

void ContractInstrumentation::runAfterPassFailed(Pass *pass, Operation *op) {
  if (!checked(op))
    return;
  std::lock_guard<std::mutex> lock(mutex);
  auto at = before.find(op);
  assert(at != before.end() && "a run on the module or the program has its entry");
  if (at->second.pass == pass)
    before.erase(at);
}

void registerContractTestPass() { PassRegistration<BreakContract>(); }

} // namespace idr
