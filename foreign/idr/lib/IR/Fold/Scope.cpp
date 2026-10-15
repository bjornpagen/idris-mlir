// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime references one fold holds, and the count of the cells it
// leaves live. A big constant is the big its decimal text reads as, and a
// big's constant is the integer its text shows: the functions of
// big.from_str and big.show, so a constant means what the program's own
// conversions make of it. The integer a constant holds is read signed.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/SmallString.h"

using namespace mlir;

namespace idr::fold {

Scope::Scope(MLIRContext *c) : ctx(c), liveAtStart(idris_rt_live_cells()) {}

Scope::~Scope() {
  for (const idris_rt_str *s : strings)
    idris_rt_str_release(s);
  for (idris_rt_big b : bigs)
    idris_rt_big_release(b);
  // What the count gained since the fold began is what it left live. Only
  // the idr dialect's ops and attributes fold, so the dialect is loaded.
  if (auto left = static_cast<int64_t>(idris_rt_live_cells() - liveAtStart))
    ctx->getLoadedDialect<IdrDialect>()->countFoldLeak(left);
}

const idris_rt_str *Scope::str(StringAttr value) {
  return keep(idris_rt_str_from_utf8(value.data(), value.size()));
}

idris_rt_big Scope::big(BigAttr value) {
  llvm::SmallString<32> text;
  value.getValue().toStringSigned(text);
  return keep(runtime<BigFromStrOp>(str(StringAttr::get(ctx, text))));
}

const idris_rt_str *Scope::keep(const idris_rt_str *s) {
  strings.push_back(s);
  return s;
}

idris_rt_big Scope::keep(idris_rt_big b) {
  bigs.push_back(b);
  return b;
}

Attribute Scope::attr(const idris_rt_str *s) {
  keep(s);
  return StringAttr::get(ctx, StringRef(idris_rt_str_bytes(s), s->bytes));
}

Attribute Scope::attr(idris_rt_big b) {
  keep(b);
  const idris_rt_str *shown = keep(runtime<BigShowOp>(b));
  StringRef text(idris_rt_str_bytes(shown), shown->bytes);
  // The bits the text needs read unsigned, and one for the sign, which a
  // positive value's top bit would otherwise be.
  return BigAttr::get(ctx, APInt(APInt::getBitsNeeded(text, 10) + 1, text, 10));
}

} // namespace idr::fold
