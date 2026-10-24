// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions as idr-lower calls them, the crashes it reports
// through them, and counting by the kind of each word; a constant's
// components are StaticData.cpp's, and the reads and writes of a cell
// RuntimeCells.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <cstddef>

using namespace mlir;

namespace idr::conversion {

namespace {

using idr::runtime::OperandKind;
using idr::runtime::ResultKind;

// The LLVM type of a value of the kind `kind`. Each kind is one C type, so
// a parameter and a result of one kind are one LLVM type.
Type llvmType(MLIRContext *ctx, OperandKind kind) {
  using enum OperandKind;
  switch (kind) {
  case Int32:
    return IntegerType::get(ctx, 32);
  case UInt8:
    return IntegerType::get(ctx, 8);
  case Int64:
  case Signed:
  case Unsigned:
  case Big:
    return IntegerType::get(ctx, 64);
  case Double:
    return Float64Type::get(ctx);
  case Str:
  case Buffer:
  case Pointer:
    return LLVM::LLVMPointerType::get(ctx);
  }
}

// A function that gives nothing back, or never returns, is void.
Type llvmType(MLIRContext *ctx, ResultKind kind) {
  using enum ResultKind;
  switch (kind) {
  case Void:
  case NoReturn:
    return LLVM::LLVMVoidType::get(ctx);
  case Int32:
  case Order:
    return IntegerType::get(ctx, 32);
  case Bool:
    return IntegerType::get(ctx, 1);
  case Int64:
  case Wrapped:
  case Big:
    return IntegerType::get(ctx, 64);
  case Double:
    return Float64Type::get(ctx);
  case Str:
  case Pointer:
    return LLVM::LLVMPointerType::get(ctx);
  }
}

// The counted kinds of word are Word's cases after its first, Uncounted,
// which no entry counts, in the order the generated tables of the counting
// entries hold them, both printed from the specification's one list of the
// kinds; each kind's entry tests exactly what the kind leaves open.
static_assert(static_cast<std::size_t>(layout::Word::Uncounted) == 0 &&
              idr::runtime::increments.size() + 1 == EnumTraits<layout::Word>::count &&
              idr::runtime::decrements.size() + 1 == EnumTraits<layout::Word>::count);

// The entry of `entries`, one of those tables, for a counted word of kind
// `word`: at the kind's place past Uncounted.
const idr::runtime::Function &countingEntry(ArrayRef<const idr::runtime::Function *> entries,
                                            layout::Word word) {
  assert(word != layout::Word::Uncounted && "an uncounted word has no counting entry");
  return *entries[static_cast<std::size_t>(word) - 1];
}

} // namespace

LLVM::LLVMFunctionType runtimeFunctionType(MLIRContext *ctx,
                                           const idr::runtime::Function &function) {
  SmallVector<Type> params;
  for (OperandKind kind : function.operands)
    params.push_back(llvmType(ctx, kind));
  return LLVM::LLVMFunctionType::get(llvmType(ctx, function.result), params);
}

// Detached: idr-lower's serial phase inserts it, once per function of the
// table. A byte argument and a truth result are narrower than an int, which
// a caller widens where the target's C convention asks it to:
// zero-extended, as the C compiler says of the definition, and LLVM applies
// the target's rule.
LLVM::LLVMFuncOp runtimeDeclaration(Location loc, const idr::runtime::Function &function) {
  OpBuilder b(loc.getContext());
  auto callee = LLVM::LLVMFuncOp::create(b, loc, StringRef(function.symbol),
                                         runtimeFunctionType(loc.getContext(), function));
  for (auto [index, kind] : llvm::enumerate(function.operands))
    if (kind == OperandKind::UInt8)
      callee.setArgAttr(static_cast<unsigned>(index), LLVM::LLVMDialect::getZExtAttrName(),
                        b.getUnitAttr());
  if (function.result == ResultKind::Bool)
    callee.setResultAttr(0, LLVM::LLVMDialect::getZExtAttrName(), b.getUnitAttr());
  if (function.result == ResultKind::NoReturn)
    callee.setNoreturn(true);
  return callee;
}

HeaderLayout HeaderLayout::of(const Layouts &layouts, MLIRContext *ctx) {
  unsigned word = layouts.sizeOf(IntegerType::get(ctx, 32));
  return {/*countAt=*/0, /*infoAt=*/word, /*bytes=*/2 * word};
}

// The converter reads no data layout of its own: the options carry what it
// needs, and a query of the shared layout would fill its caches.
Runtime::Runtime(MLIRContext *ctx, const Layouts &l, const Statics &statics,
                 const LowerToLLVMOptions &options)
    : layouts(l), staticData(statics), llvmTypes(ctx, options, /*analysis=*/nullptr),
      headerLayout(HeaderLayout::of(l, ctx)) {}

LLVM::CallOp Runtime::call(OpBuilder &b, Location loc, const idr::runtime::Function &function,
                           ValueRange args) const {
  auto made = LLVM::CallOp::create(b, loc, runtimeFunctionType(b.getContext(), function),
                                   StringRef(function.symbol), args);
  if (function.result == ResultKind::NoReturn)
    made.setNoreturn(true);
  return made;
}

LLVM::CallOp Runtime::call(OpBuilder &b, Operation *op, const idr::runtime::Function &function,
                           ArrayRef<ValueRange> operands) const {
  Location loc = op->getLoc();
  Type i64 = b.getI64Type();
  SmallVector<Value> args;
  for (auto [kind, components] : llvm::zip_equal(function.operands, operands)) {
    Value value = components.front();
    // An integer of the op's width, which is 64 bits already or is
    // extended to them by its signedness.
    if ((kind == OperandKind::Signed || kind == OperandKind::Unsigned) && value.getType() != i64)
      value = kind == OperandKind::Signed ? Value(arith::ExtSIOp::create(b, loc, i64, value))
                                          : Value(arith::ExtUIOp::create(b, loc, i64, value));
    args.push_back(value);
  }
  return call(b, loc, function, args);
}

SmallVector<Value, 4> Runtime::siteOperands(OpBuilder &b, Location loc, SiteAttr site) const {
  SiteTexts texts = staticData.site(site);
  return {staticAddress(b, loc, texts.function), staticAddress(b, loc, texts.file),
          i32Constant(b, loc, static_cast<int64_t>(site.getLine())),
          i32Constant(b, loc, static_cast<int64_t>(site.getColumn()))};
}

// The call is cold, and so what leads only to it: LLVM lays the crash
// checks out of the way of the paths that run.
void Runtime::crash(OpBuilder &b, Location loc, CrashCause cause, SiteAttr site) const {
  SmallVector<Value> args{i32Constant(b, loc, static_cast<int64_t>(cause))};
  llvm::append_range(args, siteOperands(b, loc, site));
  call(b, loc, idr::runtime::helper::crashAt, args).setCold(true);
}

void Runtime::crashWith(OpBuilder &b, Location loc, Value message, SiteAttr site) const {
  SmallVector<Value> args{message};
  llvm::append_range(args, siteOperands(b, loc, site));
  call(b, loc, idr::runtime::helper::crashMessageAt, args).setCold(true);
}

void Runtime::crashIf(OpBuilder &b, Location loc, Value condition, CrashCause cause,
                      SiteAttr site) const {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  crash(b, loc, cause, site);
}

void Runtime::outOfMemoryIf(OpBuilder &b, Location loc, Value condition) const {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  call(b, loc, idr::runtime::helper::outOfMemory, ValueRange{}).setCold(true);
}

void Runtime::inc(OpBuilder &b, Location loc, ArrayRef<layout::Component> components,
                  ValueRange values) const {
  for (auto [component, value] : llvm::zip_equal(components, values))
    if (component.word != layout::Word::Uncounted)
      inc(b, loc, component.word, value);
}

void Runtime::dec(OpBuilder &b, Location loc, ArrayRef<layout::Component> components,
                  ValueRange values) const {
  for (auto [component, value] : llvm::zip_equal(components, values))
    if (component.word != layout::Word::Uncounted)
      dec(b, loc, component.word, value);
}

void Runtime::inc(OpBuilder &b, Location loc, layout::Word word, Value value) const {
  call(b, loc, countingEntry(idr::runtime::increments, word), value);
}

void Runtime::dec(OpBuilder &b, Location loc, layout::Word word, Value value) const {
  call(b, loc, countingEntry(idr::runtime::decrements, word), value);
}

Value Runtime::isUnique(OpBuilder &b, Location loc, Value cell) const {
  return call(b, loc, idr::runtime::helper::isUnique, cell).getResult();
}

} // namespace idr::conversion
