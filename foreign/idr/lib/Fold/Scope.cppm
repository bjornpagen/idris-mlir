// idr.fold:scope: the runtime references one fold holds.
module;
// The runtime's C ABI: its strings and bigs.
#include "idris_rt.h"

export module idr.fold:scope;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::fold {

// The owned references one fold holds, released together when it ends.
// Every runtime operation returns an owned reference, even when what it
// returns is one of its arguments (appending the empty string gives the
// other argument, with one more reference), so the scope keeps every
// reference it is given, a repeated one as often as it was given, and
// releases each once; and counts on the context the cells it leaves live,
// read on the thread that folds: the runtime counts by thread, and a fold
// never changes thread. Scopes do not nest on one thread; a nested pair
// would count an inner leak twice.
class Scope {
public:
  explicit Scope(mlir::MLIRContext *c);
  ~Scope();
  Scope(const Scope &) = delete;
  Scope &operator=(const Scope &) = delete;

  const idris_rt_str *str(mlir::StringAttr value);
  idris_rt_big big(BigAttr value);
  const idris_rt_str *keep(const idris_rt_str *s);
  idris_rt_big keep(idris_rt_big b);
  mlir::Attribute attr(const idris_rt_str *s);
  mlir::Attribute attr(idris_rt_big b);

private:
  mlir::MLIRContext *ctx;
  uint64_t liveAtStart;
  llvm::SmallVector<const idris_rt_str *> strings;
  llvm::SmallVector<idris_rt_big> bigs;
};

} // namespace idr::fold

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
