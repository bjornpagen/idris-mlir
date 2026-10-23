// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a constant value is laid out as static data, the answer of
// ConstantAttrInterface::getStaticForm for an attribute of ours and of
// idr::staticFormOf for any constant: a closed sum, which each writer of
// static data folds with `match`, so a form it gains is refused at every
// writer that forgot it. Included by the dialect's header after the
// attributes and types its alternatives hold.
#ifndef IDR_IR_INTERFACES_STATICFORM_H
#define IDR_IR_INTERFACES_STATICFORM_H

#include "mlir/IR/BuiltinAttributeInterfaces.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <variant>

namespace idr {

namespace static_form {
// A string's bytes, at the string's own datum.
struct Text {
  llvm::StringRef bytes;
};
// An Integer or a natural, at a big's datum or in its word.
struct Big {
  BigAttr value;
};
// A numeral, its value at its place: a word of its layout's width, or a
// natural where its place is laid out as one.
struct Numeral {
  DataType place;
  std::uint64_t value;
};
// An integer or a Double, its own type's literal.
struct Word {
  mlir::TypedAttr literal;
};
// Poison, which stands for a cell pointer only.
struct Nothing {};
// A constructor of a family laid out in place: its fields, in its words.
struct InPlace {
  ConAttr con;
};
// A constructor in a cell of its own. A closure reaches static data only as
// its label's constructor, defunctionalization having rewritten it.
struct Cell {
  ConAttr con;
};
} // namespace static_form

struct StaticForm
    : std::variant<static_form::Text, static_form::Big, static_form::Numeral, static_form::Word,
                   static_form::Nothing, static_form::InPlace, static_form::Cell> {
  using variant::variant;
};

// How `value`, held at `held`, is laid out as static data: an attribute of
// ours answers through ConstantAttrInterface, and the upstream attributes a
// constant holds are classified here, the one place they are named.
StaticForm staticFormOf(mlir::Attribute value, mlir::Type held);

} // namespace idr

#endif // IDR_IR_INTERFACES_STATICFORM_H
