// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A reuse token's grade, carried into the C++ that builds IR from it. A
// pass holding an mlir::Value can copy it freely, so counting's walk holds
// each token, a dead cell its type says is used once, in a handle C++
// treats the same way: it moves and never copies, and gives its value up
// only to the one op that uses it, so the walk cannot recycle one dead cell
// into two constructions or free one it recycled. A copy fails to compile
// with the reason in its message. A value's other quantities, exclusivity
// among them, are its grade, in its type, which every reader reads there:
// a handle beside the type would hold the same claim twice.
//
// MLIR's own machinery (clone, OperationState, the conversion driver)
// builds ops without the handle, so the verifier after every pass stays
// the complete check of a quantity; the handle moves the error to compile
// time on counting's own path. The header names no generated type, so any
// header may include it.
#ifndef IDR_IR_QUANTITIES_H
#define IDR_IR_QUANTITIES_H

#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <type_traits>
#include <utility>

namespace idr {

// A reuse token in counting's forward walk: a dead cell of one size, held
// until a construction of that size recycles it. It leaves the walk exactly
// three ways, each consuming it: into a recycle, as a join argument at a
// rejoin, or freed; and only `branch` gives more than one handle on it, one
// per path of which exactly one runs. Made where a token is born in the
// walk: an op's token result, which that op's verifier holds to be a token
// used once (its type the grade it is held at, over `!idr.token`), never
// from a handle's value, which only `consume` gives up.
class Token {
public:
  explicit Token(mlir::Value born) : v(born) {}
  Token(Token &&other) noexcept : v(std::exchange(other.v, {})) {}
  Token &operator=(Token &&other) noexcept {
    v = std::exchange(other.v, {});
    return *this;
  }
  Token(const Token &) = delete("a token is used once");
  Token &operator=(const Token &) = delete("a token is used once");

  // Its type, the grade it is held at over the cells it may be: what a
  // choice among tokens reads. The handle still holds it.
  mlir::Type type() const { return v.getType(); }
  // The token handed to the one op that uses it; the handle is empty.
  [[nodiscard]] mlir::Value consume() && { return std::exchange(v, {}); }

private:
  mlir::Value v;
};

// A token held before an op that runs exactly one of its regions, handed to
// every path the op can take: one handle per path, each consumed on its own
// path, since only one of them runs. An op that can take none (a match on
// a type with no constructor) gives none, as nothing past it runs.
[[nodiscard]] inline llvm::SmallVector<Token> branch(Token held, unsigned paths) {
  mlir::Value token = std::move(held).consume();
  llvm::SmallVector<Token> handles;
  handles.reserve(paths);
  for (unsigned path = 0; path < paths; ++path)
    handles.emplace_back(token);
  return handles;
}

// What tells tokens apart at a rejoin: the layout a token may be recycled
// into, compared, and copied into what the rejoin gives back.
template <class L>
concept TokenLayout = std::equality_comparable<L> && std::copy_constructible<L>;

// The tokens one path holds at a point, each with the layout it may be
// recycled into, in the order the path gives them up: the first of a layout
// leaves first.
template <TokenLayout Layout>
struct Available {
  llvm::SmallVector<std::pair<Layout, Token>, 2> tokens;
};

// How many tokens of a layout the code after a rejoin can use.
template <class F, class Layout>
concept Wants = std::same_as<std::invoke_result_t<F &, const Layout &>, std::uint32_t>;

// What takes the tokens of a layout that leave a rejoin together, one per
// path, as join arguments; no token comes back from it.
template <class F, class Layout>
concept Joins =
    std::same_as<std::invoke_result_t<F &, const Layout &, llvm::SmallVector<Token>>, void>;

// What takes a token that does not leave a rejoin, with the position of the
// path that held it; no token comes back from it.
template <class F, class Layout>
concept Drops = std::same_as<std::invoke_result_t<F &, unsigned, const Layout &, Token>, void>;

// The paths an op's regions take, rejoining at its results, each with what
// it holds at its yield. Of each layout, as many leave together as every
// path holds and `wanted` caps; the k-th to leave takes each path's k-th
// token of that layout, in path order, which `join` consumes as join
// arguments. Every other token goes to `drop`. No token comes out: the
// tokens after the rejoin are the op's results, which exist only once the
// op is made again with their types, so the rejoin gives back the layout of
// each join, in the order `join` was called, for that. The paths are taken
// by value, so no token of any of them outlives the rejoin unconsumed or
// is used on two of them; with no path, nothing leaves.
template <TokenLayout Layout, Wants<Layout> Wanted, Joins<Layout> Join, Drops<Layout> Drop>
[[nodiscard]] llvm::SmallVector<Layout> rejoin(llvm::SmallVector<Available<Layout>> arms,
                                               Wanted wanted, Join join, Drop drop) {
  // Each layout the first path holds, once, with how many of it leave and
  // where its joins begin among all the joins; a layout the first path
  // lacks is held by not every path, and none of it leaves.
  struct Leaving {
    Layout layout;
    std::uint32_t count;
    std::uint32_t first;
  };
  llvm::SmallVector<Leaving, 4> leaving;
  std::uint32_t joins = 0;
  if (!arms.empty())
    for (const auto &held : arms.front().tokens) {
      const Layout &layout = held.first;
      if (llvm::any_of(leaving, [&](const Leaving &seen) { return seen.layout == layout; }))
        continue;
      std::uint32_t count = std::invoke(wanted, layout);
      for (const Available<Layout> &arm : arms) {
        auto of = llvm::count_if(arm.tokens, [&](const auto &h) { return h.first == layout; });
        count = std::min(count, static_cast<std::uint32_t>(of));
      }
      leaving.push_back({layout, count, joins});
      joins += count;
    }
  // Each join's tokens, which every path fills in its turn, so each holds
  // one token per path in path order.
  llvm::SmallVector<llvm::SmallVector<Token>, 4> together(joins);
  for (unsigned at = 0; at < arms.size(); ++at) {
    llvm::SmallVector<std::uint32_t, 4> taken(leaving.size(), 0);
    for (auto &[layout, token] : arms[at].tokens) {
      auto entry = llvm::find_if(leaving, [&](const Leaving &l) { return l.layout == layout; });
      if (entry != leaving.end()) {
        std::uint32_t &k = taken[static_cast<std::size_t>(entry - leaving.begin())];
        if (k < entry->count) {
          together[entry->first + k++].push_back(std::move(token));
          continue;
        }
      }
      std::invoke(drop, at, std::as_const(layout), std::move(token));
    }
  }
  llvm::SmallVector<Layout> joined;
  for (const Leaving &l : leaving)
    for (std::uint32_t k = 0; k < l.count; ++k) {
      std::invoke(join, l.layout, std::move(together[l.first + k]));
      joined.push_back(l.layout);
    }
  return joined;
}

} // namespace idr

#endif // IDR_IR_QUANTITIES_H
