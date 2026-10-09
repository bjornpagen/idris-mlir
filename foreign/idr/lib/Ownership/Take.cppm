// idr.ownership:take: taking a box apart where it dies.
export module idr.ownership:take;

import idr.mlir;
import idr.dialect;

import :fields;

using namespace mlir;

namespace idr::ownership {

// Takes the box `box`, built by `ctor`, apart at `at` in `block`: an
// idr.take whose fields replace the reads of the box's fields after that
// point, the arguments of `fields` (the case region that bound them, when
// one did) and idr.field, so that a field read after the box dies keeps the
// box's reference instead of taking one of its own where the box reads it,
// only for the box to drop it again. Reads before the take are borrowed
// from the box, which is still alive there.
export TakeOp takeAt(Value box, CtorOp ctor, Block &block, Block::iterator at, Block *fields) {
  OpBuilder b(&block, at);
  Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
  auto name = SymbolRefAttr::get(ctor->getParentOfType<DataOp>().getSymNameAttr(),
                                 {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  SymbolTableCollection symbols;
  Operation *scope = block.getParentOp();
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (!ctor.getFieldTypes().empty())
    results.push_back(owned(TokenType::get(ctor.getContext())));
  for (unsigned index = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); index < e;
       ++index) {
    Type field = fieldType(box.getType(), ctor.getFieldType(index));
    results.push_back(holdsReferences(field, symbols, scope) ? owned(field) : field);
  }
  auto take = TakeOp::create(b, loc, results, box, name);
  eachField(box, ctor, fields, [&](Value field, unsigned index) {
    field.replaceUsesWithIf(take.getFields()[index],
                            [&](OpOperand &use) { return fromPoint(block, at, use); });
  });
  return take;
}

} // namespace idr::ownership
