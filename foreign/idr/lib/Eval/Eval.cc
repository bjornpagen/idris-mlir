// idr-eval: compile-time evaluation is runtime evaluation, run early. A
// closed call of a function that performs no IO runs the program's own
// lowered code on the same runtime, and its results replace it as
// constants. Whether Idris proves the code terminating decides only how
// much the call may spend, as Idris's own evaluator unfolds partial
// definitions as readily as total ones. Every call runs metered: a call of
// total code ends, but perhaps not soon, so it gets a larger budget than
// one that reaches code Idris does not prove terminating. A call that
// spends its budget, or that the machine refuses memory, stays, to run at
// runtime, as a call that crashes does.

#include "Eval/Child.h"
#include "Eval/Reify.h"
#include "Lower/Runtime.h"
#include "Support/Actions.h"

#include "idr/Idr.h"

#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Conversion/ConvertToLLVM/ToLLVMPass.h"
#include "mlir/Conversion/ReconcileUnrealizedCasts/ReconcileUnrealizedCasts.h"
#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/Support/FormatVariadic.h"

#include <chrono>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREVAL
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

// A call is known by its callee and its constant arguments; a closure's
// captures come before the arguments of its application.
using Key = std::pair<Attribute, Attribute>;

// What a callee computes, as the cache knows it: a clone by its key (its
// owner and the patterns of what it fixed), which tells what it computes,
// any other function by its name. A clone's name does not: once the module
// no longer holds a clone, the next clone of its owner may take its name
// and compute something else.
Attribute calleeKey(func::FuncOp callee) {
  if (auto clone = callee->getAttrOfType<idr::CloneAttr>("idr.clone"))
    return clone.getKey();
  return FlatSymbolRefAttr::get(callee.getSymNameAttr());
}

// How a call runs: what it may spend (ticks, counted where code enters a
// function or goes round a loop, bytes of arena and bytes of stack), and
// how its remark says it did not finish.
struct Meter {
  idr::eval::Budget budget;
  const char *unfinished;
};

// A call of code Idris does not prove terminating may never end, so one
// that does not costs the compilation well under a second.
constexpr Meter partialCode{
    {/*ticks=*/uint64_t{1} << 25, /*bytes=*/uint64_t{1} << 28, /*stack=*/uint64_t{1} << 28},
    "reaches code Idris does not prove terminating and did not finish",
};

// A call of total code ends, and gets room for what a program computes from
// its constants, bounded all the same.
constexpr Meter totalCode{
    {/*ticks=*/uint64_t{1} << 31, /*bytes=*/uint64_t{1} << 32, /*stack=*/uint64_t{1} << 30},
    "did not finish within the budget of total code",
};

// A result is worth its call when its constants take at most this much
// static data. A larger one would make the executable larger than running
// the call does, and its compilation slower: the call stays, to run at
// runtime, as upstream Idris runs its calls there. The value is never at
// stake, only the size and the speed.
constexpr uint64_t resultBytes = uint64_t{1} << 20;

// The table of the address of each label's code, by label number, which the
// reifier reads a closure's label from: a closure is a code pointer and
// captures, nothing more.
constexpr llvm::StringLiteral codesName = "__idr_codes";

// What the child sends for a call: "results" and the results
// (encodeResults), or "too-large" or "unreadable" and why not.
constexpr llvm::StringLiteral sentResults = "results";
constexpr llvm::StringLiteral sentTooLarge = "too-large";
constexpr llvm::StringLiteral sentUnreadable = "unreadable";

struct Outcome {
  SmallVector<Attribute> results;
  // The call crashed or did not finish: it stays, to run at runtime.
  bool stays = false;
};

struct Call {
  Operation *op;
  func::FuncOp callee;
  ArrayAttr args;
  const Meter *meter;
};

