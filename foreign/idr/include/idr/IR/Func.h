// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr.func and idr.call hold beyond their generated classes, which
// the specification's attributes and properties name, so it comes before
// them: Idris's proof that a function's own loops end, the bound a
// function puts into a lifetime parameter, where each scoped parameter and
// result lives, what a function gives back, and which part of a
// function's per-parameter record each parameter's type admits. Each part
// exists only where the parameter's type admits it: the record names a
// parameter by its position among the parameters that admit that part, so
// a write part cannot describe a lifetime, nor an amount a value. Last,
// the operands a call's callee writes through, which every reader of a
// call's effects asks. The dialect's inliner rules come first. Each value's
// text and bytecode, and the row's, are hooks the specification declares
// with every other (Generated/Hooks.h.inc), after the classes they name.
//
// It reads types alone (Grades.h, Lifetimes.h), and no op but a call's
// copy of its callee's write part; what a function's body does and the one
// derivation of its row are Analysis/Effects.h's.
#ifndef IDR_IR_FUNC_H
#define IDR_IR_FUNC_H

#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/ValueRange.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <limits>
#include <variant>

namespace idr {

class IdrDialect;

// Every call, op and region of the dialect may be inlined; a return becomes
// the values it gives back, and a lifetime given where a view is asked
// passes as the view it is.
void addInlinerInterface(IdrDialect &dialect);

//===----------------------------------------------------------------------===//
// Termination
//===----------------------------------------------------------------------===//

// Idris proved the function's own loops and recursion end, in the
// component of its call graph with this number.
struct InComponent {
  std::uint32_t component;
  bool operator==(const InComponent &) const = default;
};
// A pass made the function with no loop of its own: it ends wherever no
// cycle of calls reaches it.
struct Acyclic {
  bool operator==(const Acyclic &) const = default;
};
// Idris did not prove the function's loops end.
struct Unproved {
  bool operator==(const Unproved &) const = default;
};

// What `#idr.terminates` holds: a proof, so a function with the attribute
// cannot claim an empty one; a function without it is unproved.
using TerminationProof = std::variant<InComponent, Acyclic>;
// What is known of a function's own loops, the attribute read: what its
// row's divergence starts from.
using Termination = std::variant<Unproved, InComponent, Acyclic>;

llvm::hash_code hash_value(const TerminationProof &proof);

//===----------------------------------------------------------------------===//
// Amounts put into a lifetime
//===----------------------------------------------------------------------===//

// How much a function puts into a lifetime parameter: a bound in bytes, or
// none. Sums saturate at none, so no count can wrap.
class Amount {
public:
  static constexpr Amount finite(std::uint64_t bytes) { return Amount(Finite{bytes}); }
  static constexpr Amount unbounded() { return Amount(Unbounded{}); }

  // Both amounts put, one after the other.
  constexpr Amount plus(Amount other) const {
    return idr::match(
        amount,
        [&](Finite mine) {
          return idr::match(
              other.amount,
              [&](Finite theirs) {
                return theirs.bytes > std::numeric_limits<std::uint64_t>::max() - mine.bytes
                           ? unbounded()
                           : finite(mine.bytes + theirs.bytes);
              },
              [](Unbounded) { return unbounded(); });
        },
        [](Unbounded) { return unbounded(); });
  }
  // Whether this amount stays within `bound`.
  constexpr bool within(Amount bound) const {
    return idr::match(
        bound.amount,
        [&](Finite limit) {
          return idr::match(
              amount, [&](Finite mine) { return mine.bytes <= limit.bytes; },
              [](Unbounded) { return false; });
        },
        [](Unbounded) { return true; });
  }
  // Nothing put at all: what a parameter starts the fold with, and what
  // passing a lifetime to a view puts.
  constexpr bool none() const {
    return idr::match(
        amount, [](Finite mine) { return mine.bytes == 0; }, [](Unbounded) { return false; });
  }

  template <class OnFinite, class OnUnbounded>
  constexpr decltype(auto) fold(OnFinite &&onFinite, OnUnbounded &&onUnbounded) const {
    return idr::match(
        amount, [&](Finite mine) { return onFinite(mine.bytes); },
        [&](Unbounded) { return onUnbounded(); });
  }

  constexpr bool operator==(const Amount &) const = default;

private:
  struct Finite {
    std::uint64_t bytes;
    constexpr bool operator==(const Finite &) const = default;
  };
  struct Unbounded {
    constexpr bool operator==(const Unbounded &) const = default;
  };
  constexpr explicit Amount(std::variant<Finite, Unbounded> amount) : amount(amount) {}

