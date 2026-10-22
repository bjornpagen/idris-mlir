// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the interval instance of the inline meanings
// (idr::numeric::Intervals), which every inline op's integer ranges and the
// e-graph's interval analysis are: each meaning over intervals holds the
// same meaning over words of every member, the words' instance being the
// folder, whose edge cases are checked when the compiler is built. The
// meanings are every one the dialect's ops have, as the specification
// lists them, a guard's condition among them; each is asked of every tuple
// of members of a case's operands (IntervalCases.cpp): its value over words
// is a member of its value over intervals, and a truth the intervals decide
// is the truth of every tuple. A tuple an op's guard refuses is asked of
// nothing. The judgement is shown failing on each instance planted with a
// fault.

#include "idr/IR/Numeric/Domain.h"
#include "idr/IR/Numeric/Inline.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/Numeric/Word.h"
#include "idr/Testing/Box.h"
#include "idr/Testing/IntervalCases.h"

#include "idr/IR/Generated/InlineMeanings.h.inc"

#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"
#include "llvm/ADT/APInt.h"
#include "llvm/Support/TypeName.h"
#include "llvm/Support/raw_ostream.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>

namespace {

namespace numeric = idr::numeric;
using idr::box::member;
using idr::box::intervals::Case;
using llvm::APInt;
using mlir::ConstantIntRanges;
using numeric::Known;
using numeric::KnownTruth;
using numeric::Word;
using numeric::Words;

// The number of seeds a case is drawn from.
constexpr std::uint64_t seeds = 400;

// The most operands a meaning of `Each` takes.
template <class Each>
constexpr unsigned widest = 0;
template <class... F>
constexpr unsigned widest<std::tuple<F...>> = std::max({0u, F::arity...});

// The operands a case draws: as many as the meaning that takes the most.
constexpr unsigned operands = widest<numeric::Meanings>;

//===----------------------------------------------------------------------===//
// The judgement
//===----------------------------------------------------------------------===//

// What an op's guard makes of the tuple a meaning is asked of.
enum class Guard : std::uint8_t { Holds, Refuses };

// The words' instance as a guarded op meets it. A division by zero is the
// one operation of a meaning that no evidence it takes rules out: an op
// that divides is guarded by idr.check.nonzero instead, and over words the
// division has no value. So it is not made: it marks the tuple as one its
// guard refuses, and which meanings divide is read off the meanings.
class Guarded {
public:
  using Value = Word;
  using Truth = numeric::Bit;
  static constexpr numeric::Overflow overflow = Words::overflow;

  explicit Guarded(Guard &guard) : guard(&guard) {}

  unsigned width(Value a) const { return w.width(a); }
  Value constant(std::int64_t c, Value like) const { return w.constant(c, like); }
  Value least(Value like) const { return w.least(like); }

  Value add(Value a, Value b) const { return w.add(a, b); }
  Value sub(Value a, Value b) const { return w.sub(a, b); }
  Value bitAnd(Value a, Value b) const { return w.bitAnd(a, b); }
  Value quotientTowardZero(Value a, const numeric::SafeDivisor<Guarded> &s) const {
    if (guardOn(s.value()) == Guard::Refuses)
      return a;
    return w.quotientTowardZero(a, numeric::divisible(w, a, s.value()));
  }
  Value remainderTowardZero(Value a, const numeric::SafeDivisor<Guarded> &s) const {
    if (guardOn(s.value()) == Guard::Refuses)
      return a;
    return w.remainderTowardZero(a, numeric::divisible(w, a, s.value()));
  }
  Value shiftLeft(Value a, const numeric::BelowWidth<Guarded> &n) const {
    return w.shiftLeft(a, numeric::belowWidth(w, n.value()));
  }
  Value shiftRightArithmetic(Value a, const numeric::BelowWidth<Guarded> &n) const {
    return w.shiftRightArithmetic(a, numeric::belowWidth(w, n.value()));
  }
  Value shiftRightLogical(Value a, const numeric::BelowWidth<Guarded> &n) const {
    return w.shiftRightLogical(a, numeric::belowWidth(w, n.value()));
  }
  Value extendSigned(Value a, unsigned to) const { return w.extendSigned(a, to); }
  Value extendUnsigned(Value a, unsigned to) const { return w.extendUnsigned(a, to); }
  Value truncate(Value a, unsigned to) const { return w.truncate(a, to); }

