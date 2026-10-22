// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one fold of every op whose meaning is a runtime function: its
// constant operands converted to the runtime's values by the kind its
// function takes each in, the function itself called (idris-mlir links the
// runtime natively, so a primitive has one implementation, at compile time
// and at run time), and the result converted back by the kind it gives.
// Which function an op calls, and the kinds, are its row of the generated
// runtime ABI (Abi<Op>), read here and by the lowering, so a fold and a
// call disagree only if one row is read two ways. The trait `RuntimeFolds`
// supplies the fold; the specification attaches it to each op whose
// meaning is `Runtime` and whose row has a constant form for every kind,
// so an IO op or a buffer op cannot carry it.
//
// A guarded op folds only where its guards hold on its constants: past a
// refuted guard the program has crashed. An op the runtime's function
// would make too large a constant for, or whose function has a precondition
// the op's type does not carry, declares `foldable` (a member hook of its
// specification), which the fold asks first.
//
// Besides: what a constant constructor or closure holds in a field or
// capture (`buildable`), and the string a constant list packs or
// concatenates to, the folds of str.pack and str.concat.
#ifndef IDR_IR_FOLD_H
#define IDR_IR_FOLD_H

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "llvm/ADT/SmallVector.h"

// The op classes by name, so the generated ABI rows can name them before
// they are defined.
#define GET_OP_FWD_DEFINES
#include "idr/IR/IdrOps.h.inc"

// The runtime's C ABI: its strings and bigs, and the prototype of each op's
// function, then each op's row: how its function takes each operand and
// gives its result, and the function itself (idr::runtime::Abi<Op>).
#include "idris_rt.h"
#include "idr/IR/Generated/RuntimeAbi.h.inc"

#include <array>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <tuple>
#include <utility>

namespace idr::fold {

// The owned references one fold holds, released together when it ends.
// Every runtime operation returns an owned reference, even when what it
// returns is one of its arguments, so the scope keeps every reference it is
// given, a repeated one as often as it was given, and releases each once.
class Scope {
public:
  explicit Scope(mlir::MLIRContext *c) : ctx(c) {}
  ~Scope();
  Scope(const Scope &) = delete;
  Scope &operator=(const Scope &) = delete;