// A closed call that may run now (idr.facts, canEvaluate).
std::optional<Call> closedCall(Operation *op, SymbolTable &symbols) {
  std::optional<idr::facts::Evaluation> evaluation = idr::facts::canEvaluate(op, symbols);
  if (!evaluation)
    return std::nullopt;
  return Call{op, evaluation->callee, ArrayAttr::get(op->getContext(), evaluation->args),
              evaluation->total ? &totalCode : &partialCode};
}

std::string evalName(size_t i) { return ("__idr_eval_" + Twine(i)).str(); }
std::string runName(size_t i) { return ("__idr_run_" + Twine(i)).str(); }

// What one run of the pass spends on each phase of evaluating its fresh
// calls, as the remark `round` of the category idr-eval reports it: the
// pass manager's timing (--timing) sees the lowering pipelines it runs,
// but not the JIT or the child.
struct Phases {
  using Clock = std::chrono::steady_clock;
  Clock::time_point mark = Clock::now();
  double prepare = 0, lower = 0, convert = 0, jit = 0, run = 0, decode = 0;

  // Adds the time since the last mark to `phase`, and marks now.
  void lap(double &phase) {
    Clock::time_point now = Clock::now();
    phase += std::chrono::duration<double, std::milli>(now - mark).count();
    mark = now;
  }

  void report(Location loc, size_t calls) const {
    remark::detail::InFlightRemark out =
        remark::analysis(loc, remark::RemarkOpts::name("round").category("idr-eval"));
    if (!out)
      return;
    auto ms = [](double value) { return llvm::formatv("{0:f3}", value).str(); };
    out << remark::metric("calls", calls) << remark::metric("prepare-ms", ms(prepare))
        << remark::metric("lower-ms", ms(lower)) << remark::metric("convert-ms", ms(convert))
        << remark::metric("jit-ms", ms(jit)) << remark::metric("run-ms", ms(run))
        << remark::metric("decode-ms", ms(decode));
  }
};

struct Eval : idr::impl::IdrEvalBase<Eval> {
  void runOnOperation() override;

  // The dialects the round's lowering creates, and the translation to LLVM
  // IR, are loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    IdrEvalBase::getDependentDialects(registry);
    registerBuiltinDialectTranslation(registry);
    registerLLVMDialectTranslation(registry);
  }

private:
  LogicalResult evaluate(ModuleOp module, ArrayRef<Key> keys,
                         const llvm::MapVector<Key, SmallVector<Call>> &calls);
  ModuleOp scratch(ModuleOp module, ArrayRef<Key> keys,
                   const llvm::MapVector<Key, SmallVector<Call>> &calls);

  // Results for the compilation, which the simplify loop runs round after
  // round with this pass. A call that stays is known too, so it is not run
  // again.
  llvm::DenseMap<Key, Outcome> cache;
};

void Eval::runOnOperation() {
  ModuleOp module = getOperation();
  SymbolTable symbols(module);
  llvm::MapVector<Key, SmallVector<Call>> calls;
  module.walk([&](Operation *op) {
    if (std::optional<Call> call = closedCall(op, symbols))
      calls[{calleeKey(call->callee), call->args}].push_back(*call);
  });
  SmallVector<Key> fresh;
  for (const auto &entry : calls)
    if (!cache.contains(entry.first))
      fresh.push_back(entry.first);
    else
      ++numCacheHits;
  if (!fresh.empty() && failed(evaluate(module, fresh, calls)))
    return signalPassFailure();

  Dialect *dialect = getContext().getLoadedDialect<idr::IdrDialect>();
  for (const auto &[key, sites] : calls) {
    const Outcome &outcome = cache.find(key)->second;
    if (outcome.stays)
      continue;
    for (const Call &call : sites)
      idr::perform<idr::EvalCallAction>(call.op, [&] {
        OpBuilder b(call.op);
        SmallVector<Value> values;
        for (auto [value, type] : llvm::zip_equal(outcome.results, call.op->getResultTypes()))
          values.push_back(dialect->materializeConstant(b, value, type, call.op->getLoc())->getResult(0));
        call.op->replaceAllUsesWith(values);
        call.op->erase();
        ++numEvaluated;
      });
  }
}

