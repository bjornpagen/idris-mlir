// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's C functions as idr-lower calls them, the crashes it
// reports through them, counting, and the merge of what the workers wrote;
// the reads and writes of a cell are RuntimeCells.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Location.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

// The runtime's C ABI: the size of its words and the stack mark of a cell's
// info are macros.
#include "idris_rt.h"

#include <cassert>
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

// Whether a function takes an operand of type `type` as `kind`: the kinds of
// an operand of several kinds tell a double from an integer, and an
// integer's signedness, which its op says. An operand of one kind has one
// function, which takes it.
bool takes(idr::runtime::Kind kind, Type type, std::optional<bool> isSigned) {
  using idr::runtime::Kind;
  type = unrestricted(type);
  switch (kind) {
  case Kind::Double:
    return type.isF64();
  case Kind::Signed:
    return type.isInteger() && isSigned == true;
  case Kind::Unsigned:
    return type.isInteger() && isSigned == false;
  case Kind::World:
  case Kind::Int32:
  case Kind::Int64:
  case Kind::Wrapped:
  case Kind::Order:
  case Kind::Str:
  case Kind::Big:
  case Kind::Buffer:
    return true;
  case Kind::Void:
    break;
  }
  llvm_unreachable("the runtime's table takes no operand as Void");
}

// The C type of a function's result, none for Void.
std::optional<Type> resultType(MLIRContext *ctx, idr::runtime::Kind kind) {
  using idr::runtime::Kind;
  switch (kind) {
  case Kind::Int32:
  case Kind::Order:
    return IntegerType::get(ctx, 32);
  case Kind::Int64:
  case Kind::Wrapped:
  case Kind::Big:
    return IntegerType::get(ctx, 64);
  case Kind::Double:
    return Float64Type::get(ctx);
  case Kind::Str:
    return LLVM::LLVMPointerType::get(ctx);
  case Kind::Void:
    return std::nullopt;
  case Kind::World:
  case Kind::Signed:
  case Kind::Unsigned:
  case Kind::Buffer:
    break;
  }
  llvm_unreachable("the runtime's table gives a result of one C value, or none");
}

} // namespace

const idr::runtime::Function &functionTaking(ArrayRef<idr::runtime::Function> functions,
                                             TypeRange operands, std::optional<bool> isSigned) {
  const idr::runtime::Function *found = llvm::find_if(functions, [&](const auto &function) {
    return llvm::all_of(llvm::zip_equal(function.operands, operands), [&](auto pair) {
      return takes(std::get<0>(pair), std::get<1>(pair), isSigned);
    });
  });
  assert(found != functions.end() && "the table has a function for each kind of each operand");
  return *found;
}

// The converter reads no data layout of its own: the options carry what
// it needs, and a worker's queries would fill the shared layout's caches.
Runtime::Runtime(Location at, const Layouts &l, const LowerToLLVMOptions &options)
    : llvmTypes(at.getContext(), options, /*analysis=*/nullptr), statics(at, l) {}

Value Runtime::call(OpBuilder &b, Location loc, StringRef name, Type result, ValueRange args) {
  return callOp(b, loc, name, result, args, /*noreturn=*/false).getResult();
}

void Runtime::perform(OpBuilder &b, Location loc, StringRef name, ValueRange args) {
  callOp(b, loc, name, std::nullopt, args, /*noreturn=*/false);
}

std::optional<Value> Runtime::call(OpBuilder &b, Operation *op,
                                   const idr::runtime::Function &function,
                                   ArrayRef<ValueRange> operands) {
  using idr::runtime::Kind;
  Location loc = op->getLoc();
  Type i64 = b.getI64Type();
  SmallVector<Value> args;
  for (auto [kind, components] : llvm::zip_equal(function.operands, operands)) {
    switch (kind) {
    case Kind::World:
      break;
    case Kind::Buffer:
      // No value holds a buffer's first byte: it is right after its cell's
      // header.
      args.push_back(components.front());
      args.push_back(elementsOf(b, loc, components.front()));
      llvm::append_range(args, components.drop_front());
      break;
    case Kind::Signed:
    case Kind::Unsigned: {
      Value integer = components.front();
      if (integer.getType() != i64)
        integer = kind == Kind::Signed ? Value(arith::ExtSIOp::create(b, loc, i64, integer))
                                       : Value(arith::ExtUIOp::create(b, loc, i64, integer));
      args.push_back(integer);
      break;
    }
    case Kind::Int32:
    case Kind::Int64:
    case Kind::Double:
    case Kind::Wrapped:
    case Kind::Order:
    case Kind::Str:
    case Kind::Big:
      args.push_back(components.front());
      break;
    case Kind::Void:
      llvm_unreachable("the runtime's table takes no operand as Void");
    }
  }
  std::optional<Type> result = resultType(b.getContext(), function.result);
  LLVM::CallOp call = callOp(b, loc, function.symbol, result, args, function.noreturn);
  if (!result)
    return std::nullopt;
  return call.getResult();
}

