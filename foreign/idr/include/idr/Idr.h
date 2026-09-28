// The idr dialect (docs/cutover.md, section 10).
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
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"

#include <algorithm>
#include <optional>
#include <string>

namespace idr {

// The resource that a possible crash writes to (IDR-EFF-1).
struct CrashResource : mlir::SideEffects::Resource::Base<CrashResource> {
  llvm::StringRef getName() const final { return "idr.crash"; }
};

// The resource that every IO op reads and writes (IDR-EFF-2), and that a
// crash and a possibly endless loop also write, so that no pass reorders
// either with output (A21).
struct IOResource : mlir::SideEffects::Resource::Base<IOResource> {
  llvm::StringRef getName() const final { return "idr.io"; }
};

// The resource that idr.may_loop writes (SEM-EVAL-5).
struct DivergenceResource : mlir::SideEffects::Resource::Base<DivergenceResource> {
  llvm::StringRef getName() const final { return "idr.divergence"; }
};

// The traits below carry what IdrOps.td declares about an op, so that each
// fact is written once, next to the op, and every pass derives from it.

// LOW-RT-1: the runtime function the op lowers to, named after the op:
// `idr.str.append` calls `idris_rt_str_append` (`Idr_CallsRuntime`).
template <typename ConcreteType>
class CallsRuntime : public mlir::OpTrait::TraitBase<ConcreteType, CallsRuntime> {
public:
  static llvm::StringRef getHelper() {
    static const std::string helper = [] {
      std::string name = "idris_rt_";
      name += ConcreteType::getOperationName().drop_front(sizeof("idr.") - 1);
      std::replace(name.begin(), name.end(), '.', '_');
      return name;
    }();
    return helper;
  }
};

// IDR-EFF-2: an idr.io op (`Idr_PerformsIO`), what idr-effects looks for.
template <typename ConcreteType>
class PerformsIO : public mlir::OpTrait::TraitBase<ConcreteType, PerformsIO> {};

// IDR-EFF-1, A21: an op that may crash writes the crash resource and the IO
// resource, and is speculatable exactly when it can neither crash nor
// allocate. All of it follows from the op's `getCrashCause` and from whether
// it allocates its result (`Idr_MayCrash`).
template <bool Allocates> struct MayCrash {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    void getEffects(
        llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>>
            &effects) {
      if constexpr (Allocates)
        effects.emplace_back(mlir::MemoryEffects::Allocate::get(),
                             this->getOperation()->getOpResult(0),
                             mlir::SideEffects::DefaultResource::get());
      if (self().getCrashCause()) {
        effects.emplace_back(mlir::MemoryEffects::Write::get(), CrashResource::get());
        effects.emplace_back(mlir::MemoryEffects::Write::get(), IOResource::get());
      }
    }
    mlir::Speculation::Speculatability getSpeculatability() {
      return Allocates || self().getCrashCause() ? mlir::Speculation::NotSpeculatable
                                                 : mlir::Speculation::Speculatable;
    }

  private:
    ConcreteType self() { return *static_cast<ConcreteType *>(this); }
  };
};

// The facts that rule out a crash (IDR-EFF-1): a constant other than zero
// (an integer or a big), a finite Double constant, and a string that cannot
// be empty (a non-empty constant, or a string built with a character or a
// number in it).
bool knownNonZero(mlir::Value value);
bool knownFinite(mlir::Value value);
bool knownNonEmpty(mlir::Value value);

// The types a field of a constructor may have (IDR-DATA-3).
bool isFieldType(mlir::Type type);

} // namespace idr

#include "idr/IdrDialect.h.inc"

#include "idr/IdrEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IdrAttrs.h.inc"

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

// The declaration a !idr.data or !idr.box type names, or null for any other
// type.
mlir::FlatSymbolRefAttr getSumName(mlir::Type type);

// The data declaration a !idr.data or !idr.box type names, or null.
DataOp lookupData(mlir::Operation *from, mlir::Type type);

// The constructor `ctor` of `data`, or null.
CtorOp lookupCtor(DataOp data, llvm::StringRef ctor);

// The constructor `@T::@C` names, or null.
CtorOp lookupCtor(mlir::Operation *from, mlir::SymbolRefAttr ctor);

// The facts idr-effects computes on a function (IDR-FACT-1): whether it is
// pure, and whether it may crash. Together with `idr.total` they decide
// whether an unused call may be removed (OPT-CALL-1).
bool isPure(mlir::func::FuncOp fn);
bool mayCrash(mlir::func::FuncOp fn);
bool isTotal(mlir::func::FuncOp fn);

// Registers the idr dialect, and (once per process) its passes and the named
// pipeline `idr-pipeline` (OPT-PIPE-1).
void registerIdr(mlir::DialectRegistry &registry);
void registerIdrPipeline();

// The pipeline steps of OPT-PIPE-1, as textual pass pipelines, in order.
llvm::ArrayRef<llvm::StringRef> pipelineSteps();

} // namespace idr
