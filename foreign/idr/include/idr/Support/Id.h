// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Dense ids, and the arrays and sets they index: the coordinates of every
// fact a solver or a pass keeps per thing. A thing numbered once is found
// by its id in one load, so no fact about it lives in a map keyed by a
// pointer, a value or a name, and no lookup by its id can miss.
//
// An id names the set `Tag` stands for, and only `Tag::Minter`, the code
// that numbered the set, can make one or say how many it made. So an id in
// hand was minted by its owner, an array sized by a Count is exactly as
// long as the set, and an id of one set cannot index another set's array:
// the tags differ, so the call does not compile. Indexing by a raw integer
// is deleted, with the reason in the message.
//
// Nothing here names MLIR. A numbering of IR handles mints these ids where
// the IR is read; what is solved over them is solved over dense integers.
#ifndef IDR_SUPPORT_ID_H
#define IDR_SUPPORT_ID_H

#include "idr/Support/Changed.h"

#include "llvm/ADT/BitVector.h"

#include <compare>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <limits>
#include <ranges>
#include <span>
#include <utility>
#include <vector>

namespace idr {

template <class IdT>
class Count;

// A dense id of the set `Tag` names, numbered from 0 by `Tag::Minter`. It
// has no default: an id always names something its minter numbered.
template <class Tag, std::unsigned_integral Rep = std::uint32_t>
class Id {
public:
  using tag = Tag;
  using rep = Rep;

  // The id's number, for the arrays it indexes and for LLVM's numbered
  // graph algorithms; never a key of a hashed container.
  constexpr Rep index() const { return raw; }

  friend constexpr auto operator<=>(Id, Id) = default;

private:
  constexpr explicit Id(Rep at) : raw(at) {}

  friend typename Tag::Minter;
  template <class>
  friend class Count;
  // A compressed row stores the ids its builder was given as their numbers
  // and hands them back typed (the solver layer's graphs): wrapping a stored
  // number mints nothing new.
  template <class>
  friend class IdRange;

  Rep raw;
};

// How many ids a minter made: the only size an IndexVector, a BitSet or a
// Ragged takes, and the one way to visit every id.
template <class IdT>
class Count {
public:
  using rep = typename IdT::rep;

  constexpr rep value() const { return n; }

  // Every id, in order.
  constexpr auto ids() const {
    return std::views::iota(rep{0}, n) | std::views::transform([](rep at) { return IdT(at); });
  }

  friend constexpr bool operator==(Count, Count) = default;

private:
  constexpr explicit Count(rep made) : n(made) {}

  friend typename IdT::tag::Minter;

  rep n;
};

// A fact per id. Indexing is libc++'s checked operator[], kept on purpose:
// the bound is not in the type, since two scopes numbered under one tag
// (two functions' values) share the type and differ in count, so an id of
// one could reach the other's array. That bound is a fact not known until
// the compiler runs, and its check is libc++'s hardening, nothing of ours.
template <class IdT, class T>
class IndexVector {
  static_assert(!std::same_as<T, bool>, "a set of ids is a BitSet");

public:
  explicit IndexVector(Count<IdT> n)
    requires std::default_initializable<T>
      : count(n), items(n.value()) {}

  IndexVector(Count<IdT> n, const T &init) : count(n), items(n.value(), init) {}

  // Each id's fact made from the id: the form for a type with no default,
  // an id of another set among them, which has no meaningful one.
  template <class Tabulate>
    requires std::invocable<Tabulate &, IdT> &&
             std::convertible_to<std::invoke_result_t<Tabulate &, IdT>, T> &&
             (!std::convertible_to<Tabulate, T>)
  IndexVector(Count<IdT> n, Tabulate tabulate) : count(n) {
    items.reserve(n.value());
    for (IdT id : n.ids())
      items.push_back(std::invoke(tabulate, id));
  }

  Count<IdT> size() const { return count; }

  T &operator[](IdT id) [[clang::lifetimebound]] { return items[id.index()]; }
  const T &operator[](IdT id) const [[clang::lifetimebound]] { return items[id.index()]; }
  template <std::integral I>
  T &operator[](I) = delete("index by the id its minter made");
  template <std::integral I>
  const T &operator[](I) const = delete("index by the id its minter made");

  friend bool operator==(const IndexVector &, const IndexVector &) = default;

private:
  Count<IdT> count;
  std::vector<T> items;
};

// A set of ids that only rises: no member leaves it and it has no reset, so
// a marking over it is monotone by its API, and a loop that pushes an id
// only when it rose ends after each id rose once.
template <class IdT>
  requires(std::numeric_limits<typename IdT::rep>::max() <=
           std::numeric_limits<unsigned>::max())
class BitSet {
public:
  explicit BitSet(Count<IdT> n) : count(n), bits(n.value()) {}

  // The set whose members are the bits a marking set, one bit per id of the
  // count; a bit past the count names no id and is dropped.
  BitSet(Count<IdT> n, llvm::BitVector marked) : count(n), bits(std::move(marked)) {
    bits.resize(n.value());
  }

  Count<IdT> size() const { return count; }

  bool test(IdT id) const { return bits.test(id.index()); }

  // Adds `id`; whether the set rose.
  [[nodiscard]] Changed raise(IdT id) {
    if (bits.test(id.index()))
      return Changed::No;
    bits.set(id.index());
    return Changed::Yes;
  }

  friend bool operator==(const BitSet &, const BitSet &) = default;

private:
  Count<IdT> count;
  llvm::BitVector bits;
};

// A fact per (owner, position) where owners differ in arity: a parameter's
// bit, a field's state. One array of rows with offsets, never a vector per
// owner. It is built whole, each owner's row asked of `rowOf` in id order,
// so the offsets are right by construction.
template <class OwnerId, class T>
class Ragged {
public:
  template <class RowOf>
    requires std::invocable<RowOf &, OwnerId> &&
             std::ranges::input_range<std::invoke_result_t<RowOf &, OwnerId>>
  Ragged(Count<OwnerId> owners, RowOf rowOf) : count(owners) {
    start.reserve(std::size_t{owners.value()} + 1);
    start.push_back(0);
    for (OwnerId owner : owners.ids()) {
      for (auto &&item : std::invoke(rowOf, owner))
        items.push_back(std::forward<decltype(item)>(item));
      start.push_back(items.size());
    }
  }

  Count<OwnerId> size() const { return count; }

  std::span<const T> operator[](OwnerId owner) const [[clang::lifetimebound]] {
    return {items.data() + start[owner.index()], items.data() + start[owner.index() + 1]};
  }
  std::span<T> operator[](OwnerId owner) [[clang::lifetimebound]] {
    return {items.data() + start[owner.index()], items.data() + start[owner.index() + 1]};
  }
  template <std::integral I>
  std::span<T> operator[](I) = delete("index by the id its minter made");
  template <std::integral I>
  std::span<const T> operator[](I) const = delete("index by the id its minter made");

private:
  Count<OwnerId> count;
  // count + 1 offsets: owner o's row is [start[o], start[o + 1]).
  std::vector<std::size_t> start;
  std::vector<T> items;
};

} // namespace idr

#endif // IDR_SUPPORT_ID_H
