// idr-eval: compile-time evaluation is runtime evaluation, run early
// (docs/cutover.md 6.4; SEM-EVAL-6, SEM-EVAL-7, EVAL-1). A closed call of a
// pure, total function runs the program's own lowered code on the same
// runtime, with no fuel, no memory cap and no time limit, and its results
// replace it as constants.

#include "Eval/Child.h"
#include "Eval/Reify.h"

#include "idr/Idr.h"

#include "mlir/Conversion/ConvertToLLVM/ToLLVMPass.h"
#include "mlir/Conversion/ReconcileUnrealizedCasts/ReconcileUnrealizedCasts.h"
#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"
#include "mlir/AsmParser/AsmParser.h"
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

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREVAL
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

// A call is known by its callee and its constant arguments; a closure's
// captures come before the arguments of its application.
using Key = std::pair<Attribute, Attribute>;

struct Outcome {
  SmallVector<Attribute> results;
  bool crashed = false;
};

struct Call {
  Operation *op;
  func::FuncOp callee;
  ArrayAttr args;
};

bool evaluable(func::FuncOp fn) {
  return fn && !fn.isExternal() && idr::isPure(fn) && idr::isTotal(fn);
}

// 6.4: a func.call, or an idr.apply of a constant closure, whose operands are
// all constants; its callee is pure and total, and so is every label in
// the constants, through captures and fields (7.1, 7.4).
std::optional<Call> closedCall(Operation *op, SymbolTable &symbols) {
  SmallVector<Attribute> args;
  FlatSymbolRefAttr callee;
  ValueRange operands;
  if (auto call = dyn_cast<func::CallOp>(op)) {
    callee = call.getCalleeAttr();
    operands = call.getOperands();
  } else if (auto apply = dyn_cast<idr::ApplyOp>(op)) {
    idr::ClosureAttr closure;
    if (!matchPattern(apply.getCallee(), m_Constant(&closure)))
      return std::nullopt;
    callee = closure.getCallee();
    llvm::append_range(args, closure.getCaptures());
    operands = apply.getArgs();
  } else {
    return std::nullopt;
  }
  for (Value operand : operands) {
    Attribute value;
    if (!matchPattern(operand, m_Constant(&value)))
      return std::nullopt;
    args.push_back(value);
  }
  auto fn = symbols.lookup<func::FuncOp>(callee.getAttr());
  if (!evaluable(fn))
    return std::nullopt;
  bool labels = true;
  for (Attribute arg : args)
    arg.walk([&](idr::ClosureAttr closure) {
      labels &= evaluable(symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()));
    });
  if (!labels)
    return std::nullopt;
  return Call{op, fn, ArrayAttr::get(op->getContext(), args)};
}

std::string evalName(size_t i) { return ("__idr_eval_" + Twine(i)).str(); }
std::string runName(size_t i) { return ("__idr_run_" + Twine(i)).str(); }

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
  // round with this pass (6.4). A call that crashed is known too, so it is
  // not run again.
  llvm::DenseMap<Key, Outcome> cache;
};

