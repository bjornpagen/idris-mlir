// idr.specialize:rebuild: rebuilding the value a pattern stands for.
export module idr.specialize:rebuild;

import idr.mlir;
import idr.dialect;

import :pattern;

using namespace mlir;

export namespace idr::specialize {

// The value `pattern` stands for, rebuilt at `b`, each hole taken from
// `holes` by its number.
mlir::Value rebuild(mlir::OpBuilder &b, const Pattern &pattern,
                    llvm::ArrayRef<mlir::Value> holes) {
  Location loc(pattern.loc);
  auto rebuildAll = [&](const std::vector<Pattern> &parts) {
    SmallVector<Value> values;
    for (const Pattern &part : parts)
      values.push_back(rebuild(b, part, holes));
    return values;
  };
  return std::visit(
      Match{[&](const Hole &hole) { return holes[hole.index]; },
            [&](const Constant &c) -> Value {
              // shapeOf() took the constant from a constant op of this type.
              Dialect *idr = b.getContext()->getLoadedDialect<IdrDialect>();
              return idr->materializeConstant(b, c.value, pattern.type, loc)->getResult(0);
            },
            [&](const Con &con) -> Value {
              return ConOp::create(b, loc, pattern.type, con.ctor, rebuildAll(con.fields));
            },
            [&](const Closure &closure) -> Value {
              return ClosureOp::create(b, loc, pattern.type, closure.callee,
                                       rebuildAll(closure.captures));
            },
            [&](const Linear &linear) -> Value {
              return LinEnterOp::create(b, loc, pattern.type,
                                        rebuild(b, linear.value.front(), holes));
            }},
      pattern.node);
}

} // namespace idr::specialize