  mlir::MLIRContext *context() const { return ctx; }
  const idris_rt_str *keep(const idris_rt_str *s);
  idris_rt_big keep(idris_rt_big b);

private:
  mlir::MLIRContext *ctx;
  llvm::SmallVector<const idris_rt_str *> strings;
  llvm::SmallVector<idris_rt_big> bigs;
};

// A constant operand as the runtime's value of the kind its function takes
// it in, or nothing where the operand is no constant of that kind.
std::optional<const idris_rt_str *> strOf(Scope &scope, mlir::Attribute constant);
std::optional<idris_rt_big> bigOf(Scope &scope, mlir::Attribute constant);
std::optional<int32_t> int32Of(mlir::Attribute constant);
std::optional<int64_t> int64Of(mlir::Attribute constant);
std::optional<int64_t> signedOf(mlir::Attribute constant);
std::optional<uint64_t> unsignedOf(mlir::Attribute constant);
std::optional<double> doubleOf(mlir::Attribute constant);

// The runtime's result as the constant of the op's result type: a string,
// a big, an integer (an int32_t or an int64_t at the result's width), a
// result modulo 2^64 wrapped to the width, a Double, a truth.
mlir::Attribute strAttr(Scope &scope, const idris_rt_str *s);
mlir::Attribute bigAttr(Scope &scope, idris_rt_big b);
mlir::Attribute intAttr(mlir::Type type, int64_t value);
mlir::Attribute wrapped(mlir::Type type, int64_t value);
mlir::Attribute doubleAttr(mlir::Type type, double value);
mlir::Attribute boolAttr(mlir::MLIRContext *ctx, bool value);

// The constant where idr.constant holds it at `type`, else null: what a
// fold of a string, a big or a constant of ours gives at its result's
// type, so a fold gives only what its dialect materializes there, and
// every folding driver can place it. Static data stands only at a static
// hold; a small big at any.
mlir::Attribute held(mlir::Attribute constant, mlir::Type type);

// Whether a comparison whose predicate is the case `predicate` of the
// dialect's CmpPredicate holds of an order: negative, zero or positive.
mlir::Attribute ordered(mlir::MLIRContext *ctx, unsigned predicate, int32_t order);

// An op whose fold has a condition beyond its guards and its kinds: the
// size of the constant it would make, or a precondition its type does not
// carry. Its specification declares the hook; its unit defines it.
template <class Op>
concept HasFoldCondition = requires(llvm::ArrayRef<mlir::Attribute> constants) {
  { Op::foldable(constants) } -> std::same_as<bool>;
};

// An op that guards its own operands (the trait GuardedOp), whose fold
// asks the guards first.
template <class Op>
concept GuardedFold = requires(typename Op::FoldAdaptor adaptor) {
  { Op::guardHolds(adaptor) } -> std::convertible_to<bool>;
};

// Whether every kind of a row has a constant form: no buffer and no
// pointer, which no constant is, no truth, which no op of the runtime
// takes, and a result that gives a value.
constexpr bool constantKinds(std::span<const runtime::OperandKind> operands,
                             runtime::ResultKind result) {
  for (runtime::OperandKind kind : operands)
    if (kind == runtime::OperandKind::Buffer || kind == runtime::OperandKind::Pointer ||
        kind == runtime::OperandKind::Bool)
      return false;
  return result != runtime::ResultKind::Void && result != runtime::ResultKind::NoReturn &&
         result != runtime::ResultKind::Pointer;
}

template <class Op>
concept FoldsByRuntime = requires {
  runtime::Abi<Op>::function;
  runtime::Abi<Op>::operands;
} && constantKinds(runtime::Abi<Op>::operands, runtime::Abi<Op>::entry.result);

// The constant operand as the C value of `Kind`.
template <runtime::OperandKind Kind>
auto operandOf(Scope &scope, mlir::Attribute constant) {
  using enum runtime::OperandKind;
  if constexpr (Kind == Str)
    return strOf(scope, constant);
  else if constexpr (Kind == Big)
    return bigOf(scope, constant);
  else if constexpr (Kind == Int32)
    return int32Of(constant);
  else if constexpr (Kind == Int64)
    return int64Of(constant);
  else if constexpr (Kind == Signed)
    return signedOf(constant);
  else if constexpr (Kind == Unsigned)
    return unsignedOf(constant);
  else
    return doubleOf(constant);
}

template <class ConcreteOp>
class RuntimeFolds : public mlir::OpTrait::TraitBase<ConcreteOp, RuntimeFolds> {
public:
  // The op's runtime function of its constant operands; nothing where one is
  // no constant, a guard refuses them, or the op's own condition does.
  static mlir::OpFoldResult foldTrait(mlir::Operation *op,
                                      llvm::ArrayRef<mlir::Attribute> operands) {
    static_assert(FoldsByRuntime<ConcreteOp>, "RuntimeFolds on an op with no constant form");
    using Row = runtime::Abi<ConcreteOp>;
    if constexpr (GuardedFold<ConcreteOp>)
      if (!ConcreteOp::guardHolds(
              typename ConcreteOp::FoldAdaptor(operands, llvm::cast<ConcreteOp>(op))))
        return {};
    if constexpr (HasFoldCondition<ConcreteOp>)
      if (!ConcreteOp::foldable(operands))
        return {};
    Scope scope(op->getContext());
    return [&]<std::size_t... I>(std::index_sequence<I...>) -> mlir::OpFoldResult {
      auto args = std::make_tuple(operandOf<Row::operands[I]>(scope, operands[I])...);
      if (!(std::get<I>(args) && ...))
        return {};
      return result(scope, op, Row::function(*std::get<I>(args)...));
    }(std::make_index_sequence<std::size(Row::operands)>());
  }

private:
  // The runtime's result as the constant its row's result kind says.
  template <class C>
  static mlir::Attribute result(Scope &scope, mlir::Operation *op, C value) {
    using enum runtime::ResultKind;
    constexpr runtime::ResultKind kind = runtime::Abi<ConcreteOp>::entry.result;
    mlir::Type type = op->getResult(0).getType();
    if constexpr (kind == Str)
      return held(strAttr(scope, value), type);
    else if constexpr (kind == Big)
      return held(bigAttr(scope, value), type);
    else if constexpr (kind == Int32 || kind == Int64)
      return intAttr(type, value);
    else if constexpr (kind == Wrapped)
      return wrapped(type, value);
    else if constexpr (kind == Order)
      return ordered(op->getContext(),
                     static_cast<unsigned>(llvm::cast<ConcreteOp>(op).getPredicate()), value);
    else if constexpr (kind == Double)
      return doubleAttr(type, value);
    else
      return boolAttr(op->getContext(), value);
  }
};

//===----------------------------------------------------------------------===//
// Constants of constructors, closures and lists
//===----------------------------------------------------------------------===//

// Whether a constant constructor, closure or suspension holds `value` in a
// field or capture of `type`: a word or a Double of exactly its type, or a
// value idr.constant holds at it. The one leaf rule of a constant's parts,
// which idr.constant's verifier and the folders of the constructions ask.
bool buildable(mlir::Attribute value, mlir::Type type);

// The string a constant list of characters packs to, or a constant list of
// strings concatenates to, as the runtime builds it; null for any other
// constant.
mlir::Attribute stringOfList(mlir::MLIRContext *context, mlir::Attribute list);

} // namespace idr::fold

#endif // IDR_IR_FOLD_H
