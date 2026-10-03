// idr.specialize:parameterattrs: the attributes of a clone's parameter:
// the hole of the key it holds.
export module idr.specialize:parameterattrs;

import idr.mlir;

import :clones;

using namespace mlir;

export namespace idr::specialize {

// `from`, the attributes of a parameter of a clone, now holding `hole`.
mlir::DictionaryAttr parameterAttrs(mlir::MLIRContext *ctx, unsigned hole,
                                    mlir::DictionaryAttr from = {}) {
  NamedAttrList list(from);
  list.set(kHoleAttr, IntegerAttr::get(IntegerType::get(ctx, 64), hole));
  return list.getDictionary(ctx);
}

} // namespace idr::specialize
