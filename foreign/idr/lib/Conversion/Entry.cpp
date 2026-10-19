// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-entry, which takes the program idr-lower lowered apart into the
// module and makes its root the program's entry.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Func.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/STLExtras.h"

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

// Every op of the lowered `program` moves into the module before it, each
// symbol into `symbols`, the module's table, and the program goes; gives
// its root. The lowered stage's verifier holds that the root names a
// func.func of the program.
FailureOr<func::FuncOp> takeApart(ProgramOp program, SymbolTable &symbols) {
  auto root = cast<func::FuncOp>(SymbolTable::lookupSymbolIn(program, program.getRootAttr()));
  SmallVector<Operation *> moved;
  for (Operation &op : llvm::make_early_inc_range(program->getRegion(0).front())) {
    op.moveBefore(program);
    moved.push_back(&op);
  }
  symbols.erase(program);
  for (Operation *op : moved) {
    auto name = op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName());
    if (!name)
      continue;
    if (symbols.lookup(name))
      return op->emitError() << "internal error: idr-entry: @" << name.getValue()
                             << " names another symbol of the module";
    symbols.insert(op);
  }
  return root;
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

// The root becomes private like every other function, and the entry body
// runs it. The root's kind is the one rule's (rootKind): a Status root
// returns the exit status; an IO root, whose world and unit result lower to
// nothing, gives 0. Either way the entry body then ends in
// idris_rt_main_return, which writes pending output and, when asked, how
// many cells are still live. @main hands the entry body and the program's
// arguments to the runtime's entry, idris_rt_start, which runs it on a
// reserved stack once the CPU has shown it has the features the module's
// target enables, and which ends a status outside 0 to 255 as a crash.
LogicalResult makeEntry(ModuleOp module, ProgramOp program, SymbolTable &symbols) {
  FailureOr<func::FuncOp> found = takeApart(program, symbols);
  if (failed(found))
    return failure();
  func::FuncOp root = *found;
  // The entry's name is the C entry's. A function of the program that
  // has it, private once lowered as every function but the entry is, takes
  // a name of its own, its uses following it.
  if (Operation *taken = symbols.lookup(entrySymbol))
    if (failed(symbols.renameToUnique(taken, {})))
      return module.emitError() << "internal error: idr-entry: @" << entrySymbol
                                << " names a symbol that cannot be renamed";
  // The lowered stage's verifier admits a root only of a type rootKind
  // gives a kind.
  RootKind kind = *rootKind(root.getFunctionType(), Stage::Lowered);
  root.setPrivate();

  MLIRContext *ctx = module.getContext();
  OpBuilder b(ctx);
  Location loc = root.getLoc();
  Type i32 = b.getI32Type(), i64 = b.getI64Type(), ptr = LLVM::LLVMPointerType::get(ctx);
  // The runtime's declaration of `function`: the module's, or a new one at
  // its start. Only the entry calls these, but the module it is given may
  // declare them, and the table would rename a second declaration.
  auto declared = [&](const idr::runtime::Function &function) {
    if (auto fn = symbols.lookup<LLVM::LLVMFuncOp>(function.symbol))
      return fn;
    LLVM::LLVMFuncOp fn = runtimeDeclaration(loc, function);
    symbols.insert(fn, module.getBody()->begin());
    return fn;
  };
  LLVM::LLVMFuncOp mainReturn = declared(idr::runtime::helper::mainReturn);
  LLVM::LLVMFuncOp start = declared(idr::runtime::helper::start);

  b.setInsertionPointToEnd(module.getBody());
  FunctionType bodyType = b.getFunctionType({}, {i64});
  auto body = func::FuncOp::create(b, loc, reservedName("entry", "body"), bodyType);
  body.setPrivate();
  symbols.insert(body);
  auto main = func::FuncOp::create(b, loc, entrySymbol, b.getFunctionType({i32, ptr}, {i32}));
  symbols.insert(main);
  b.setInsertionPointToStart(body.addEntryBlock());
  auto call = func::CallOp::create(b, loc, root, ValueRange{});
  Value code;
  switch (kind) {
  case RootKind::Status:
    code = call.getResult(0);
    break;
  case RootKind::IO:
    code = LLVM::ConstantOp::create(b, loc, i64, 0);
    break;
  }
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

  void runOnProgram(ProgramOp program) override {
    ModuleOp module = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    if (failed(makeEntry(module, program, symbols)))
      return signalPassFailure();
    // Every symbol it adds goes through the table, and no declaration
    // changes.
    markAnalysesPreserved<SymbolTable, Layouts, TypeGraph>();
  }
};

} // namespace

} // namespace idr::conversion
