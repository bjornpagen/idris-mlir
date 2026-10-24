// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower adds to a function besides converted ops: calls of the
// runtime's C functions, crashes at their sites, cells, counting by the
// kind of each counted word, and references to static data. Every runtime
// function is declared and every static datum made in idr-lower's serial
// phase, before any function is lowered, so a Runtime writes nothing
// outside the function it lowers into: it holds no state but the table of
// the static data made, read only, and one serves every function at once.

#ifndef IDR_CONVERSION_RUNTIME_H
#define IDR_CONVERSION_RUNTIME_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/StaticData.h"

// The runtime's C ABI, then the C functions idr-lower calls, generated from
// the dialect's specification: an op's, Abi<Op>::entry, and the lowering's
// own, helper::<name>, each with how it takes its operands and gives its
// result, the counting entries of each kind of word, `increments` and
// `decrements`, and the list of them all, `functions`.
#include "idris_rt.h"
#include "idr/IR/Generated/RuntimeAbi.h.inc"

#include "mlir/Conversion/LLVMCommon/LoweringOptions.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

namespace idr::conversion {

// The C symbol of the program's entry, which idr-entry defines and the
// driver keeps when it internalizes the rest: the lowering owns the entry,
// so its name is said here once. No program symbol is it: every program
// symbol carries the program's prefix (Mangle.h).
inline constexpr llvm::StringLiteral entrySymbol = "main";

// The declaration of the runtime function `function`, detached, in no
// module: the one declaration builder, which idr-lower's serial phase uses.
// Its type is the function's kinds'; a byte parameter and a truth result,
// each narrower than an int, are zeroext, as the C compiler says of the
// runtime's definition, and a function that does not return is noreturn,
// so LLVM treats what follows a call as unreachable.
mlir::LLVM::LLVMFuncOp runtimeDeclaration(mlir::Location loc,
                                          const idr::runtime::Function &function);

// The LLVM type of the runtime function `function`, from its kinds alone:
// its declaration and every call of it have it.
mlir::LLVM::LLVMFunctionType runtimeFunctionType(mlir::MLIRContext *ctx,
                                                 const idr::runtime::Function &function);

// Whether what a load reads stays while the pointer it reads through names
// it: a data cell's fields and tag do, since a cell is immutable until its
// memory is reused, and a reuse launders the pointer; a memo cell's state
// and fields change under one pointer when it is forced.
enum class Contents : std::uint8_t { Stays, MayChange };

// Where a cell's header puts its two words, as the target lays out
// idris_rt_header: the count, then the info word, each an i32, the two one
// word. Read from the module's data layout through the layouts, never from
// the host's.
struct HeaderLayout {
  unsigned countAt;
  unsigned infoAt;
  unsigned bytes;

  static HeaderLayout of(const Layouts &layouts, mlir::MLIRContext *ctx);
};

class Runtime {
public:
  // The runtime of the lowering of a program whose values are laid out as
  // `layouts` and whose static data `statics` holds. `options` are what
  // convert-to-llvm reads from the module's data layout, made once, before
  // any function is lowered, since reading a data layout fills its caches.
  Runtime(mlir::MLIRContext *ctx, const Layouts &layouts, const Statics &statics,
          const mlir::LowerToLLVMOptions &options);

  // How upstream's memref patterns, here and in convert-to-llvm, convert a
  // memref to its descriptor: the same options, so that a descriptor built
  // here is the one convert-to-llvm reads.
  mlir::LLVMTypeConverter &llvmTypeConverter() { return llvmTypes; }
  const mlir::LLVMTypeConverter &llvmTypeConverter() const { return llvmTypes; }

  // The global made for each static datum the program's lowering names.
  const Statics &statics() const { return staticData; }

  // Calls `function` with `args`, C values already of its kinds. The call
  // names its callee, which idr-lower's serial phase declared with the same
  // type, so MLIR's verification of the call's symbol use checks it against
  // that one declaration. A function that never returns says so at the call
  // too, since linking the runtime replaces the declaration's attributes by
  // the definition's.
  mlir::LLVM::CallOp call(mlir::OpBuilder &b, mlir::Location loc,
                          const idr::runtime::Function &function, mlir::ValueRange args) const;

  // Calls `function`, the runtime function of `op`, with `operands`, the
  // components of the op's operands in order, each passed as the function
  // takes it: an integer of the op's width extended to 64 bits as Signed or
  // Unsigned says, any other as its one component.
  mlir::LLVM::CallOp call(mlir::OpBuilder &b, mlir::Operation *op,
                          const idr::runtime::Function &function,
                          llvm::ArrayRef<mlir::ValueRange> operands) const;

