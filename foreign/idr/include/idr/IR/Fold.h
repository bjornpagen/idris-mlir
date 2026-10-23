// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one fold of every op whose meaning is a runtime function, written
// once over where its constants live: its constant operands read as the
// runtime's values by the kind its function takes each in, the function
// itself called (idris-mlir links the runtime natively, so a primitive has
// one implementation, at compile time and at run time), and the result made
// a constant again by the kind it gives. Which function an op calls, and
// the kinds, are its row of the generated runtime ABI (Abi<Op>), read here
// and by the lowering, so a fold and a call disagree only if one row is
// read two ways.
//
// A constant lives in one of two places, a domain the fold is instantiated
// over as the numeric template is over words and intervals (the concept
// Where): an attribute, for MLIR's own fold, which the trait `RuntimeFolds`
// supplies (the specification attaches it to each op whose meaning is
// `Runtime` and whose row has a constant form for every kind, so an IO op
// or a buffer op cannot carry it); and a value of the e-graph's own, which
// computes a constant and makes no attribute (Transforms/EGraph). A domain
// says only how it reads each kind of constant and how it makes one; the
// row, the call and the reading of an integer by its kind are this
// header's, once.
//
// A guarded op folds only where its guards hold on its constants: past a
// refuted guard the program has crashed. An op the runtime's function would
// make too large a constant for, or whose function has a precondition the
// op's type does not carry, declares `foldable` (a member hook of its
// specification), which the fold asks first. A domain asks those of what
// it holds. A Double the function gives as a NaN is no constant: its sign
// and payload are each machine's, which IEEE leaves open.
//
// Besides: what a constant constructor or closure holds in a field or
// capture (`buildable`), the string a constant list packs or concatenates
// to (the folds of str.pack and str.concat), and where idr.constant holds
// static data.
#ifndef IDR_IR_FOLD_H
#define IDR_IR_FOLD_H

// The grades and the dialect's enums: where static data stands, and a
// comparison's predicate.
#include "idr/IR/Grades.h"

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
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

#include <cassert>
#include <cmath>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <optional>
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

// A constant held as an attribute, read as what it is: an integer, a
// Double (an f64's), or the runtime's string or big, a reference the scope
// keeps; nothing where the attribute is no constant of that kind.
std::optional<llvm::APInt> integerOf(mlir::Attribute constant);
std::optional<double> realOf(mlir::Attribute constant);
std::optional<const idris_rt_str *> strOf(Scope &scope, mlir::Attribute constant);
std::optional<idris_rt_big> bigOf(Scope &scope, mlir::Attribute constant);

// The attribute a runtime string or big is, the reference borrowed: a
// string's bytes, and a big's decimal text as big.show's function writes it.
mlir::Attribute strAttr(mlir::MLIRContext *context, const idris_rt_str *s);
mlir::Attribute bigAttr(mlir::MLIRContext *context, idris_rt_big b);

// An integer the runtime gives, wrapped modulo 2^64 to the width of the
// integer type `type`: the result of every integer kind.
llvm::APInt wrappedTo(mlir::Type type, int64_t value);
// The same as a constant of `type`.
mlir::Attribute wrapped(mlir::Type type, int64_t value);

// Whether a comparison whose predicate is `predicate` holds of an order:
// negative, zero or positive.
bool orderHolds(CmpPredicate predicate, int32_t order);
// The same as the truth constant, the predicate by its case number.
mlir::Attribute ordered(mlir::MLIRContext *ctx, unsigned predicate, int32_t order);

// The constant where idr.constant holds it at `type`, else null: what a
// fold of a string, a big or a constant of ours gives at its result's
// type, so a fold gives only what its dialect materializes there, and
// every folding driver can place it. Static data stands only at a static
// hold; a small big at any.
mlir::Attribute held(mlir::Attribute constant, mlir::Type type);

// Where a constant of idr.constant's lives at run time: in a cell, static
// data, as a string and a big past the small range do; or in its word, as a
// small big does, which has no cell for a count to write.
enum class Storage : std::uint8_t { Cell, Word };

// Whether idr.constant may stand at `type` for a constant stored so: a
// value used any number of times, at no hold or a static one, or, in its
// word, at any hold. The grade's half of what idr.constant holds, which a
// constant the e-graph computes asks without an attribute.
bool constantStandsAt(mlir::Type type, Storage storage);

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

