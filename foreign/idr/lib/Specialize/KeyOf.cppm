// idr.specialize:keyof: a pattern as a key.
export module idr.specialize:keyof;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

namespace idr::specialize {

namespace {

// A constant as a key: constructors and closures as the nodes they fold
// from. Each shared part is keyed once, in `keys`. A run is keyed as the
// constructors it stands for, from its tail back to its first cell, so that
// each cell is read once.
Attribute keyOfConstant(Attribute value, llvm::DenseMap<Attribute, Attribute> &keys) {
  if (Attribute known = keys.lookup(value))
    return known;
  MLIRContext *ctx = value.getContext();
  auto keysOf = [&](ArrayAttr parts) {
    return llvm::map_to_vector(parts, [&](Attribute part) { return keyOfConstant(part, keys); });
  };
  Attribute key = value;
  if (auto con = dyn_cast<ConAttr>(value)) {
    StringAttr data = con.getCtor().getRootReference();
    StringAttr ctor = con.getCtor().getLeafReference();
    if (!con.isRun()) {
      key = KeyConAttr::get(ctx, data, ctor, ArrayAttr::get(ctx, keysOf(con.getFields())));
    } else {
      key = keyOfConstant(con.getTail(), keys);
      for (ArrayAttr cell : llvm::reverse(con.getRunCells())) {
        auto fields = keysOf(cell);
        fields.insert(fields.begin() + con.getSpine(), key);
        key = KeyConAttr::get(ctx, data, ctor, ArrayAttr::get(ctx, fields));
      }
    }
  } else if (auto closure = dyn_cast<ClosureAttr>(value)) {
    key = KeyClosureAttr::get(ctx, closure.getCallee().getAttr(),
                              ArrayAttr::get(ctx, keysOf(closure.getCaptures())));
  }
  return keys[value] = key;
}

Attribute keyOfConstant(Attribute value) {
  llvm::DenseMap<Attribute, Attribute> keys;
  return keyOfConstant(value, keys);
}

} // namespace

} // namespace idr::specialize

export namespace idr::specialize {

// The pattern as a key: a typed attribute, whose labels are names and not
// symbol uses, so that a key keeps no function alive. A constructor or
// closure constant is keyed as the node it folds from, so that both key the
// same clone.
mlir::Attribute keyOf(const Pattern &pattern) {
  MLIRContext *ctx = pattern.type.getContext();
  auto keysOf = [&](const std::vector<Pattern> &parts) {
    return ArrayAttr::get(ctx, llvm::map_to_vector(parts, [](const Pattern &part) {
                            return keyOf(part);
                          }));
  };
  return std::visit(
      Match{[&](const Hole &hole) -> Attribute { return KeyHoleAttr::get(ctx, hole.index); },
            [](const Constant &c) { return keyOfConstant(c.value); },
            [&](const Con &con) -> Attribute {
              return KeyConAttr::get(ctx, con.ctor.getRootReference(),
                                     con.ctor.getLeafReference(), keysOf(con.fields));
            },
            [&](const Closure &closure) -> Attribute {
              return KeyClosureAttr::get(ctx, closure.callee.getAttr(), keysOf(closure.captures));
            },
            // The type of the position says the value is linear.
            [](const Linear &linear) { return keyOf(linear.value.front()); }},
      pattern.node);
}

} // namespace idr::specialize
