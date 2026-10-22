// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants the program holds as globals: strings, bigs outside the
// small range, cells of data and memo cells of constant suspensions, the
// cells of constant arrays, `nothing` (the cell poison of a cell pointer
// is), and the texts a crash site names (its function and its file).
// idr-lower-statics makes each once, before any function is lowered; the
// lowering names it. Each is named from its content, `__idr$<kind>$<hash>`
// (reservedName), so both sides reach one global by the one function of
// the content, `StaticNames`, and the name says what the global holds,
// never when it was made.

#ifndef IDR_CONVERSION_STATICDATA_H
#define IDR_CONVERSION_STATICDATA_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <string>

namespace idr::conversion {

// A memref.global read as the constant array idr-lower writes as a static
// cell: constant, its initial value constant elements of words. Only `of`
// makes one, once per global, so nothing that writes the cell checks the
// global again. That it is aligned no further than a cell's element is the
// program's verifier's rule.
class ConstantArray {
public:
  // `global` as a constant array, or an internal error at it.
  static mlir::FailureOr<ConstantArray> of(mlir::memref::GlobalOp global);

  mlir::MemRefType type() const { return arrayType; }
  mlir::ElementsAttr elements() const { return values; }
  // The name of its static cell (StaticNames::array), read once, here.
  llvm::StringRef name() const { return cellName; }

private:
  ConstantArray(mlir::MemRefType type, mlir::ElementsAttr elements, std::string name)
      : arrayType(type), values(elements), cellName(std::move(name)) {}

  mlir::MemRefType arrayType;
  mlir::ElementsAttr values;
  std::string cellName;
};

// Whether a global may be written: a memo cell, whose first force writes
// its state and value, is the one static datum that is.
enum class Mutability : std::uint8_t { Constant, Written };

// The name of each static datum, a function of its content alone: what
// idr-lower-statics names a global and what the lowering's address of it
// reads. A content is digested from its value, an attribute the context
// uniques, so equal contents are one name; a cell after the first of a
// spine run is its constant's name and its place in the run.
class StaticNames {
public:
  static std::string string(llvm::StringRef bytes);
  static std::string big(BigAttr value);
  // The cell of the constant constructor `con`, the `k`th of its spine run.
  static std::string cell(ConAttr con, unsigned k);
  static std::string array(mlir::memref::GlobalOp global);
  static std::string nothing();
  // A text of a crash site: a function's name, or a source file's.
  static std::string text(llvm::StringRef bytes);
  // The per-thread cursors of the program's homes, one slot per home site.
  static std::string homes();
};

// The address of the static datum `name`, made by idr-lower-statics: what
// the lowering writes for every constant that is static data.
mlir::Value staticAddress(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef name);

// The word of the big literal `value`, as the runtime reads its text: a
// small value's tagged word, or the address of the static bignum
// idr-lower-statics made for it. Usable in code and in the initializer of a
// global.
mlir::Value bigConstant(mlir::OpBuilder &b, mlir::Location loc, BigAttr value);

// The maker of every static datum of one program, used once, by
// idr-lower-statics, serially: each global is made at the start of the
// program through its symbol table, the first time its name is asked, so a
// datum named twice is made once.
class StaticData {
public:
  StaticData(mlir::Operation *program, mlir::SymbolTable &symbols, const Layouts &layouts,
             unsigned headerBytes);

  // The datum of the constant `value` of type `type`, if it is one, and the
  // data it holds, each made once.
  void constant(mlir::Attribute value, mlir::Type type);
  // The static cell of `array`: its header, then its data.
  void constantArray(const ConstantArray &array);
  // The cell poison of a cell pointer is.
  void nothing();
  // A text of a crash site.
  void text(llvm::StringRef bytes);
  // The per-thread cursor of each of `sites` homes, each null until its
  // first put: the memory of a shard is its thread's.
  void homes(unsigned sites);

private:
  // The components a field holding `value` of type `type` puts in a static
  // cell, built with `b`: a scalar's constant, an unboxed sum's words, and a
  // datum's address, the datum made first.
  llvm::SmallVector<mlir::Value> components(mlir::OpBuilder &b, mlir::Attribute value,
                                            mlir::Type type);
  // The cells of the constant constructor `con`, the run of its spine from
  // the last back to the first, each made once.
  void cells(ConAttr con);
  void string(llvm::StringRef bytes);
  void big(BigAttr value);

  // The global `name`, made with its initializer by `init` the first time.
  template <std::invocable<mlir::OpBuilder &> Init>
  void global(llvm::StringRef name, mlir::Type type, Mutability mutability, unsigned alignment,
              Init &&init) {
    if (symbols.lookup(name))
      return;
    mlir::OpBuilder b = mlir::OpBuilder::atBlockBegin(&program->getRegion(0).front());
    auto made = mlir::LLVM::GlobalOp::create(b, at, type, mutability == Mutability::Constant,
                                             mlir::LLVM::Linkage::Private, name,
                                             mlir::Attribute(), alignment);
    b.createBlock(&made.getInitializerRegion());
    mlir::LLVM::ReturnOp::create(b, at, mlir::Value(init(b)));
    symbols.insert(made);
  }
  // A static cell's header, the first two members of its struct: count 0,
  // the runtime's mark of a cell no count frees, and the info word.
  llvm::SmallVector<mlir::Value> header(mlir::OpBuilder &b, layout::CellInfo info);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Type structType, mlir::ValueRange members);

  mlir::Operation *program;
  mlir::SymbolTable &symbols;
  const Layouts &layouts;
  unsigned headerBytes;
  mlir::Location at;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_STATICDATA_H
