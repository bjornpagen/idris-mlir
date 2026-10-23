// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The e-graph's own values and the one fold's value instance over them.
//
// A constant the graph knows is a value of its own until the write-back
// places it: an integer, the one value of its class's interval; a Double,
// by its bits; and a string or a big past the small range as the runtime
// holds it, one reference of the graph's own. A big in the small range the
// runtime holds in its word, so it is an integer, as the runtime's
// representation says. An op whose meaning is a runtime function computes
// over these through the one fold (IR/Fold.h), the same row, call and
// reading of integers as the op's MLIR fold, which is its attribute
// instance; so a constant is computed once, by the runtime's own function,
// and no attribute is made until the write-back places one, here too.
//
// What the graph knows of a guard is what its classes' intervals say: the
// guard's own decision over them, which the skeleton rule asks too. An op
// whose fold has a condition beyond its guards states it over attributes
// (its `foldable` hook), so the graph does not compute it.

#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Fold.h"
#include "idr/IR/Ranges.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/APFloat.h"
#include "llvm/Support/ErrorHandling.h"

#include <array>
#include <cstdint>
#include <tuple>

using namespace mlir;

namespace idr::egraph::detail {

//===----------------------------------------------------------------------===//
// The values
//===----------------------------------------------------------------------===//

// A string's bytes never change; its count, in its header, is the one word
// a reference writes.
Text Text::share(const idris_rt_str *s) {
  idris_rt_inc_cell(&const_cast<idris_rt_str *>(s)->header);
  return Text(s);
}

Text::~Text() {
  if (s)
    idris_rt_dec_cell(&const_cast<idris_rt_str *>(s)->header);
}

llvm::StringRef Text::bytes() const { return llvm::StringRef(idris_rt_str_bytes(s), s->bytes); }

Big Big::share(idris_rt_big b) {
  idris_rt_inc_big(b);
  return Big(b);
}

Big::~Big() { idris_rt_dec_big(word); }

bool operator==(const Big &a, const Big &b) {
  return runtime::Abi<BigCmpOp>::function(a.word, b.word) == 0;
}

// A big's word past the small range is its cell's address.
namespace {
const idris_rt_bignum *cellOf(const Big &big) {
  return reinterpret_cast<const idris_rt_bignum *>(static_cast<std::uintptr_t>(big.get()));
}
} // namespace

// Equal values hash alike: a big by its value modulo 2^64, the runtime's
// own conversion to a word.
llvm::hash_code hash_value(const Constant &constant) {
  return match(
      constant, [](const Text &text) { return llvm::hash_value(text.bytes()); },
      [](const Real &real) { return llvm::hash_value(real.bits); },
      [](const Big &big) {
        return llvm::hash_value(runtime::Abi<BigToIntOp>::function(big.get()));
      });
}

std::uint64_t bytesOf(const Constant &constant) {
  return match(
      constant,
      [](const Text &text) -> std::uint64_t { return sizeof(idris_rt_str) + text.get()->bytes; },
      [](const Real &) -> std::uint64_t { return 0; },
      [](const Big &big) -> std::uint64_t {
        std::int64_t limbs = cellOf(big)->size;
        return sizeof(idris_rt_bignum) +
               static_cast<std::uint64_t>(limbs < 0 ? -limbs : limbs) * IDRIS_RT_WORD_BYTES;
      });
}

// A string and a big past the small range are static data, in a cell.
bool placedAt(const Constant &constant, Type type) {
  return match(
      constant, [&](const Real &) { return type.isF64(); },
      [&](const OneOf<Text, Big> auto &) {
        return fold::constantStandsAt(type, fold::Storage::Cell);
      });
}

namespace {

// A big as the graph knows it: in the small range, the one value of its
// interval, as the runtime holds it in its word; past it, its cell.
Facts factsOfBig(Big big) {
  idris_rt_big word = big.get();
  if (!idris_rt_word_is_small(word))
    return {std::nullopt, std::move(big)};
  std::int64_t value = idris_rt_small_value(word);
  return {ranges::rangeOf(ranges::bounded(value, value)), std::nullopt};
}

// The interval a guard reads of an operand: its class's, or every value of
// its type, of no width where it holds no integer.
ConstantIntRanges guardRange(const Class &cls) {
  if (cls.facts.range)
    return *cls.facts.range;
  unsigned width = ConstantIntRanges::getStorageBitwidth(cls.type);
  if (width == 0)
    return ConstantIntRanges::constant(APInt::getZero(0));
  return ConstantIntRanges::maxRange(width);
}

//===----------------------------------------------------------------------===//
// The value instance
//===----------------------------------------------------------------------===//

// The one fold where a constant is what a class's facts say: read from an
// operand's root class, and made as the facts the computing node says.
// Nothing it reads is copied, and what the runtime makes is the graph's.
class InGraph {
public:
  using Operand = const Class *;
  using Result = Facts;

