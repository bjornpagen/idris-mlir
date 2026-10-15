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

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/LLVMIR/LLVMTypes.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::expect {

// Every copy of @f has the function type the argument writes: a builtin
// function type for an idr.func or a func.func, an LLVM one for an
// llvm.func.
LogicalResult signature(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "signature";
  auto [function, text] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  Type wanted = parseType(text, module.getContext());
  if (!wanted)
    return fail(module.getLoc(), property) << "cannot read the type " << text;
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    if (fn.getFunctionType() == wanted)
      continue;
    fail(fn->getLoc(), property) << where(fn) << " has the type " << fn.getFunctionType()
                                 << ", not " << wanted;
    held = false;
  }
  return success(held);
}

// Every copy of @f is an llvm.func of the calling convention the argument
// names, as LLVM spells it (ccc, tailcc, ...).
LogicalResult convention(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "convention";
  auto [function, text] = splitAt(module, argument, property);
  if (function.empty())
    return failure();
  std::optional<LLVM::cconv::CConv> wanted = LLVM::cconv::symbolizeCConv(text);
  if (!wanted)
    return fail(module.getLoc(), property) << "no calling convention is spelled " << text;
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    auto llvmFn = dyn_cast<LLVM::LLVMFuncOp>(fn.getOperation());
    if (llvmFn && llvmFn.getCConv() == *wanted)
      continue;
    if (llvmFn)
      fail(fn->getLoc(), property) << where(fn) << " is called by "
                                   << LLVM::cconv::stringifyCConv(llvmFn.getCConv()) << ", not "
                                   << text;
    else
      fail(fn->getLoc(), property) << where(fn) << " is no llvm.func, which has a convention";
    held = false;
  }
  return success(held);
}

// After idr-entry, the module's one public function with a body is @main,
// which takes the C entry's count and vector and returns its status:
// (i32, !llvm.ptr) -> i32. Every other function the program defines is
// private; the runtime's are declarations.
LogicalResult entry(ModuleOp module, AnalysisManager &, StringRef) {
  constexpr StringRef property = "entry";
  MLIRContext *context = module.getContext();
  Type i32 = IntegerType::get(context, 32);
  SmallVector<Type> inputs{i32, LLVM::LLVMPointerType::get(context)};
  bool held = true, found = false;
  for (FunctionOpInterface fn : functionsOf(module)) {
    if (fn.isExternal() || !fn.isPublic())
      continue;
    if (SymbolTable::getSymbolName(fn).getValue() != "main") {
      fail(fn->getLoc(), property) << where(fn) << " is public, and only @main is";
      held = false;
      continue;
    }
    found = true;
    if (llvm::equal(fn.getArgumentTypes(), inputs) &&
        llvm::equal(fn.getResultTypes(), ArrayRef(i32)))
      continue;
    fail(fn->getLoc(), property) << "@main has the type " << fn.getFunctionType()
                                 << ", not the C entry's (i32, !llvm.ptr) -> i32";
    held = false;
  }
  if (!found) {
    fail(module.getLoc(), property) << "no public @main";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
