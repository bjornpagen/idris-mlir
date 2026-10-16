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
// hold its op half done: idr-rc (Ownership/Rc.cpp) grades every value
// owned and sets the owned stage, then places the counts in such a run, so
// the program it holds before that run does not verify. A contract is a
// relation at a pass's boundary, so the pass is checked whole.

#include "idr/Transforms/Contracts.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Expect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassRegistry.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"

#include <cassert>
#include <system_error>

using namespace mlir;

namespace idr {

namespace {

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

// What each idr.func of the module's program declares, by symbol. Once
// lowered, the program's functions are upstream's, which declare none of
// it.
llvm::DenseMap<StringAttr, FunctionFacts> factsOf(ModuleOp module) {
  llvm::DenseMap<StringAttr, FunctionFacts> facts;
  for (FunctionOpInterface function : expect::functionsOf(module))
    if (auto fn = dyn_cast<FuncOp>(function.getOperation()))
      facts.try_emplace(fn.getSymNameAttr(),
                        FunctionFacts{fn.getEffects(),
                                      llvm::map_to_vector(fn.getArgumentTypes(), quantityOf),
                                      llvm::map_to_vector(fn.getResultTypes(), quantityOf)});
  return facts;
}

// Prints the module with its locations to a new temporary file, which
// `snapshot` owns from the moment it exists, so that every way out removes
// it; what kept the module from being written, if anything did.
std::error_code writeModule(ModuleOp module, Snapshot &snapshot) {
  int fd = -1;
  llvm::SmallString<128> path;
  if (std::error_code ec = llvm::sys::fs::createTemporaryFile("idr-contracts", "mlir", fd, path))
    return ec;
  snapshot.printed = std::make_unique<llvm::FileRemover>(path);
  snapshot.path = path.str().str();
  llvm::raw_fd_ostream os(fd, /*shouldClose=*/true);
  module->print(os, OpPrintingFlags().enableDebugInfo(/*enable=*/true, /*prettyForm=*/false));
  os.close();
  std::error_code ec = os.error();
  os.clear_error();
  return ec;
}

// A function the pass kept: an idr.func of the program after it whose
// symbol the snapshot holds, and what it declared before. A function the
// pass made or erased is compared with nothing: a copy it makes (a
// specialization's raise node, a trmc clone) has no predecessor with its
// contract.
struct Kept {
  FuncOp fn;
  const FunctionFacts *before;
};

// The error that `relation` is broken by `pass`, at `loc`; a relation that
// says where goes on after a colon.
InFlightDiagnostic broken(Location loc, StringRef relation, StringRef pass) {
  return emitError(loc) << "contract " << relation << " broken by " << pass;
}

// A relation idr-expect states of the module: its property, which reports
// each place it fails, then the contract's error at the module.
bool stated(StringRef relation, expect::Check property, StringRef argument, StringRef pass,
            ModuleOp module, AnalysisManager &analyses) {
  if (succeeded(property(module, analyses, argument)))
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
    auto compare = [&](StringRef what, ArrayRef<Quantity> declared, ArrayRef<Type> types) {
      if (declared.size() != types.size())
        return;
      for (auto [i, then, type] : llvm::enumerate(declared, types)) {
        Quantity now = quantityOf(type);
        if (now == then)
          continue;
        broken(k.fn.getLoc(), "linear-kept", pass)
            << ": " << what << " " << i << " of @" << k.fn.getSymName() << " has quantity "
            << stringifyQuantity(now) << " after it, and had " << stringifyQuantity(then)
            << " before it";
        held = false;
      }
    };
    compare("parameter", k.before->parameters, k.fn.getArgumentTypes());
    compare("result", k.before->results, k.fn.getResultTypes());
  }
  return held;
}

// effects-not-widened: what a function the pass kept may do after it is
// among what it might do before.
bool effectsNotWidened(StringRef pass, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    Effect now = k.fn.getEffects();
    if (bitEnumContainsAll(k.before->effects, now))
      continue;
    broken(k.fn.getLoc(), "effects-not-widened", pass)
        << ": @" << k.fn.getSymName() << " may do " << stringifyEffect(now)
        << " after it, and did " << stringifyEffect(k.before->effects) << " before it";
    held = false;
  }
  return held;
}

