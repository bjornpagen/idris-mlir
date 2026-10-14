// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime references one fold holds, and the count of the cells it
// leaves live.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "idris_rt.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"

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
  return keep(idris_rt_big_from_str(str(StringAttr::get(ctx, value.getValue()))));
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
  const idris_rt_str *text = keep(idris_rt_big_show(b));
  return BigAttr::get(ctx, StringRef(idris_rt_str_bytes(text), text->bytes));
}

} // namespace idr::fold
