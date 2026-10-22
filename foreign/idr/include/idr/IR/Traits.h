// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C++ halves of the dialect's own op traits, which the specification
// names (Spec.idr's core declarations) and its printed ODS gives the ops as
// bases, so IdrDialect.h includes this before them: an op whose result is
// its operand at another grade, one that keeps its operand's identity too,
// one that eliminates its first operand, one whose result is used as often
// as the values it takes, and a partial op's guards.
#ifndef IDR_IR_TRAITS_H
#define IDR_IR_TRAITS_H

#include "idr/IR/Grades.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpDefinition.h"
#include "llvm/ADT/STLExtras.h"

#include <array>
#include <tuple>

namespace idr {

// The result is the operand's value at whatever grade the result has: an
// op that only changes a grade, which a pass looks through by this trait.
template <typename ConcreteType>
class ResultCarriesOperand : public mlir::OpTrait::TraitBase<ConcreteType, ResultCarriesOperand> {
public:
  static mlir::LogicalResult verifyTrait(mlir::Operation *op) {
    if (unrestricted(op->getResult(0).getType()) != unrestricted(op->getOperand(0).getType()))
      return op->emitOpError("expects its result to be its operand's value, at any grade");
    return mlir::success();
  }
};

// A grade op whose result is its operand's value with its identity and its
// exclusivity kept, which a value's source looks through.
template <typename ConcreteType>
class SameValue : public mlir::OpTrait::TraitBase<ConcreteType, SameValue> {};

// An op that eliminates its first operand and does nothing else with it (a
// match on a closure sum, a read of its field, a string's output): where a
// chain of single uses ends that raising moves into a clone of the callee
// building the operand. Raising asks for the trait, so no op is named.
template <typename ConcreteType>
class EliminatesOperand : public mlir::OpTrait::TraitBase<ConcreteType, EliminatesOperand> {};

// The grade's own rule over an op's groups: each value of its result group
// `Result` is used once exactly when a value of one of its operand groups
// `From...` is (a closure over a linear capture is linear). The positions
// are ODS's groups, printed from the specification's rule.
template <unsigned Result, unsigned... From>
struct ResultUsesMax {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    static mlir::LogicalResult verifyTrait(mlir::Operation *op) {
      auto concrete = llvm::cast<ConcreteType>(op);
      auto once = [](mlir::Value value) { return usesOf(value.getType()) == Uses::Once; };
      Uses expected =
          (llvm::any_of(concrete.getODSOperands(From), once) || ...) ? Uses::Once : Uses::Many;
      for (mlir::Value result : concrete.getODSResults(Result))
        if (usesOf(result.getType()) != expected)
          return op->emitOpError("expects its result to be used once exactly when a value it "
                                 "takes is");
      return mlir::success();
    }
  };
};

// A guard a pure total op takes: the guard op `GuardOp`, and the indices of
// the op's operands it is given, in the guard op's operand order, the one it
// guards first. All of it is the type; nothing is stored.
template <typename GuardOp, unsigned... Operands>
struct Guard {};

// The guards of the op `Op`, in the order its specification lists them:
// `using Guards = std::tuple<Guard<...>...>`, printed for every op that
// takes one (Generated/Guards.h.inc). No definition here, so an op with the
// trait and no printed guards does not compile.
template <typename Op>
struct Guarded;

// A pure total op whose guards read its own operands. Its folder and its
// speculatability ask each guard op's own condition (its `holds`) on the
// op's operands at the guard's indices, read from Guarded<ConcreteType> at
// compile time: no op names its guard again, and nothing is looked up by op
// at run time.
template <typename ConcreteType>
class GuardedOp : public mlir::OpTrait::TraitBase<ConcreteType, GuardedOp> {
public:
  // Whether every guard's condition holds of the constants the op's fold
  // adaptor holds at the operands the guard is given: what the op's folder
  // asks first. Where one fails, the guard crashes first, at run time, and
  // the op computes nothing.
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
