// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C++ halves of the idr dialect's op traits, and the guards'
// vocabulary: what the ODS declares about an op, so that each fact is
// written once, next to the op, and every pass derives from it. The
// generated ops name them as their bases, so IdrDialect.h includes this
// before them.
#ifndef IDR_IR_TRAITS_H
#define IDR_IR_TRAITS_H

#include "idr/IR/Grades.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <array>
#include <tuple>

namespace idr {

// A Free of ReferenceResource on each operand of `op` that `consumes`
// names and whose grade is own or excl; nothing before idr-rc.
void consumedEffects(mlir::Operation *op,
    llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects);

// A trait exists only as a base of its op: the op's mlir::Op base
// constructs it, and nothing else may.

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

// An idr.io op (`Idr_PerformsIO`), which the frontend orders in the world's
// chain; what a function may do is idr::bodyEffect's.
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

// The trait behind Idr_ConsumesOnly: an op whose only effect is what it
// takes over, which its flow says, reports that (consumedEffects).
template <typename ConcreteType>
class ConsumesOperands : public mlir::OpTrait::TraitBase<ConcreteType, ConsumesOperands> {
public:
  void getEffects(llvm::SmallVectorImpl<
      mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects) {
    consumedEffects(this->getOperation(), effects);
  }
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

// A grade op whose result is its operand's value, its identity and its
// exclusivity kept (Idr_SameValue), which a value's source looks through
// (sourceOf). idr.share carries its operand but forgets exclusivity, so it
// lacks this.
template <typename ConcreteType>
class SameValue : public mlir::OpTrait::TraitBase<ConcreteType, SameValue> {};

// An op whose result takes a reference of its own to what it reads, which
// its lowering counts (Idr_TakesReference).
template <typename ConcreteType>
class TakesReference : public mlir::OpTrait::TraitBase<ConcreteType, TakesReference> {};

// An op that builds the value it gives at run time (Idr_BuildsValue): a
// constructor, a closure, a suspension. The one list is the ops' own, in
// their definitions.
template <typename ConcreteType>
class BuildsValue : public mlir::OpTrait::TraitBase<ConcreteType, BuildsValue> {};

// The op has no runtime form: its result is its first operand at run time,
// a change of grade, linearity or kind (Idr_NoRuntimeForm), which idr-lower
// lowers to the operand's components, by one pattern for every op with the
// trait.
template <typename ConcreteType>
class NoRuntimeForm : public mlir::OpTrait::TraitBase<ConcreteType, NoRuntimeForm> {};

// A guard a pure total op takes (Idr_Guarded): the guard op `GuardOp`, and
// the indices of the op's operands it is given, in the guard op's operand
// order, the one it guards first. All of it is the type; nothing is stored.
template <typename GuardOp, unsigned... Operands>
struct Guard {};

// The guards of the op `Op`, in the order its ODS lists them:
// `using Guards = std::tuple<Guard<...>...>`, which idris-mlir-tblgen
// generates from the op's Idr_Guarded marks (IdrGuards.inc) for every op
// with Idr_GuardedOp. No definition here, so an op that lists the trait and
// has no generated guards does not compile.
template <typename Op>
struct Guarded;

// A pure total op whose guards read its own operands (Idr_GuardedOp). Its
// folder and its speculatability ask each guard op's own condition (its
// `holds`) on the op's operands at the guard's indices, read from
// Guarded<ConcreteType> at compile time: no op names its guard again, and
// nothing is looked up by op at run time. MLIR supplies an interface
// method from a trait so, as AlwaysSpeculatableImplTrait supplies
// getSpeculatability.
template <typename ConcreteType>
class GuardedOp : public mlir::OpTrait::TraitBase<ConcreteType, GuardedOp> {
public:
  // Whether every guard's condition holds of the constants the op's fold
  // adaptor `adaptor` holds at the operands the guard is given: what the
  // op's folder asks first, `if (!guardHolds(adaptor)) return {};`. Where
  // one fails, the guard crashes first, at run time, and the op computes
  // nothing.
  template <typename Adaptor>
  static bool guardHolds(Adaptor adaptor) {
    llvm::ArrayRef<mlir::Attribute> constants = adaptor.getOperands();
    auto holds = [&]<typename G, unsigned... Given>(Guard<G, Given...>) {
      std::array<mlir::Attribute, sizeof...(Given)> given{constants[Given]...};
      return G::holds(typename G::FoldAdaptor(given));
    };
    return std::apply([&](auto... guards) { return (holds(guards) && ...); },
                      typename Guarded<ConcreteType>::Guards{});
  }

  // Speculatable when every guard is passed: the operand it guards is the
  // result of the same guard op given the op's own other operands, which
  // has checked it, or the constants the operands are pass its condition.
  // A guard proved away by the path that reaches the op so leaves the op
  // below that path. An op that speculates lists ConditionallySpeculatable
  // beside the trait and takes this as its own.
  mlir::Speculation::Speculatability getSpeculatability() {
    mlir::Operation *op = this->getOperation();
    auto constantOf = [](mlir::Value value) {
      mlir::Attribute constant;
      mlir::matchPattern(value, mlir::m_Constant(&constant));
      return constant;
    };
    auto passed = [&]<typename G, unsigned Checked, unsigned... Others>(
                      Guard<G, Checked, Others...>) {
      std::array<mlir::Value, sizeof...(Others)> others{op->getOperand(Others)...};
      auto guard = op->getOperand(Checked).getDefiningOp<G>();
      if (guard && llvm::equal(guard->getOperands().drop_front(), others))
        return true;
      std::array<mlir::Attribute, 1 + sizeof...(Others)> constants{
          constantOf(op->getOperand(Checked)), constantOf(op->getOperand(Others))...};
      return G::holds(typename G::FoldAdaptor(constants));
    };
    bool all = std::apply([&](auto... guards) { return (passed(guards) && ...); },
                          typename Guarded<ConcreteType>::Guards{});
    return all ? mlir::Speculation::Speculatable : mlir::Speculation::NotSpeculatable;
  }
};

} // namespace idr

#endif // IDR_IR_TRAITS_H
