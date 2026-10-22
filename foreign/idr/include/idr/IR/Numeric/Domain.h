// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op of inline arithmetic is written over: a numeric domain, a
// concept, of which each meaning in Inline.h is one function. The same
// function, instantiated over a domain of fixed-width words, is the op's
// folder and the static_asserts that pin its edge cases; over intervals, the
// op's integer ranges; over an IR builder, its expansion into arith; over the
// runtime's small Integers, the runtime's own path. So the meaning is written
// once and every reader computes it, never a copy kept in step.
//
// Two rules keep one meaning right in every domain, each a type here rather
// than a convention a template could forget:
// - A truth of the domain is no bool. An IR builder's truth is an i1 value,
//   and an mlir::Value converts to bool (null or not): a template that
//   branched on a truth would compile over that domain and lower
//   `idr.int.divs -7, 2` to -3. Truths are combined and selected on, never
//   branched on, so `Truth` must not be constructible as a bool.
// - A partial operation takes evidence only the meaning mints. Truncating
//   division takes a SafeDivisor, which only `divisible` makes, and a shift
//   takes a BelowWidth, which only `belowWidth` makes; so no instantiation
//   can build arith.divsi at MIN / -1 or a shift by the width, both poison in
//   arith, whatever the template's author meant.
//
// Freestanding: no MLIR, no LLVM, so the runtime includes it as the compiler
// does. The domains that need MLIR are in Ranges.h and Arith.h.
#ifndef IDR_IR_NUMERIC_DOMAIN_H
#define IDR_IR_NUMERIC_DOMAIN_H

// The vocabulary the specification states for its inline ops: Signedness,
// Direction, Part and Law, printed as plain enums from Spec.Ops.Numeric.
#include "idr/IR/Generated/NumericEnums.h.inc"

#include <concepts>
#include <cstdint>

namespace idr::numeric {

// How a domain meets the one quotient its width cannot hold, the least
// signed value over -1: a fixed width wraps it to the least value again, as
// Idris's IntN does; a domain wider than its values (the runtime's 63-bit
// smalls in 64-bit words) holds it exactly, and needs no case for it.
enum class Overflow : unsigned char { Wraps, Cannot };

template <class D>
class SafeDivisor;
template <class D>
class BelowWidth;

// The operations Euclidean division needs: constants of an operand's width,
// sum and difference, truncating division by a safe divisor, equality and
// signed order, and their truths combined and selected on.
template <class D>
concept Arithmetic =
    std::copy_constructible<typename D::Value> && std::copy_constructible<typename D::Truth> &&
    !std::constructible_from<bool, typename D::Truth> &&
    requires(const D &d, typename D::Value a, typename D::Value b, typename D::Truth t,
             typename D::Truth u, const SafeDivisor<D> &s, std::int64_t c) {
      { D::overflow } -> std::convertible_to<Overflow>;
      { d.constant(c, a) } -> std::same_as<typename D::Value>;
      { d.add(a, b) } -> std::same_as<typename D::Value>;
      { d.sub(a, b) } -> std::same_as<typename D::Value>;
      { d.quotientTowardZero(a, s) } -> std::same_as<typename D::Value>;
      { d.remainderTowardZero(a, s) } -> std::same_as<typename D::Value>;
      { d.equal(a, b) } -> std::same_as<typename D::Truth>;
      { d.lessSigned(a, b) } -> std::same_as<typename D::Truth>;
      { d.both(t, u) } -> std::same_as<typename D::Truth>;
      { d.select(t, a, b) } -> std::same_as<typename D::Value>;
    } &&
    // A domain that wraps names its least signed value, the one dividend
    // whose quotient by -1 it cannot hold.
    (D::overflow != Overflow::Wraps || requires(const D &d, typename D::Value a) {
      { d.least(a) } -> std::same_as<typename D::Value>;
    });

// What the shifts and the char conversions need besides: a width, the bit
// operations, unsigned order, widening and narrowing, and every truth.
template <class D>
concept Bitwise =
    Arithmetic<D> &&
    requires(const D &d, typename D::Value a, typename D::Value b, typename D::Truth t,
             typename D::Truth u, const BelowWidth<D> &n, unsigned w) {
      { d.width(a) } -> std::same_as<unsigned>;
      { d.bitAnd(a, b) } -> std::same_as<typename D::Value>;
      { d.lessUnsigned(a, b) } -> std::same_as<typename D::Truth>;
      { d.shiftLeft(a, n) } -> std::same_as<typename D::Value>;
      { d.shiftRightArithmetic(a, n) } -> std::same_as<typename D::Value>;
      { d.shiftRightLogical(a, n) } -> std::same_as<typename D::Value>;
      { d.extendSigned(a, w) } -> std::same_as<typename D::Value>;
      { d.extendUnsigned(a, w) } -> std::same_as<typename D::Value>;
      { d.truncate(a, w) } -> std::same_as<typename D::Value>;
      { d.either(t, u) } -> std::same_as<typename D::Truth>;
      { d.negation(t) } -> std::same_as<typename D::Truth>;
    };

// A domain every inline op is written over.
template <class D>
concept Domain = Bitwise<D>;

template <Arithmetic D>
constexpr SafeDivisor<D> divisible(const D &d, typename D::Value dividend,
                                   typename D::Value divisor);
template <Bitwise D>
constexpr BelowWidth<D> belowWidth(const D &d, typename D::Value amount);

// A divisor truncating division may take at its dividend: not -1 where the
// dividend is the least signed value of a width that wraps. Not zero either,
// which no evidence states: an op that divides is guarded by
// idr.check.nonzero, and its meaning is asked only past the guard.
template <class D>
class SafeDivisor {
public:
  constexpr const typename D::Value &value() const { return divisor; }

private:
  constexpr explicit SafeDivisor(typename D::Value v) : divisor(v) {}
  typename D::Value divisor;

  template <Arithmetic E>
  friend constexpr SafeDivisor<E> divisible(const E &, typename E::Value, typename E::Value);
};

// A shift amount below the width of the value it shifts.
template <class D>
class BelowWidth {
public:
  constexpr const typename D::Value &value() const { return amount; }

private:
  constexpr explicit BelowWidth(typename D::Value v) : amount(v) {}
  typename D::Value amount;

  template <Bitwise E>
  friend constexpr BelowWidth<E> belowWidth(const E &, typename E::Value);
};

// The divisor itself, or 1 where the dividend is the least value and the
// divisor -1 in a domain that wraps: dividing by 1 gives the least value and
// remainder 0, exactly the wrapped Euclidean pair. A domain that cannot
// overflow divides by the divisor as it is.
template <Arithmetic D>
constexpr SafeDivisor<D> divisible(const D &d, typename D::Value dividend,
                                   typename D::Value divisor) {
  if constexpr (D::overflow == Overflow::Wraps) {
    auto overflows = d.both(d.equal(dividend, d.least(dividend)),
                            d.equal(divisor, d.constant(-1, divisor)));
    return SafeDivisor<D>(d.select(overflows, d.constant(1, divisor), divisor));
  } else {
    return SafeDivisor<D>(divisor);
  }
}

// The amount masked to the width less one, which is below the width for
// every width a power of two (the integers Idris has: 8, 16, 32, 64): where
// the amount itself is at or past the width, a meaning selects the fill
// instead, so the masked shift's value is never the one taken.
template <Bitwise D>
constexpr BelowWidth<D> belowWidth(const D &d, typename D::Value amount) {
  return BelowWidth<D>(d.bitAnd(amount, d.constant(d.width(amount) - 1, amount)));
}

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_DOMAIN_H
