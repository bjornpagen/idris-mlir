// idr.lower:facts: what idr-lower tells LLVM about the values functions
// take and return, which the types say and the LLVM types no longer do.
module;
// assert is a macro.
#include <cassert>

export module idr.lower:facts;

import idr.mlir;
import idr.dialect;
import idr.layout;

using namespace mlir;

namespace idr::lower {

namespace {

// Whether a value of `type` is one pointer to a cell: a box, a closure or a
// string. Static data and live cells alike are 8-aligned and start with an
// 8-byte header.
bool isCell(Type type) { return isa<BoxType, FnType, LazyType, StrType>(unrestricted(type)); }

// The attributes of a pointer to a cell.
SmallVector<NamedAttribute> cellFacts(Builder &b) {
  return {b.getNamedAttr(LLVM::LLVMDialect::getNonNullAttrName(), b.getUnitAttr()),
          b.getNamedAttr(LLVM::LLVMDialect::getAlignAttrName(), b.getI64IntegerAttr(8)),
          b.getNamedAttr(LLVM::LLVMDialect::getDereferenceableAttrName(), b.getI64IntegerAttr(8))};
}

// The facts of each component of a value of `type`, in order: a cell's
// pointer, and an unboxed sum's tag, which is below its number of
// constructors.
SmallVector<SmallVector<NamedAttribute>>
componentFacts(Type type, bool mayBeNull, layout::Layouts &layouts,
               const llvm::DenseMap<StringAttr, uint64_t> &constructors, Builder &b) {
  SmallVector<SmallVector<NamedAttribute>> facts(layouts.components(type).size());
  if (isCell(type)) {
    if (!mayBeNull)
      facts.front() = cellFacts(b);
    return facts;
  }
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return facts;
  const layout::SumLayout &layout = layouts.sum(data.getName().getAttr());
  if (!layout.tag)
    return facts;
  unsigned width = layout.tag.getIntOrFloatBitWidth();
  uint64_t count = constructors.lookup(data.getName().getAttr());
  // A tag type that the constructors fill has no range to state.
  if (count != 0 && count < (uint64_t{1} << width))
    facts.front().push_back(b.getNamedAttr(
        LLVM::LLVMDialect::getRangeAttrName(),
        LLVM::ConstantRangeAttr::get(b.getContext(), width, 0, static_cast<int64_t>(count))));
  return facts;
}

} // namespace

export class Facts {
public:
  // Reads each function's idr signature, and the parameters some call
  // passes poison, before the conversion takes the types apart. A force
  // calls a memo label's function directly, its captures in order as its
  // parameters, but that call is made by the conversion: before it, the
  // call is the label's constructor, built new or in a reused cell, whose
  // fields are the captures. The memo sum's other two states, running and
  // forced, have no function.
  explicit Facts(ModuleOp m) : module(m) {
    for (auto fn : module.getOps<func::FuncOp>())
      signatures[fn] = fn.getFunctionType();
    DenseSet<StringAttr> memos;
    for (auto data : module.getOps<DataOp>()) {
      constructors[data.getSymNameAttr()] = static_cast<uint64_t>(data.getCtors().size());
      if (isMemo(data))
        memos.insert(data.getSymNameAttr());
    }
    SymbolTable symbols(module);
    module.walk([&](Operation *op) {
      func::FuncOp callee;
      OperandRange passed = op->getOperands();
      SymbolRefAttr label;
      if (auto call = dyn_cast<func::CallOp>(op)) {
        callee = symbols.lookup<func::FuncOp>(call.getCallee());
      } else if (auto con = dyn_cast<ConOp>(op)) {
        label = con.getCtor();
        passed = con.getFields();
      } else if (auto reuse = dyn_cast<ReuseOp>(op)) {
        label = reuse.getCtor();
        passed = reuse.getFields();
      }
      if (label && memos.contains(label.getRootReference()) &&
          label.getLeafReference().getValue() != memoRunning &&
          label.getLeafReference().getValue() != memoForced)
        callee = symbols.lookup<func::FuncOp>(label.getLeafReference());
      if (!callee)
        return;
      for (auto [index, value] : llvm::enumerate(passed))
        if (value.getDefiningOp<ub::PoisonOp>())
          poisoned.insert({callee, static_cast<unsigned>(index)});
    });
  }

  // After the conversion, marks each function's parameters and result:
  //   - a box, a closure or a string is a pointer to a cell, never null,
  //     8-aligned, with at least its 8-byte header to read (`nonnull`,
  //     `align 8`, `dereferenceable(8)`);
  //   - an unboxed sum's tag is in [0, n) for n constructors (`range`).
  // A parameter some call passes poison gets no pointer facts: its poison
  // is lowered to null, which the callee may drop, and a null that is
  // `dereferenceable` is undefined behaviour even if nothing reads it.
  void apply(layout::Layouts &layouts) {
    Builder b(module.getContext());
    for (auto fn : module.getOps<func::FuncOp>()) {
      auto it = signatures.find(fn);
      if (it == signatures.end())
        continue;
      FunctionType before = it->second;
      unsigned at = 0;
      for (auto [index, type] : llvm::enumerate(before.getInputs())) {
        bool mayBeNull = poisoned.contains({fn, static_cast<unsigned>(index)});
        for (const SmallVector<NamedAttribute> &facts :
             componentFacts(type, mayBeNull, layouts, constructors, b)) {
          for (const NamedAttribute &fact : facts)
            fn.setArgAttr(at, fact.getName(), fact.getValue());
          ++at;
        }
      }
      assert(at == fn.getNumArguments() && "the conversion made one parameter per component");
      // A result of several components becomes one struct in LLVM, which
      // takes no such facts.
      if (before.getNumResults() == 1 && fn.getNumResults() == 1 && isCell(before.getResult(0)))
        for (const NamedAttribute &fact : cellFacts(b))
          fn.setResultAttr(0, fact.getName(), fact.getValue());
    }
  }

private:
  ModuleOp module;
  DenseMap<Operation *, FunctionType> signatures;
  DenseSet<std::pair<Operation *, unsigned>> poisoned;
  // How many constructors each data type has, read before the conversion
  // erases the declarations.
  DenseMap<StringAttr, uint64_t> constructors;
};

} // namespace idr::lower