// Where a constant lives: how each kind of constant is read from where it
// lives (Operand), and made there (Result). A string or a big read stays
// valid until the fold ends; one made is the runtime's owned reference,
// which the domain takes.
template <class W>
concept Where = requires(W &where, const typename W::Operand &constant, mlir::Type type,
                         const llvm::APInt &integer, double real, const idris_rt_str *str,
                         idris_rt_big big) {
  { where.integerOf(constant) } -> std::same_as<std::optional<llvm::APInt>>;
  { where.realOf(constant) } -> std::same_as<std::optional<double>>;
  { where.strOf(constant) } -> std::same_as<std::optional<const idris_rt_str *>>;
  { where.bigOf(constant) } -> std::same_as<std::optional<idris_rt_big>>;
  { where.integer(type, integer) } -> std::same_as<std::optional<typename W::Result>>;
  { where.real(type, real) } -> std::same_as<std::optional<typename W::Result>>;
  { where.str(type, str) } -> std::same_as<std::optional<typename W::Result>>;
  { where.big(type, big) } -> std::same_as<std::optional<typename W::Result>>;
};

// The attribute instance, MLIR's own fold: a constant is an attribute, read
// where an op holds it, and made at the op's result, a string or a big only
// where idr.constant holds it there. Its guards and conditions are the
// op's own, asked of the attributes.
class InAttributes {
public:
  using Operand = mlir::Attribute;
  using Result = mlir::Attribute;

  explicit InAttributes(mlir::MLIRContext *context) : scope(context) {}

  std::optional<llvm::APInt> integerOf(mlir::Attribute constant) const {
    return fold::integerOf(constant);
  }
  std::optional<double> realOf(mlir::Attribute constant) const { return fold::realOf(constant); }
  std::optional<const idris_rt_str *> strOf(mlir::Attribute constant) {
    return fold::strOf(scope, constant);
  }
  std::optional<idris_rt_big> bigOf(mlir::Attribute constant) {
    return fold::bigOf(scope, constant);
  }

  std::optional<mlir::Attribute> integer(mlir::Type type, const llvm::APInt &value) const;
  std::optional<mlir::Attribute> real(mlir::Type type, double value) const;
  std::optional<mlir::Attribute> str(mlir::Type type, const idris_rt_str *made);
  std::optional<mlir::Attribute> big(mlir::Type type, idris_rt_big made);

  template <class Op>
  bool admits(llvm::ArrayRef<mlir::Attribute> constants,
              const typename Op::Properties &properties) const {
    if constexpr (GuardedFold<Op>)
      if (!Op::guardHolds(typename Op::FoldAdaptor(constants, mlir::DictionaryAttr(), properties)))
        return false;
    if constexpr (HasFoldCondition<Op>)
      if (!Op::foldable(constants))
        return false;
    return true;
  }

private:
  Scope scope;
};
static_assert(Where<InAttributes>, "an attribute is a place a constant lives");

// The constant operand as the C value of the kind its function takes it
// in: one overload per kind that has a constant form, so these overloads
// are the one statement of which kinds do, and a kind with none is never
// read as another's. An integer is read at its width, extended to the
// kind's with its sign or with zeros. No overload: a buffer and a pointer,
// which no constant is; a truth, which no op of the runtime takes; a byte,
// which only io.exit takes, an exit status its lowering narrows the op's
// i64 to past the test that ends a status outside 0 to 255 as a crash, so
// no constant of the op's operand is the runtime's byte.
template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Str)
std::optional<const idris_rt_str *> operandOf(W &where, const typename W::Operand &constant) {
  return where.strOf(constant);
}

template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Big)
std::optional<idris_rt_big> operandOf(W &where, const typename W::Operand &constant) {
  return where.bigOf(constant);
}

template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Int32)
std::optional<int32_t> operandOf(W &where, const typename W::Operand &constant) {
  return where.integerOf(constant).transform(
      [](const llvm::APInt &value) { return static_cast<int32_t>(value.getSExtValue()); });
}

template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Int64 || Kind == runtime::OperandKind::Signed)
std::optional<int64_t> operandOf(W &where, const typename W::Operand &constant) {
  return where.integerOf(constant).transform(
      [](const llvm::APInt &value) { return value.getSExtValue(); });
}

template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Unsigned)
std::optional<uint64_t> operandOf(W &where, const typename W::Operand &constant) {
  return where.integerOf(constant).transform(
      [](const llvm::APInt &value) { return value.getZExtValue(); });
}

template <runtime::OperandKind Kind, Where W>
  requires(Kind == runtime::OperandKind::Double)
