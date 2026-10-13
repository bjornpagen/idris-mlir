// What idr-lower tells LLVM about the values functions take and return.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Facts.h"
#include "idr/Conversion/Mangle.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;

namespace idr::conversion {

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
componentFacts(Type type, bool mayBeNull, const Layouts &layouts,
               const DenseMap<StringAttr, uint64_t> &constructors, Builder &b) {
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

Facts::Facts(ModuleOp m, SymbolTable &symbols) : module(m) {
  MLIRContext *ctx = module.getContext();
  // Each function's name as LLVM will have it, mangled once.
  DenseMap<Operation *, StringAttr> mangled;
  for (auto fn : module.getOps<idr::FuncOp>()) {
    StringAttr name = StringAttr::get(ctx, mangle(fn.getSymName()));
    mangled[fn] = name;
    signatures[name] = fn.getFunctionType();
  }
  DenseSet<StringAttr> memos;
  for (auto data : module.getOps<DataOp>()) {
    constructors[data.getSymNameAttr()] = static_cast<uint64_t>(data.getCtors().size());
    if (isMemo(data))
      memos.insert(data.getSymNameAttr());
  }
  module.walk([&](Operation *op) {
    idr::FuncOp callee;
    OperandRange passed = op->getOperands();
    SymbolRefAttr label;
    if (auto call = dyn_cast<idr::CallOp>(op)) {
      callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
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
      callee = symbols.lookup<idr::FuncOp>(label.getLeafReference());
    if (!callee)
      return;
    StringAttr name = mangled.lookup(callee);
    for (auto [index, value] : llvm::enumerate(passed))
      if (value.getDefiningOp<ub::PoisonOp>())
        poisoned.insert({name, static_cast<unsigned>(index)});
  });
}

void Facts::apply(const Layouts &layouts) {
  Builder b(module.getContext());
  for (auto fn : module.getOps<func::FuncOp>()) {
    auto it = signatures.find(fn.getSymNameAttr());
    if (it == signatures.end())
      continue;
    FunctionType before = it->second;
    unsigned at = 0;
    for (auto [index, type] : llvm::enumerate(before.getInputs())) {
      bool mayBeNull = poisoned.contains({it->first, static_cast<unsigned>(index)});
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

} // namespace idr::conversion
