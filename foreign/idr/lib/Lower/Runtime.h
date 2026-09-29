// What idr-lower adds to a module besides converted ops: calls of the
// runtime's C functions, static data, cells and crashes, in executable or
// JIT mode.
#pragma once

#include "Lower/Layout.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

#include <string>

namespace idr::lower {

class Runtime {
public:
  Runtime(mlir::ModuleOp m, Layouts &l, bool jitMode) : module(m), layouts(l), jit(jitMode) {}

  // Whether the code is lowered for compile-time evaluation, where every
  // cell comes from the arena and is never counted.
  bool isJit() const { return jit; }

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

  // A new cell of `size` bytes with its header: count 1 and `info`.
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, unsigned size, uint32_t info);
  void store(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
             llvm::ArrayRef<Slot> slots, mlir::ValueRange values);
  llvm::SmallVector<mlir::Value> load(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell,
                                      llvm::ArrayRef<Slot> slots);
  // The i32 at offset 4 of a cell: a box's tag or a closure's label.
  mlir::Value loadInfo(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

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

  mlir::ModuleOp module;
  Layouts &layouts;
  bool jit;
  unsigned globals = 0;
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Type>, mlir::LLVM::GlobalOp> statics;
  llvm::StringMap<mlir::LLVM::GlobalOp> messages;
  llvm::SmallVector<unsigned> usedCode;
};

// The name of the code of the label numbered `id`.
std::string codeName(unsigned id);

// The message of a crash: its cause and the Idris location.
std::string crashMessage(mlir::Location loc, llvm::StringRef cause);

} // namespace idr::lower
