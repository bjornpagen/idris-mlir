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
#include "mlir/IR/Builders.h"
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

// A grade: what Idris proved of a value, kept in its type where no pass
// can drop it. The quantity is the number of uses Idris allows, 0, 1 or
// ω (Quantity); the permission is what the value owns, nothing to say (·),
// a borrow, one reference of its own, or an exclusive cell graph, which the
// owned stage decides. A plain type T is the grade (ω, ·).
enum class Quantity : uint8_t { Zero, One, Many };
enum class Permission : uint8_t { None, Borrow, Own, Excl };

struct Grade {
  Quantity quantity = Quantity::Many;
  Permission permission = Permission::None;
  bool operator==(const Grade &) const = default;
  bool plain() const { return quantity == Quantity::Many && permission == Permission::None; }
};

inline llvm::hash_code hash_value(Grade grade) {
  return llvm::hash_combine(static_cast<unsigned>(grade.quantity),
                            static_cast<unsigned>(grade.permission));
}

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

// func.call answers MemoryEffectOpInterface from its callee's facts
// (lib/Facts/CallEffects.cc); registered with the dialect.
void registerCallEffects(mlir::DialectRegistry &registry);

// Whether `op`, with everything in it, only computes: its effects are at
// most the allocation of its own results, so it may move across any op,
// run on fewer paths, or not at all.
bool onlyAllocates(mlir::Operation *op);

// Whether `op`, or something in it, may perform IO: an effect on the IO
// resource. An op that does not may run later, past ops that only compute,
// though it may crash or not return.
bool performsIO(mlir::Operation *op);

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

// Whether output of `str` writes the pieces it is built from and never the
// string (the output fusion of Canonicalize.td): a concatenation, a
// character before a string, one character, a number, or a list packed or
// concatenated for that output alone.
bool writtenInPieces(mlir::Value str);

// The types a field of a constructor may have.
bool isFieldType(mlir::Type type);

// An array: `memref<?xE>` of a field type E at no grade (Idr_ArrayType).
bool isArray(mlir::Type type);

// How often a value may be used, as its type says: never (!idr.erased),
// exactly once (!idr.lin<T> and the world), or any number of times.
Quantity quantityOf(mlir::Type type);

// The type of the value itself: T for !idr.lin<T>, the type otherwise.
mlir::Type unrestricted(mlir::Type type);

// The value `value` was made from, seen through the linear positions it
// passed: `lin.enter %x` and `lin.use (lin.enter %x)` are %x. What a value
// is (its constructor, a field) does not change on the way; whether a read
// may take a linear part of it is the reader's to decide.
mlir::Value throughLinear(mlir::Value value);

// Whether the field at `index` of a constructor value is read exactly once,
// and the value is read no other way: through its grade changes every use
// is a field read, and one of them reads `index`. Then a linear operand at
// that index moves into its one read.
bool fieldReadOnce(mlir::Value value, unsigned index);

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

namespace idr {

// The grade of a type: its own for !idr.q, (ω, ·) for a plain type.
Grade gradeOf(mlir::Type type);

// The type `value` at `grade`, in canonical form: `value` itself at
// (ω, ·), and never a grade of a graded type.
mlir::Type graded(Grade grade, mlir::Type value);

// The spellings: !idr.lin<T>, !idr.erased and !idr.world.
mlir::Type linear(mlir::Type value);
mlir::Type erased(mlir::MLIRContext *ctx);
mlir::Type world(mlir::MLIRContext *ctx);

// Whether a type is a linear value other than the world (one that entered
// its grade and is used out of it), which its grade says; or the world or
// the erased value, which their carriers say, graded or stripped.
bool isLinear(mlir::Type type);
bool isWorld(mlir::Type type);
bool isErased(mlir::Type type);

// The owned stage's grades: a value that holds a reference of its own
// (own, or excl), and the view of it, which holds none. `owned` and `view`
// keep the quantity and change the permission; `atQuantity` keeps the
// permission and changes the quantity.
bool isOwned(mlir::Type type);
mlir::Type owned(mlir::Type type);
mlir::Type view(mlir::Type type);
mlir::Type atQuantity(mlir::Type type, Quantity quantity);

// Whether a value holds the only reference to every cell of its cell
// graph (the excl permission), which idr-rc proves and writes into the
// type: taking it apart needs no count test, and its cells no null test.
bool isExclusive(mlir::Type type);

// Idris's product of quantities: 0 absorbs, 1 is the unit, and ω·ω is ω.
Quantity times(Quantity a, Quantity b);

// The type at which a region of a match binds a field of its scrutinee:
// the field's value at the product of the scrutinee's quantity and the
// field's, as Idris binds a pattern variable (a linear field of a value
// used many times is used many times; a field of a linear value is used as
// the field says). The world, which is only ever at its own grade, stays
// the world.
mlir::Type fieldType(mlir::Type scrutinee, mlir::Type field);

// `value` held as `type`, its own type at another quantity: entered into a
// linear type, or used out of one; itself when the types agree.
mlir::Value heldAs(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value, mlir::Type type);

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

} // namespace idr

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

// The cons constructor of the list type `list` the string builders walk
// (a box of a nil without fields and a cons of `element` and the list), or
// null with an error at `op`.
CtorOp listCons(mlir::Operation *op, mlir::Type list, mlir::Type element);

// The string a constant list of characters packs to, or a constant list of
// strings concatenates to, as the runtime builds it (lib/Fold); null for
// any other constant.
mlir::Attribute stringOfList(mlir::MLIRContext *context, mlir::Attribute list);

// The elimination of a value that begins at one of its uses: an apply of
// the value, or of one field of it (an action in `MkIO f`), each read
// through the one use of a linear value, where the value may first pass a
// linear position entered and used at once. Each step is the one use of
// the step before, so the apply is all the use does with the value. It is
// what raising moves into a clone of a callee whose result it eliminates,
// where it meets the closure each tail builds; so a call's result that has
// one is worth moving to where the elimination is.
struct Elimination {
  // The pair that only moves the value into a linear position and out
  // again before it is read, or null.
  LinEnterOp enter;
  LinUseOp exit;
  FieldOp field; // null: the value itself is applied
  LinUseOp use;  // null: what is applied is not linear
  ApplyOp apply;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);

// Registers the idr dialect, and (once per process) its passes and the named
// pipeline `idr-pipeline`.
void registerIdr(mlir::DialectRegistry &registry);
void registerIdrPipeline();

// The pipeline's steps, as textual pass pipelines, in order.
llvm::ArrayRef<llvm::StringRef> pipelineSteps();

} // namespace idr
