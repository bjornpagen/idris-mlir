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

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/STLExtras.h"

// The target entry's description, and its list of CPU features, an
// X-macro, whose feature bits the runtime's start tests.
#include "idr/TargetEntry.h"

#include "cpu_features.h"

#define GEN_PASS_DEF_IDRENTRY
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// The IDRIS_RT_CPU_FEATURES bits of the features the module's code may use:
// the program CPU's, whose list the target's entry holds, every feature it
// implies among them, and which idr-target writes on the module. A constant
// of the build, as the tools' own startup check reads it.
constexpr uint64_t requiredCpuFeatures =
    rt::platform::featureBitsOf(IDRIS_MLIR_PROGRAM_CPU_FEATURES);

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
void makeEntry(ModuleOp module, ProgramOp program) {
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
        b, loc, value,
        LLVM::ConstantOp::create(b, loc, i64, static_cast<int64_t>(requiredCpuFeatures)),
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
}

struct Entry : idr::impl::IdrEntryBase<Entry> {
  using IdrEntryBase::IdrEntryBase;

  void runOnProgram(ProgramOp program) { makeEntry(getOperation(), program); }
};

} // namespace

} // namespace idr::conversion