  std::optional<APInt> integerOf(const Class *cls) const { return cls->facts.integer(); }

  std::optional<double> realOf(const Class *cls) const {
    if (!cls->facts.constant)
      return std::nullopt;
    return match(
        *cls->facts.constant,
        [](const Real &real) -> std::optional<double> { return real.value(); },
        [](const OneOf<Text, Big> auto &) -> std::optional<double> { return std::nullopt; });
  }

  std::optional<const idris_rt_str *> strOf(const Class *cls) const {
    if (!cls->facts.constant)
      return std::nullopt;
    return match(
        *cls->facts.constant,
        [](const Text &text) -> std::optional<const idris_rt_str *> { return text.get(); },
        [](const OneOf<Real, Big> auto &) -> std::optional<const idris_rt_str *> {
          return std::nullopt;
        });
  }

  // A big in the small range is its interval's one value, which the
  // runtime's word for it holds, with no cell to keep.
  std::optional<idris_rt_big> bigOf(const Class *cls) const {
    if (cls->facts.constant)
      return match(
          *cls->facts.constant,
          [](const Big &big) -> std::optional<idris_rt_big> { return big.get(); },
          [](const OneOf<Text, Real> auto &) -> std::optional<idris_rt_big> {
            return std::nullopt;
          });
    if (!cls->facts.range)
      return std::nullopt;
    ranges::Bounds bounds = ranges::boundsOf(*cls->facts.range);
    if (!bounds.lo || !bounds.hi || *bounds.lo != *bounds.hi)
      return std::nullopt;
    return runtime::Abi<BigSmallOp>::function(*bounds.lo);
  }

  std::optional<Facts> integer(Type, const APInt &value) const {
    return Facts{ConstantIntRanges::constant(value), std::nullopt};
  }
  std::optional<Facts> real(Type, double value) const {
    return Facts{std::nullopt, Real{std::bit_cast<std::uint64_t>(value)}};
  }
  std::optional<Facts> str(Type, const idris_rt_str *made) const {
    return Facts{std::nullopt, Text::adopt(made)};
  }
  std::optional<Facts> big(Type, idris_rt_big made) const { return factsOfBig(Big::adopt(made)); }

