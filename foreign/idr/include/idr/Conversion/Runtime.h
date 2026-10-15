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

// The runtime functions the ops call, generated from the ops' marks: for
// each op class, its functions and how each takes the op's operands.
#include "idr/IR/IdrRuntimeAbi.inc"

#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

#include <optional>

namespace idr::conversion {

// The function among an op's runtime functions `functions` (one, or one
// per kind of the operand that has several) that takes the op's operands
// of `operands`' types: a double as a double, an integer as `isSigned`
// says.
const idr::runtime::Function &functionTaking(llvm::ArrayRef<idr::runtime::Function> functions,
                                             mlir::TypeRange operands,
                                             std::optional<bool> isSigned);

// The runtime function `op` calls, as the table generated from the ops'
// marks says (IdrRuntimeAbi.inc).
template <typename OpT>
const idr::runtime::Function &runtimeFunctionOf(OpT op) {
  std::optional<bool> isSigned;
  if constexpr (requires { op.getIsSigned(); })
    isSigned = op.getIsSigned();
  return functionTaking(idr::runtime::Abi<OpT>::functions, op->getOperandTypes(), isSigned);
}

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

  // Calls the runtime function `name` with `args`, returning `result` (or
  // nothing when it is null). The call names its callee; merge declares it.
  mlir::Value call(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name, mlir::Type result,
                   mlir::ValueRange args);

  // Calls `function`, a runtime function of `op`, with `operands`, the
  // components of the op's operands in order, each passed as the function
  // takes it (runtime::Kind): an integer of the op's width widened as its
  // kind says, a buffer as its cell, its first byte and its size, a world as
  // nothing. Gives the result as the function gives it, null for none.
  mlir::Value call(mlir::OpBuilder &b, mlir::Operation *op, const idr::runtime::Function &function,
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

  // A new cell of the constructor `tag` laid out as `cell`: count 1 and
  // its info (idris_rt_cell), then the words after the header the layout
  // has.
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, const layout::Cell &cell,
                       unsigned tag);

  // Writes the header of the cell at `address`, of the constructor `tag`
  // laid out as `cell`: count 1, `info` (the cell's own, or the same cell in
  // a stack frame), and the words after the header the layout has.
  void storeHeader(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                   const layout::Cell &cell, unsigned tag, layout::CellInfo info);

  // Writes the words after the header a cell of the constructor `tag` laid
  // out as `cell` has: the count of its object slots, where the header
  // cannot hold it, and its constructor's group, for a sum of more
  // constructors than a header's tag holds.
  void storeCellWords(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                      const layout::Cell &cell, unsigned tag);

  // The tag of a box of `data`: its header's, and its group's where the sum
  // has more constructors than a header's tag holds; an i64.
  mlir::Value loadTag(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, DataType data,
                      const Layouts &layouts);

  // The info word of a cell's header (offset 4), and its write: a memo
  // cell's state is written there.
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

  // One more, or one less, reference for each counted component of a value
  // (idris_rt_inc, idris_rt_dec); `counted` says which components are.
  // Static data holds no count, so a component that is the address of a
  // global or a constant word takes no call: nothing would change at run
  // time.
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

  // What every worker wrote, into `program` through `symbols`, its table,
  // once every function is lowered: one declaration per runtime function
  // the functions call, in name order, then one global per name of static
  // data, in name order, at the start of the program; then
  // @__idr_release_cafs, which releases what the program's static memo
  // cells hold when it ends (idris_rt_caf_release on each, in name order),
  // made in every program so that the entry calls it without asking. Fails,
  // having reported it, when one function is called with two types or one
  // name holds two contents.
  static mlir::LogicalResult merge(mlir::Operation *program, mlir::SymbolTable &symbols,
                                   llvm::ArrayRef<Runtime *> workers);

private:
  // What a runtime function is declared as: the type its calls have, and
  // whether it returns.
  struct Callee {
    mlir::LLVM::LLVMFunctionType type;
    bool noreturn = false;
  };

  // The call of the runtime function `name`, by name.
  mlir::LLVM::CallOp callOp(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                            mlir::Type result, mlir::ValueRange args, bool noreturn);

  // Calls `name` on the pointer of each counted component.
  void countEach(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                 mlir::ValueRange components, llvm::ArrayRef<bool> counted);

  mlir::LLVMTypeConverter llvmTypes;
  StaticData statics;
  llvm::StringMap<Callee> called;
  bool mistyped = false;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RUNTIME_H
