// The idr dialect (docs/architecture/08-idr-dialect.md).
#pragma once

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"

namespace idr {

// The resource that a possible crash writes to (IDR-EFF-1).
struct CrashResource : mlir::SideEffects::Resource::Base<CrashResource> {
  llvm::StringRef getName() const final { return "idr.crash"; }
};

// The resource that every IO op reads and writes (IDR-EFF-2).
struct IOResource : mlir::SideEffects::Resource::Base<IOResource> {
  llvm::StringRef getName() const final { return "idr.io"; }
};

} // namespace idr

#include "idr/IdrDialect.h.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IdrTypes.h.inc"

#define GET_OP_CLASSES
#include "idr/IdrOps.h.inc"

namespace idr {

#define GEN_PASS_DECL
#include "idr/Passes.h.inc"

#define GEN_PASS_REGISTRATION
#include "idr/Passes.h.inc"

// The data declaration a !idr.data type names, or null.
DataOp lookupData(mlir::Operation *from, DataType type);

// The constructor `ctor` of `data`, or null.
CtorOp lookupCtor(DataOp data, llvm::StringRef ctor);

// Registers the idr dialect, and (once per process) its passes and the named
// pipeline `idr-pipeline` (OPT-PIPE-1 steps 1-10).
void registerIdr(mlir::DialectRegistry &registry);
void registerIdrPipeline();

// The pipeline steps of OPT-PIPE-1 (1-10), as textual pass pipelines, in order.
llvm::ArrayRef<llvm::StringRef> pipelineSteps();

} // namespace idr
