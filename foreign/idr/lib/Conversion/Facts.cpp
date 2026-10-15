// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
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

// Whether a value of `type` is one pointer to a cell, never empty: a box or
// a string. idr-lower reads these facts after idr-defunctionalize, where
// every closure and suspension is already a box, so the box says it once.
// Static data and live cells alike are 8-aligned and start with an 8-byte
// header. A counted value is not enough: a big's word is a pointer only
// when it is not small, a reuse token is null where its cell was shared,
// and a sum held in place leaves the slots of the other constructors
// empty.
bool isCell(Type type) { return isa<BoxType, StrType>(unrestricted(type)); }

// The attributes of a pointer to a cell.
SmallVector<NamedAttribute> cellFacts(Builder &b) {
  return {b.getNamedAttr(LLVM::LLVMDialect::getNonNullAttrName(), b.getUnitAttr()),
          b.getNamedAttr(LLVM::LLVMDialect::getAlignAttrName(), b.getI64IntegerAttr(8)),
          b.getNamedAttr(LLVM::LLVMDialect::getDereferenceableAttrName(), b.getI64IntegerAttr(8))};
}

// The facts of each component of a value of `type`, in order: a cell's
// pointer, and an unboxed sum's tag, which is below its number of
// constructors.
SmallVector<SmallVector<NamedAttribute>> componentFacts(Type type, bool mayBeNull,
                                                        const Layouts &layouts, Builder &b) {
  SmallVector<SmallVector<NamedAttribute>> facts(layouts.components(type).size());
  if (isCell(type)) {
    if (!mayBeNull)
      facts.front() = cellFacts(b);
    return facts;
  }
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return facts;
  const layout::SumLayout &layout = layouts.sum(data);
  if (!layout.tag)
    return facts;
  unsigned width = layout.tag.getIntOrFloatBitWidth();
  uint64_t count = data.getCtors().size();
  // A tag type that the constructors fill has no range to state.
  if (count != 0 && count < (uint64_t{1} << width))
    facts.front().push_back(b.getNamedAttr(
        LLVM::LLVMDialect::getRangeAttrName(),
        LLVM::ConstantRangeAttr::get(b.getContext(), width, 0, static_cast<int64_t>(count))));
  return facts;
}

} // namespace

Facts::Facts(ProgramOp p) : program(p) {
  MLIRContext *ctx = program.getContext();
  auto mangled = [&](StringRef name) { return StringAttr::get(ctx, mangle(name)); };
  // A label's constructor names its function in the sum's body.
  auto labelFunction = [](DataType data, unsigned tag) {
    const Ctor &ctor = data.getCtor(tag);
    return ctor.role == CtorRole::Label ? ctor.fn : FlatSymbolRefAttr();
  };
  for (auto fn : program->getRegion(0).getOps<idr::FuncOp>())
    signatures[mangled(fn.getSymName())] = fn.getFunctionType();
  program.walk([&](Operation *op) {
    FlatSymbolRefAttr callee;
    OperandRange passed = op->getOperands();
    if (auto call = dyn_cast<idr::CallOp>(op)) {
      callee = call.getCalleeAttr();
    } else if (auto con = dyn_cast<ConOp>(op)) {
      callee = labelFunction(con.getDataType(), con.getTag());
      passed = con.getFields();
    } else if (auto reuse = dyn_cast<ReuseOp>(op)) {
      callee = labelFunction(reuse.getDataType(), reuse.getTag());
      passed = reuse.getFields();
    }
    if (!callee)
      return;
    StringAttr name = mangled(callee.getValue());
    for (auto [index, value] : llvm::enumerate(passed))
      if (value.getDefiningOp<ub::PoisonOp>())
        poisoned.insert({name, static_cast<unsigned>(index)});
  });
}

void Facts::apply(const Layouts &layouts) {
  Builder b(program.getContext());
  for (auto fn : program->getRegion(0).getOps<func::FuncOp>()) {
    auto it = signatures.find(fn.getSymNameAttr());
    if (it == signatures.end())
      continue;
    FunctionType before = it->second;
    unsigned at = 0;
    for (auto [index, type] : llvm::enumerate(before.getInputs())) {
      bool mayBeNull = poisoned.contains({it->first, static_cast<unsigned>(index)});
      for (const SmallVector<NamedAttribute> &facts :
           componentFacts(type, mayBeNull, layouts, b)) {
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
