// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the vocabulary refuses to compile, each refusal beside a use it
// takes, so that what is refused is the use and never the header. The unit
// is in no box: it is compiled once with clang's -verify, which passes only
// when every refusal below is made, at its line and with its message, and
// nothing else is, so one compile checks them all. Each refusal is a
// namespace of its own, so that no fixture of one meets another's.

#include "idr/IR/Numeric/Domain.h"
#include "idr/IR/Quantities.h"
#include "idr/Support/Enum.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/PointerUnion.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <variant>

//===----------------------------------------------------------------------===//
// Ids
//===----------------------------------------------------------------------===//

// An id, and the count of a set of ids, are made only by the set's minter:
// an id in hand names something its owner numbered, and only the owner
// says how long an array of its facts is. Anyone else's is refused.
namespace minting {

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;

// The minter may.
struct Things::Minter {
  static Thing first() { return Thing(0); }
  static idr::Count<Thing> count(std::uint32_t n) { return idr::Count<Thing>(n); }
};

Thing forgedId() {
  return Thing(3); // expected-error {{calling a private constructor of class 'idr::Id}}
}

idr::Count<Thing> forgedCount() {
  return idr::Count<Thing>(3); // expected-error {{calling a private constructor of class 'idr::Count}}
}

} // namespace minting

// A fact per id is found by the id its minter made, never by a raw
// integer, which could be any set's position or none.
namespace raw_index {

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;
struct Things::Minter {
  static Thing first() { return Thing(0); }
};

void byId(idr::IndexVector<Thing, int> &facts) { facts[Things::Minter::first()] = 1; }

void written(idr::IndexVector<Thing, int> &facts) {
  facts[0] = 1; // expected-error {{index by the id its minter made}}
}

int read(const idr::IndexVector<Thing, int> &facts) {
  return facts[std::uint32_t{0}]; // expected-error {{index by the id its minter made}}
}

void row(const idr::Ragged<Thing, int> &rows) {
  (void)rows[0]; // expected-error {{index by the id its minter made}}
}

} // namespace raw_index

// A yes or no per id is a set of ids, a BitSet, which only rises; never an
// array of bools beside it.
namespace set_of_ids {

struct Things {
  struct Minter;
};
using Thing = idr::Id<Things>;
struct Things::Minter {
  static idr::Count<Thing> count(std::uint32_t n) { return idr::Count<Thing>(n); }
};

void sets() {
  idr::BitSet<Thing> marked(Things::Minter::count(4));
  // expected-error@idr/Support/Id.h:* {{a set of ids is a BitSet}}
  idr::IndexVector<Thing, bool> flags(Things::Minter::count(4));
}

} // namespace set_of_ids

//===----------------------------------------------------------------------===//
// Closed sets and sums
//===----------------------------------------------------------------------===//

// A table over a closed set is indexed by the set's enum, never by the
// position a case happens to have.
namespace enum_index {
enum class Three : unsigned char { A, B, C };
} // namespace enum_index

template <>
struct idr::EnumTraits<enum_index::Three> {
  static constexpr std::size_t count = 3;
};

namespace enum_index {

int byCase(const idr::EnumArray<Three, int> &table) { return table[Three::C]; }

int byPosition(const idr::EnumArray<Three, int> &table) {
  return table[2]; // expected-error {{index by the enum}}
}

} // namespace enum_index

// A match over a closed sum has a case for every alternative, and every
// case gives one type: a sum that gains an alternative is refused at every
// match that forgot it.
namespace match_cases {

using Sum = std::variant<int, std::string>;

int whole(const Sum &sum) {
  return idr::match(sum, [](int) { return 0; }, [](const std::string &) { return 1; });
}

void missing(const Sum &sum) {
  // expected-error@idr/Support/Match.h:* {{a match has a case for every alternative}}
  idr::match(sum, [](int) {});
}

void twoTypes(const Sum &sum) {
  // expected-error@idr/Support/Match.h:* {{every case of a match gives one type}}
  idr::match(sum, [](int) { return 0; }, [](const std::string &) { return 0.5; });
}

// A case for several alternatives names them, by a list or by a concept
// they share; a case that takes every type is a default, which an
// alternative the sum gains would reach silently, in a sum of data or of
// handles alike.
int listed(const Sum &sum) {
  return idr::match(sum, [](const idr::OneOf<int, std::string> auto &) { return 0; });
}

void everyType(const Sum &sum) {
  // expected-error@idr/Support/Match.h:* {{no case of a match takes every type}}
  idr::match(sum, [](int) { return 0; }, [](const auto &) { return 1; });
}

using Handle = llvm::PointerUnion<int *, double *>;

int listedHandles(Handle handle) {
  return idr::match(handle, [](idr::OneOf<int *, double *> auto) { return 0; });
}

void everyHandle(Handle handle) {
  // expected-error@idr/Support/Match.h:* {{no case of a match takes every type}}
  idr::match(handle, [](int *) { return 0; }, [](auto *) { return 1; });
}

} // namespace match_cases

