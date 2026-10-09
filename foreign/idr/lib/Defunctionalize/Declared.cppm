// idr.defunctionalize:declared: the type of every slot as decided, and the
// sums declared for the converted keys.
export module idr.defunctionalize:declared;

import idr.mlir;
import idr.dialect;

import :closures;
import :decided;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

struct Declared : Decided {
  using Decided::Decided;

  Type sumOf(const Key &key) {
    return isConverted(key) ? keys.lookup(key) : Type();
  }

  // The type of a slot of `key`: its sum, or the closure type unchanged.
  Type typeOf(const Key &key) {
    if (Type sum = sumOf(key))
      return sum;
    return key.first;
  }

  // The type of a slot of `key` whose type was `type`: its sum or closure
  // type, linear when `type` is. A slot no key covers keeps its type, but
  // for the elements of the arrays in it, which are slots of their own.
  Type typeOf(Type type, const Key &key) {
    if (!key.first)
      return arrayed(type);
    Type slot = typeOf(key);
    return idr::isLinear(type) ? idr::linear(slot) : slot;
  }

  // `type` with the element type of each array in it retyped by the key of
  // its elements, at its grade.
  Type arrayed(Type type) {
    auto array = dyn_cast<MemRefType>(idr::unrestricted(type));
    if (!array || !idr::isArray(array))
      return type;
    Type element = array.getElementType();
    Type now = typeOf(element, elements(array));
    if (now == element)
      return type;
    return idr::graded(idr::gradeOf(type), MemRefType::get(array.getShape(), now,
                                                           array.getLayout(),
                                                           array.getMemorySpace()));
  }

  // The types of the captures of `label` as a closure or suspension of
  // `type`, as converted.
  ArrayRef<Type> captureTypes(StringAttr label, Type type) {
    return module.function(label).getArgumentTypes().drop_back(arity(type));
  }

  // The type of the value a cell of lazy key `key` holds once forced, as
  // converted: what each of its labels returns.
  Type forcedType(const Key &key) {
    return typeOf(cast<idr::LazyType>(key.first).getValue(), forced(key));
  }

  void retype() {
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>()) {
      SmallVector<Type> inputs, outputs;
      for (auto [i, type] : llvm::enumerate(fn.getArgumentTypes()))
        inputs.push_back(typeOf(type, argument(fn, static_cast<unsigned>(i))));
      for (auto [i, type] : llvm::enumerate(fn.getResultTypes()))
        outputs.push_back(typeOf(type, result(fn, static_cast<unsigned>(i))));
      fn.setFunctionType(FunctionType::get(ctx, inputs, outputs));
    }
    // Every value: those of slots by their keys, and every other one for
    // the arrays in its type.
    auto slot = [&](Value value) { value.setType(typeOf(value.getType(), values.lookup(value))); };
    module.op.walk([&](Operation *op) {
      llvm::for_each(op->getResults(), slot);
      for (Region &region : op->getRegions())
        for (Block &block : region)
          llvm::for_each(block.getArguments(), slot);
    });
    module.op.walk([&](idr::CtorOp ctor) {
      auto data = ctor->getParentOfType<idr::DataOp>().getSymNameAttr();
      SmallVector<Type> types;
      for (auto [i, type] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        types.push_back(typeOf(type, fields.lookup({data, ctor.getSymNameAttr(), unsigned(i)})));
      ctor.setFieldTypesAttr(Builder(ctx).getTypeArrayAttr(types));
    });
  }

  // A sum of closures has a constructor per label, whose fields are its
  // captures. A memo sum has one too, and then the states a force writes
  // its cell into: `running` while a label runs, and `forced` with the
  // value. Its `labels` names the label functions where the module resolves
  // them: nothing else uses a label's function once its suspensions are
  // constructors, and a function nothing uses is dead to every analysis.
  void declareSums(OpBuilder &b) {
    b.setInsertionPointToStart(module.op.getBody());
    for (auto &[key, sum] : keys) {
      if (!sum)
        continue;
      StringAttr name = idr::getSumName(sum).getAttr();
      bool memo = isLazy(key);
      SmallVector<Attribute> labels;
      for (auto label : key.second.getAsRange<StringAttr>())
        labels.push_back(FlatSymbolRefAttr::get(label));
      auto data = idr::DataOp::create(b, module.op.getLoc(), name,
                                      isa<idr::BoxType>(sum) ? b.getUnitAttr() : UnitAttr(),
                                      memo ? UnitAttr() : b.getUnitAttr(),
                                      memo ? b.getUnitAttr() : UnitAttr(),
                                      memo ? b.getArrayAttr(labels) : ArrayAttr());
      OpBuilder inner = OpBuilder::atBlockEnd(&data.getBody().emplaceBlock());
      for (auto label : key.second.getAsRange<StringAttr>()) {
        func::FuncOp fn = module.function(label);
        // The captures' types carry their quantities into the fields.
        ArrayRef<Type> types = captureTypes(label, key.first);
        idr::CtorOp::create(inner, fn.getLoc(), label, b.getTypeArrayAttr(types), UnitAttr());
      }
      if (!memo)
        continue;
      idr::CtorOp::create(inner, module.op.getLoc(), b.getStringAttr(idr::memoRunning),
                          b.getTypeArrayAttr(TypeRange()), UnitAttr());
      idr::CtorOp::create(inner, module.op.getLoc(), b.getStringAttr(idr::memoForced),
                          b.getTypeArrayAttr({forcedType(key)}), UnitAttr());
    }
  }
};

} // namespace idr::defunctionalize
