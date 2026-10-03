// idr.ownership:counting: which types hold references.
export module idr.ownership:counting;

import idr.mlir;
import idr.dialect;

import :isstatic;

using namespace mlir;

namespace idr::ownership {

// Which types hold references. An unboxed sum does when a field of one of
// its constructors does; the answers are computed once per module.
export class Counting {
public:
  explicit Counting(Operation *module) : module(module) {}

  bool counted(Type type) {
    // A linear value is counted as the value it is; its quantity decides
    // only how it is used.
    type = unrestricted(type);
    if (isa<StrType, BigType, NatType, BoxType, FnType, TokenType>(type) || isArray(type))
      return true;
    auto data = dyn_cast<DataType>(type);
    if (!data)
      return false;
    if (datas.empty())
      for (Region &region : module->getRegions())
        for (Block &block : region)
          for (auto decl : block.getOps<DataOp>())
            datas[decl.getSymNameAttr()] = decl;
    Attribute name = data.getName().getAttr();
    auto known = sums.find(name);
    if (known != sums.end())
      return known->second;
    // Containment through unboxed sums is acyclic; the provisional answer
    // only guards a module the verifier has yet to reject.
    sums[name] = false;
    DataOp decl = datas.lookup(name);
    bool any = false;
    if (decl)
      for (CtorOp ctor : decl.getCtors())
        for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
          any = any || counted(field);
    sums[name] = any;
    return any;
  }

  // Whether `value` holds references: its type does, and it is not static.
  bool tracked(Value value) { return counted(value.getType()) && !isStatic(value); }

private:
  Operation *module;
  llvm::DenseMap<Attribute, DataOp> datas;
  llvm::DenseMap<Attribute, bool> sums;
};

} // namespace idr::ownership
