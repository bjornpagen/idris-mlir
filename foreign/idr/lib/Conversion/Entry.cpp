// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-entry, which takes the program idr-lower lowered apart into the
// module and makes its root the program's entry.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Target/LLVMIR/Transforms/TargetUtils.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Target/TargetMachine.h"

// The target entry's list of CPU features, an X-macro, whose feature bits
// the runtime's start tests.
#include "cpu_features.h"

namespace idr {
#define GEN_PASS_DEF_IDRENTRY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// The IDRIS_RT_CPU_FEATURES bits of the features the module's code may use:
// those its target's machine has, the CPU's and its features with all they
// imply, as the code generator reads them, found by their LLVM names. The
// module's target is the one idr-target wrote, from the target's entry;
// one LLVM has no machine for is an error.
FailureOr<uint64_t> requiredCpuFeatures(ModuleOp module) {
  auto target = module->getAttrOfType<LLVM::TargetAttr>(LLVM::LLVMDialect::getTargetAttrName());
  uint64_t bits = 0;
  if (!target)
    return bits;
  LLVM::detail::initializeBackendsOnce();
  FailureOr<std::unique_ptr<llvm::TargetMachine>> machine = LLVM::detail::getTargetMachine(target);
  if (failed(machine) || !*machine)
    return module.emitError() << "internal error: idr-entry: no target machine for " << target;
  const llvm::MCSubtargetInfo &subtarget = (*machine)->getMCSubtargetInfo();
#define IDR_REQUIRED_FEATURE(bit, test, name)                                                   \
  if (subtarget.checkFeatures("+" name))                                                       \
    bits |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDR_REQUIRED_FEATURE)
#undef IDR_REQUIRED_FEATURE
  return bits;
}

// Every op of the lowered program moves into the module before it, and the
// program goes. Every program symbol has the program's prefix and every
// other symbol is the runtime's or a reserved name, so none meets another.
LLVM::LLVMFuncOp takeApart(ProgramOp program) {
  auto root = cast<LLVM::LLVMFuncOp>(SymbolTable::lookupSymbolIn(program, program.getRootAttr()));
  for (Operation &op : llvm::make_early_inc_range(program->getRegion(0).front()))
    op.moveBefore(program);
  program.erase();
  return root;
}

// The program's entry. The root, like every function of the program, takes
// tailcc, so a C caller cannot call it: the entry body, of C's convention,
// calls it and returns. The program's static facts reach the runtime's
// entry as one constant record (idris_rt_program: the body, and the CPU
// features the module's target enables, which the processor must have);
// @main hands it and the program's arguments to idris_rt_start, which runs
// the body on the stack the program needs and ends the process by the
// ending the run reaches, so @main does not return.
LogicalResult makeEntry(ModuleOp module, ProgramOp program) {
  FailureOr<uint64_t> required = requiredCpuFeatures(module);
  if (failed(required))
    return failure();
  LLVM::LLVMFuncOp root = takeApart(program);
  MLIRContext *ctx = module.getContext();
  OpBuilder b(ctx);
  Location loc = root.getLoc();
  Type i32 = b.getI32Type(), i64 = b.getI64Type(), ptr = LLVM::LLVMPointerType::get(ctx);
  Type none = LLVM::LLVMVoidType::get(ctx);

  b.setInsertionPointToEnd(module.getBody());
  auto body = LLVM::LLVMFuncOp::create(b, loc, reservedName("entry", "body"),
                                       LLVM::LLVMFunctionType::get(none, {}),
                                       LLVM::Linkage::Private, /*dsoLocal=*/true);
  {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(body.addEntryBlock(b));
    auto run = LLVM::CallOp::create(b, loc, root, ValueRange{});
    run.setCConv(LLVM::cconv::CConv::Tail);
    LLVM::ReturnOp::create(b, loc, ValueRange{});
  }

  auto recordType = LLVM::LLVMStructType::getLiteral(ctx, {ptr, i64});
  auto record = LLVM::GlobalOp::create(b, loc, recordType, /*isConstant=*/true,
                                       LLVM::Linkage::Private, reservedName("entry", "program"),
                                       Attribute(), /*alignment=*/0, /*addrSpace=*/0,
                                       /*dsoLocal=*/true);
  {
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(b.createBlock(&record.getInitializerRegion()));
    Value value = LLVM::PoisonOp::create(b, loc, recordType);
    value = LLVM::InsertValueOp::create(b, loc, value, LLVM::AddressOfOp::create(b, loc, body),
                                        ArrayRef<int64_t>{0});
    value = LLVM::InsertValueOp::create(
        b, loc, value, LLVM::ConstantOp::create(b, loc, i64, static_cast<int64_t>(*required)),
        ArrayRef<int64_t>{1});
    LLVM::ReturnOp::create(b, loc, value);
  }

  auto main = LLVM::LLVMFuncOp::create(b, loc, entrySymbol,
                                       LLVM::LLVMFunctionType::get(i32, {i32, ptr}));
  Block *entry = main.addEntryBlock(b);
  b.setInsertionPointToStart(entry);
  Value facts = LLVM::AddressOfOp::create(b, loc, record);
  const idr::runtime::Function &start = idr::runtime::helper::start;
  LLVM::CallOp::create(b, loc, runtimeFunctionType(ctx, start), StringRef(start.symbol),
                       ValueRange{facts, entry->getArgument(0), entry->getArgument(1)})
      .setNoreturn(true);
  LLVM::UnreachableOp::create(b, loc);
  return success();
}

struct Entry : idr::impl::IdrEntryBase<Entry> {
  using IdrEntryBase::IdrEntryBase;

  void runOnProgram(ProgramOp program) {
    if (failed(makeEntry(getOperation(), program)))
      return signalPassFailure();
  }
};

} // namespace

} // namespace idr::conversion
