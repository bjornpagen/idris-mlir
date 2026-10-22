// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions as idr-lower calls them, the crashes it reports
// through them, counting by the kind of each word, and the constants that
// are static data; the reads and writes of a cell are RuntimeCells.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"

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
  case Bool:
    return IntegerType::get(ctx, 1);
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

// The entry of `count` for a word of kind `word`: the kinds form a lattice
// (a cell below a maybe-cell and a big, their join any), and each entry
// tests exactly what its kind leaves open. An uncounted word has none.
const idr::runtime::Function &incOf(layout::Word word) {
  using enum layout::Word;
  switch (word) {
  case Cell:
    return idr::runtime::helper::incCell;
  case MaybeCell:
    return idr::runtime::helper::incMaybeCell;
  case Big:
    return idr::runtime::helper::incBig;
  case Any:
  case Uncounted:
    break;
  }
  return idr::runtime::helper::incAny;
}

const idr::runtime::Function &decOf(layout::Word word) {
  using enum layout::Word;
  switch (word) {
  case Cell:
    return idr::runtime::helper::decCell;
  case MaybeCell:
    return idr::runtime::helper::decMaybeCell;
  case Big:
    return idr::runtime::helper::decBig;
  case Any:
  case Uncounted:
    break;
  }
  return idr::runtime::helper::decAny;
}

} // namespace

LLVM::LLVMFunctionType runtimeFunctionType(MLIRContext *ctx,
                                           const idr::runtime::Function &function) {
  SmallVector<Type> params;
  for (OperandKind kind : function.operands)
    params.push_back(llvmType(ctx, kind));
  // A function that gives its results through pointers takes one for each,
  // after the operands.
  params.append(function.outs.size(), LLVM::LLVMPointerType::get(ctx));
  return LLVM::LLVMFunctionType::get(llvmType(ctx, function.result), params);
}

// Detached: idr-lower-runtime inserts it, once per function of the table.
LLVM::LLVMFuncOp runtimeDeclaration(Location loc, const idr::runtime::Function &function) {
  OpBuilder b(loc.getContext());
  auto callee = LLVM::LLVMFuncOp::create(b, loc, StringRef(function.symbol),
                                         runtimeFunctionType(loc.getContext(), function));
  for (auto [index, kind] : llvm::enumerate(function.operands))
    if (kind == OperandKind::Bool)
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
Runtime::Runtime(MLIRContext *ctx, const Layouts &l, const LowerToLLVMOptions &options)
    : layouts(l), llvmTypes(ctx, options, /*analysis=*/nullptr),
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
                           ArrayRef<ValueRange> operands, ArrayRef<Value> resultSlots) const {
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
  llvm::append_range(args, resultSlots);
  return call(b, loc, function, args);
}

SmallVector<Value, 4> Runtime::siteOperands(OpBuilder &b, Location loc, SiteAttr site) const {
  return {staticAddress(b, loc, StaticNames::text(StringRef(site.getFunction()))),
          staticAddress(b, loc, StaticNames::text(StringRef(site.getFile()))),
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
  call(b, loc, incOf(word), value);
}

void Runtime::dec(OpBuilder &b, Location loc, layout::Word word, Value value) const {
  call(b, loc, decOf(word), value);
}

Value Runtime::isUnique(OpBuilder &b, Location loc, Value cell) const {
  return call(b, loc, idr::runtime::helper::isUnique, cell).getResult();
}

// The one ladder of constants a value may be: strings, bigs, scalars,
// poison of a cell pointer, then constructors, in place or in a cell. Each
// datum is idr-lower-statics', named by its content.
SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value,
                                     Type type) const {
  type = unrestricted(type);
  if (auto text = dyn_cast<StringAttr>(value))
    return {staticAddress(b, loc, StaticNames::string(text.getValue()))};
  if (auto number = dyn_cast<BigAttr>(value))
    return {bigConstant(b, loc, number)};
  if (isa<IntegerAttr, FloatAttr>(value))
    return {LLVM::ConstantOp::create(b, loc, type, cast<TypedAttr>(value))};
  // Poison stands for a cell pointer only: of any other value it is each
  // component's (Cells.cpp).
  if (isa<ub::PoisonAttr>(value))
    return {staticAddress(b, loc, StaticNames::nothing())};
  auto con = cast<ConAttr>(value);
  DataType data = con.getData();
  if (data.layout() == Layout::Cell)
    return {staticAddress(b, loc, StaticNames::cell(con, 0))};
  families::CtorView ctor = data.ctor(con.getTag());
  SmallVector<SmallVector<Value>> held;
  for (auto [field, fieldType] : llvm::zip_equal(con.getFields(), ctor.fields))
    held.push_back(constant(b, loc, field, fieldType));
  SmallVector<ValueRange> fields(held.begin(), held.end());
  return unboxedSum(b, loc, layouts.sum(data), con.getTag(), fields);
}

Value Runtime::constantArray(OpBuilder &b, Location loc, const ConstantArray &array) const {
  return staticAddress(b, loc, array.name());
}

} // namespace idr::conversion
