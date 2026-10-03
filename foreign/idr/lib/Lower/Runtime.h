// What idr-lower adds to a module besides converted ops: calls of the
// runtime's C functions, static data, cells and crashes, in executable or
// JIT mode.
#pragma once

#include "idr/Idr.h"

#include "idris_rt.h"

#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringMap.h"

#include <expected>
#include <memory>
#include <string>

import idr.layout;

namespace idr::lower {

// The layouts idr-lower builds values in (idr.layout).
using layout::Cell;
using layout::CellInfo;
using layout::codeName;
using layout::Element;
using layout::Label;
using layout::Layouts;
using layout::Slot;
using layout::SumLayout;
using layout::tagMask;

class Runtime {
public:
  Runtime(mlir::ModuleOp m, Layouts &l, bool jitMode)
      : module(m), layouts(l), jit(jitMode),
        llvmTypes(m.getContext(), mlir::LowerToLLVMOptions(m.getContext(), mlir::DataLayout(m))) {}

  // Whether the code is lowered for compile-time evaluation, where every
  // cell comes from the arena and is never counted.
  bool isJit() const { return jit; }

  // How convert-to-llvm will convert the memref types idr-lower leaves (an
  // array's view of its elements, Arrays.cc): the same converter over the
  // module's data layout, so that a descriptor built here is the one it
  // reads.
  const mlir::LLVMTypeConverter &llvmTypeConverter() const { return llvmTypes; }

  // Calls the runtime function `name` with `args`, returning `result` (or
  // nothing when it is null). The declaration is added on first use.
  mlir::Value call(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                   mlir::Type result, mlir::ValueRange args);

  // A crash at `loc` reporting `cause`: idris_rt_crash, or in
  // JIT mode idris_rt_eval_crash, neither of which returns.
  void crash(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef cause);
  // The same, where `condition` holds at runtime.
  void crashIf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value condition,
               llvm::StringRef cause);

  // Where code that need not end may go on: an effect no MLIR pass
  // removes, and LLVM keeps too, so a loop that may not terminate stays. In
  // JIT mode it is a tick of the evaluator's meter, which is what stops a
  // metered call that does not end.
  void mayLoop(mlir::OpBuilder &b, mlir::Location loc);

  // A new cell of `size` bytes with its header: count 1 and `info`
  // (idris_rt_cell), or in JIT mode an arena cell with count 0, which is
  // never counted.
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, unsigned size, CellInfo info);
  // Writes the header of a cell: count 1 and `info`.
  void storeHeader(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, CellInfo info);
  void store(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
             llvm::ArrayRef<Slot> slots, mlir::ValueRange values);
  llvm::SmallVector<mlir::Value> load(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
                                      llvm::ArrayRef<Slot> slots);
  // The address of a word of a cell: a destination.
  mlir::Value address(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, Slot slot);
  // Writes a word at an address `address` gave.
  void storeWord(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address, mlir::Value value);
  // The tag of a box: the low bits of its info word (offset 4).
  mlir::Value loadTag(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

  // One more, or one less, reference for each counted component of a value
  // (idris_rt_inc, idris_rt_dec); `counted` says which components are. In
  // JIT mode every cell is persistent, and both do nothing.
  void inc(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange components,
           llvm::ArrayRef<bool> counted);
  void dec(mlir::OpBuilder &b, mlir::Location loc, mlir::ValueRange components,
           llvm::ArrayRef<bool> counted);
  // Whether the cell holds the only reference to itself, where it may be
  // reused: count 1, and not in a stack frame, whose cell a callee it was
  // lent to must never take over.
  mlir::Value exclusive(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);
  // The empty value of a counted component: a null pointer, or the word 0.
  mlir::Value null(mlir::OpBuilder &b, mlir::Location loc, mlir::Type component);
  // Whether a lowered component is static data, which holds no count: the
  // address of a global, or a constant word.
  static bool isStatic(mlir::Value component);

  // The components of the constant `value` of type `type`:
  // scalars as LLVM constants, strings, bigs outside the small range, boxes
  // and closures as static data. Usable in code and in the initializer of a
  // global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // The address of the code of `label`'s closures: a function taking the
  // closure, then the arguments.
  mlir::Value code(mlir::OpBuilder &b, mlir::Location loc, const Label &label);
  // The type of that code, and the code itself, once the functions have
  // their converted signatures.
  mlir::FunctionType codeType(const Label &label);
  void emitCode();

private:
  mlir::LLVM::GlobalOp global(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef prefix,
                              mlir::Type type,
                              llvm::function_ref<mlir::Value(mlir::OpBuilder &)> init);
  mlir::Value string(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef bytes);
  mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, BigAttr value);
  mlir::Value addressOf(mlir::OpBuilder &b, mlir::Location loc, mlir::LLVM::GlobalOp global);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Location loc, mlir::Type structType,
                   mlir::ValueRange members);
  // A cell as static data, count 0: its header, then the components of
  // each field in the cell's address order.
  mlir::LLVM::GlobalOp staticCell(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef prefix,
                                  const Cell &cell,
                                  llvm::function_ref<llvm::SmallVector<mlir::Value>(
                                      mlir::OpBuilder &, unsigned field)>
                                      components);
  // Calls `name` on the pointer of each counted component.
  void countEach(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name,
                 mlir::ValueRange components, llvm::ArrayRef<bool> counted);

  mlir::ModuleOp module;
  Layouts &layouts;
  bool jit;
  mlir::LLVMTypeConverter llvmTypes;
  unsigned globals = 0;
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Type>, mlir::LLVM::GlobalOp> statics;
  llvm::StringMap<mlir::LLVM::GlobalOp> messages;
  llvm::SetVector<unsigned> usedCode;
  // The module's symbols, looked up once per name: idr-lower asks for them
  // per op, and a module can hold many thousands.
  mlir::SymbolTableCollection symbols;
};

// The message of a crash: its cause and the Idris location.
std::string crashMessage(mlir::Location loc, llvm::StringRef cause);

} // namespace idr::lower
