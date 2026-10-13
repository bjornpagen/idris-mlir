// The idr dialect: what TableGen generates from IdrOps.td, with what the
// generated code needs declared around it, in the order it needs it: the
// grades, the resources, the traits and the guards' vocabulary before the
// generated attributes, types and interfaces, and those before the ops.
#ifndef IDR_IR_IDRDIALECT_H
#define IDR_IR_IDRDIALECT_H

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/InferTypeOpInterface.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include <algorithm>
#include <atomic>
#include <optional>
#include <string>

// The enums, then the grades over them: the generated type builders name
// ::idr::Grade.
#include "idr/IR/Grades.h"

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

// The resource a consumed reference is freed from.
struct ReferenceResource : mlir::SideEffects::Resource::Base<ReferenceResource> {
  llvm::StringRef getName() const final { return "idr.reference"; }
};

// Whether `operand`'s position takes over the reference its value holds: an
// idr op says so by ConsumingOpInterface (an idr.call by its operand's
// grade, which is its callee's parameter's); a return, a yield of scf, a
// condition's carried values and a while's inits do. Given `symbols`, an
// idr.call answers from its callee's parameter through that table instead.
bool consumes(mlir::OpOperand &operand, mlir::SymbolTable *symbols = nullptr);

// A Free of ReferenceResource on each operand of `op` that `consumes`
// names and whose grade is own or excl; nothing before idr-rc.
void consumedEffects(mlir::Operation *op,
    llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects);

// What an op on a buffer or an array does besides computing: IO in the
// world's order, and for a new array or string an allocation (`allocated`,
// or null). A range or an index it reads is its guard's to check.
void ioEffects(mlir::Value allocated,
    llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects);

// Whether `op`, with everything in it, only computes: its effects are at
// most the allocation of its own results, so it may move across any op,
// run on fewer paths, or not at all.
bool onlyAllocates(mlir::Operation *op);

// Whether `op`, or something in it, may perform IO: an effect on the IO
// resource. An op that does not may run later, past ops that only compute,
// though it may crash or not return.
bool performsIO(mlir::Operation *op);

// The traits below carry what the ODS declares about an op, so that each
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

// An idr.io op (`Idr_PerformsIO`), what idr-effects looks for.
template <typename ConcreteType>
class PerformsIO : public mlir::OpTrait::TraitBase<ConcreteType, PerformsIO> {
private:
  PerformsIO() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// An op Idris names as a primitive (`Idr_Primitive`), what
// idris-mlir-tblgen generates the Idris side's primitive set from.
template <typename ConcreteType>
class Primitive : public mlir::OpTrait::TraitBase<ConcreteType, Primitive> {
private:
  Primitive() = default;
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

// The trait behind Idr_Consumes: the ODS operand groups an op takes over.
template <unsigned... Groups>
struct ConsumesOperands {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    bool consumedByTrait(unsigned number) {
      auto *op = static_cast<ConcreteType *>(this);
      return ((number >= op->getODSOperandIndexAndLength(Groups).first &&
               number < op->getODSOperandIndexAndLength(Groups).first +
                            op->getODSOperandIndexAndLength(Groups).second) || ...);
    }
    // Used by ops whose only effect is what they take over (Idr_ConsumesOnly).
    void getEffects(llvm::SmallVectorImpl<
        mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects) {
      consumedEffects(this->getOperation(), effects);
    }
  };
};

// The result is the operand's value at whatever grade the result has: an
// op that computes a new value of its operands' type, which the owned
// stage then owns.
template <typename ConcreteType>
class ResultCarriesOperand : public mlir::OpTrait::TraitBase<ConcreteType, ResultCarriesOperand> {
public:
  static mlir::LogicalResult verifyTrait(mlir::Operation *op) {
    if (unrestricted(op->getResult(0).getType()) != unrestricted(op->getOperand(0).getType()))
      return op->emitOpError("expects its result to be its operand's value, at any grade");
    return mlir::success();
  }
};

// The visibility of a declaration that is public, always
// (`Idr_PublicSymbol`): the op stores none. No pass of ours hides a
// declaration, so a request to is a broken invariant, which ends the run
// rather than leaving an error the pass that asked cannot see.
template <typename ConcreteType>
class PublicSymbol : public mlir::OpTrait::TraitBase<ConcreteType, PublicSymbol> {
public:
  mlir::SymbolTable::Visibility getVisibility() { return mlir::SymbolTable::Visibility::Public; }
  void setVisibility(mlir::SymbolTable::Visibility visibility) {
    if (visibility != mlir::SymbolTable::Visibility::Public)
      llvm::reportFatalInternalError(llvm::Twine("a pass asked to hide '") +
                                     ConcreteType::getOperationName() +
                                     "', a declaration, which is public, always");
  }

private:
  PublicSymbol() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// The facts that rule out a crash: a constant other than zero
// (an integer or a big), a finite Double constant, and a string that cannot
// be empty (a non-empty constant, or a string built with a character or a
// number in it).
bool knownNonZero(mlir::Value value);
bool knownFinite(mlir::Value value);
bool knownNonEmpty(mlir::Value value);

// The condition a guard (idr.check.*) checks.
enum class CheckKind { Nonzero, InBounds, Nonempty, Byte, Finite, Range };

// Whether the condition of a guard of `kind` holds of `constants`, the
// guard's operands in order: what a guard's folder and every total op's
// folder ask before computing. A null one is not a constant, and the
// condition does not hold of it.
bool checkHolds(CheckKind kind, mlir::ArrayRef<mlir::Attribute> constants);

// Whether the pure total op `op` may run before the condition that guards
// it: each of its operands that `guarded` numbers is the result of its
// guard (for an index, the guard against the length of the op's own
// string), or a constant the guard's condition holds of. A guard proved
// away by the path that reaches the op so leaves the op below that path.
mlir::Speculation::Speculatability checkSpeculatability(mlir::Operation *op,
                                                       mlir::ArrayRef<unsigned> guarded);

// Whether output of `str` writes the pieces it is built from and never the
// string (the output fusion of the canonicalization's rewrites): a
// concatenation, a character before a string, one character, a number, or
// a list packed or concatenated for that output alone.
bool writtenInPieces(mlir::Value str);

} // namespace idr

// The attributes come first: the dialect's helpers for its discardable
// attributes and the types' parameters name them.
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

#include "idr/IR/IdrInterfaces.h.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

namespace idr {

// The two constructors every memo sum has besides its labels: a suspension
// whose force is running, and a forced one, which holds its value. Every
// pass that builds or reads them names them by these.
inline constexpr llvm::StringLiteral memoRunning = "running";
inline constexpr llvm::StringLiteral memoForced = "forced";

// The most static data a folded constant may take: a folded op whose result
// can outgrow its operands (a big shifted left). A larger one would make the
// executable larger than computing it at runtime does, and the compilation
// slower, so it stays, to run at runtime. The value is never at stake, only
// the size and the speed.
inline constexpr uint64_t constantBytes = uint64_t{1} << 20;

// The value an evaluated suspension holds: the operand of the body's one
// op when that op is an idr.yield of one value, which is then defined above
// the delay; null for any other delay. Forcing such a suspension computes
// nothing, so idr-isolate leaves it, defunctionalization builds its memo
// cell forced, and a force of it folds to the value.
mlir::Value evaluatedValue(DelayOp delay);

namespace detail {
// Adds the dialect's asm interface: the aliases of its data types and of
// its large constants.
void addAsmInterface(IdrDialect &dialect);
} // namespace detail

} // namespace idr

#endif // IDR_IR_IDRDIALECT_H
