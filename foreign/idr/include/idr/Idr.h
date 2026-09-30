// The idr dialect.
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

// The resource that a possible crash writes to.
struct CrashResource : mlir::SideEffects::Resource::Base<CrashResource> {
  llvm::StringRef getName() const final { return "idr.crash"; }
};

// The resource that every IO op reads and writes, and that a crash and a
// possibly endless loop also write, so that no pass reorders either with
// output.
struct IOResource : mlir::SideEffects::Resource::Base<IOResource> {
  llvm::StringRef getName() const final { return "idr.io"; }
};

// The resource that idr.may_loop writes, so that a loop that may not end is
// never removed as dead.
struct DivergenceResource : mlir::SideEffects::Resource::Base<DivergenceResource> {
  llvm::StringRef getName() const final { return "idr.divergence"; }
};

// The resource that idr.lin.enter and idr.lin.use allocate their results
// on: no heap, only a new value that no pass may merge with another.
struct LinResource : mlir::SideEffects::Resource::Base<LinResource> {
  llvm::StringRef getName() const final { return "idr.lin"; }
};

// The traits below carry what IdrOps.td declares about an op, so that each
// fact is written once, next to the op, and every pass derives from it. A
// trait exists only as a base of its op: the op's mlir::Op base constructs
// it, and nothing else may.

// The runtime function the op lowers to, named after the op:
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

private:
  CallsRuntime() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// Whether each discardable attribute of `op` names the dialect that
// verifies it, or is one of the few names of no dialect that our own tools
// read. MLIR asks a dialect only about the attributes named with its
// prefix, so any other name would be accepted and read by no one.
mlir::LogicalResult verifyDiscardableAttrs(mlir::Operation *op);

// Every idr op (`Idr_KnownAttributes`): its discardable attributes are
// known ones.
template <typename ConcreteType>
class KnownAttributes : public mlir::OpTrait::TraitBase<ConcreteType, KnownAttributes> {
public:
  static mlir::LogicalResult verifyTrait(mlir::Operation *op) { return verifyDiscardableAttrs(op); }

private:
  KnownAttributes() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// An idr.io op (`Idr_PerformsIO`), what idr-effects looks for.
template <typename ConcreteType>
class PerformsIO : public mlir::OpTrait::TraitBase<ConcreteType, PerformsIO> {
private:
  PerformsIO() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// An op that may crash writes the crash resource and the IO
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
    Impl() = default;
    friend ConcreteType;
    template <typename, template <typename> class...> friend class mlir::Op;

    ConcreteType self() { return *static_cast<ConcreteType *>(this); }
  };
};

// The facts that rule out a crash: a constant other than zero
// (an integer or a big), a finite Double constant, and a string that cannot
// be empty (a non-empty constant, or a string built with a character or a
// number in it).
bool knownNonZero(mlir::Value value);
bool knownFinite(mlir::Value value);
bool knownNonEmpty(mlir::Value value);

// The types a field of a constructor may have.
bool isFieldType(mlir::Type type);

// How often a value may be used, as its type says: never (!idr.erased),
// exactly once (!idr.lin<T> and the world), or any number of times.
enum class Quantity : uint8_t { Zero, One, Many };
Quantity quantityOf(mlir::Type type);

// The type of the value itself: T for !idr.lin<T>, the type otherwise.
mlir::Type unrestricted(mlir::Type type);

// The value `value` was made from, seen through the linear positions it
// passed: `lin.enter %x` and `lin.use (lin.enter %x)` are %x. What a value
// is (its constructor, a field) does not change on the way; whether a read
// may take a linear part of it is the reader's to decide.
mlir::Value throughLinear(mlir::Value value);

// Whether `value` has one use, and so has each value it was made from
// through a linear position: a read of it is the only one, and may take
// its linear parts.
bool readOnce(mlir::Value value);

} // namespace idr

// The attributes come first: the dialect's helpers for its discardable
// attributes read them by their types.
#include "idr/IdrEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "idr/IdrAttrs.h.inc"

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

// The declaration a !idr.data or !idr.box type names, or null for any other
// type.
mlir::FlatSymbolRefAttr getSumName(mlir::Type type);

// The data declaration a !idr.data or !idr.box type names, or null.
DataOp lookupData(mlir::Operation *from, mlir::Type type);

// The constructor `ctor` of `data`, or null.
CtorOp lookupCtor(DataOp data, llvm::StringRef ctor);

// The constructor `@T::@C` names, or null.
CtorOp lookupCtor(mlir::Operation *from, mlir::SymbolRefAttr ctor);

// Registers the idr dialect, and (once per process) its passes and the named
// pipeline `idr-pipeline`.
void registerIdr(mlir::DialectRegistry &registry);
void registerIdrPipeline();

// The pipeline's steps, as textual pass pipelines, in order.
llvm::ArrayRef<llvm::StringRef> pipelineSteps();

} // namespace idr