// The call names its callee, which no worker declares: two workers would
// declare it twice, and a declaration made while functions are converted
// lands in the order they are. One function has one type, whichever call
// is the first to name it. A function that does not return says so at
// each call too, since linking the runtime replaces the declaration's
// attributes by the definition's.
LLVM::CallOp Runtime::callOp(OpBuilder &b, Location loc, StringRef name,
                             std::optional<Type> result, ValueRange args, bool noreturn) {
  Type returns = result ? *result : LLVM::LLVMVoidType::get(b.getContext());
  auto type = LLVM::LLVMFunctionType::get(returns, llvm::to_vector(args.getTypes()));
  auto [it, inserted] = called.try_emplace(name, Callee{type, noreturn});
  if (!inserted && (it->second.type != type || it->second.noreturn != noreturn)) {
    emitError(loc) << "internal error: idr-lower: the runtime function " << name
                   << " is called as " << type << " and as " << it->second.type;
    mistyped = true;
  }
  SmallVector<Type, 1> results;
  if (result)
    results.push_back(*result);
  auto call = LLVM::CallOp::create(b, loc, results, name, args);
  if (noreturn)
    call.setNoreturn(true);
  return call;
}

void Runtime::crash(OpBuilder &b, Location loc, StringRef cause) {
  std::string text = crashMessage(loc, cause);
  Value ptr = statics.message(b, loc, text);
  Value len = i64Constant(b, loc, static_cast<int64_t>(text.size()));
  // The call is cold, and what leads only to it: LLVM lays the crash
  // checks out of the way of the paths that run.
  LLVM::CallOp call =
      callOp(b, loc, "idris_rt_crash", std::nullopt, ValueRange{ptr, len}, /*noreturn=*/true);
  call.setCold(true);
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

void Runtime::inc(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_inc", components, counted);
}

void Runtime::dec(OpBuilder &b, Location loc, ValueRange components, ArrayRef<bool> counted) {
  countEach(b, loc, "idris_rt_dec", components, counted);
}

SmallVector<Value> Runtime::constant(OpBuilder &b, Location loc, Attribute value, Type type) {
  return statics.constant(b, loc, value, type);
}

Value Runtime::constantArray(OpBuilder &b, Location loc, const ConstantArray &array) {
  return statics.constantArray(b, loc, array);
}

namespace {

// The declaration of the runtime function `name` of type `type`, detached,
// as clang declares it from idris_rt.h on every target. The C ABI extends an
// integer narrower than 32 bits, an argument in its caller and a result in
// its callee, and the runtime's narrow integers are unsigned (a bool):
// without zeroext, a caller would pass garbage in an argument's upper bits.
// A function that does not return lets LLVM treat what follows its call as
// unreachable.
LLVM::LLVMFuncOp declaration(Location loc, StringRef name, LLVM::LLVMFunctionType type,
                             bool noreturn) {
  OpBuilder b(loc.getContext());
  auto callee = LLVM::LLVMFuncOp::create(b, loc, name, type);
  auto narrow = [](Type value) {
    auto integer = dyn_cast<IntegerType>(value);
    return integer && integer.getWidth() < 32;
  };
  for (auto [i, arg] : llvm::enumerate(type.getParams()))
    if (narrow(arg))
      callee.setArgAttr(static_cast<unsigned>(i), LLVM::LLVMDialect::getZExtAttrName(),
                        b.getUnitAttr());
  if (narrow(type.getReturnType()))
    callee.setResultAttr(0, LLVM::LLVMDialect::getZExtAttrName(), b.getUnitAttr());
  if (noreturn)
    callee.setNoreturn(true);
  return callee;
}

} // namespace

LogicalResult Runtime::merge(Operation *program, SymbolTable &symbols,
                             ArrayRef<Runtime *> workers) {
  MLIRContext *ctx = program->getContext();
  Location loc = program->getLoc();
  bool merged = true;
  llvm::StringMap<Callee> functions;
  auto require = [&](StringRef name, Callee callee) {
    auto [it, inserted] = functions.try_emplace(name, callee);
    if (!inserted && (it->second.type != callee.type || it->second.noreturn != callee.noreturn)) {
      emitError(loc) << "internal error: idr-lower: the runtime function " << name
                     << " is called as " << callee.type << " and as " << it->second.type;
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
        std::string keys;
        llvm::raw_string_ostream(keys) << it->second.key << " and " << entry.getValue().key;
        emitError(loc) << "internal error: two keys name " << entry.getKey() << ": " << keys;
        merged = false;
      }
    }
    for (const auto &name : worker->statics.memoCells())
      memoCells.insert(name.getKey());
  }
  Type ptr = LLVM::LLVMPointerType::get(ctx);
  StringRef cafRelease = "idris_rt_caf_release";
  if (!memoCells.empty())
    require(cafRelease, Callee{LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), ptr)});
  if (!merged)
    return failure();

  // Each before the program's first op, so in the order inserted.
  Block *body = &program->getRegion(0).front();
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
  for (StringRef name : sorted(functions)) {
    const Callee &callee = functions.find(name)->second;
    enter(declaration(loc, name, callee.type, callee.noreturn), name);
  }
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
    if (!isCounted || StaticData::isStatic(component))
      continue;
    Value pointer = component;
    if (!isa<LLVM::LLVMPointerType>(pointer.getType()))
      pointer = LLVM::IntToPtrOp::create(b, loc, ptrType(b.getContext()), pointer);
    perform(b, loc, name, pointer);
  }
}

} // namespace idr::conversion
