// The idr dialect (docs/architecture/08-idr-dialect.md).
#pragma once

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlow.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"

#include <algorithm>
#include <cstddef>
#include <optional>

namespace idr {

// The resource that a possible crash writes to (IDR-EFF-1).
struct CrashResource : mlir::SideEffects::Resource::Base<CrashResource> {
  llvm::StringRef getName() const final { return "idr.crash"; }
};

// The resource that every IO op reads and writes (IDR-EFF-2).
struct IOResource : mlir::SideEffects::Resource::Base<IOResource> {
  llvm::StringRef getName() const final { return "idr.io"; }
};

// The traits below carry what IdrOps.td declares about an op, so that each
// fact is written once, next to the op, and every pass derives from it.

// IDR-MOD-1: the first contract version that admits the op (`Idr_Since`).
template <int Version> struct Since {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    static constexpr int since = Version;
  };
};

// A string usable as a template argument.
template <std::size_t N> struct Name {
  char chars[N];
  constexpr Name(const char (&text)[N]) { std::copy_n(text, N, chars); }
  constexpr llvm::StringRef str() const { return {chars, N - 1}; }
};

// LOW-IO-2: the runtime helper the op lowers to (`Idr_Helper`).
template <Name Helper> struct CallsHelper {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    static llvm::StringRef getHelper() { return Helper.str(); }
  };
};

// IDR-EFF-1: an op that may crash writes the crash resource, and is
// speculatable exactly when it cannot crash. Both follow from the op's
// `getCrashCause` (`Idr_MayCrash`).
template <typename ConcreteType>
class MayCrash : public mlir::OpTrait::TraitBase<ConcreteType, MayCrash> {
public:
  void getEffects(
      llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>>
          &effects) {
    if (self().getCrashCause())
      effects.emplace_back(mlir::MemoryEffects::Write::get(), CrashResource::get());
  }
  mlir::Speculation::Speculatability getSpeculatability() {
    return self().getCrashCause() ? mlir::Speculation::NotSpeculatable
                                  : mlir::Speculation::Speculatable;
  }

private:
  ConcreteType self() { return *static_cast<ConcreteType *>(this); }
};

// Whether a value is a constant other than zero, and whether a Double is a
// finite constant: the facts that rule out a crash (IDR-EFF-1).
bool knownNonZero(mlir::Value value);
bool knownFinite(mlir::Value value);

// The types a value may have in the input (IDR-IN-1), and a field (IDR-DATA-2).
bool isValueType(mlir::Type type);
bool isFieldType(mlir::Type type);

} // namespace idr

#include "idr/IdrDialect.h.inc"

#include "idr/IdrInterfaces.h.inc"

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

// The first contract version that admits `op` (IDR-MOD-1): its `Since` trait,
// or 0. Every idr op is covered, because the list is ODS's own.
int sinceVersion(mlir::Operation *op);

} // namespace idr