// The callees and every function they reach, a wrapper per call that
// materializes its arguments and returns its results, and the declarations,
// in a module nested in the one being evaluated, where the pass can run its
// pipelines.
ModuleOp Eval::scratch(ModuleOp module, ArrayRef<Key> keys,
                       const llvm::MapVector<Key, SmallVector<Call>> &calls) {
  MLIRContext *ctx = &getContext();
  OpBuilder b(ctx);
  b.setInsertionPointToEnd(module.getBody());
  ModuleOp copy = ModuleOp::create(b, module.getLoc());
  b.setInsertionPointToEnd(copy.getBody());
  for (auto data : module.getOps<idr::DataOp>())
    b.clone(*data);
  SymbolTable symbols(module);
  llvm::SetVector<func::FuncOp> reached;
  auto reach = [&](Attribute symbol) {
    if (auto name = dyn_cast<FlatSymbolRefAttr>(symbol))
      if (auto fn = symbols.lookup<func::FuncOp>(name.getAttr()))
        reached.insert(fn);
  };
  for (const Key &key : keys) {
    reached.insert(calls.find(key)->second.front().callee);
    Attribute args = key.second;
    args.walk([&](idr::ClosureAttr closure) { reach(closure.getCallee()); });
  }
  for (size_t i = 0; i < reached.size(); ++i)
    if (auto uses = SymbolTable::getSymbolUses(reached[i]))
      for (const SymbolTable::SymbolUse &use : *uses)
        reach(use.getSymbolRef());
  for (func::FuncOp fn : reached)
    cast<func::FuncOp>(b.clone(*fn)).setPrivate();
  Dialect *dialect = ctx->getLoadedDialect<idr::IdrDialect>();
  for (auto [i, key] : llvm::enumerate(keys)) {
    func::FuncOp callee = calls.find(key)->second.front().callee;
    FunctionType type = callee.getFunctionType();
    Location loc = calls.find(key)->second.front().op->getLoc();
    auto wrapper = func::FuncOp::create(b, loc, evalName(i), b.getFunctionType({}, type.getResults()));
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(wrapper.addEntryBlock());
    SmallVector<Value> args;
    for (auto [value, input] : llvm::zip_equal(cast<ArrayAttr>(key.second), type.getInputs()))
      args.push_back(dialect->materializeConstant(b, value, input, loc)->getResult(0));
    auto call = func::CallOp::create(b, loc, callee.getSymName(), type.getResults(), args);
    func::ReturnOp::create(b, loc, call.getResults());
  }
  return copy;
}

