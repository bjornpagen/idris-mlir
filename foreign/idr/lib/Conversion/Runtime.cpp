// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions as idr-lower calls them, the crashes it
// reports through them, counting, and the merge of what the workers wrote;
// the reads and writes of a cell are RuntimeCells.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/raw_ostream.h"

// The runtime's C ABI: the size of its words and the stack mark of a cell's
// info are macros.
#include "idris_rt.h"

#include <string>

using namespace mlir;

namespace idr::conversion {

namespace {

using idr::runtime::OperandKind;
using idr::runtime::ResultKind;

// The message of a crash, as the runtime prints it after its own prefix:
// its cause and, where the location names a place in the Idris source, the
// start of that place.
std::string crashMessage(Location loc, StringRef cause) {
  auto place = loc->findInstanceOf<FileLineColRange>();
  // A location may name no place at all: an op the lowering made from none.
  if (!place)
    return cause.str();
  return (cause + " at " + place.getFilename().getValue() + ":" + Twine(place.getStartLine()) +
          ":" + Twine(place.getStartColumn()))
      .str();
}

// The LLVM type of a parameter of the kind `kind`, appended to `params`:
// none for the world, which is no C value.
void appendParameter(SmallVectorImpl<Type> &params, MLIRContext *ctx, OperandKind kind) {
  using enum OperandKind;
  switch (kind) {
  case World:
    return;
  case Int32:
    params.push_back(IntegerType::get(ctx, 32));
    return;
  case Bool:
    params.push_back(IntegerType::get(ctx, 1));
    return;
  case Int64:
  case Signed:
  case Unsigned:
  case Big:
    params.push_back(IntegerType::get(ctx, 64));
    return;
  case Double:
    params.push_back(Float64Type::get(ctx));
    return;
  case Str:
  case Buffer:
  case Pointer:
    params.push_back(LLVM::LLVMPointerType::get(ctx));
    return;
  }
}

// The LLVM type of a result of the kind `kind`: void for none.
Type resultType(MLIRContext *ctx, ResultKind kind) {
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

// The type of a runtime function, from its kinds alone: every call and its
// one declaration have it.
LLVM::LLVMFunctionType functionType(MLIRContext *ctx, const idr::runtime::Function &function) {
  SmallVector<Type> params;
  for (OperandKind kind : function.operands)
    appendParameter(params, ctx, kind);
  return LLVM::LLVMFunctionType::get(resultType(ctx, function.result), params);
}

} // namespace

// Detached: no worker declares a function, since two would declare it
// twice, and a declaration made while functions are converted would land
// in the order they are; merge and idr-entry insert it.
LLVM::LLVMFuncOp runtimeDeclaration(Location loc, const idr::runtime::Function &function) {
  OpBuilder b(loc.getContext());
  auto callee = LLVM::LLVMFuncOp::create(b, loc, StringRef(function.symbol),
                                         functionType(loc.getContext(), function));
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

// The converter reads no data layout of its own: the options carry what
// it needs, and a worker's queries would fill the shared layout's caches.
Runtime::Runtime(Location at, const Layouts &l, const LowerToLLVMOptions &options)
    : llvmTypes(at.getContext(), options, /*analysis=*/nullptr), statics(at, l) {}

// A function that does not return says so at each call too, since linking
// the runtime replaces the declaration's attributes by the definition's.
LLVM::CallOp Runtime::call(OpBuilder &b, Location loc, const idr::runtime::Function &function,
                           ValueRange args) {
  called.insert(&function);
  auto made = LLVM::CallOp::create(b, loc, functionType(b.getContext(), function),
                                   StringRef(function.symbol), args);
  if (function.result == ResultKind::NoReturn)
    made.setNoreturn(true);
  return made;
}

LLVM::CallOp Runtime::call(OpBuilder &b, Operation *op, const idr::runtime::Function &function,
                           ArrayRef<ValueRange> operands) {
  Location loc = op->getLoc();
  Type i64 = b.getI64Type();
  SmallVector<Value> args;
  for (auto [kind, components] : llvm::zip_equal(function.operands, operands)) {
    using enum OperandKind;
    switch (kind) {
    case World:
      break;
    case Signed:
    case Unsigned: {
      // An integer of the op's width, which is 64 bits already or is
      // extended to them.
      Value integer = components.front();
      if (integer.getType() != i64)
        integer = kind == Signed
                      ? Value(arith::ExtSIOp::create(b, loc, i64, integer))
                      : Value(arith::ExtUIOp::create(b, loc, i64, integer));
      args.push_back(integer);
      break;
    }
    case Int32:
    case Int64:
    case Double:
    case Str:
    case Big:
    case Buffer:
    case Pointer:
    case Bool:
      args.push_back(components.front());
      break;
    }
  }
  return call(b, loc, function, args);
}

void Runtime::crash(OpBuilder &b, Location loc, StringRef cause) {
  std::string text = crashMessage(loc, cause);
  Value ptr = statics.message(b, loc, text);
  Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
  // The call is cold, and what leads only to it: LLVM lays the crash
  // checks out of the way of the paths that run.
  call(b, loc, idr::runtime::helper::crash, ValueRange{ptr, len}).setCold(true);
}

void Runtime::crashIf(OpBuilder &b, Location loc, Value condition, StringRef cause) {
  auto check = scf::IfOp::create(b, loc, condition, /*withElseRegion=*/false);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(check.thenBlock());
  crash(b, loc, cause);
}

// llvm.sideeffect is the effect LLVM keeps in place and emits as no
// instruction, so the body of a loop that may not end never empties. A
// fence would not do: LLVM hoists it out of the loop.
void Runtime::mayLoop(OpBuilder &b, Location loc) {
  LLVM::CallIntrinsicOp::create(b, loc, b.getStringAttr("llvm.sideeffect"), ValueRange{});
}

void Runtime::inc(OpBuilder &b, Location loc, ValueRange references) {
  countEach(b, loc, idr::runtime::helper::inc, references);
}

void Runtime::dec(OpBuilder &b, Location loc, ValueRange references) {
  countEach(b, loc, idr::runtime::helper::dec, references);
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  return statics.constant(b, loc, value, type);
}

Value Runtime::constantArray(OpBuilder &b, Location loc, const ConstantArray &array) {
  return statics.constantArray(b, loc, array);
}

LogicalResult Runtime::merge(Operation *program, SymbolTable &symbols,
                             ArrayRef<Runtime *> workers) {
  MLIRContext *ctx = program->getContext();
  Location loc = program->getLoc();
  bool merged = true;
  llvm::SmallPtrSet<const idr::runtime::Function *, 16> functions;
  // Equal names are equal contents, by how names are made: one global of
  // each name is kept, the others go with their worker.
  llvm::StringMap<StaticData::Written> data;
  llvm::StringSet<> memoCells;
  for (Runtime *worker : workers) {
    merged = merged && !worker->statics.collided();
    functions.insert(worker->called.begin(), worker->called.end());
    for (const auto &entry : worker->statics.written()) {
      auto [it, inserted] = data.try_emplace(entry.getKey(), entry.getValue());
      if (!inserted && it->second.key != entry.getValue().key) {
        std::string keys;
        llvm::raw_string_ostream(keys) << it->second.key << " and " << entry.getValue().key;
        emitError(loc) << "internal error: two keys name " << entry.getKey() << ": " << keys;
        merged = false;
      }
    }
    for (const auto &name : worker->statics.memoCells())
      memoCells.insert(name.getKey());
  }
  if (!memoCells.empty())
    functions.insert(&idr::runtime::helper::cafRelease);

  // Each before the program's first op, so in the order inserted. A C name
  // is its own mangling, so a program symbol could be one, and
  // SymbolTable::insert would rename the declaration silently: such a
  // program is refused here. Static data and the release function have
  // reserved names (idr::reservedName), which no program symbol is.
  Block *body = &program->getRegion(0).front();
  Block::iterator first = body->begin();
  SmallVector<const idr::runtime::Function *> declared(functions.begin(), functions.end());
  llvm::sort(declared, [](const idr::runtime::Function *a, const idr::runtime::Function *c) {
    return a->symbol < c->symbol;
  });
  for (const idr::runtime::Function *function : declared) {
    StringRef name(function->symbol);
    if (symbols.lookup(name)) {
      emitError(loc) << "internal error: idr-lower: @" << name
                     << ", a function of the runtime, names a symbol of the program";
      merged = false;
      continue;
    }
    symbols.insert(runtimeDeclaration(loc, *function), first);
  }
  SmallVector<StringRef> names;
  for (const auto &entry : data)
    names.push_back(entry.getKey());
  llvm::sort(names);
  for (StringRef name : names) {
    LLVM::GlobalOp global = data.lookup(name).global;
    global->remove();
    symbols.insert(global, first);
  }
  if (!merged)
    return failure();

  OpBuilder b = OpBuilder::atBlockEnd(body);
  auto release =
      func::FuncOp::create(b, loc, idr::releaseCafsName(), b.getFunctionType({}, {}));
  release.setPrivate();
  symbols.insert(release);
  b.setInsertionPointToStart(release.addEntryBlock());
  SmallVector<StringRef> cells;
  for (const auto &entry : memoCells)
    cells.push_back(entry.getKey());
  llvm::sort(cells);
  Type ptr = LLVM::LLVMPointerType::get(ctx);
  for (StringRef name : cells)
    LLVM::CallOp::create(b, loc, functionType(ctx, idr::runtime::helper::cafRelease),
                         StringRef(idr::runtime::helper::cafRelease.symbol),
                         ValueRange{LLVM::AddressOfOp::create(b, loc, ptr, name)});
  func::ReturnOp::create(b, loc);
  return success();
}

void Runtime::countEach(OpBuilder &b, Location loc, const idr::runtime::Function &function,
                        ValueRange references) {
  for (Value reference : references) {
    if (StaticData::isStatic(reference))
      continue;
    // A counted word that is no pointer (a big's) is passed as the address
    // it holds.
    Value pointer = reference;
    if (!isa<LLVM::LLVMPointerType>(pointer.getType()))
      pointer = LLVM::IntToPtrOp::create(b, loc, ptrType(b.getContext()), pointer);
    call(b, loc, function, pointer);
  }
}

} // namespace idr::conversion