void Eval::runOnOperation() {
  ModuleOp module = getOperation();
  if (getContext().isMultithreadingEnabled()) {
    module.emitError("internal error: idr-eval forks, so MLIR must run single-threaded "
                     "(--mlir-disable-threading)");
    return signalPassFailure();
  }
  SymbolTable symbols(module);
  llvm::MapVector<Key, SmallVector<Call>> calls;
  module.walk([&](Operation *op) {
    if (std::optional<Call> call = closedCall(op, symbols))
      calls[{FlatSymbolRefAttr::get(call->callee.getSymNameAttr()), call->args}].push_back(*call);
  });
  SmallVector<Key> fresh;
  for (const auto &entry : calls)
    if (!cache.contains(entry.first))
      fresh.push_back(entry.first);
  if (!fresh.empty() && failed(evaluate(module, fresh, calls)))
    return signalPassFailure();

  Dialect *dialect = getContext().getLoadedDialect<idr::IdrDialect>();
  for (const auto &[key, sites] : calls) {
    const Outcome &outcome = cache.find(key)->second;
    if (outcome.crashed)
      continue;
    for (const Call &call : sites) {
      OpBuilder b(call.op);
      SmallVector<Value> values;
      for (auto [value, type] : llvm::zip_equal(outcome.results, call.op->getResultTypes()))
        values.push_back(dialect->materializeConstant(b, value, type, call.op->getLoc())->getResult(0));
      call.op->replaceAllUsesWith(values);
      call.op->erase();
    }
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
    reach(key.first);
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
  ModuleOp lowered = scratch(module, keys, calls);
  auto erase = llvm::make_scope_exit([&] { lowered.erase(); });
  // The layouts of the values, read before idr-lower takes the types apart.
  OwningOpRef<ModuleOp> pristine = lowered.clone();
  idr::lower::Layouts layouts(*pristine);
  SmallVector<SmallVector<Type>> resultTypes;
  for (size_t i = 0; i < keys.size(); ++i)
    resultTypes.push_back(
        llvm::to_vector(pristine->lookupSymbol<func::FuncOp>(evalName(i)).getResultTypes()));

  // LOW-JIT-1: the executable's own lowering, in JIT mode.
  OpPassManager lower(ModuleOp::getOperationName());
  lower.addPass(idr::createIdrLower(idr::IdrLowerOptions{/*jit=*/true}));
  lower.addPass(createCanonicalizerPass());
  lower.addPass(createCSEPass());
  if (failed(runPipeline(lower, lowered)))
    return internal(0, "lowering the round's calls failed");
  // Each call stores its results' components through a pointer, one 8-byte
  // slot each, behind a C function the JIT finds by name.
  SmallVector<size_t> words;
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
    entries.push_back(runName(i));
  }
  OpPassManager toLLVM(ModuleOp::getOperationName());
  toLLVM.addPass(createSCFToControlFlowPass());
  toLLVM.addPass(createConvertToLLVMPass());
  toLLVM.addPass(createReconcileUnrealizedCastsPass());
  if (failed(runPipeline(toLLVM, lowered)))
    return internal(0, "lowering the round's calls to the LLVM dialect failed");
  std::string why;
  std::unique_ptr<idr::eval::Jit> jit = idr::eval::Jit::compile(lowered, entries, why);
  if (!jit)
    return internal(0, "the JIT: " + why);

  idr::eval::Reifier reifier(layouts);
  auto reify = [&](size_t i, ArrayRef<uint64_t> slots) {
    SmallVector<std::string> texts;
    for (Type type : resultTypes[i]) {
      std::string text;
      llvm::raw_string_ostream os(text);
      reifier.value(type, slots).print(os);
      texts.push_back(std::move(text));
    }
    return texts;
  };
  size_t next = 0;
  while (next < keys.size()) {
    idr::eval::Run run = idr::eval::runInChild(jit->getEntries(), words, next, reify);
    for (idr::eval::Result &result : run.results) {
      Outcome outcome;
      for (const std::string &text : result.texts) {
        Attribute value = parseAttribute(text, ctx);
        if (!value)
          return internal(next, "cannot read back the result " + text);
        outcome.results.push_back(value);
      }
      Call call = site(next);
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
      // OPT-SAFE-1: the crash happens at runtime, where the call stays.
      Call call = site(next);
      remark::missed(call.op->getLoc(), remark::RemarkOpts::name("Crashed")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("the call of @" + call.callee.getSymName() + " crashes, so it stays: " + run.message)
                 .str();
      cache[keys[next++]].crashed = true;
      break;
    }
    case idr::eval::Run::Status::Exhausted:
      site(next).op->emitError("EVAL-1: the machine cannot finish evaluating this call of @")
          << site(next).callee.getSymName() << ", which is total: " << run.message;
      return failure();
    case idr::eval::Run::Status::Failed:
      return internal(next, run.message);
    }
  }
  return success();
}

} // namespace
