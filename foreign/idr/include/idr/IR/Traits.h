// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C++ halves of the dialect's own op traits, which the specification
// names (Spec.idr's core declarations) and its printed ODS gives the ops as
// bases, so IdrDialect.h includes this before them: an op whose result is
// its operand at another grade, which gives it on with no run-time work,
// one that keeps its operand's identity too, one that eliminates its first
// operand, one whose result is used as often as the values it takes, and a
// partial op's guards. And the answer StructureOpInterface gives, a sum
// whose alternatives hold values, which no generated header can state, so
// it is declared here, before the generated interfaces that name it.
#ifndef IDR_IR_TRAITS_H
#define IDR_IR_TRAITS_H

#include "idr/IR/Grades.h"
// What an op does at run time to give its operand on, which a change of
// grade answers here, before the generated interfaces.
#include "idr/IR/Generated/Carry.h.inc"
// Where a guard's operands' values come from, which its condition reads.
#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Intervals.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpDefinition.h"
#include "llvm/ADT/STLExtras.h"

#include <array>
#include <tuple>
#include <variant>

namespace idr {

// How an op's result is built of its operands, as StructureOpInterface
// answers: a constructor of its fields, a natural's successor or
// predecessor of another, or none of these where the op runs. Each
// alternative holds only what its kind has, so a reader folds the answer
// and names no op.
namespace structural {
// The constructor `tag`, its fields `fields`, operands of the op.
struct Built {
  Tag tag;
  mlir::OperandRange fields;
};
// `of` plus one.
struct Successor {
  mlir::Value of;
};
// `of` minus one, `of` a natural that is not zero.
struct Predecessor {
  mlir::Value of;
};
// None of these: an op that builds its result of an operand where its
// operands allow, here computing it otherwise (a sum neither of whose
// operands is a constant one).
struct Unbuilt {};
} // namespace structural
using Structure = std::variant<structural::Unbuilt, structural::Built, structural::Successor,
                               structural::Predecessor>;

// Declared by the generated interfaces, after this header.
class CarriesOnOpInterface;

namespace detail {
// The trait by which an op of class `ConcreteType` implements the op
// interface `Interface`, found through the op's class, so where the op is
// defined: a trait here may implement an interface the generated header
// declares after it, since the generated ops come after both.
template <typename Interface, typename ConcreteType>
struct InterfaceTraitOf {
  using type = typename Interface::template Trait<ConcreteType>;
};
} // namespace detail

// The result is the operand's value at whatever grade the result has: an
// op that only changes a grade, which a pass looks through by this trait.
// A grade has no run-time form, so every such op gives its operand on with
// no run-time work: the class is the carrying interface's trait, which
// registers the interface for each op of the trait, and answers `Free`
// here, once for all of them. Given an operand of another type, its result
// takes the weakest hold that operand's and its own fit, so both may stand
// where it is asked, and keeps its own where the operand's fits it or no
// hold fits both (two releases).
template <typename ConcreteType>
class ResultCarriesOperand
    : public detail::InterfaceTraitOf<CarriesOnOpInterface, ConcreteType>::type {
public:
  static mlir::LogicalResult verifyTrait(mlir::Operation *op) {
    if (unrestricted(op->getResult(0).getType()) != unrestricted(op->getOperand(0).getType()))
      return op->emitOpError("expects its result to be its operand's value, at any grade");
    return mlir::success();
  }

  static constexpr Carry getCarry() { return Carry::Free; }

  mlir::Type getCarriedType(mlir::Type operand) {
    mlir::Type own = this->getOperation()->getResult(0).getType();
    std::optional<Hold> from = holdOf(operand);
    std::optional<Hold> at = holdOf(own);
    if (!from || !at || from->fits(*at))
      return own;
    std::optional<Hold> joined = weakest({*from, *at});
    return joined ? atHold(own, *joined) : own;
  }
};

// A grade op whose result is its operand's value with its identity and its
// exclusivity kept, which a value's source looks through.
template <typename ConcreteType>
class SameValue : public mlir::OpTrait::TraitBase<ConcreteType, SameValue> {};

// An op that eliminates its first operand and does nothing else with it (a
// match on a closure sum, a read of its field, a string's output). Two
// readers ask for the trait, so neither names an op: raising, where a chain
// of single uses it moves into a clone of the callee building the operand
// ends; and the string lowering, where a string made only to be written is
// written from its maker's operands instead. That lowering knows one output
// of a string, so the specification's generator refuses a second op that
// eliminates a string.
template <typename ConcreteType>
class EliminatesOperand : public mlir::OpTrait::TraitBase<ConcreteType, EliminatesOperand> {};

// An op on which a pass's run covers the whole program, on the pass
// manager's own thread, so the contracts and a test's stage expectations
// are checked around that run; the instrumentation asks for the trait, so
// no op is named.
template <typename ConcreteType>
class CheckedRoot : public mlir::OpTrait::TraitBase<ConcreteType, CheckedRoot> {};

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
// speculatability ask each guard op's own condition (its `decide`) on the
// op's operands at the guard's indices, read from Guarded<ConcreteType> at
// compile time: no op names its guard again, and nothing is looked up by op
// at run time.
template <typename ConcreteType>
class GuardedOp : public mlir::OpTrait::TraitBase<ConcreteType, GuardedOp> {
public:
  // Whether every guard's condition holds of the op's operands as `where`
  // knows them (each one's interval, and the constant `where` holds of it)
  // at the operands the guard is given: what the op's fold asks first,
  // wherever its constants live. Where one fails, the guard crashes first,
  // at run time, and the op computes nothing.
  template <fold::Where W>
  static bool guardsHold(W &where, llvm::ArrayRef<mlir::ConstantIntRanges> ranges,
                         llvm::ArrayRef<typename W::Operand> operands) {
    auto holds = [&]<typename G, unsigned... Given>(Guard<G, Given...>) {
      std::array<mlir::ConstantIntRanges, sizeof...(Given)> intervals{ranges[Given]...};
      std::array<typename W::Operand, sizeof...(Given)> given{operands[Given]...};
      return G::decide(where, intervals, given) == numeric::Known::Holds;
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
      fold::InAttributes where(op->getContext());
      return G::decide(where, fold::rangesOf(constants), constants) == numeric::Known::Holds;
    };
    bool all = std::apply([&](auto... guards) { return (passed(guards) && ...); },
                          typename Guarded<ConcreteType>::Guards{});
    return all ? mlir::Speculation::Speculatable : mlir::Speculation::NotSpeculatable;
  }
};

} // namespace idr

#endif // IDR_IR_TRAITS_H