  Truth equal(Value a, Value b) const { return w.equal(a, b); }
  Truth lessSigned(Value a, Value b) const { return w.lessSigned(a, b); }
  Truth lessUnsigned(Value a, Value b) const { return w.lessUnsigned(a, b); }
  Truth both(Truth t, Truth u) const { return w.both(t, u); }
  Truth either(Truth t, Truth u) const { return w.either(t, u); }
  Truth negation(Truth t) const { return w.negation(t); }
  Value select(Truth t, Value a, Value b) const { return w.select(t, a, b); }

private:
  // What the guard makes of a divisor: zero it refuses, and marks the tuple.
  Guard guardOn(Value divisor) const {
    if (divisor.bits != 0)
      return Guard::Holds;
    *guard = Guard::Refuses;
    return Guard::Refuses;
  }

  Words w;
  Guard *guard;
};

static_assert(numeric::Domain<Guarded>);

std::string printed(const ConstantIntRanges &range) {
  std::string text;
  llvm::raw_string_ostream os(text);
  os << range;
  return text;
}
std::string printed(KnownTruth truth) {
  constexpr const char *names[] = {"holds", "fails", "unknown"};
  return names[std::to_underlying(truth.known)];
}
std::string printed(Word word) { return std::to_string(Words::signedOf(word)); }
std::string printed(numeric::Bit truth) { return truth.holds ? "holds" : "fails"; }

// Whether the words' answer `concrete` is among what the intervals'
// answer `abstract` allows: a value is a member; a truth the intervals
// decide is the one the words give.
bool allows(KnownTruth abstract, numeric::Bit concrete) {
  return abstract.known == Known::Unknown ||
         (abstract.known == Known::Holds) == concrete.holds;
}
bool allows(const ConstantIntRanges &abstract, Word concrete) {
  return member(abstract, APInt(concrete.width, concrete.bits));
}

// The first tuple of members of `drawn`'s operands its guards let through
// on which meaning `F` over the instance `intervals` does not allow what it
// gives over words, as a line; nothing when there is none. The tuples are
// walked as an odometer, the first operand's member the fastest digit.
template <class F, class D>
std::string disagreement(const D &intervals, const Case &drawn) {
  constexpr std::size_t arity = F::arity;
  auto abstract = [&]<std::size_t... I>(std::index_sequence<I...>) {
    return F::apply(intervals, drawn.operands[I].interval...);
  }(std::make_index_sequence<arity>());
  std::array<std::size_t, arity> at{};
  // One step of the odometer: the digit it stepped, or arity once every
  // digit has rolled over and the walk is back at its first tuple, where it
  // ends.
  auto step = [&] {
    std::size_t digit = 0;
    for (; digit < arity; ++digit) {
      if (++at[digit] < drawn.operands[digit].members.size())
        break;
      at[digit] = 0;
    }
    return digit;
  };
  do {
    auto tuple = [&]<std::size_t... I>(std::index_sequence<I...>) {
      return std::array<Word, arity>{drawn.operands[I].members[at[I]]...};
    }(std::make_index_sequence<arity>());
    Guard guard = Guard::Holds;
    Guarded words(guard);
    auto concrete = [&]<std::size_t... I>(std::index_sequence<I...>) {
      return F::apply(words, tuple[I]...);
    }(std::make_index_sequence<arity>());
    if (guard == Guard::Holds && !allows(abstract, concrete)) {
      std::string line = "\n  " + llvm::getTypeName<F>().str() + " at width " +
                         std::to_string(drawn.width) + " on";
      for (std::size_t i = 0; i < arity; ++i)
        line += (i == 0 ? " " : ", ") + printed(tuple[i]) + " of " +
                printed(drawn.operands[i].interval);
      return line + ": the words give " + printed(concrete) + ", the intervals " +
             printed(abstract);
    }
  } while (step() < arity);
  return {};
}

// What every meaning of `Each`, a tuple of function objects, disagrees on.
template <class D, class... F>
std::string disagreements(const D &intervals, const Case &drawn,
                          std::type_identity<std::tuple<F...>>) {
  return (disagreement<F>(intervals, drawn) + ... + std::string());
}

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The cases, over every seed up to `limit` of them, on which some meaning
// over the instance `intervals` does not allow what it gives over words.
// Each is reported, when `report` says so, with its seed and what it
// disagrees on.
template <class D>
unsigned judge(const D &intervals, unsigned limit, Report report) {
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    Case drawn = idr::box::intervals::caseOf(seed, operands);
    std::string why = disagreements(intervals, drawn, std::type_identity<numeric::Meanings>());
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << ":" << why;
  }
  return failures;
}

TEST(Intervals, EveryMeaningHoldsEveryMember) {
  EXPECT_EQ(judge(numeric::Intervals{}, 10, Report::Each), 0u);
}

//===----------------------------------------------------------------------===//
// The planted faults
//===----------------------------------------------------------------------===//

