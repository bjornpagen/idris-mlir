// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions as idr-lower calls them, the crashes it
// reports through them, and the merge of what the workers wrote.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/Twine.h"

// The runtime's C ABI: the size of its words and the stack mark of a cell's
// info are macros.
#include "idris_rt.h"

#include <string>

using namespace mlir;

namespace idr::conversion {

namespace {

// Where in the Idris source `loc` is, as the start of its span.
std::string describe(Location loc) {
  if (auto span = dyn_cast<FileLineColRange>(loc))
    return (span.getFilename().getValue() + ":" + Twine(span.getStartLine()) + ":" +
            Twine(span.getStartColumn()))
        .str();
  if (auto fused = dyn_cast<FusedLoc>(loc))
    for (Location inner : fused.getLocations())
      if (auto text = describe(inner); !text.empty())
        return text;
  if (auto named = dyn_cast<NameLoc>(loc))
    return describe(named.getChildLoc());
  if (auto site = dyn_cast<CallSiteLoc>(loc))
    return describe(site.getCallee());
  return "";
}

// The message of a crash, as the runtime prints it: its cause and the Idris
// location.
std::string crashMessage(Location loc, StringRef cause) {
  std::string where = describe(loc);
  return ("idris-mlir: " + cause + (where.empty() ? "" : " at " + where) + "\n").str();
}

} // namespace

Runtime::Runtime(ModuleOp m, const Layouts &l, const DataLayoutAnalysis &dataLayouts)
    : module(m),
      llvmTypes(m.getContext(), LowerToLLVMOptions(m.getContext(), dataLayouts.getAtOrAbove(m)),
                &dataLayouts),
      statics(m, l) {}

Value Runtime::call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
  LLVM::CallOp op = callOp(b, loc, name, result, args);
  return result ? op.getResult() : Value();
}

// The call names its callee, which no worker declares: two workers would
// declare it twice, and a declaration made while functions are converted
// lands in the order they are. One function has one type, whichever call
// is the first to name it.
LLVM::CallOp Runtime::callOp(OpBuilder &b, Location loc, StringRef name, Type result,
                             ValueRange args) {
  Type returns = result ? result : LLVM::LLVMVoidType::get(b.getContext());
  auto type = LLVM::LLVMFunctionType::get(returns, llvm::to_vector(args.getTypes()));
  auto [it, inserted] = called.try_emplace(name, type);
  if (!inserted && it->second != type) {
    emitError(loc) << "internal error: idr-lower: the runtime function " << name
                   << " is called as " << type << " and as " << it->second;
    mistyped = true;
  }
  SmallVector<Type, 1> results;
  if (result)
    results.push_back(result);
  return LLVM::CallOp::create(b, loc, results, name, args);
}

void Runtime::crash(OpBuilder &b, Location loc, StringRef cause) {
  std::string text = crashMessage(loc, cause);
  Value ptr = statics.message(b, loc, text);
  Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
  // The call is cold, and what leads only to it: LLVM lays the crash
  // checks out of the way of the paths that run. The call site says so
  // itself, since linking the runtime replaces the declaration's
  // attributes by the definition's.
  LLVM::CallOp call = callOp(b, loc, "idris_rt_crash", Type(), ValueRange{ptr, len});
  call.setCold(true);
  call.setNoreturn(true);
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

Value Runtime::allocate(OpBuilder &b, Location loc, unsigned size, layout::CellInfo info) {
  return call(b, loc, "idris_rt_cell", ptrType(b.getContext()),
              ValueRange{i64Constant(b, loc, size), i32Constant(b, loc, info.word())});
}

void Runtime::storeHeader(OpBuilder &b, Location loc, Value cell, layout::CellInfo info) {
  LLVM::StoreOp::create(b, loc, i32Constant(b, loc, 1), cell, alignAt(0));
  storeInfo(b, loc, cell, i32Constant(b, loc, info.word()));
}

Value Runtime::loadInfo(OpBuilder &b, Location loc, Value cell) {
  return LLVM::LoadOp::create(b, loc, b.getI32Type(), at(b, loc, cell, 4), alignAt(4));
}

void Runtime::storeInfo(OpBuilder &b, Location loc, Value cell, Value info) {
  LLVM::StoreOp::create(b, loc, info, at(b, loc, cell, 4), alignAt(4));
}

void Runtime::store(OpBuilder &b, Location loc, Value cell, ArrayRef<layout::Slot> slots,
                    ValueRange values) {
  for (auto [slot, value] : llvm::zip_equal(slots, values))
    LLVM::StoreOp::create(b, loc, value, at(b, loc, cell, slot.offset), alignAt(slot.offset));
}

SmallVector<Value> Runtime::load(OpBuilder &b, Location loc, Value cell,
                                 ArrayRef<layout::Slot> slots) {
  SmallVector<Value> values;
  for (const layout::Slot &slot : slots)
    values.push_back(LLVM::LoadOp::create(b, loc, slot.type, at(b, loc, cell, slot.offset),
                                          alignAt(slot.offset)));
  return values;
}

void Runtime::storeWord(OpBuilder &b, Location loc, Value address, Value value) {
  LLVM::StoreOp::create(b, loc, value, address, IDRIS_RT_WORD_BYTES);
}

Value Runtime::loadTag(OpBuilder &b, Location loc, Value cell) {
  return LLVM::AndOp::create(b, loc, loadInfo(b, loc, cell), i32Constant(b, loc, layout::tagMask));
}

void Runtime::inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_inc", components, counted);
}

void Runtime::dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_dec", components, counted);
}