  std::variant<Finite, Unbounded> amount;
};

// One bound of `#idr.put_bounds`: the put parameter at `parameter` among
// the function's put parameters, and its bound in bytes.
struct PutBound {
  std::uint32_t parameter;
  std::uint64_t bytes;
  bool operator==(const PutBound &) const = default;
};

llvm::hash_code hash_value(const PutBound &bound);

//===----------------------------------------------------------------------===//
// Where scoped values live
//===----------------------------------------------------------------------===//

// A scoped parameter or result at `value`, and the lifetime parameter at
// `lifetime` it lives in, both positions in the signature: `2 in 0`.
struct LivesIn {
  std::uint32_t value;
  std::uint32_t lifetime;
  bool operator==(const LivesIn &) const = default;
};

// The lifetime parameter at `longer` lives at least as long as the one at
// `shorter`: `0 >= 1`.
struct Outlives {
  std::uint32_t longer;
  std::uint32_t shorter;
  bool operator==(const Outlives &) const = default;
};

llvm::hash_code hash_value(const LivesIn &entry);
llvm::hash_code hash_value(const Outlives &bound);

//===----------------------------------------------------------------------===//
// What a function gives back
//===----------------------------------------------------------------------===//

// A component of a result or of the arguments: the value at `index`, then
// down through `fields`, each a field of a constructor its type lays out
// inline. A view: the attribute owns what it holds, and whoever builds one
// owns the fields until the attribute copies them.
struct GivenBackPath {
  std::uint32_t index;
  llvm::ArrayRef<std::uint32_t> fields;
  bool operator==(const GivenBackPath &other) const {
    return index == other.index && fields == other.fields;
  }
  // The order entries are listed in: by position, then field by field.
  bool operator<(const GivenBackPath &other) const {
    if (index != other.index)
      return index < other.index;
    return std::lexicographical_compare(fields.begin(), fields.end(), other.fields.begin(),
                                        other.fields.end());
  }
};

// On every path that returns, component `result` of the result is
// component `argument` of the arguments: the same value.
struct GivenBackEntry {
  GivenBackPath result;
  GivenBackPath argument;
  bool operator==(const GivenBackEntry &) const = default;
};

//===----------------------------------------------------------------------===//
// The record's parts, by parameter
//===----------------------------------------------------------------------===//

// Whether a parameter of `type` admits a write part: a value freed by its
// count whose holder alone reaches what a write in place touches, its own
// family's cells or everything it reaches. Rebuilding in place writes only
// the family's cells, which the spine's claim covers. Whether it admits an
// amount is whether it is a lifetime something may be put into
// (admitsPuts).
bool admitsWrite(mlir::Type type);

// The part a parameter's type admits, with its position among the
// parameters that admit that part.
struct WritePart {
  std::uint32_t position;
};
struct PutPart {
  std::uint32_t position;
};
struct NoPart {};
using RecordPart = std::variant<WritePart, PutPart, NoPart>;

// A signature's parameters by the part each admits, read off their types
// once: the coordinates of a function's record and of a call's copy of its
// write part, which name a parameter by its position among its kind.
class ParameterParts {
public:
  explicit ParameterParts(mlir::TypeRange parameters);

  const RecordPart &operator[](unsigned parameter) const { return parts[parameter]; }
  unsigned size() const { return parts.size(); }
  std::uint32_t writable() const { return writes; }
  std::uint32_t puttable() const { return puts; }

private:
  llvm::SmallVector<RecordPart, 8> parts;
  std::uint32_t writes = 0;
  std::uint32_t puts = 0;
};

//===----------------------------------------------------------------------===//
// A call's write part
//===----------------------------------------------------------------------===//

// A call holding its copy of its callee's write part: its arguments, and
// the positions, among those that admit a write part, its callee never
// writes through, increasing.
template <class C>
concept HoldsWritePart = requires(C call) {
  { call.getArgsMutable() } -> std::convertible_to<mlir::MutableOperandRange>;
  { call.getUntouchedAttr() } -> std::convertible_to<mlir::DenseI32ArrayAttr>;
};

// Each operand of `call` its callee writes through: every operand that
// admits a write part and is not listed untouched. The operands come in
// order and the untouched positions increase, so one pass meets both. It
// takes the call as a template parameter, not as a member of idr.call,
// since this header comes before the op classes: every reader of a call's
// effects, the generated ones among them, sees it here.
template <HoldsWritePart C, std::invocable<mlir::OpOperand &> Visit>
void forEachWritten(C call, Visit &&visit) {
  llvm::ArrayRef<std::int32_t> untouched;
  if (mlir::DenseI32ArrayAttr listed = call.getUntouchedAttr())
    untouched = listed.asArrayRef();
  std::int32_t position = 0;
  for (mlir::OpOperand &operand : call.getArgsMutable()) {
    if (!admitsWrite(operand.get().getType()))
      continue;
    if (!untouched.empty() && untouched.front() == position)
      untouched = untouched.drop_front();
    else
      visit(operand);
    ++position;
  }
}

} // namespace idr

#endif // IDR_IR_FUNC_H