//===----------------------------------------------------------------------===//
// Quantities
//===----------------------------------------------------------------------===//

// A reuse token is a dead cell held for one construction: it moves along
// counting's walk and is used once, so it is never copied, by construction
// or by assignment.
namespace token {

idr::Token moved(idr::Token held) { return idr::Token(std::move(held)); }

void copied(const idr::Token &held) {
  idr::Token twice(held); // expected-error {{a token is used once}}
}

void assigned(idr::Token &into, const idr::Token &held) {
  into = held; // expected-error {{a token is used once}}
}

} // namespace token

// At a rejoin a token leaves as a join argument or is dropped, and none
// comes out of it: the tokens after it are the op's results, which exist
// only once the op is made again with their types. A join that gives a
// token back, or a drop that carries one across, is refused.
namespace rejoin_gives_none {

enum class Size : unsigned char { Small, Large };

auto wanted = [](const Size &) -> std::uint32_t { return 1; };
auto joined = [](const Size &, llvm::SmallVector<idr::Token> tokens) {
  for (idr::Token &token : tokens)
    (void)std::move(token).consume();
};
auto dropped = [](unsigned, const Size &, idr::Token token) { (void)std::move(token).consume(); };

llvm::SmallVector<Size> rejoined(llvm::SmallVector<idr::Available<Size>> arms) {
  return idr::rejoin(std::move(arms), wanted, joined, dropped);
}

llvm::SmallVector<Size> joinGivesOne(llvm::SmallVector<idr::Available<Size>> arms) {
  auto gives = [](const Size &, llvm::SmallVector<idr::Token> tokens) {
    return std::move(tokens.front());
  };
  // expected-error@+1 {{no matching function for call to 'rejoin'}}
  return idr::rejoin(std::move(arms), wanted, gives, dropped);
}

llvm::SmallVector<Size> dropCarries(llvm::SmallVector<idr::Available<Size>> arms) {
  auto carries = [](unsigned, const Size &, idr::Token token) {
    return std::optional<idr::Token>(std::move(token));
  };
  // expected-error@+1 {{no matching function for call to 'rejoin'}}
  return idr::rejoin(std::move(arms), wanted, joined, carries);
}

} // namespace rejoin_gives_none

//===----------------------------------------------------------------------===//
// Numeric domains
//===----------------------------------------------------------------------===//

// An op of inline arithmetic is one template over a numeric domain, and a
// domain's truth is never a bool: over an IR builder a truth is an i1
// value, and an mlir::Value converts to bool, so a template that branched
// on a truth would compile there and lower `-7 div 2` to -3. Two domains
// the same in every respect but what their comparisons give: the one whose
// truth no bool is made from is a domain, the other is refused.
namespace truth_domain {

struct Holds {
  bool holds;
};
constexpr bool holds(Holds t) { return t.holds; }
constexpr bool holds(bool t) { return t; }

template <class T>
struct Integers {
  using Value = std::int64_t;
  using Truth = T;
  static constexpr idr::numeric::Overflow overflow = idr::numeric::Overflow::Cannot;

  constexpr Value constant(std::int64_t c, Value) const { return c; }
  constexpr Value add(Value a, Value b) const { return a + b; }
  constexpr Value sub(Value a, Value b) const { return a - b; }
  constexpr Value quotientTowardZero(Value a,
                                     const idr::numeric::SafeDivisor<Integers> &s) const {
    return a / s.value();
  }
  constexpr Value remainderTowardZero(Value a,
                                      const idr::numeric::SafeDivisor<Integers> &s) const {
    return a % s.value();
  }
  constexpr T equal(Value a, Value b) const { return T{a == b}; }
  constexpr T lessSigned(Value a, Value b) const { return T{a < b}; }
  constexpr T both(T t, T u) const { return T{holds(t) && holds(u)}; }
  constexpr Value select(T t, Value a, Value b) const { return holds(t) ? a : b; }
};

static_assert(idr::numeric::Arithmetic<Integers<Holds>>);
// expected-error@+1 {{a truth is never a bool}}
static_assert(idr::numeric::Arithmetic<Integers<bool>>, "a truth is never a bool");

} // namespace truth_domain
