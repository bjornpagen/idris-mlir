// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower adds to a function besides converted ops: calls of the
// runtime's C functions, cells, counting, static data and crashes. Each
// worker of the lowering has its own Runtime and writes only into it and
// into the function it converts; merge then brings the workers'
// declarations and globals into the program, in name order.

#ifndef IDR_CONVERSION_RUNTIME_H
#define IDR_CONVERSION_RUNTIME_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/StaticData.h"

// The runtime's C functions idr-lower calls, generated from the ODS: an
// op's, Abi<Op>::entry, and the lowering's own, helper::<name>, each with
// how it takes its operands and gives its result.
#include "idr/IR/IdrRuntimeAbi.inc"

#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace idr::conversion {

// The C symbol of the program's entry, which idr-entry defines and the
// driver keeps when it internalizes the rest: the lowering owns the entry,
// so its name is said here once.
inline constexpr llvm::StringLiteral entrySymbol = "main";

// The declaration of the runtime function `function`, detached, in no
// module: the one declaration builder, which merge and idr-entry use. Its
// type is the function's kinds'; a Bool parameter or result is zeroext, as
// the C ABI extends a bool in its caller and its callee, and a function
// that does not return is noreturn, so LLVM treats what follows a call as
// unreachable.
mlir::LLVM::LLVMFuncOp runtimeDeclaration(mlir::Location loc,
                                          const idr::runtime::Function &function);

class Runtime {
public:
  // A runtime for lowering the functions of a program at `at`, which it
  // never writes: merge does. `options` are what convert-to-llvm reads from
  // the module's data layout, made once, before any worker, since reading
  // a data layout fills its caches.
  Runtime(mlir::Location at, const Layouts &layouts, const mlir::LowerToLLVMOptions &options);

  // How upstream's memref patterns, here and in convert-to-llvm, convert a
  // memref to its descriptor: the same options, so that a descriptor built
  // here is the one convert-to-llvm reads. Inside a function every memref
  // op works on it; addMemrefConversions teaches it this lowering's memrefs.
  mlir::LLVMTypeConverter &llvmTypeConverter() { return llvmTypes; }
  const mlir::LLVMTypeConverter &llvmTypeConverter() const { return llvmTypes; }

  // Calls `function` with `args`, C values already of its kinds (a World
  // operand of an op's function has none). The call is typed by the
  // function, and names its callee, which merge declares once with the same
  // type, so MLIR's verification of the call's symbol use checks each call
  // against the one declaration. A caller wanting the result takes
  // `.getResult()`.
  mlir::LLVM::CallOp call(mlir::OpBuilder &b, mlir::Location loc,
                          const idr::runtime::Function &function, mlir::ValueRange args);

  // Calls `function`, the runtime function of `op`, with `operands`, the
  // components of the op's operands in order, each passed as the function
  // takes it: the world as nothing, an integer of the op's width extended
  // to 64 bits as Signed or Unsigned says, any other as its one component.
  mlir::LLVM::CallOp call(mlir::OpBuilder &b, mlir::Operation *op,
                          const idr::runtime::Function &function,
                          llvm::ArrayRef<mlir::ValueRange> operands);

  // A crash at `loc` reporting `cause`: idris_rt_crash, which does not
  // return.
  void crash(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef cause);

  // The same, where `condition` holds at runtime.
  void crashIf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value condition,
               llvm::StringRef cause);

  // Where code that need not end may go on: an effect no MLIR pass
  // removes, and LLVM keeps too, so a loop that may not terminate stays.
  void mayLoop(mlir::OpBuilder &b, mlir::Location loc);

  // A new cell laid out as `cell`: count 1 and its info (idris_rt_cell),
  // then the cell's own words after the header.
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, const layout::Cell &cell);

  // Writes the header of the cell at `address`, laid out as `cell`: count
  // 1, `info` (the cell's own, or the same cell in a stack frame), and the
  // cell's own words after the header.
  void storeHeader(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                   const layout::Cell &cell, layout::CellInfo info);

  // Writes the words after the header a cell laid out as `cell` has, each
  // with its value: the count of its object slots, where the header cannot
  // hold it, and its constructor's group, for a sum of more constructors
  // than a header's tag holds.
  void storeCellWords(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                      const layout::Cell &cell);

  // The tag of a box of `data`: its header's, and its group's where the sum
  // has more constructors than a header's tag holds; an i64.
  mlir::Value loadTag(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, DataType data,
                      const Layouts &layouts);

  // The info word of a cell's header, at its offset in the runtime's header
  // (offsetof(idris_rt_header, info)), and its write: a memo cell's state is
  // written there.
  mlir::Value loadInfo(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);
  void storeInfo(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, mlir::Value info);

  // The components in `slots` at their offsets from `address`, which is
  // aligned to `align`: a cell's start (cellAlignment()), or an element's.
  void store(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address, unsigned align,
             llvm::ArrayRef<layout::Slot> slots, mlir::ValueRange values);
  llvm::SmallVector<mlir::Value> load(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                                      unsigned align, llvm::ArrayRef<layout::Slot> slots);

  // Writes a word at the address of a word of a cell, a destination.
  void storeWord(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address, mlir::Value value);

  // One more, or one less, reference for each of `references`, the counted
  // components of a value, which the caller selects (a lone cell is the
  // cell): idris_rt_inc, idris_rt_dec. Static data holds no count, so a
  // component that is the address of a global or a constant word takes no
  // call: nothing would change at run time.
  void inc(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange references);
  void dec(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange references);

  // Whether the cell holds the only reference to itself, where it may be
  // reused, as the runtime decides it (idris_rt_is_unique); an i1.
  mlir::Value exclusive(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

  // The components of the constant `value` of type `type`: scalars as LLVM
  // constants, strings, bigs outside the small range and boxes (memo cells
  // among them) as static data. Usable in code and in the initializer of a
  // global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // The static cell of the constant array `global`.
  mlir::Value constantArray(mlir::OpBuilder &b, mlir::Location loc, const ConstantArray &array);

  // What every worker wrote, into `program` through `symbols`, its table,
  // once every function is lowered: one declaration per runtime function
  // the functions call, in symbol order, then one global per name of
  // static data, in name order, at the start of the program. Fails, having
  // reported it, when one name of static data holds two contents, or a
  // runtime function's C name is a symbol of the program.
  static mlir::LogicalResult merge(mlir::Operation *program, mlir::SymbolTable &symbols,
                                   llvm::ArrayRef<Runtime *> workers);

private:
  // Calls `function`, idris_rt_inc or idris_rt_dec, on the pointer of each
  // of `references` that is no static datum.
  void countEach(mlir::OpBuilder &b, mlir::Location loc, const idr::runtime::Function &function,
                 mlir::ValueRange references);

  mlir::LLVMTypeConverter llvmTypes;
  StaticData statics;
  // The runtime functions this worker's calls name, by their entries in
  // the generated table: one entry per function, so its address is its
  // identity.
  llvm::SmallPtrSet<const idr::runtime::Function *, 16> called;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RUNTIME_H