std::optional<double> operandOf(W &where, const typename W::Operand &constant) {
  return where.realOf(constant);
}

// A kind a constant operand can be read as: one `operandOf` reads.
template <runtime::OperandKind Kind>
concept ConstantOperand = requires(InAttributes &where, mlir::Attribute constant) {
  operandOf<Kind>(where, constant);
};

// Whether a row has a constant form: every operand's kind one a constant
// is read as, and a result that gives a value, which nothing (a function
// that returns none, or never returns) and a pointer do not.
template <class Row, std::size_t... I>
constexpr bool constantRow(std::index_sequence<I...>) {
  using enum runtime::ResultKind;
  constexpr runtime::ResultKind result = Row::entry.result;
  return (ConstantOperand<Row::operands[I]> && ...) && result != Void && result != NoReturn &&
         result != Pointer;
}

template <class Op>
concept FoldsByRuntime = requires {
  runtime::Abi<Op>::function;
  runtime::Abi<Op>::operands;
  runtime::Abi<Op>::entry;
} && constantRow<runtime::Abi<Op>>(std::make_index_sequence<std::size(runtime::Abi<Op>::operands)>());

// The runtime's result as the constant its row's result kind says, made
// where `where` keeps constants. A comparison's verdict is its predicate,
// one of the op's properties, on the order the function gives.
template <class Op, Where W, class C>
std::optional<typename W::Result> resultOf(W &where, mlir::Type type,
                                           const typename Op::Properties &properties, C value) {
  using enum runtime::ResultKind;
  constexpr runtime::ResultKind kind = runtime::Abi<Op>::entry.result;
  if constexpr (kind == Str)
    return where.str(type, value);
  else if constexpr (kind == Big)
    return where.big(type, value);
  else if constexpr (kind == Int32 || kind == Int64 || kind == Wrapped)
    return where.integer(type, wrappedTo(type, value));
  else if constexpr (kind == Order)
    return where.integer(type, llvm::APInt(1, orderHolds(properties.getPredicate(), value)));
  else if constexpr (kind == Double) {
    if (std::isnan(value))
      return std::nullopt;
    return where.real(type, value);
  } else {
    static_assert(kind == Bool, "a constant row gives a value");
    return where.integer(type, llvm::APInt(1, value));
  }
}

// The op's runtime function of its constant operands, where `where` keeps
// them: none where one is no constant of its kind, or where the op's guards
// or its own condition do not admit them as `where` knows them. `type` is
// the op's result type; `properties` are the op's, or the defaults of its
// class where no op stands.
template <class Op, Where W>
  requires FoldsByRuntime<Op>
std::optional<typename W::Result> evaluate(W &where,
                                           llvm::ArrayRef<typename W::Operand> operands,
                                           mlir::Type type,
                                           const typename Op::Properties &properties) {
  using Row = runtime::Abi<Op>;
  assert(operands.size() == std::size(Row::operands) && "an op takes its row's operands");
  if (!where.template admits<Op>(operands, properties))
    return std::nullopt;
  return [&]<std::size_t... I>(std::index_sequence<I...>) -> std::optional<typename W::Result> {
    auto args = std::make_tuple(operandOf<Row::operands[I]>(where, operands[I])...);
    if (!(std::get<I>(args) && ...))
      return std::nullopt;
    return resultOf<Op>(where, type, properties, Row::function(*std::get<I>(args)...));
  }(std::make_index_sequence<std::size(Row::operands)>());
}

template <class ConcreteOp>
class RuntimeFolds : public mlir::OpTrait::TraitBase<ConcreteOp, RuntimeFolds> {
public:
  // The one fold's attribute instance: the op's runtime function of its
  // constant operands, as MLIR's folding drivers ask it.
  static mlir::OpFoldResult foldTrait(mlir::Operation *op,
                                      llvm::ArrayRef<mlir::Attribute> operands) {
    static_assert(FoldsByRuntime<ConcreteOp>, "RuntimeFolds on an op with no constant form");
    InAttributes where(op->getContext());
    std::optional<mlir::Attribute> folded =
        evaluate<ConcreteOp>(where, operands, op->getResult(0).getType(),
                             llvm::cast<ConcreteOp>(op).getProperties());
    return folded ? mlir::OpFoldResult(*folded) : mlir::OpFoldResult();
  }
};

// An op whose meaning is its runtime function, by its trait: one the
// e-graph computes over values of its own.
template <class Op>
concept Folds = requires { requires Op::template hasTrait<RuntimeFolds>(); };

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
