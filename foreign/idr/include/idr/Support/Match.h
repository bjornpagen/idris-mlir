// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one fold over a closed sum of ours: `match(sum, case...)` hands the
// alternative the sum holds to the one case that takes it. A sum of our own
// data is a std::variant, or a class with members of its own that derives
// from one publicly, which the fold reads as that variant, as std::visit
// does; a sum of pointer-sized handles is an llvm::PointerUnion, read by
// the same fold; and a type of the dialect is an mlir::Type folded over the
// classes the dialect's specification generates. MLIR's types are an open
// set, the dialect's a closed one, so a fold over them is a fold over a
// sum, and a type interface, MLIR's answer for an open set, is not used to
// say what each of our types is.
//
// Every alternative must have a case and every case must give one type, or
// the match does not compile, and says which: a sum that gains an
// alternative is refused at every match that forgot it, which a ladder of
// asks never was. So nothing else reads an alternative: std::get_if,
// std::holds_alternative, std::visit and TypeSwitch are not used (each asks
// and throws the answer away, or, for visit, dispatches through a matrix
// of function pointers above eleven alternatives in libc++). The fold is
// one compare per alternative, which compiles to a jump table at any size.
//
// No case takes every type. A generic case beside named ones is a default,
// and an alternative the sum gains would go to it silently, which is the
// coverage the fold exists to keep; so the fold probes its cases with a
// type of its own that no sum holds, and a match one of whose cases takes
// it does not compile. A case for several alternatives names them: by a
// list, `OneOf<A, B> auto &`, or by a concept they share and the probe
// lacks.
//
// The fold reads the sum only to find the alternative it holds, before
// the case runs, and reads neither the sum nor that alternative after the
// case returns: a case may move or destroy the sum it was handed, as one
// that pushes or pops the work stack holding it does.
#ifndef IDR_SUPPORT_MATCH_H
#define IDR_SUPPORT_MATCH_H

#include "mlir/IR/Types.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/PointerUnion.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/ErrorHandling.h"

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

// A case for several alternatives, named by their list: `T`, however it is
// passed, is one of `Alternatives`.
template <class T, class... Alternatives>
concept OneOf = (std::same_as<std::remove_cvref_t<T>, Alternatives> || ...);

// The classes of a closed set of MLIR types, in the order a list generated
// for them gives.
template <class... Ts>
struct TypeClasses {};

// The dialect's types: the classes its specification generates, as a
// TypeClasses, completed beside their generated declarations. The dialect's
// own header includes this one before it declares them, so the fold below
// reads the list only where a match is instantiated.
struct DialectTypes;

