// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one fold over a closed sum of ours: `match(sum, case...)` hands the
// alternative the sum holds to the one case that takes it. A sum of our own
// data is a std::variant; a sum of pointer-sized handles is an
// llvm::PointerUnion, read by the same fold.
//
// Every alternative must have a case and every case must give one type, or
// the match does not compile, and says which: a sum that gains an
// alternative is refused at every match that forgot it, which a ladder of
// asks never was. So nothing else reads an alternative: std::get_if,
// std::holds_alternative, std::visit and TypeSwitch are not used (each asks
// and throws the answer away, or, for visit, dispatches through a matrix
// of function pointers above eleven alternatives in libc++). The fold is
// one compare per alternative, which compiles to a jump table at any size.
#ifndef IDR_SUPPORT_MATCH_H
#define IDR_SUPPORT_MATCH_H

#include "llvm/ADT/PointerUnion.h"
#include "llvm/Support/Casting.h"

#include <concepts>
#include <cstddef>
#include <functional>
#include <memory>
#include <optional>
#include <type_traits>
#include <utility>
#include <variant>

namespace idr {

// The cases of a match, one callable per alternative, as one overload set.
template <class... Fs>
struct Cases : Fs... {
  using Fs::operator()...;
};

namespace detail {

template <class V>
inline constexpr bool isVariant = false;
template <class... Ts>
inline constexpr bool isVariant<std::variant<Ts...>> = true;

// `A` as the sum `V` was passed: a case of a const sum sees a const
// alternative, a case of a sum given away may take its alternative.
template <class V, class A>
using Like = std::conditional_t<
    std::is_lvalue_reference_v<V>,
    std::conditional_t<std::is_const_v<std::remove_reference_t<V>>, const A &, A &>,
    std::conditional_t<std::is_const_v<std::remove_reference_t<V>>, const A &&, A &&>>;

template <class V, std::size_t I>
using Alternative = Like<V, std::variant_alternative_t<I, std::remove_cvref_t<V>>>;

template <class C, class V, std::size_t... I>
consteval bool handlesEach(std::index_sequence<I...>) {
  return (std::invocable<C &, Alternative<V, I>> && ...);
}

template <class C, class V, class R, std::size_t... I>
consteval bool givesOne(std::index_sequence<I...>) {
  return (std::same_as<std::invoke_result_t<C &, Alternative<V, I>>, R> && ...);
}

// The alternative the fold has just found the sum to hold, as the sum was
// passed: the one read of an alternative there is.
template <std::size_t I, class V>
constexpr Alternative<V, I> alternative(std::remove_reference_t<V> &sum) {
  return static_cast<Alternative<V, I>>(*std::get_if<I>(std::addressof(sum))); // NOLINT(bugprone-unsafe-functions)
}

// A case's result named, so a result that is a reference of either kind is
// held by its address.
template <class T>
constexpr T &named(T &&result) {
  return result;
}

// One test per alternative, the case of the one that holds run once. A
// result that is a reference is held by address and an object in an
// optional until the fold ends, so a result with no default works.
template <class R, class C, class V, std::size_t... I>
constexpr R fold(C &cases, V &&sum, std::index_sequence<I...>) {
  if constexpr (std::is_void_v<R>) {
    (void)((sum.index() == I && (std::invoke(cases, alternative<I, V>(sum)), true)) || ...);
  } else if constexpr (std::is_reference_v<R>) {
    std::remove_reference_t<R> *out = nullptr;
    (void)((sum.index() == I &&
            (out = std::addressof(named(std::invoke(cases, alternative<I, V>(sum)))), true)) ||
           ...);
    return static_cast<R>(*out);
  } else {
    std::optional<R> out;
    (void)((sum.index() == I &&
            (out.emplace(std::invoke(cases, alternative<I, V>(sum))), true)) ||
           ...);
    return *std::move(out);
  }
}

template <class R, class C, class... PTs>
R foldHandles(C &cases, llvm::PointerUnion<PTs...> handle) {
  if constexpr (std::is_void_v<R>) {
    (void)((llvm::isa<PTs>(handle) && (std::invoke(cases, llvm::cast<PTs>(handle)), true)) ||
           ...);
  } else if constexpr (std::is_reference_v<R>) {
    std::remove_reference_t<R> *out = nullptr;
    (void)((llvm::isa<PTs>(handle) &&
            (out = std::addressof(named(std::invoke(cases, llvm::cast<PTs>(handle)))), true)) ||
           ...);
    return static_cast<R>(*out);
  } else {
    std::optional<R> out;
    (void)((llvm::isa<PTs>(handle) &&
            (out.emplace(std::invoke(cases, llvm::cast<PTs>(handle))), true)) ||
           ...);
    return *std::move(out);
  }
}

} // namespace detail

template <class V>
concept ClosedSum = detail::isVariant<std::remove_cvref_t<V>>;

template <ClosedSum V, class... Fs>
constexpr decltype(auto) match(V &&sum, Fs &&...fs) {
  using C = Cases<std::remove_cvref_t<Fs>...>;
  using Order = std::make_index_sequence<std::variant_size_v<std::remove_cvref_t<V>>>;
  static_assert(detail::handlesEach<C, V>(Order{}), "a match has a case for every alternative");
  if constexpr (detail::handlesEach<C, V>(Order{})) {
    using R = std::invoke_result_t<C &, detail::Alternative<V, 0>>;
    static_assert(detail::givesOne<C, V, R>(Order{}), "every case of a match gives one type");
    if constexpr (detail::givesOne<C, V, R>(Order{})) {
      C cases{std::forward<Fs>(fs)...};
      return detail::fold<R>(cases, std::forward<V>(sum), Order{});
    }
  }
}

// A union of handles is never null where it is matched: each of its
// alternatives is a handle that names something.
template <class... PTs, class... Fs>
decltype(auto) match(llvm::PointerUnion<PTs...> handle, Fs &&...fs) {
  using C = Cases<std::remove_cvref_t<Fs>...>;
  static_assert((std::invocable<C &, PTs> && ...), "a match has a case for every alternative");
  if constexpr ((std::invocable<C &, PTs> && ...)) {
    using R = std::invoke_result_t<C &, PTs...[0]>;
    static_assert((std::same_as<std::invoke_result_t<C &, PTs>, R> && ...),
                  "every case of a match gives one type");
    if constexpr ((std::same_as<std::invoke_result_t<C &, PTs>, R> && ...)) {
      C cases{std::forward<Fs>(fs)...};
      return detail::foldHandles<R>(cases, handle);
    }
  }
}

} // namespace idr

#endif // IDR_SUPPORT_MATCH_H
