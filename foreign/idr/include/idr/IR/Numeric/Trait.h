// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The trait of an op of inline arithmetic, `InlineArith<F>`, which the
// specification attaches to each op whose meaning is `Inline f` and names
// with the meaning's function object (Inline.h): it is the op's folder (F
// over words), its integer ranges (F over intervals, through upstream's
// InferIntRangeInterface, whose trait this one is, so the op lists no
// interface and declares no method: the trait's method is the op's by
// inheritance; and, with no op at all, `inferRanges`, the same function)
// and, through `expand`, its arith (F over an IR builder).
// So an op's class says nothing of its arithmetic, and no reader of an
// inline op names the op.
//
// The fold is over constant operands alone: an identity with one operand
// unknown (a quotient by 1) is a rule of the specification, checked
// against F (Laws.h), never a partial fold. A guarded op folds only where
// its guards hold on its constants: past a refuted guard the program has
// crashed, and the op computes nothing.
#ifndef IDR_IR_NUMERIC_TRAIT_H
#define IDR_IR_NUMERIC_TRAIT_H

#include "idr/IR/Numeric/Arith.h"
#include "idr/IR/Numeric/Inline.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/Numeric/Word.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <array>
#include <cstddef>
#include <utility>

namespace idr::numeric {

// The word an integer constant is.
Word wordOf(mlir::IntegerAttr constant);
// The integer constant of `type` a word is.
mlir::IntegerAttr attrOf(mlir::Type type, Word word);

// An op that guards its own operands (the trait GuardedOp, from the
// specification's guards) asks them before folding.
template <class ConcreteOp>
concept GuardsItsOperands = requires(typename ConcreteOp::FoldAdaptor adaptor) {
  { ConcreteOp::guardHolds(adaptor) } -> std::convertible_to<bool>;
};

template <class F>
struct InlineArith {
  // F over the operands' intervals, at the shape of upstream's own range
  // functions (`mlir::intrange::inferAnd` and kin): one body, which the op's
  // interface answers with and which the e-graph's table of range functions
  // names for a node a rule built, where no op stands to be asked.
  static mlir::ConstantIntRanges inferRanges(llvm::ArrayRef<mlir::ConstantIntRanges> ranges) {
    Intervals d;
    return [&]<std::size_t... I>(std::index_sequence<I...>) {
      return F::apply(d, ranges[I]...);
    }(std::make_index_sequence<F::arity>());
  }

  // The interface's trait is the base, not a sibling: an op holding both
  // would find two `inferResultRanges`, the interface's default and ours;
  // derived from it, ours hides the default, and this trait alone registers
  // the interface, its base giving the interface's id and model.
  template <class ConcreteOp>
  class Impl : public mlir::InferIntRangeInterface::Trait<ConcreteOp> {
    static constexpr std::size_t arity = F::arity;

  public:
    // F of the op's constant operands, each a word of its own width; none
    // where an operand is no constant or a guard refuses them.
    static mlir::OpFoldResult foldTrait(mlir::Operation *op,
                                        llvm::ArrayRef<mlir::Attribute> operands) {
      std::array<mlir::IntegerAttr, arity> constants;
      for (std::size_t i = 0; i < arity; ++i) {
        constants[i] = llvm::dyn_cast_if_present<mlir::IntegerAttr>(operands[i]);
        if (!constants[i])
          return {};
      }
      if constexpr (GuardsItsOperands<ConcreteOp>)
        if (!ConcreteOp::guardHolds(
                typename ConcreteOp::FoldAdaptor(operands, llvm::cast<ConcreteOp>(op))))
          return {};
      Words d;
      Word result = [&]<std::size_t... I>(std::index_sequence<I...>) {
        return F::apply(d, wordOf(constants[I])...);
      }(std::make_index_sequence<arity>());
      return attrOf(op->getResult(0).getType(), result);
    }

    // F over the operands' intervals, as upstream's analyses ask.
    void inferResultRanges(llvm::ArrayRef<mlir::ConstantIntRanges> ranges,
                           mlir::SetIntRangeFn setResultRange) {
      setResultRange(this->getOperation()->getResult(0), InlineArith::inferRanges(ranges));
    }

    // F built as arith at `builder`'s insertion point over `operands`, the
    // op's operands as the conversion gives them.
    static mlir::Value expand(mlir::OpBuilder &builder, mlir::Location loc,
                              mlir::ValueRange operands) {
      Arith d(builder, loc);
      return [&]<std::size_t... I>(std::index_sequence<I...>) {
        return F::apply(d, operands[I]...);
      }(std::make_index_sequence<arity>());
    }
  };
};

// An op whose meaning is inline arithmetic, by its trait.
template <class Op>
concept InlineOp = requires(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange operands) {
  { Op::expand(b, loc, operands) } -> std::same_as<mlir::Value>;
};

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_TRAIT_H