LogicalResult Eval::evaluate(ModuleOp module, ArrayRef<Key> keys,
                             const llvm::MapVector<Key, SmallVector<Call>> &calls) {
  MLIRContext *ctx = &getContext();
  auto site = [&](size_t i) -> Call { return calls.find(keys[i])->second.front(); };
  auto internal = [&](size_t i, const Twine &why) {
    site(i).op->emitError("internal error: idr-eval: ") << why;
    return failure();
  };
  Phases phases;
  llvm::scope_exit report([&] { phases.report(module.getLoc(), keys.size()); });
  ModuleOp lowered = scratch(module, keys, calls);
  llvm::scope_exit erase([&] { lowered.erase(); });
  // The layouts of the values, read before idr-lower takes the types apart.
  // The clone is out of the program, so it takes the program's data layout
  // with it: idr-lower builds the JIT's code in the scratch module, inside
  // the program, by that layout.
  OwningOpRef<ModuleOp> pristine = lowered.clone();
  for (NamedAttribute attr : module->getAttrs())
    if (isa<DataLayoutSpecInterface>(attr.getValue()))
      (*pristine)->setAttr(attr.getName(), attr.getValue());
  FailureOr<idr::lower::Layouts> layouts = idr::lower::Layouts::of(*pristine);
  if (failed(layouts))
    return failure();
  SmallVector<SmallVector<Type>> resultTypes;
  for (size_t i = 0; i < keys.size(); ++i)
    resultTypes.push_back(
        llvm::to_vector(pristine->lookupSymbol<func::FuncOp>(evalName(i)).getResultTypes()));

  phases.lap(phases.prepare);
  // The executable's own lowering, in JIT mode.
  OpPassManager lower(ModuleOp::getOperationName());
  lower.addPass(idr::createIdrLower(idr::IdrLowerOptions{/*jit=*/true}));
  lower.addPass(createConvertLinalgToLoopsPass());
  lower.addPass(createCanonicalizerPass());
  lower.addPass(createCSEPass());
  if (failed(runPipeline(lower, lowered)))
    return internal(0, "lowering the round's calls failed");
  phases.lap(phases.lower);
  // Each call stores its results' components through a pointer, one 8-byte
  // slot each, behind a C function the JIT finds by name.
  SmallVector<size_t> words;
  SmallVector<idr::eval::Budget> budgets;
  SmallVector<std::string> entries;
  OpBuilder b(ctx);
  b.setInsertionPointToEnd(lowered.getBody());
  auto ptr = LLVM::LLVMPointerType::get(ctx);
  for (size_t i = 0; i < keys.size(); ++i) {
    auto wrapped = lowered.lookupSymbol<func::FuncOp>(evalName(i));
    wrapped.setPrivate();
    Location loc = wrapped.getLoc();
    auto run = func::FuncOp::create(b, loc, runName(i), b.getFunctionType({ptr}, {}));
    OpBuilder::InsertionGuard guard(b);
    Block *entry = run.addEntryBlock();
    b.setInsertionPointToStart(entry);
    auto call = func::CallOp::create(b, loc, wrapped, ValueRange{});
    for (auto [j, result] : llvm::enumerate(call.getResults())) {
      Value slot = LLVM::GEPOp::create(b, loc, ptr, b.getI64Type(), entry->getArgument(0),
                                       ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(j)});
      LLVM::StoreOp::create(b, loc, result, slot);
    }
    func::ReturnOp::create(b, loc);
    words.push_back(call.getNumResults());
    budgets.push_back(site(i).meter->budget);
    entries.push_back(runName(i));
  }
  OpPassManager toLLVM(ModuleOp::getOperationName());
  toLLVM.addPass(createSCFToControlFlowPass());
  toLLVM.addPass(createConvertToLLVMPass());
  toLLVM.addPass(createReconcileUnrealizedCastsPass());
  toLLVM.addPass(idr::createIdrTailCalls());
  if (failed(runPipeline(toLLVM, lowered)))
    return internal(0, "lowering the round's calls to the LLVM dialect failed");
  if (unsigned labels = layouts->numLabels()) {
    SymbolTable symbols(lowered);
    Location loc = lowered.getLoc();
    auto type = LLVM::LLVMArrayType::get(ptr, labels);
    auto table = LLVM::GlobalOp::create(b, loc, type, /*isConstant=*/true, LLVM::Linkage::External,
                                        codesName, Attribute(), /*alignment=*/8);
    OpBuilder::InsertionGuard guard(b);
    b.createBlock(&table.getInitializerRegion());
    Value codes = LLVM::ZeroOp::create(b, loc, type);
    for (unsigned id = 0; id < labels; ++id)
      if (auto code = symbols.lookup<LLVM::LLVMFuncOp>(idr::lower::codeName(id)))
        codes = LLVM::InsertValueOp::create(b, loc, codes, LLVM::AddressOfOp::create(b, loc, code),
                                            static_cast<int64_t>(id));
    LLVM::ReturnOp::create(b, loc, codes);
  }
  phases.lap(phases.convert);
  std::string why;
  std::unique_ptr<idr::eval::Jit> jit = idr::eval::Jit::compile(lowered, entries, why);
  if (!jit)
    return internal(0, "the JIT: " + why);
  phases.lap(phases.jit);

  llvm::DenseMap<uint64_t, unsigned> codes;
  if (const auto *table = static_cast<const uint64_t *>(jit->address(codesName)))
    for (unsigned id = 0; id < layouts->numLabels(); ++id)
      if (table[id] != 0)
        codes[table[id]] = id;
  idr::eval::Reifier reifier(*layouts, std::move(codes), resultBytes);
  auto reify = [&](size_t i, ArrayRef<uint64_t> slots) -> SmallVector<std::string> {
    auto values = reifier.results(resultTypes[i], slots);
    if (!values)
      return {(values.error().why == idr::eval::Unread::Why::TooLarge ? sentTooLarge
                                                                       : sentUnreadable)
                  .str(),
              values.error().message};
    std::expected<std::string, std::string> bytes = idr::eval::encodeResults(*values, ctx);
    if (!bytes)
      return {sentUnreadable.str(), bytes.error()};
    return {sentResults.str(), std::move(*bytes)};
  };
  size_t next = 0;
  while (next < keys.size()) {
    idr::eval::Run run = idr::eval::runInChild(jit->getEntries(), words, budgets, next, reify);
    for (idr::eval::Result &result : run.results) {
      Call call = site(next);
      if (result.texts.size() != 2)
        return internal(next, "the evaluation child sent no results");
      if (result.texts[0] == sentTooLarge) {
        remark::missed(call.op->getLoc(), remark::RemarkOpts::name("TooLarge")
                                              .category("idr-eval")
                                              .function(call.callee.getSymName()))
            << ("the call of @" + call.callee.getSymName() + " stays: " + result.texts[1]).str();
        cache[keys[next++]].stays = true;
        ++numStayedLarge;
        continue;
      }
      if (result.texts[0] != sentResults)
        return internal(next, "cannot read back the results: " + result.texts[1]);
      phases.lap(phases.run);
      auto values = idr::eval::decodeResults(result.texts[1], ctx);
      phases.lap(phases.decode);
      if (!values)
        return internal(next, "cannot read back the results: " + values.error());
      Outcome outcome;
      outcome.results = std::move(*values);
      remark::passed(call.op->getLoc(), remark::RemarkOpts::name("Evaluated")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("evaluated a call of @" + call.callee.getSymName() + " in " +
              llvm::formatv("{0:f3}", static_cast<double>(result.nanoseconds) / 1e6).str() + " ms")
                 .str();
      cache[keys[next++]] = std::move(outcome);
    }
    switch (run.status) {
    case idr::eval::Run::Status::Done:
      if (next < keys.size())
        return internal(next, "the evaluation child stopped before this call");
      break;
    case idr::eval::Run::Status::Crashed: {
      // The crash happens at runtime, where the call stays.
      Call call = site(next);
      remark::missed(call.op->getLoc(), remark::RemarkOpts::name("Crashed")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("the call of @" + call.callee.getSymName() + " crashes, so it stays: " + run.message)
                 .str();
      cache[keys[next++]].stays = true;
      ++numStayedCrash;
      break;
    }
    case idr::eval::Run::Status::OverBudget:
    case idr::eval::Run::Status::Exhausted: {
      // What does not finish at compile time runs at runtime.
      Call call = site(next);
      remark::missed(call.op->getLoc(), remark::RemarkOpts::name("Unfinished")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("the call of @" + call.callee.getSymName() + " " + call.meter->unfinished +
              ", so it stays: " + run.message)
                 .str();
      cache[keys[next++]].stays = true;
      ++numStayedBudget;
      break;
    }
    case idr::eval::Run::Status::Failed:
      return internal(next, run.message);
    }
  }
  phases.lap(phases.run);
  return success();
}

} // namespace
