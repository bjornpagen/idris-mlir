// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value's grade proves, carried into the C++ that builds IR from it.
// A pass holding an mlir::Value can copy it freely, so a value its type
// says is owned alone, or used once, is held here in a handle C++ treats
// the same way: it moves and never copies, so our own code cannot hand one
// cell to two owners or recycle one dead cell into two constructions. A
// copy fails to compile with the reason in its message.
//
// MLIR's own machinery (clone, OperationState, the conversion driver)
// builds ops without our builders, so the verifier after every pass stays
// the complete check of a quantity; these handles move the error to
// compile time on our own paths. The header names no generated type's
// definition, so the dialect's builders may take its handles.
#ifndef IDR_IR_QUANTITIES_H
#define IDR_IR_QUANTITIES_H

#include "mlir/IR/Value.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <functional>
#include <optional>
#include <type_traits>
#include <utility>

namespace idr {

// !idr.token<...>, a reuse token: the dialect's generated type.
class TokenType;

// A value whose grade is `counted unique deep`: freed by its count, with
// nothing it reaches shared, so it owns its whole cell graph alone. Its
// release reads no count, and the builder of that release takes this
// handle, never a bare Value, so it cannot be handed a value that may be
// shared. Made only by asExclusive, the parse of the value's type.
class Exclusive {
public:
  Exclusive(Exclusive &&other) noexcept : v(std::exchange(other.v, {})) {}
  Exclusive &operator=(Exclusive &&other) noexcept {
    v = std::exchange(other.v, {});
    return *this;
  }
  Exclusive(const Exclusive &) = delete("an exclusive value has one owner");
  Exclusive &operator=(const Exclusive &) = delete("an exclusive value has one owner");

  // The value, to read its type and place; the handle still owns it.
  mlir::Value value() const { return v; }
  // The value handed to the one op that takes it over; the handle is empty.
  [[nodiscard]] mlir::Value consume() && { return std::exchange(v, {}); }

private:
  explicit Exclusive(mlir::Value owned) : v(owned) {}
  friend std::optional<Exclusive> asExclusive(mlir::Value value);

  mlir::Value v;
};

// The boundary where exclusivity is read: once, from the value's grade, by
// the one reader of a hold (defined with the grade). None when the grade
// claims less than `counted unique deep`.
[[nodiscard]] std::optional<Exclusive> asExclusive(mlir::Value value);

// A reuse token in counting's forward walk: a dead cell of one layout,
// held until a construction of that layout recycles it. It leaves the walk
// exactly three ways, each consuming it: into a recycle, as a join
// argument across a rejoin, or dropped. Made where a token value is born
// in the walk, never from a value already wrapped.
class Token {
public:
  explicit Token(mlir::TypedValue<TokenType> born) : v(born) {}
  Token(Token &&other) noexcept : v(std::exchange(other.v, {})) {}
  Token &operator=(Token &&other) noexcept {
    v = std::exchange(other.v, {});
    return *this;
  }
  Token(const Token &) = delete("a token is used once");
  Token &operator=(const Token &) = delete("a token is used once");

  // The token value, to read its layout; the handle still holds it.
  mlir::TypedValue<TokenType> value() const { return v; }
  // The token handed to the one op that uses it; the handle is empty.
  [[nodiscard]] mlir::TypedValue<TokenType> consume() && { return std::exchange(v, {}); }

private:
  mlir::TypedValue<TokenType> v;
};

// The tokens one path holds at a point, each with the layout it may be
// recycled into.
template <class Layout>
struct Available {
  llvm::SmallVector<std::pair<Layout, Token>, 2> tokens;
};

// Which of two rejoining paths a token came from.
enum class Arm : std::uint8_t { Left, Right };

// Two paths rejoining. A layout both hold becomes one token after the
// rejoin, which `both` makes from the two (each the join argument of its
// arm); a token only one arm holds goes to `one`, which drops it or carries
// it across, giving the token after the rejoin. Both sides are taken by
// value, so no token of either arm outlives the rejoin unconsumed or is
// used on both sides of it.
template <class Layout, class Both, class One>
  requires std::equality_comparable<Layout> && std::copy_constructible<Layout> &&
           std::same_as<std::invoke_result_t<Both &, const Layout &, Token, Token>, Token> &&
           std::same_as<std::invoke_result_t<One &, Arm, const Layout &, Token>,
                        std::optional<Token>>
Available<Layout> rejoin(Available<Layout> left, Available<Layout> right, Both both, One one) {
  Available<Layout> after;
  for (auto &[layout, token] : left.tokens) {
    auto partner =
        llvm::find_if(right.tokens, [&](const auto &held) { return held.first == layout; });
    if (partner != right.tokens.end()) {
      Token joined = std::invoke(both, std::as_const(layout), std::move(token),
                                 std::move(partner->second));
      after.tokens.emplace_back(layout, std::move(joined));
      right.tokens.erase(partner);
      continue;
    }
    if (std::optional<Token> carried =
            std::invoke(one, Arm::Left, std::as_const(layout), std::move(token)))
      after.tokens.emplace_back(layout, std::move(*carried));
  }
  for (auto &[layout, token] : right.tokens)
    if (std::optional<Token> carried =
            std::invoke(one, Arm::Right, std::as_const(layout), std::move(token)))
      after.tokens.emplace_back(layout, std::move(*carried));
  return after;
}

} // namespace idr

#endif // IDR_IR_QUANTITIES_H
