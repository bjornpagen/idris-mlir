// idr.ops:inliner: the inliner's rules for the dialect's ops, which the
// dialect registers when it is initialized.
export module idr.ops:inliner;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

// Every idr op may be inlined anywhere.
struct IdrInliner : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;
  bool isLegalToInline(Operation *, Region *, bool, IRMapping &) const final { return true; }
  bool isLegalToInline(Region *, Region *, bool, IRMapping &) const final {
    return true;
  }
};

} // namespace

export namespace idr::ops {

// Registers the inliner's rules for the dialect's ops.
void addInlinerInterface(IdrDialect &dialect) { dialect.addInterfaces<IdrInliner>(); }

} // namespace idr::ops