  // A crash of `cause` at `site`, given `reads`, the operands its line
  // reads (operandsRead): none, idris_rt_crash_at; or the operand a guard
  // found false, an integer the runtime prints, idris_rt_crash_operand_at.
  // Cold, and it does not return. The cause passes as its position in the
  // closed set, the function and the file as the program's one static text
  // of each, the line and column as immediates: nothing of a crash is text
  // made at its site.
  void crash(mlir::OpBuilder &b, mlir::Location loc, CrashCause cause, mlir::ValueRange reads,
             SiteAttr site) const;

  // A crash of the program's own string `message` at `site`, which a trusted
  // library gave idris_crash: idris_rt_crash_message_at.
  void crashWith(mlir::OpBuilder &b, mlir::Location loc, mlir::Value message,
                 SiteAttr site) const;

  // The same crash where `condition` holds at run time.
  void crashIf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value condition, CrashCause cause,
               mlir::ValueRange reads, SiteAttr site) const;

  // The machine out of memory where `condition` holds: a size found too
  // large before any allocation, which names no site.
  void outOfMemoryIf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value condition) const;

  // The four values every crash entry takes after what it says: its
  // function's and its file's texts (the globals made for its site), its
  // line and its column.
  llvm::SmallVector<mlir::Value, 4> siteOperands(mlir::OpBuilder &b, mlir::Location loc,
                                                 SiteAttr site) const;

  // A new counted cell laid out as `cell`: count 1 and its info, which the
  // runtime writes (idris_rt_cell), then the cell's own words after the
  // header. Fresh memory: no load of another cell's may be read through it.
  mlir::Value allocate(mlir::OpBuilder &b, mlir::Location loc, const layout::Cell &cell) const;

  // Writes the header of a cell of a lexical lifetime at `address`, laid out
  // as `cell`: count 0, the runtime's mark of a cell no count frees, its
  // info, and its own words.
  void storeUncountedHeader(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                            const layout::Cell &cell) const;

  // Writes the info word of the header of the cell at `address`, and the
  // cell's own words, laid out as `cell`: a recycled cell taking another
  // constructor's header, its count left as the take found it, 1.
  void storeInfoAndWords(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                         const layout::Cell &cell) const;

  // Writes the words after the header a cell laid out as `cell` has, each
  // with its value: the count of its object slots, where the header cannot
  // hold it, and its constructor's group, for a sum of more constructors
  // than a header's tag holds.
  void storeCellWords(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                      const layout::Cell &cell) const;

  // The tag of a cell of `data`: its header's, and its group's where the
  // sum has more constructors than a header's tag holds; an i64. `stays`
  // says the cell is immutable while the pointer names it, so the loads
  // carry LLVM's invariant group.
  mlir::Value loadTag(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, DataType data,
                      Contents stays) const;

  // The components in `slots` at their offsets from `address`, which is
  // aligned to `align`: a cell's start (cellAlignment()), or an element's.
  // A load of contents that stay as long as the pointer names them carries
  // LLVM's invariant group: a cell another constructor reuses, or a frame
  // slot written again, is a laundered pointer.
  void store(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address, unsigned align,
             llvm::ArrayRef<layout::Slot> slots, mlir::ValueRange values) const;
  llvm::SmallVector<mlir::Value> load(mlir::OpBuilder &b, mlir::Location loc, mlir::Value address,
                                      unsigned align, llvm::ArrayRef<layout::Slot> slots,
                                      Contents stays = Contents::MayChange) const;

  // A pointer to memory that held another cell, or will hold another at the
  // next run, made a pointer of its own for LLVM's invariant group: loads
  // through it see only what is written through it.
  mlir::Value launder(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell) const;

  // One more, or one less, reference for each counted component of a value,
  // `values` its components laid out as `components`: each by the entry of
  // its word's kind, which tests exactly what the kind leaves open.
  void inc(mlir::OpBuilder &b, mlir::Location loc, llvm::ArrayRef<layout::Component> components,
           mlir::ValueRange values) const;
  void dec(mlir::OpBuilder &b, mlir::Location loc, llvm::ArrayRef<layout::Component> components,
           mlir::ValueRange values) const;

  // One more, or one less, reference for one counted word of kind `word`.
  void inc(mlir::OpBuilder &b, mlir::Location loc, layout::Word word, mlir::Value value) const;
  void dec(mlir::OpBuilder &b, mlir::Location loc, layout::Word word, mlir::Value value) const;

  // Whether the counted cell holds the only reference to itself: its count
  // is 1 (idris_rt_is_unique); an i1.
  mlir::Value isUnique(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell) const;

private:
  const Layouts &layouts;
  const Statics &staticData;
  mlir::LLVMTypeConverter llvmTypes;
  HeaderLayout headerLayout;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_RUNTIME_H