  // Each guard decides on its operands' intervals, as the skeleton rule
  // asks it: the op computes only where every one holds.
  template <class Op>
  bool admits(llvm::ArrayRef<const Class *> operands, const typename Op::Properties &) const {
    if constexpr (fold::HasFoldCondition<Op>)
      return false;
    else if constexpr (fold::GuardedFold<Op>)
      return std::apply([&](auto... guards) { return (holds(guards, operands) && ...); },
                        typename Guarded<Op>::Guards{});
    else
      return true;
  }

private:
  template <class G, unsigned... Given>
  static bool holds(Guard<G, Given...>, llvm::ArrayRef<const Class *> operands) {
    std::array<ConstantIntRanges, sizeof...(Given)> ranges{guardRange(*operands[Given])...};
    std::array<Attribute, sizeof...(Given)> constants{};
    return G::decide(ranges, constants) == numeric::Known::Holds;
  }
};

static_assert(fold::Where<InGraph>, "the graph's values are a place a constant lives");

template <class Op>
std::optional<Facts> meaningOf(llvm::ArrayRef<const Class *> operands, Type type,
                               const typename Op::Properties &properties) {
  InGraph where;
  return fold::evaluate<Op>(where, operands, type, properties);
}

template <class Op>
std::optional<Facts> ofInput(Operation *op, Type type, llvm::ArrayRef<const Class *> operands) {
  return meaningOf<Op>(operands, type, cast<Op>(op).getProperties());
}

template <class Op>
std::optional<Facts> ofBuilt(Type type, llvm::ArrayRef<const Class *> operands) {
  return meaningOf<Op>(operands, type, typename Op::Properties{});
}

template <class... Ops>
std::vector<std::pair<TypeID, Meaning>> meaningsOf() {
  std::vector<std::pair<TypeID, Meaning>> out;
  (
      [&] {
        if constexpr (fold::Folds<Ops>)
          out.emplace_back(TypeID::get<Ops>(), Meaning{&ofInput<Ops>, &ofBuilt<Ops>});
      }(),
      ...);
  return out;
}

} // namespace

// A dialect materializes what it folds to (MLIR's folding contract), and the
// graph makes a constant only where its op stands, so a constant class
// always has its op.
Value materialized(Dialect &dialect, RewriterBase &rewriter, Location loc, Type type,
                   Attribute value) {
  Operation *op = dialect.materializeConstant(rewriter, value, type, loc);
  if (!op)
    llvm::reportFatalInternalError("idr-simplify: a constant its dialect does not materialize "
                                   "at its type");
  return op->getResult(0);
}

std::vector<std::pair<TypeID, Meaning>> runtimeMeanings() {
  return meaningsOf<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >();
}

// A constant an op holds is read by the attribute instance's readers and
// kept as the graph's: a string or a big, a reference of the graph's own
// beside the scope's, which the scope releases.
Facts heldFacts(Attribute value) {
  if (std::optional<APInt> integer = fold::integerOf(value))
    return {ConstantIntRanges::constant(*integer), std::nullopt};
  if (std::optional<double> real = fold::realOf(value))
    return {std::nullopt, Real{std::bit_cast<std::uint64_t>(*real)}};
  fold::Scope scope(value.getContext());
  if (std::optional<const idris_rt_str *> str = fold::strOf(scope, value))
    return {std::nullopt, Text::share(*str)};
  if (std::optional<idris_rt_big> big = fold::bigOf(scope, value))
    return factsOfBig(Big::share(*big));
  return {};
}

//===----------------------------------------------------------------------===//
// The write-back
//===----------------------------------------------------------------------===//

// A word and a splat are arith's constants; a small big is idr.constant's,
// which stands at any hold.
Value writeBack(RewriterBase &rewriter, Location loc, Type type, const node::Integer &integer,
                Dialect &constants) {
  TypedAttr value;
  switch (integer.form) {
  case IntegerForm::Word:
    value = IntegerAttr::get(type, integer.value);
    break;
  case IntegerForm::Splat:
    value = DenseIntElementsAttr::get(cast<ShapedType>(type), integer.value);
    break;
  case IntegerForm::Small:
    return materialized(constants, rewriter, loc, type,
                        BigAttr::get(rewriter.getContext(), integer.value));
  }
  return arith::ConstantOp::create(rewriter, loc, type, value).getResult();
}

// A Double is arith's constant of its bits; a string's and a big's
// attributes are the ones the runtime's results make in the one fold.
Value writeBack(RewriterBase &rewriter, Location loc, Type type, const node::Known &known,
                Dialect &constants) {
  MLIRContext *context = rewriter.getContext();
  return match(
      known.value,
      [&](const Real &real) -> Value {
        APFloat bits(APFloat::IEEEdouble(), APInt(64, real.bits));
        TypedAttr value = FloatAttr::get(type, bits);
        return arith::ConstantOp::create(rewriter, loc, type, value).getResult();
      },
      [&](const Text &text) -> Value {
        return materialized(constants, rewriter, loc, type, fold::strAttr(context, text.get()));
      },
      [&](const Big &big) -> Value {
        return materialized(constants, rewriter, loc, type, fold::bigAttr(context, big.get()));
      });
}

} // namespace idr::egraph::detail