// crash-sites-not-added: a function the pass kept that could not crash
// before it has no place that may crash after it, by idr-expect's
// crash-sites. That property is reached through its argument, `@f:0`,
// which names every function made from f and splits at the first `:`, so
// it is asked of a function only when no other function is made from its
// symbol and the symbol holds no `:`.
bool crashSitesNotAdded(StringRef pass, ModuleOp module, AnalysisManager &analyses,
                        MutableArrayRef<FunctionOpInterface> functions, ArrayRef<Kept> kept) {
  bool held = true;
  for (Kept k : kept) {
    StringRef symbol = k.fn.getSymName();
    auto madeFrom = [&](FunctionOpInterface fn) { return expect::names(fn, symbol); };
    if (bitEnumContainsAny(k.before->effects, Effect::crash) || symbol.contains(':') ||
        llvm::count_if(functions, madeFrom) != 1)
      continue;
    if (succeeded(expect::crashSites(module, analyses, (llvm::Twine("@") + symbol + ":0").str())))
      continue;
    broken(k.fn.getLoc(), "crash-sites-not-added", pass) << ": @" << symbol;
    held = false;
  }
  return held;
}

// effects-not-widened, broken: every function may do IO. Every caller
// widens with its callees, so each still covers what it calls.
void widenEffects(ProgramOp program) {
  for (FuncOp fn : program.getOps<FuncOp>())
    setEntry(fn, fn.getEffects() | Effect::io);
}

// linear-kept, broken: every function no symbol use names gives back each
// of its linear results unrestricted, its one use moved to the return. No
// call sees the new type; the root is no such function, since the program
// names it outside its body. A result that is no linear value (the world,
// a destination) is left as it is, as only a linear value has a use.
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

  Option<std::string> relation{
      *this, "relation",
      llvm::cl::desc("The contract to break: effects-not-widened or linear-kept")};

  void runOnOperation() override {
    ProgramOp program = getOperation();
    if (relation.getValue() == "effects-not-widened")
      return widenEffects(program);
    if (relation.getValue() == "linear-kept")
      return unrestrictResults(program);
    // The option is the command line's text, which may name another
    // relation or none.
    program.emitError("test-idr-break-contract: relation is effects-not-widened or linear-kept");
    signalPassFailure();
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
  Snapshot &snapshot = at->second;
  ModuleOp module = moduleOf(op);
  snapshot.pass = pass;
  snapshot.functions = factsOf(module);
  if (std::error_code ec = writeModule(module, snapshot)) {
    // The file goes first. The entry stays this run's, and goes with the
    // run MLIR then reports failed.
    snapshot.printed.reset();
    module.emitError() << "--idr-contracts: cannot write the module before " << nameOf(pass)
                       << ": " << ec.message();
    signalPassFailure(pass);
  }
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
  SmallVector<FunctionOpInterface> functions = expect::functionsOf(module);
  SmallVector<Kept> kept;
  for (FunctionOpInterface function : functions)
    if (auto fn = dyn_cast<FuncOp>(function.getOperation()))
      if (auto was = snapshot.functions.find(fn.getSymNameAttr()); was != snapshot.functions.end())
        kept.push_back({fn, &was->second});

  // Every relation is checked, in this order, each reporting every place
  // it fails.
  bool held =
      stated("quantities-kept", expect::quantitiesKept, snapshot.path, name, module, analyses);
  held = linearKept(name, kept) && held;
  held = effectsNotWidened(name, kept) && held;
  held = crashSitesNotAdded(name, module, analyses, functions, kept) && held;
  held = stated("folds-balanced", expect::foldsBalanced, "", name, module, analyses) && held;
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
