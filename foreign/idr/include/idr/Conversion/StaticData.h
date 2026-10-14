// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants idr-lower writes as globals of the module, each written
// once: strings, bigs outside the small range, boxes, among them the memo
// cells of constant thunks, and the messages of crashes; and
// @__idr_release_cafs, which releases what those memo cells hold.

#ifndef IDR_CONVERSION_STATICDATA_H
#define IDR_CONVERSION_STATICDATA_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

#include <optional>
#include <utility>

namespace idr::conversion {

class StaticData {
public:
  // Every declaration and global is entered in `symbols`, the module's
  // table, which the lowering reads its declarations from too.
  StaticData(mlir::ModuleOp module, const Layouts &layouts, mlir::SymbolTable &symbols);

  mlir::SymbolTable &symbolTable() const { return symbols; }

  // Whether a lowered component is static data, which holds no count: the
  // address of a global, or a constant word.
  static bool isStatic(mlir::Value component);

  // The address of the bytes of `text`, written once however many crashes
  // report it.
  mlir::Value message(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef text);

  // The components of the constant `value` of type `type`: scalars as LLVM
  // constants, strings, bigs outside the small range and boxes as static
  // data. Usable in code and in the initializer of a global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // @__idr_release_cafs, which the program's entry calls when the program
  // ends: idris_rt_caf_release on each static memo cell, which releases
  // what its first force stored there. A module without one has it too,
  // empty, so that the entry calls it without asking. Built once, after the
  // last constant is lowered.
  void emitReleaseCafs(mlir::OpBuilder &b);

private:
  llvm::SmallVector<mlir::Value> unboxed(mlir::OpBuilder &b, mlir::Location loc, ConAttr con,
                                         DataType data);
  mlir::LLVM::GlobalOp box(mlir::OpBuilder &b, mlir::Location loc, ConAttr con, mlir::Type type);
  mlir::LLVM::GlobalOp run(mlir::OpBuilder &b, mlir::Location loc, ConAttr con, CtorOp ctor);
  static bool isMemoCell(const layout::Cell &cell);
  mlir::LLVM::LLVMFuncOp cafRelease(mlir::OpBuilder &b);
  mlir::LLVM::GlobalOp global(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef prefix,
                              mlir::Type type, bool isConstant,
                              llvm::function_ref<mlir::Value(mlir::OpBuilder &)> init);
  mlir::Value addressOf(mlir::OpBuilder &b, mlir::Location loc, mlir::LLVM::GlobalOp global);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Location loc, mlir::Type structType,
                   mlir::ValueRange members);
  mlir::LLVM::GlobalOp
  staticCell(mlir::OpBuilder &b, mlir::Location loc, CtorOp ctor,
             llvm::function_ref<llvm::SmallVector<mlir::Value>(mlir::OpBuilder &, unsigned field)>
                 components);
  mlir::Value string(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef bytes);
  mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, BigAttr value);

  mlir::ModuleOp module;
  const Layouts &layouts;
  mlir::SymbolTable &symbols;
  unsigned globals = 0;
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Type>, mlir::LLVM::GlobalOp> statics;
  llvm::StringMap<mlir::LLVM::GlobalOp> messages;
  // The static memo cells, in the order they were written.
  llvm::SmallVector<mlir::LLVM::GlobalOp> cafs;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_STATICDATA_H
