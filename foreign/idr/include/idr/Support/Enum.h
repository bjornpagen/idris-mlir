// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A closed set of ours is a scoped enum dense from zero, its count beside
// it; a table over the set is an EnumArray indexed by the enum, and a
// subset of it an EnumSet. The specification's enums get their EnumTraits
// from the generator, which prints them dense by construction (a case's
// position is its number) with their names for printing; an enum only our
// C++ has states its own count. So every per-case fact is one load, every
// table has exactly one row per case, and a subset is a word or a few.
//
// An EnumSet is a lattice of finite height: bottom the empty set, top
// every case, join the union, its height the count. A row of effects (a
// set of atoms) is one, so a solve over rows ends by its type.
#ifndef IDR_SUPPORT_ENUM_H
#define IDR_SUPPORT_ENUM_H

#include "idr/Support/Changed.h"

#include <array>
#include <bit>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <type_traits>
#include <utility>

namespace idr {

// Specialized for every closed set: `count`, the number of cases. A
// generated specialization also holds `names`, the cases' printed names.
template <class E>
struct EnumTraits;

template <class E>
concept Enumerated = std::is_scoped_enum_v<E> && requires {
  { EnumTraits<E>::count } -> std::convertible_to<std::size_t>;
};

// Every case, in order.
template <Enumerated E>
consteval std::array<E, EnumTraits<E>::count> allOf() {
  std::array<E, EnumTraits<E>::count> out{};
  for (std::size_t at = 0; at < out.size(); ++at)
    out[at] = static_cast<E>(at);
  return out;
}

// A fact per case. An aggregate, so a generated table is written as one
// braced list in the cases' order.
template <Enumerated E, class T>
struct EnumArray {
  std::array<T, EnumTraits<E>::count> items;

  constexpr T &operator[](E e) { return items[static_cast<std::size_t>(std::to_underlying(e))]; }
  constexpr const T &operator[](E e) const {
    return items[static_cast<std::size_t>(std::to_underlying(e))];
  }
  template <std::integral I>
  T &operator[](I) = delete("index by the enum");
  template <std::integral I>
  const T &operator[](I) const = delete("index by the enum");

  friend constexpr bool operator==(const EnumArray &, const EnumArray &) = default;
};

// A subset of the cases, one bit per case.
template <Enumerated E>
class EnumSet {
  static constexpr std::size_t cases = EnumTraits<E>::count;
  static constexpr std::size_t words = (cases + 63) / 64;

  static constexpr std::size_t wordOf(E e) {
    return static_cast<std::size_t>(std::to_underlying(e)) / 64;
  }
  static constexpr std::uint64_t bitOf(E e) {
    return std::uint64_t{1} << (static_cast<std::size_t>(std::to_underlying(e)) % 64);
  }

public:
  // The longest chain from bottom to top: one case added at each step.
  static constexpr unsigned height = static_cast<unsigned>(cases);

  constexpr EnumSet() = default;
  constexpr EnumSet(std::initializer_list<E> members) {
    for (E e : members)
      bits[wordOf(e)] |= bitOf(e);
  }

  static constexpr EnumSet bottom() { return {}; }
  static constexpr EnumSet top() {
    EnumSet all;
    for (E e : allOf<E>())
      all.bits[wordOf(e)] |= bitOf(e);
    return all;
  }

  constexpr bool contains(E e) const { return (bits[wordOf(e)] & bitOf(e)) != 0; }
  constexpr bool empty() const { return *this == EnumSet(); }
  // Whether every member of `other` is a member of this one.
  constexpr bool includes(EnumSet other) const { return (other - *this).empty(); }
  constexpr std::size_t size() const {
    std::size_t members = 0;
    for (std::uint64_t word : bits)
      members += static_cast<std::size_t>(std::popcount(word));
    return members;
  }

  friend constexpr EnumSet operator|(EnumSet a, EnumSet b) {
    for (std::size_t at = 0; at < words; ++at)
      a.bits[at] |= b.bits[at];
    return a;
  }
  friend constexpr EnumSet operator&(EnumSet a, EnumSet b) {
    for (std::size_t at = 0; at < words; ++at)
      a.bits[at] &= b.bits[at];
    return a;
  }
  // The members of `a` that are not members of `b`.
  friend constexpr EnumSet operator-(EnumSet a, EnumSet b) {
    for (std::size_t at = 0; at < words; ++at)
      a.bits[at] &= ~b.bits[at];
    return a;
  }

  // The union, in place; whether it grew.
  constexpr Changed join(const EnumSet &other) {
    if (includes(other))
      return Changed::No;
    *this = *this | other;
    return Changed::Yes;
  }

  friend constexpr bool operator==(const EnumSet &, const EnumSet &) = default;

private:
  std::array<std::uint64_t, words> bits{};
};

} // namespace idr

#endif // IDR_SUPPORT_ENUM_H