Value Runtime::exclusive(OpBuilder &b, Location loc, Value cell) {
  Value count = LLVM::LoadOp::create(b, loc, b.getI32Type(), cell, alignAt(0));
  Value info = loadInfo(b, loc, cell);
  Value one = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, count, i32Constant(b, loc, 1));
  Value stack = LLVM::AndOp::create(b, loc, info, i32Constant(b, loc, IDRIS_RT_STACK_CELL));
  Value heap = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, stack, i32Constant(b, loc, 0));
  return LLVM::AndOp::create(b, loc, one, heap);
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  return statics.constant(b, loc, value, type);
}

Value Runtime::constantArray(OpBuilder &b, Location loc, memref::GlobalOp global) {
  return statics.constantArray(b, loc, global);
}

namespace {

// The declaration of the runtime function `name` of type `type`, detached.
// The C ABI has the caller extend an argument narrower than 32 bits, and the
// runtime's narrow parameters are unsigned (a byte): without zeroext, a
// caller would pass garbage in the upper bits. A crash or an exit does not
// return, which lets LLVM treat what follows as unreachable.
LLVM::LLVMFuncOp declaration(ModuleOp module, StringRef name, LLVM::LLVMFunctionType type) {
  OpBuilder b(module.getContext());
  auto callee = LLVM::LLVMFuncOp::create(b, module.getLoc(), name, type);
  for (auto [i, arg] : llvm::enumerate(type.getParams()))
    if (auto integer = dyn_cast<IntegerType>(arg); integer && integer.getWidth() < 32)
      callee.setArgAttr(static_cast<unsigned>(i), LLVM::LLVMDialect::getZExtAttrName(),
                        b.getUnitAttr());
  if (name == "idris_rt_crash" || name == "idris_rt_crash_str" || name == "idris_rt_io_exit")
    callee.setNoreturn(true);
  return callee;
}

} // namespace

LogicalResult Runtime::merge(ModuleOp module, SymbolTable &symbols, ArrayRef<Runtime *> workers) {
  MLIRContext *ctx = module.getContext();
  Location loc = module.getLoc();
  bool merged = true;
  llvm::StringMap<LLVM::LLVMFunctionType> functions;
  auto require = [&](StringRef name, LLVM::LLVMFunctionType type) {
    auto [it, inserted] = functions.try_emplace(name, type);
    if (!inserted && it->second != type) {
      emitError(loc) << "internal error: idr-lower: the runtime function " << name
                     << " is called as " << type << " and as " << it->second;
      merged = false;
    }
  };
  // Equal names are equal contents, by how names are made: one global of
  // each name is kept, the others go with their worker.
  llvm::StringMap<StaticData::Written> data;
  llvm::StringSet<> memoCells;
  for (Runtime *worker : workers) {
    merged = merged && !worker->mistyped && !worker->statics.collided();
    for (const auto &entry : worker->called)
      require(entry.getKey(), entry.getValue());
    for (const auto &entry : worker->statics.written()) {
      auto [it, inserted] = data.try_emplace(entry.getKey(), entry.getValue());
      if (!inserted && it->second.key != entry.getValue().key) {
        emitError(loc) << "internal error: two keys name " << entry.getKey() << ": "
                       << it->second.key << " and " << entry.getValue().key;
        merged = false;
      }
    }
    for (const auto &name : worker->statics.memoCells())
      memoCells.insert(name.getKey());
  }
  Type ptr = LLVM::LLVMPointerType::get(ctx);
  StringRef cafRelease = "idris_rt_caf_release";
  if (!memoCells.empty())
    require(cafRelease, LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), ptr));
  if (!merged)
    return failure();

  // Each before the module's first op, so in the order inserted.
  Block *body = module.getBody();
  Block::iterator first = body->begin();
  auto enter = [&](Operation *op, StringRef name) {
    if (symbols.lookup(name)) {
      op->erase();
      emitError(loc) << "internal error: idr-lower: @" << name
                     << ", which the lowering writes, names another symbol";
      merged = false;
      return;
    }
    symbols.insert(op, first);
  };
  auto sorted = [](const auto &map) {
    SmallVector<StringRef> names;
    for (const auto &entry : map)
      names.push_back(entry.getKey());
    llvm::sort(names);
    return names;
  };
  for (StringRef name : sorted(functions))
    enter(declaration(module, name, functions.lookup(name)), name);
  for (StringRef name : sorted(data)) {
    LLVM::GlobalOp global = data.lookup(name).global;
    global->remove();
    enter(global, name);
  }
  if (!merged)
    return failure();

  OpBuilder b = OpBuilder::atBlockEnd(body);
  StringRef releaseName = "__idr_release_cafs";
  if (symbols.lookup(releaseName))
    return emitError(loc) << "internal error: idr-lower: @" << releaseName
                          << ", which the lowering writes, names another symbol";
  auto release = func::FuncOp::create(b, loc, releaseName, b.getFunctionType({}, {}));
  release.setPrivate();
  symbols.insert(release);
  b.setInsertionPointToStart(release.addEntryBlock());
  for (StringRef name : sorted(memoCells))
    LLVM::CallOp::create(b, loc, TypeRange{}, cafRelease,
                         ValueRange{LLVM::AddressOfOp::create(b, loc, ptr, name)});
  func::ReturnOp::create(b, loc);
  return success();
}

void Runtime::countEach(OpBuilder &b, Location loc, StringRef name, ValueRange components,
                        ArrayRef<bool> counted) {
  for (auto [component, isCounted] : llvm::zip_equal(components, counted)) {
    if (!isCounted)
      continue;
    Value pointer = component;
    if (!isa<LLVM::LLVMPointerType>(pointer.getType()))
      pointer = LLVM::IntToPtrOp::create(b, loc, ptrType(b.getContext()), pointer);
    call(b, loc, name, Type(), pointer);
  }
}

} // namespace idr::conversion
