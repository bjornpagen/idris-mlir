// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect: what TableGen generates from IdrOps.td, with what the
// generated code needs declared around it, in the order it needs it: the
// grades, the resources, the traits, the guards' vocabulary and a data
// type's constructors before the generated attributes, types and
// interfaces, the flow vocabulary and its interface before the ops, and
// what reads the ops after them.
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
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

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

// Whether `operand`'s position takes over the reference its value holds,
// as the edges of its op's flow say (lib/IR/Effects.cpp): a use the op
// moves on or ends, a forwarded value, or an argument whose parameter owns
// it, which the program's stage says how to read. Given `symbols`, a call's
// callee is found through that table.
bool consumes(mlir::OpOperand &operand, mlir::SymbolTable *symbols = nullptr);

// A Free of ReferenceResource on each operand of `op` that `consumes`
// names and whose grade is own or excl; nothing before idr-rc.
void consumedEffects(mlir::Operation *op,
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

// An op that lowers to a call of a runtime function (`Idr_Runtime`), which
// its ODS names: the table idris-mlir-tblgen writes from the marks says
// which, and the runtime's prototypes are generated from the same marks.
template <typename ConcreteType>
class CallsRuntime : public mlir::OpTrait::TraitBase<ConcreteType, CallsRuntime> {
private:
  CallsRuntime() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};

// An op that does not return (`Idr_NoReturn`): the runtime function it
// calls is noreturn, and what follows it is unreachable.
template <typename ConcreteType>
class NoReturn : public mlir::OpTrait::TraitBase<ConcreteType, NoReturn> {
private:
  NoReturn() = default;
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

// An IO op the program's outside can observe (`Idr_ObservableIO`), what
// makes a memo label that reaches it `by_name`.
template <typename ConcreteType>
class ObservableIO : public mlir::OpTrait::TraitBase<ConcreteType, ObservableIO> {
private:
  ObservableIO() = default;
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

// The trait behind Idr_ConsumesOnly: an op whose only effect is what it
// takes over, which its flow says, reports that (consumedEffects). The
// operand groups it is written with say nothing more.
template <unsigned... Groups>
struct ConsumesOperands {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    void getEffects(llvm::SmallVectorImpl<
        mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects) {
      consumedEffects(this->getOperation(), effects);
    }
  };
};

// The result is the operand's value at whatever grade the result has: an
// op that only changes a grade (a linear position, a view, an exclusive
// value given on as owned), which a pass looks through by this trait, and
// through ViewLikeOpInterface where it asks for views.
template <typename ConcreteType>
class ResultCarriesOperand : public mlir::OpTrait::TraitBase<ConcreteType, ResultCarriesOperand> {
public:
  static mlir::LogicalResult verifyTrait(mlir::Operation *op) {
    if (unrestricted(op->getResult(0).getType()) != unrestricted(op->getOperand(0).getType()))
      return op->emitOpError("expects its result to be its operand's value, at any grade");
    return mlir::success();
  }
};

// The facts that rule out a crash: a constant other than zero
// (an integer or a big), a finite Double constant, and a string that cannot
// be empty (a non-empty constant, or a string built with a character or a
// number in it).
bool knownNonZero(mlir::Value value);
bool knownFinite(mlir::Value value);
bool knownNonEmpty(mlir::Value value);

// Whether output of `str` writes the pieces it is built from and never the
// string (the output fusion of the canonicalization's rewrites): a
// concatenation, a character before a string, one character, a number, or
// a list packed or concatenated for that output alone.
bool writtenInPieces(mlir::Value str);

namespace detail {
struct DataTypeStorage;
} // namespace detail

// A data type, which a constant constructor names before the types are
// declared (IdrTypes.td).
class DataType;

// One constructor of a data type's body (DataType). Its tag is its
// position in the body, and its name is unique there. `role` is what the
// constructor is to the passes that read it: base's nil or cons, a label of
// a closure or memo sum, a memo cell's Running or Forced state, or plain.
// `fn` is the label's function, exactly when the role is Label, so a label
// is never found by its name. `byName`: a memo sum's label whose function
// reaches an observable effect, so that the effect happens where the value
// is demanded: its cell is never written, and every force runs the
// function.
struct Ctor {
  mlir::StringAttr name;
  llvm::ArrayRef<mlir::Type> fields;
  bool byName = false;
  CtorRole role = CtorRole::Plain;
  mlir::FlatSymbolRefAttr fn;
  bool operator==(const Ctor &) const = default;
};

} // namespace idr

// The attributes come first: the dialect's helpers for its discardable
// attributes and the types' parameters name them.
#define GET_ATTRDEF_CLASSES
#include "idr/IR/IdrAttrs.h.inc"

#include "idr/IR/IdrDialect.h.inc"

// How a value moves, and the flow interface every op that moves one holds,
// which the ops name.
#include "idr/IR/FlowEdges.h"

#include "idr/IR/IdrInterfaces.h.inc"
#include "idr/IR/IdrTypeInterfaces.h.inc"

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.h.inc"

#define GET_OP_CLASSES
#include "idr/IR/IdrOps.h.inc"

namespace idr {

// The names a memo sum gives its two states, which their roles
// (CtorRole::Running, CtorRole::Forced) identify; a reader finds them by
// role, never by name.
inline constexpr llvm::StringLiteral memoRunning = "running";
inline constexpr llvm::StringLiteral memoForced = "forced";

// Whether the pure total op that reads `guarded` may run before the guard
// `Guard` that its ODS names (Idr_Guarded): `guarded` is the result of such
// a guard whose other operands are `against`, the op's own operands its
// condition reads beside it (for a string index, the string), or a
// constant the condition holds of with them. A guard proved away by the
// path that reaches the op so leaves the op below that path.
mlir::Speculation::Speculatability
guardedSpeculatability(mlir::Value guarded, mlir::ValueRange against,
                       llvm::function_ref<bool(mlir::Operation *)> isGuard,
                       llvm::function_ref<bool(llvm::ArrayRef<mlir::Attribute>)> holds);
template <typename Guard>
mlir::Speculation::Speculatability guardedSpeculatability(mlir::Value guarded,
                                                          mlir::ValueRange against = {}) {
  return guardedSpeculatability(
      guarded, against, [](mlir::Operation *op) { return mlir::isa<Guard>(op); },
      &Guard::holds);
}

// The most static data a folded constant may take: a folded op whose result
// can outgrow its operands (a big shifted left). A larger one would make the
// executable larger than computing it at runtime does, and the compilation
// slower, so it stays, to run at runtime. The value is never at stake, only
// the size and the speed.
inline constexpr uint64_t constantBytes = uint64_t{1} << 20;

// `unsupported (<phrase>)`: the words every refusal of a program begins
// with, the phrase the rule's ODS case spells. The one place they are
// written.
std::string refusalHead(Rule rule);

// A refusal of the program by `rule`: an error at `loc`, or at `op`, whose
// message begins with refusalHead(rule) and ": ", the caller streaming what
// was found after it. The rule is the diagnostic's metadata, data a handler
// reads (refusalRule), not printed text.
mlir::InFlightDiagnostic refuse(mlir::Location loc, Rule rule);
mlir::InFlightDiagnostic refuse(mlir::Operation *op, Rule rule);

// The rule a diagnostic refuses the program by; nothing for any other
// diagnostic.
std::optional<Rule> refusalRule(mlir::Diagnostic &diagnostic);

namespace detail {
// Adds the dialect's asm interface: the aliases of its data types and of
// its large constants.
void addAsmInterface(IdrDialect &dialect);

// What the ops that hold a constructor's tag share (lib/IR/OpsCon.cpp): the
// constructor `tag` of the data type of a value of `type`, or null after an
// error at `op`; the rule of the holes of a constructor built with `fields`
// values given and `dests` destinations given back; and, for a constructor
// built with `fields` and `holes`, the value given for field `index`, or
// null for a hole, and the destination of a hole, or null for a field
// given.
const Ctor *ctorAt(mlir::Operation *op, mlir::Type type, unsigned tag);
mlir::LogicalResult verifyHoles(mlir::Operation *op, const Ctor &ctor,
                                llvm::ArrayRef<int32_t> holes, size_t fields,
                                mlir::TypeRange dests);
mlir::Value givenField(mlir::ValueRange fields, llvm::ArrayRef<int32_t> holes, unsigned index);
mlir::Value holeDest(mlir::ResultRange dests, llvm::ArrayRef<int32_t> holes, unsigned index);
mlir::Type destOf(const Ctor &ctor, int32_t index);
} // namespace detail

} // namespace idr

#endif // IDR_IR_IDRDIALECT_H
