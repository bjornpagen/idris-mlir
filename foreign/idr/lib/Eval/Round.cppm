// idr.eval:round: one round of evaluation: the calls whose outcome is not
// known yet, lowered together, compiled once by the JIT and run in a
// child, their results read back into the cache. Nothing here is exported.
export module idr.eval:round;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :calls;
import :child;
import :encoding;
import :jit;
import :phases;
import :reify;
import :scratch;

using namespace mlir;

namespace idr::eval {

namespace {

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

std::string runName(size_t i) { return ("__idr_run_" + Twine(i)).str(); }

} // namespace

// Evaluates the calls of `keys`, which `cache` does not know yet, into it.
LogicalResult evaluateRound(ModuleOp module, ArrayRef<Key> keys,
                            const llvm::MapVector<Key, SmallVector<Call>> &calls, Cache &cache,
                            Statistics &stats, RunPipeline runPipeline) {
  MLIRContext *ctx = module.getContext();
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
  FailureOr<idr::layout::Layouts> layouts = idr::layout::Layouts::of(*pristine);
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
  SmallVector<Budget> budgets;
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
      if (auto code = symbols.lookup<LLVM::LLVMFuncOp>(idr::layout::codeName(id)))
        codes = LLVM::InsertValueOp::create(b, loc, codes, LLVM::AddressOfOp::create(b, loc, code),
                                            static_cast<int64_t>(id));
    LLVM::ReturnOp::create(b, loc, codes);
  }
  phases.lap(phases.convert);
  std::string why;
  std::unique_ptr<Jit> jit = Jit::compile(lowered, entries, why);
  if (!jit)
    return internal(0, "the JIT: " + why);
  phases.lap(phases.jit);

  llvm::DenseMap<uint64_t, unsigned> codes;
  if (const auto *table = static_cast<const uint64_t *>(jit->address(codesName)))
    for (unsigned id = 0; id < layouts->numLabels(); ++id)
      if (table[id] != 0)
        codes[table[id]] = id;
  Reifier reifier(*layouts, std::move(codes), resultBytes);
  auto reify = [&](size_t i, ArrayRef<uint64_t> slots) -> SmallVector<std::string> {
    auto values = reifier.results(resultTypes[i], slots);
    if (!values)
      return {(values.error().why == Unread::Why::TooLarge ? sentTooLarge
                                                                       : sentUnreadable)
                  .str(),
              values.error().message};
    std::expected<std::string, std::string> bytes = encodeResults(*values, ctx);
    if (!bytes)
      return {sentUnreadable.str(), bytes.error()};
    return {sentResults.str(), std::move(*bytes)};
  };
  size_t next = 0;
  while (next < keys.size()) {
    Run run = runInChild(jit->getEntries(), words, budgets, next, reify);
    for (Result &result : run.results) {
      Call call = site(next);
      if (result.texts.size() != 2)
        return internal(next, "the evaluation child sent no results");
      if (result.texts[0] == sentTooLarge) {
        remark::missed(call.op->getLoc(), remark::RemarkOpts::name("TooLarge")
                                              .category("idr-eval")
                                              .function(call.callee.getSymName()))
            << ("the call of @" + call.callee.getSymName() + " stays: " + result.texts[1]).str();
        cache[keys[next++]].stays = true;
        ++stats.stayedLarge;
        continue;
      }
      if (result.texts[0] != sentResults)
        return internal(next, "cannot read back the results: " + result.texts[1]);
      phases.lap(phases.run);
      auto values = decodeResults(result.texts[1], ctx);
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
    case Run::Status::Done:
      if (next < keys.size())
        return internal(next, "the evaluation child stopped before this call");
      break;
    case Run::Status::Crashed: {
      // The crash happens at runtime, where the call stays.
      Call call = site(next);
      remark::missed(call.op->getLoc(), remark::RemarkOpts::name("Crashed")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("the call of @" + call.callee.getSymName() + " crashes, so it stays: " + run.message)
                 .str();
      cache[keys[next++]].stays = true;
      ++stats.stayedCrash;
      break;
    }
    case Run::Status::OverBudget:
    case Run::Status::Exhausted: {
      // What does not finish at compile time runs at runtime.
      Call call = site(next);
      remark::missed(call.op->getLoc(), remark::RemarkOpts::name("Unfinished")
                                            .category("idr-eval")
                                            .function(call.callee.getSymName()))
          << ("the call of @" + call.callee.getSymName() + " " + call.meter->unfinished +
              ", so it stays: " + run.message)
                 .str();
      cache[keys[next++]].stays = true;
      ++stats.stayedBudget;
      break;
    }
    case Run::Status::Failed:
      return internal(next, run.message);
    }
  }
  phases.lap(phases.run);
  return success();
}

} // namespace idr::eval
