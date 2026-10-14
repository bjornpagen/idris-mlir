// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-entry, which makes the root idr-lower lowered the program's entry.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Analysis/Holds.h"
#include "idr/Conversion/Passes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

// The target entry's list of CPU features, an X-macro, and the runtime's
// C ABI, whose feature bits it names.
#include "cpu_features.h"
#include "idris_rt.h"

namespace idr {
#define GEN_PASS_DEF_IDRENTRY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// The root: the one public function, whatever its mangled name.
FailureOr<func::FuncOp> findRoot(ModuleOp module, SymbolTable &symbols) {
  SmallVector<func::FuncOp> roots;
  for (auto fn : module.getOps<func::FuncOp>())
    if (fn.isPublic())
      roots.push_back(fn);
  if (roots.size() != 1 || symbols.lookup("main"))
    return module.emitError("internal error: idr-entry needs exactly one public function, "
                            "the root, and no @main");
  return roots.front();
}

// The IDRIS_RT_CPU_FEATURES bits of the features the module's target
// enables, found by their LLVM names. A module with no target states no
// requirement.
uint64_t requiredCpuFeatures(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  LLVM::TargetFeaturesAttr features = target ? target.getFeatures() : nullptr;
  uint64_t bits = 0;
  if (!features)
    return bits;
#define IDR_REQUIRED_FEATURE(bit, test, name)                                                   \
  if (features.contains("+" name))                                                             \
    bits |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDR_REQUIRED_FEATURE)
#undef IDR_REQUIRED_FEATURE
  return bits;
}

// The runtime's C function `name`, declared where the lowering left none.
// Neither of those the entry calls is a crash or takes an argument narrower
// than 32 bits, so neither declaration needs an attribute.
LLVM::LLVMFuncOp runtimeFunction(ModuleOp module, SymbolTable &symbols, StringRef name,
                                 LLVM::LLVMFunctionType type) {
  if (auto fn = symbols.lookup<LLVM::LLVMFuncOp>(name))
    return fn;
  auto b = OpBuilder::atBlockBegin(module.getBody());
  auto fn = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
  symbols.insert(fn);
  return fn;
}

// The root, the only public function, becomes private, and @__idr_main runs
// it. Its lowered type is its kind: `() -> i64` returns the exit status; an
// IO root, whose world and unit result lower to nothing, is `() -> ()`, and
// the status is then 0. Either way @__idr_main then releases what the static
// thunks hold once forced (@__idr_release_cafs, which idr-lower makes in
// every module), so that it is not counted as live, and ends in
// idris_rt_main_return, which writes pending output and, when asked, how
// many cells are still live. @main hands @__idr_main and the program's
// arguments to the runtime's entry, idris_rt_start, which runs it on a
// reserved stack once the CPU has shown it has the features the module's
// target enables, and which ends a status outside 0 to 255 as a crash.
LogicalResult makeEntry(ModuleOp module, SymbolTable &symbols) {
  FailureOr<func::FuncOp> found = findRoot(module, symbols);
  if (failed(found))
    return failure();
  func::FuncOp root = *found;
  FunctionType kind = root.getFunctionType();
  bool status = kind.getNumResults() == 1 && kind.getResult(0).isInteger(64);
  if (kind.getNumInputs() != 0 || (kind.getNumResults() != 0 && !status))
    return root.emitError("internal error: idr-entry: the root is neither `() -> i64` nor "
                          "`() -> ()`");
  root.setPrivate();

  MLIRContext *ctx = module.getContext();
  OpBuilder b(ctx);
  Location loc = root.getLoc();
  Type i32 = b.getI32Type(), i64 = b.getI64Type(), ptr = LLVM::LLVMPointerType::get(ctx);
  LLVM::LLVMFuncOp mainReturn = runtimeFunction(
      module, symbols, "idris_rt_main_return",
      LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), {}));
  LLVM::LLVMFuncOp start = runtimeFunction(module, symbols, "idris_rt_start",
                                           LLVM::LLVMFunctionType::get(i32, {ptr, i64, i32, ptr}));
  auto release = symbols.lookup<func::FuncOp>("__idr_release_cafs");
  if (!release)
    return module.emitError("internal error: idr-entry: no @__idr_release_cafs, which "
                            "idr-lower makes");

  b.setInsertionPointToEnd(module.getBody());
  FunctionType bodyType = b.getFunctionType({}, {i64});
  auto body = func::FuncOp::create(b, loc, "__idr_main", bodyType);
  body.setPrivate();
  symbols.insert(body);
  auto main = func::FuncOp::create(b, loc, "main", b.getFunctionType({i32, ptr}, {i32}));
  symbols.insert(main);
  b.setInsertionPointToStart(body.addEntryBlock());
  auto call = func::CallOp::create(b, loc, root, ValueRange{});
  Value code = status ? Value(call.getResult(0)) : Value(LLVM::ConstantOp::create(b, loc, i64, 0));
  func::CallOp::create(b, loc, release, ValueRange{});
  LLVM::CallOp::create(b, loc, mainReturn, ValueRange{});
  func::ReturnOp::create(b, loc, code);

  // The body is a function value until convert-to-llvm makes it a pointer;
  // the cast between the two disappears then.
  Block *entry = main.addEntryBlock();
  b.setInsertionPointToStart(entry);
  Value function = func::ConstantOp::create(b, loc, bodyType, body.getSymName());
  Value pointer = UnrealizedConversionCastOp::create(b, loc, ptr, function).getResult(0);
  Value cpu =
      LLVM::ConstantOp::create(b, loc, i64, static_cast<int64_t>(requiredCpuFeatures(module)));
  Value started = LLVM::CallOp::create(b, loc, start,
                                       ValueRange{pointer, cpu, entry->getArgument(0),
                                                  entry->getArgument(1)})
                      .getResult();
  func::ReturnOp::create(b, loc, started);
  return success();
}

struct Entry : idr::impl::IdrEntryBase<Entry> {
  using IdrEntryBase::IdrEntryBase;

  void runOnOperation() override {
    if (failed(makeEntry(getOperation(), getAnalysis<SymbolTable>())))
      return signalPassFailure();
    // Every symbol it adds goes through the table, and no declaration
    // changes.
    markAnalysesPreserved<SymbolTable, Layouts, TypeGraph, Holds>();
  }
};

} // namespace

} // namespace idr::conversion
