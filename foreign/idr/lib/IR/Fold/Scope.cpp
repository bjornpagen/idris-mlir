// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime references one fold holds, and the strings and bigs a fold
// converts. A big constant is the big its decimal text reads as, and a
// big's constant is the integer its text shows: the functions of
// big.from_str and big.show, so a constant means what the program's own
// conversions make of it. The text goes to the runtime as bytes, never as
// an attribute made for the fold.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/SmallString.h"

using namespace mlir;

namespace idr::fold {

// Each reference is released by the runtime's entry of its word's kind: a
// string's word is always its cell, a big's a small or a cell. A string's
// bytes are immutable; its count is the one word a release writes.
Scope::~Scope() {
  for (const idris_rt_str *s : strings)
    idris_rt_dec_cell(const_cast<idris_rt_str *>(s));
  for (idris_rt_big b : bigs)
    idris_rt_dec_big(b);
}

const idris_rt_str *Scope::keep(const idris_rt_str *s) {
  strings.push_back(s);
  return s;
}

idris_rt_big Scope::keep(idris_rt_big b) {
  bigs.push_back(b);
  return b;
}

std::optional<const idris_rt_str *> strOf(Scope &scope, Attribute constant) {
  auto text = dyn_cast_or_null<StringAttr>(constant);
  if (!text)
    return std::nullopt;
  return scope.keep(idris_rt_str_from_utf8(text.data(), text.size()));
}

std::optional<idris_rt_big> bigOf(Scope &scope, Attribute constant) {
  auto big = dyn_cast_or_null<BigAttr>(constant);
  if (!big)
    return std::nullopt;
  llvm::SmallString<32> text;
  big.getValue().toStringSigned(text);
  const idris_rt_str *s = scope.keep(idris_rt_str_from_utf8(text.data(), text.size()));
  return scope.keep(runtime::Abi<BigFromStrOp>::function(s));
}

Attribute strAttr(Scope &scope, const idris_rt_str *s) {
  scope.keep(s);
  return StringAttr::get(scope.context(), StringRef(idris_rt_str_bytes(s), s->bytes));
}

Attribute bigAttr(Scope &scope, idris_rt_big b) {
  scope.keep(b);
  const idris_rt_str *shown = scope.keep(runtime::Abi<BigShowOp>::function(b));
  StringRef text(idris_rt_str_bytes(shown), shown->bytes);
  // The bits the text needs read unsigned, and one for the sign, which a
  // positive value's top bit would otherwise be.
  return BigAttr::get(scope.context(), APInt(APInt::getBitsNeeded(text, 10) + 1, text, 10));
}

} // namespace idr::fold