namespace detail {

// The probe: a type no sum holds, which only a case that takes every type
// takes.
struct Unheld {};

// The variant a sum is or derives from, as the sum was passed: found by
// deducing the base, so a class deriving from two variants is no sum.
template <class... Ts>
constexpr std::variant<Ts...> &asVariant(std::variant<Ts...> &sum) {
  return sum;
}
template <class... Ts>
constexpr const std::variant<Ts...> &asVariant(const std::variant<Ts...> &sum) {
  return sum;
}
template <class... Ts>
constexpr std::variant<Ts...> &&asVariant(std::variant<Ts...> &&sum) {
  return std::move(sum);
}
template <class... Ts>
constexpr const std::variant<Ts...> &&asVariant(const std::variant<Ts...> &&sum) {
  return std::move(sum);
}

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

// `List`, named through the cases of a match, so a list completed after
// this header is read where the match is instantiated and not where the
// fold is defined.
template <class List, class...>
struct Late {
  using type = List;
};

// One compare per class against the type's id, read once, the case of the
// class that holds run once. A type of no class of the list is of another
// dialect, which the caller asks before it folds.
template <class R, class C, class... Ts>
R foldTypes(C &cases, mlir::Type type, TypeClasses<Ts...>) {
  mlir::TypeID id = type.getTypeID();
  auto other = [] {
    llvm::reportFatalInternalError("a type of another dialect folded over the dialect's types");
  };
  if constexpr (std::is_void_v<R>) {
    if (!((id == mlir::TypeID::get<Ts>() && (std::invoke(cases, llvm::cast<Ts>(type)), true)) ||
          ...))
      other();
  } else if constexpr (std::is_reference_v<R>) {
    std::remove_reference_t<R> *out = nullptr;
    if (!((id == mlir::TypeID::get<Ts>() &&
           (out = std::addressof(named(std::invoke(cases, llvm::cast<Ts>(type)))), true)) ||
          ...))
      other();
    return static_cast<R>(*out);
  } else {
    std::optional<R> out;
    if (!((id == mlir::TypeID::get<Ts>() &&
           (out.emplace(std::invoke(cases, llvm::cast<Ts>(type))), true)) ||
          ...))
      other();
    return *std::move(out);
  }
}

// A case taking mlir::Type, or anything built from one, takes every class,
// as a generic case does, so mlir::Type is the probe. A case for several
// classes names them, by a list or by what they share and mlir::Type lacks
// (a type interface they each declare, whose constructor from mlir::Type
// is explicit).
template <class... Ts, class... Fs>
decltype(auto) matchTypes(mlir::Type type, TypeClasses<Ts...>, Fs &&...fs) {
  using C = Cases<std::remove_cvref_t<Fs>...>;
  constexpr bool eachNamed = !std::invocable<C &, mlir::Type>;
  static_assert(eachNamed, "no case of a match takes every type");
  if constexpr (eachNamed) {
    static_assert((std::invocable<C &, Ts> && ...),
                  "a match has a case for every type of the dialect");
    if constexpr ((std::invocable<C &, Ts> && ...)) {
      using R = std::invoke_result_t<C &, Ts...[0]>;
      static_assert((std::same_as<std::invoke_result_t<C &, Ts>, R> && ...),
                    "every case of a match gives one type");
      if constexpr ((std::same_as<std::invoke_result_t<C &, Ts>, R> && ...)) {
        C cases{std::forward<Fs>(fs)...};
        return foldTypes<R>(cases, type, TypeClasses<Ts...>{});
      }
    }
  }
}

} // namespace detail

template <class S>
concept ClosedSum = requires(S &&sum) { detail::asVariant(std::forward<S>(sum)); };

// The fold runs on the sum's variant, `V` as the sum was passed. The probe
// is passed as the sum's alternatives are, so a case is refused exactly
// when it would take an alternative the sum does not yet hold.
template <ClosedSum S, class... Fs>
constexpr decltype(auto) match(S &&sum, Fs &&...fs) {
  using V = decltype(detail::asVariant(std::declval<S>()));
  using C = Cases<std::remove_cvref_t<Fs>...>;
  using Order = std::make_index_sequence<std::variant_size_v<std::remove_cvref_t<V>>>;
  constexpr bool named = !std::invocable<C &, detail::Like<V, detail::Unheld>>;
  static_assert(named, "no case of a match takes every type");
  if constexpr (named) {
    static_assert(detail::handlesEach<C, V>(Order{}), "a match has a case for every alternative");
    if constexpr (detail::handlesEach<C, V>(Order{})) {
      using R = std::invoke_result_t<C &, detail::Alternative<V, 0>>;
      static_assert(detail::givesOne<C, V, R>(Order{}), "every case of a match gives one type");
      if constexpr (detail::givesOne<C, V, R>(Order{})) {
        C cases{std::forward<Fs>(fs)...};
        return detail::fold<R>(cases, detail::asVariant(std::forward<S>(sum)), Order{});
      }
    }
  }
}

// A union of handles is never null where it is matched: each of its
// alternatives is a handle that names something. Its alternatives are
// passed as pointers, and so is the probe.
template <class... PTs, class... Fs>
decltype(auto) match(llvm::PointerUnion<PTs...> handle, Fs &&...fs) {
  using C = Cases<std::remove_cvref_t<Fs>...>;
  constexpr bool named = !std::invocable<C &, detail::Unheld *>;
  static_assert(named, "no case of a match takes every type");
  if constexpr (named) {
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
}

// A type of the dialect, handed to the case of its class. Every class the
// specification generates must have a case, so a class it adds is refused
// at every match that forgot it. The type must be the dialect's.
template <class... Fs>
decltype(auto) match(mlir::Type type, Fs &&...fs) {
  return detail::matchTypes(type, typename detail::Late<DialectTypes, Fs...>::type{},
                            std::forward<Fs>(fs)...);
}

} // namespace idr

#endif // IDR_SUPPORT_MATCH_H
