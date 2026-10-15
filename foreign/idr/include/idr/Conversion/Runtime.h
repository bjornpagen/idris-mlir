// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower adds to a function besides converted ops: calls of the
// runtime's C functions, cells, counting, static data and crashes. Each
// worker of the lowering has its own Runtime and writes only into it and
// into the function it converts; merge then brings the workers' functions
// and globals into the module, in name order.

#ifndef IDR_CONVERSION_RUNTIME_H
#define IDR_CONVERSION_RUNTIME_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/StaticData.h"

#include "mlir/Analysis/DataLayoutAnalysis.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

class Runtime {
public:
  // A runtime for lowering the functions of `module`, which it never
  // writes: merge does. `dataLayouts` is the module's, which convert-to-llvm
  // reads too.
  Runtime(mlir::ModuleOp module, const Layouts &layouts,
          const mlir::DataLayoutAnalysis &dataLayouts);

  // How convert-to-llvm will convert the memref types idr-lower leaves (a
  // buffer of words a legal op holds): the same converter over the same data
  // layouts, so that a descriptor built here is the one it reads.
  const mlir::LLVMTypeConverter &llvmTypeConverter() const { return llvmTypes; }

  // Calls the runtime function `name` with `args`, returning `result` (or
  // nothing when it is null). The call names its callee; merge declares it.
  mlir::Value call(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name, mlir::Type result,
                   mlir::ValueRange args);

  // A crash at `loc` reporting `cause`: idris_rt_crash, which does not
  // return.
  void crash(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef cause);

  // The same, where `condition` holds at runtime.
  void crashIf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value condition,
               llvm::StringRef cause);

  // Where code that need not end may go on: an effect no MLIR pass
  // removes, and LLVM keeps too, so a loop that may not terminate stays.
  void mayLoop(mlir::OpBuilder &b, mlir::Location loc);

  // A new cell of `size` bytes with its header: count 1 and `info`
  // (idris_rt_cell).
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, unsigned size,
                       layout::CellInfo info);

  // Writes the header of a cell: count 1 and `info`.
  void storeHeader(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
                   layout::CellInfo info);

  // The info word of a cell's header (offset 4), and its write: a force
  // writes the state a memo cell is in.
  mlir::Value loadInfo(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);
  void storeInfo(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, mlir::Value info);

  void store(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
             llvm::ArrayRef<layout::Slot> slots, mlir::ValueRange values);
  llvm::SmallVector<mlir::Value> load(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
                                      llvm::ArrayRef<layout::Slot> slots);

  // Writes a word at the address of a word of a cell, a destination.
  void storeWord(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address, mlir::Value value);

  // The tag of a box: the low bits of its info word.
  mlir::Value loadTag(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

  // One more, or one less, reference for each counted component of a value
  // (idris_rt_inc, idris_rt_dec); `counted` says which components are.
  void inc(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange components,
           llvm::ArrayRef<bool> counted);
  void dec(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange components,
           llvm::ArrayRef<bool> counted);

  // Whether the cell holds the only reference to itself, where it may be
  // reused: count 1, and not in a stack frame, whose cell a callee it was
  // lent to must never take over.
  mlir::Value exclusive(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

  // The components of the constant `value` of type `type`: scalars as LLVM
  // constants, strings, bigs outside the small range and boxes (memo cells
  // among them) as static data. Usable in code and in the initializer of a
  // global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // The static cell of the constant array `global`.
  mlir::Value constantArray(mlir::OpBuilder &b, mlir::Location loc,
                            mlir::memref::GlobalOp global);

  // What every worker wrote, into `module` through `symbols`, once every
  // function is lowered: one declaration per runtime function the functions
  // call, in name order, then one global per name of static data, in name
  // order, at the start of the module; then @__idr_release_cafs, which
  // releases what the module's static memo cells hold when the program
  // ends (idris_rt_caf_release on each, in name order), made in every module
  // so that the entry calls it without asking. Fails, having reported it,
  // when one function is called with two types or one name holds two
  // contents.
  static mlir::LogicalResult merge(mlir::ModuleOp module, mlir::SymbolTable &symbols,
                                   llvm::ArrayRef<Runtime *> workers);

private:
  // The call of the runtime function `name`, by name.
  mlir::LLVM::CallOp callOp(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                            mlir::Type result, mlir::ValueRange args);

  // Calls `name` on the pointer of each counted component.
  void countEach(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                 mlir::ValueRange components, llvm::ArrayRef<bool> counted);

  mlir::ModuleOp module;
  mlir::LLVMTypeConverter llvmTypes;
  StaticData statics;
  // Each runtime function called, with the type its calls have.
  llvm::StringMap<mlir::LLVM::LLVMFunctionType> called;
  bool mistyped = false;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RUNTIME_H
