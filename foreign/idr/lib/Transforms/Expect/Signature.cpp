// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// signature, convention and entry: the types a function is called at, and
// the convention it is called by, which after lowering are the program's
// calling convention and the C entry's. A
// lowered signature says how each value travels, a sum as its tag and its
// slots, an array as its cell and its sizes, a linear value as the value,
// the world as nothing, so a test states that by the type and not by the
// names of the parameters.

#include "idr/Transforms/Expect.h"

#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::expect {

// Every copy of @f has the function type the argument writes: a builtin
// function type for an idr.func or a func.func, an LLVM one for an
// llvm.func.
LogicalResult signature(const Request<TypeOf> &request) {
  Type wanted = request.argument.type;
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions) {
    if (fn.getFunctionType() == wanted)
      continue;
    fail(fn->getLoc(), request.property) << where(fn) << " has the type " << fn.getFunctionType()
                                         << ", not " << wanted;
    held = false;
  }
  return success(held);
}

// Every copy of @f is an llvm.func of the calling convention the argument
// names, as LLVM spells it (ccc, tailcc, ...).
LogicalResult convention(const Request<ConventionOf> &request) {
  LLVM::cconv::CConv wanted = request.argument.convention;
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions) {
    auto llvmFn = dyn_cast<LLVM::LLVMFuncOp>(fn.getOperation());
    if (llvmFn && llvmFn.getCConv() == wanted)
      continue;
    if (llvmFn)
      fail(fn->getLoc(), request.property)
          << where(fn) << " is called by " << LLVM::cconv::stringifyCConv(llvmFn.getCConv())
          << ", not " << LLVM::cconv::stringifyCConv(wanted);
    else
      fail(fn->getLoc(), request.property)
          << where(fn) << " is no llvm.func, which has a convention";
    held = false;
  }
  return success(held);
}

// After idr-entry, the module's one public function with a body is the
// process entry, which takes the C entry's count and vector and returns its
// status: (i32, !llvm.ptr) -> i32. Every other function the program
// defines is private; the runtime's are declarations.
LogicalResult entry(const Request<Nothing> &request) {
  ModuleOp module = request.module;
  StringRef entryName = conversion::entrySymbol;
  MLIRContext *context = module.getContext();
  Type i32 = IntegerType::get(context, 32);
  SmallVector<Type> inputs{i32, LLVM::LLVMPointerType::get(context)};
  bool held = true, found = false;
  for (FunctionOpInterface fn : functionsOf(module)) {
    if (fn.isExternal() || !fn.isPublic())
      continue;
    if (SymbolTable::getSymbolName(fn).getValue() != entryName) {
      fail(fn->getLoc(), request.property) << where(fn) << " is public, and only @" << entryName
                                           << " is";
      held = false;
      continue;
    }
    found = true;
    if (llvm::equal(fn.getArgumentTypes(), inputs) &&
        llvm::equal(fn.getResultTypes(), ArrayRef(i32)))
      continue;
    fail(fn->getLoc(), request.property) << "@" << entryName << " has the type "
                                         << fn.getFunctionType()
                                         << ", not the C entry's (i32, !llvm.ptr) -> i32";
    held = false;
  }
  if (!found) {
    fail(module.getLoc(), request.property) << "no public @" << entryName;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