// A fault planted in one operation of the instance, each a real way to be
// wrong: a select on an unknown truth that keeps one side, a comparison the
// intervals leave undecided taken to hold, a conjunction no side of which
// fails taken to hold, truncating division by the unsigned rule, a signed
// widening that fills with zeros.
enum class Fault : std::uint8_t {
  SelectKeepsOneSide,
  UndecidedHolds,
  ConjunctionHolds,
  UnsignedQuotient,
  ZeroExtends
};

// The interval instance with `F` planted, every other operation its own.
// Evidence a meaning minted for this domain is minted again for the
// instance from the same values, which gives the same interval or a wider
// one, so only the fault can leave a member out.
template <Fault F>
class Planted {
public:
  using Value = ConstantIntRanges;
  using Truth = KnownTruth;
  static constexpr numeric::Overflow overflow = numeric::Intervals::overflow;

  unsigned width(const Value &a) const { return d.width(a); }
  Value constant(std::int64_t c, const Value &like) const { return d.constant(c, like); }
  Value least(const Value &like) const { return d.least(like); }

  Value add(const Value &a, const Value &b) const { return d.add(a, b); }
  Value sub(const Value &a, const Value &b) const { return d.sub(a, b); }
  Value bitAnd(const Value &a, const Value &b) const { return d.bitAnd(a, b); }
  Value quotientTowardZero(const Value &a, const numeric::SafeDivisor<Planted> &s) const {
    if constexpr (F == Fault::UnsignedQuotient)
      return mlir::intrange::inferDivU({a, s.value()});
    else
      return d.quotientTowardZero(a, numeric::divisible(d, a, s.value()));
  }
  Value remainderTowardZero(const Value &a, const numeric::SafeDivisor<Planted> &s) const {
    return d.remainderTowardZero(a, numeric::divisible(d, a, s.value()));
  }
  Value shiftLeft(const Value &a, const numeric::BelowWidth<Planted> &n) const {
    return d.shiftLeft(a, numeric::belowWidth(d, n.value()));
  }
  Value shiftRightArithmetic(const Value &a, const numeric::BelowWidth<Planted> &n) const {
    return d.shiftRightArithmetic(a, numeric::belowWidth(d, n.value()));
  }
  Value shiftRightLogical(const Value &a, const numeric::BelowWidth<Planted> &n) const {
    return d.shiftRightLogical(a, numeric::belowWidth(d, n.value()));
  }
  Value extendSigned(const Value &a, unsigned to) const {
    if constexpr (F == Fault::ZeroExtends)
      return d.extendUnsigned(a, to);
    else
      return d.extendSigned(a, to);
  }
  Value extendUnsigned(const Value &a, unsigned to) const { return d.extendUnsigned(a, to); }
  Value truncate(const Value &a, unsigned to) const { return d.truncate(a, to); }

  Truth equal(const Value &a, const Value &b) const { return decided(d.equal(a, b)); }
  Truth lessSigned(const Value &a, const Value &b) const { return decided(d.lessSigned(a, b)); }
  Truth lessUnsigned(const Value &a, const Value &b) const {
    return decided(d.lessUnsigned(a, b));
  }
  Truth both(Truth t, Truth u) const {
    if constexpr (F == Fault::ConjunctionHolds)
      if (t.known != Known::Fails && u.known != Known::Fails)
        return {Known::Holds};
    return d.both(t, u);
  }
  Truth either(Truth t, Truth u) const { return d.either(t, u); }
  Truth negation(Truth t) const { return d.negation(t); }
  Value select(Truth t, const Value &a, const Value &b) const {
    if constexpr (F == Fault::SelectKeepsOneSide)
      if (t.known == Known::Unknown)
        return a;
    return d.select(t, a, b);
  }

private:
  Truth decided(Truth t) const {
    if constexpr (F == Fault::UndecidedHolds)
      if (t.known == Known::Unknown)
        return {Known::Holds};
    return t;
  }

  numeric::Intervals d;
};

static_assert(numeric::Domain<Planted<Fault::SelectKeepsOneSide>>);

// The judgement can fail: the instance with each fault planted disagrees
// with the words on some case.
TEST(Intervals, EachPlantedFaultIsCaught) {
  EXPECT_GT(judge(Planted<Fault::SelectKeepsOneSide>{}, 1, Report::None), 0u);
  EXPECT_GT(judge(Planted<Fault::UndecidedHolds>{}, 1, Report::None), 0u);
  EXPECT_GT(judge(Planted<Fault::ConjunctionHolds>{}, 1, Report::None), 0u);
  EXPECT_GT(judge(Planted<Fault::UnsignedQuotient>{}, 1, Report::None), 0u);
  EXPECT_GT(judge(Planted<Fault::ZeroExtends>{}, 1, Report::None), 0u);
}

} // namespace
