// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants idr-lower writes as globals: strings, bigs outside the
// small range, boxes, among them the memo cells of constant thunks, the
// messages of crashes, the cells of constant arrays, and `nothing`, the
// cell poison of a cell pointer is. Each is named from its content,
// `__idr$<kind>$<hash>` (reservedName), so a name says what the global
// holds and never when it was written: two functions lowered on two threads
// that write the same constant write the same global, and the program keeps
// one. A content is digested from its bytes, or from the canonical text of
// its attributes and types, which no printing flag reaches.

#ifndef IDR_CONVERSION_STATICDATA_H
#define IDR_CONVERSION_STATICDATA_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"

#include <optional>
#include <string>
#include <utility>

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

private:
  ConstantArray(mlir::MemRefType type, mlir::ElementsAttr elements)
      : arrayType(type), values(elements) {}

  mlir::MemRefType arrayType;
  mlir::ElementsAttr values;
};

class StaticData {
public:
  // The globals are built in a module of their own, never in the program,
  // so that one function's lowering touches nothing outside it;
  // Runtime::merge moves them into the program once every function is
  // lowered. Each is at `location`, the program's: no function's.
  StaticData(mlir::Location location, const Layouts &layouts);

  // Whether a lowered component is static data, which holds no count: the
  // address of a global, or a constant word.
  static bool isStatic(mlir::Value component);

  // The address of the bytes of `text`.
  mlir::Value message(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef text);

  // The components of the constant `value` of type `type`: scalars as LLVM
  // constants, strings, bigs outside the small range and boxes as static
  // data, and poison of a cell pointer as `nothing`. Usable in code and in
  // the initializer of a global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // The static cell of `array`: its header, then its data.
  mlir::Value constantArray(mlir::OpBuilder &b, mlir::Location loc, const ConstantArray &array);

  // What Runtime::merge reads: the globals written, by name, each with the
  // digest of the content its name was made from.
  struct Written {
    mlir::LLVM::GlobalOp global;
    Digest key;
  };
  const llvm::StringMap<Written> &written() const { return globals; }

  // Whether two contents met under one name, which was reported at the op.
  bool collided() const { return collision; }

private:
  // A constant as static data: its components, and what it contributes to
  // the content, and so to the name, of a datum that holds it: a scalar its
  // canonical digest, an unboxed sum its constructor and its fields' keys,
  // a reference the name of what it points at. A datum's key follows from
  // its fields' keys, so one walk writes a datum and names it.
  struct Datum {
    std::string key;
    llvm::SmallVector<mlir::Value> components;
  };
  // A datum's name and the digest of the content it is made from.
  struct Named {
    std::string name;
    Digest key;
  };

  // The datum of the constant `value` of type `type`, its components built
  // with `b` at `loc`.
  Datum datum(mlir::OpBuilder &b, mlir::Location loc, mlir::Attribute value, mlir::Type type);
  // The global of the box `con` of type `type`, written once however many
  // constants hold it.
  mlir::LLVM::GlobalOp box(mlir::Location loc, ConAttr con, mlir::Type type);
  // The static cell of the constructor `tag` of `data`, of type `type`,
  // each field's datum given by `fields` with the initializer's builder:
  // the global written under the name of its content, or the one already
  // written under it.
  mlir::LLVM::GlobalOp
  staticCell(mlir::Location loc, DataType data, Tag tag, mlir::Type type,
             llvm::function_ref<llvm::SmallVector<Datum>(mlir::OpBuilder &)> fields);
  // The global of the bytes of `bytes` as a string.
  mlir::LLVM::GlobalOp string(mlir::Location loc, llvm::StringRef bytes);
  // The word of the big `value`, whose canonical digest is `key`.
  mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, BigAttr value, Digest key);
  // The cell `nothing`: a header with no object slot, count 0.
  mlir::LLVM::GlobalOp nothing(mlir::Location loc);

  // The name of a datum of `kind` whose content is `key`, interned: a name
  // already given to another content is reported at `loc`.
  Named intern(mlir::Location loc, llvm::StringRef kind, Digest key);
  // A cell's content: its type, its constructor and its fields' keys.
  Digest cellKey(mlir::Type type, const Ctor &ctor, llvm::ArrayRef<std::string> fields);
  // "caf" for a static memo cell, "box" for any other.
  static llvm::StringRef kindOf(DataType data);
  // A static cell's header, the first two members of its struct: its
  // types, and its words for a cell of `info`.
  static llvm::SmallVector<mlir::Type> headerTypes(mlir::MLIRContext *ctx);
  static llvm::SmallVector<mlir::Value> header(mlir::OpBuilder &b, mlir::Location loc,
                                               layout::CellInfo info);

  // The global `name`, or none when it is not yet written.
  std::optional<mlir::LLVM::GlobalOp> find(llvm::StringRef name) const;
  mlir::LLVM::GlobalOp global(llvm::StringRef name, Digest key, mlir::Type type, bool isConstant,
                              unsigned alignment,
                              llvm::function_ref<mlir::Value(mlir::OpBuilder &)> init);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Location loc, mlir::Type structType,
                   mlir::ValueRange members);

  mlir::Location at;
  const Layouts &layouts;
  // Where the globals are built until the merge.
  mlir::OwningOpRef<mlir::ModuleOp> scratch;
  // Each name given, with the content it was made from.
  ContentNames names;
  // The boxes already written, since a box's global reaches every datum
  // that holds it.
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Type>, mlir::LLVM::GlobalOp> boxes;
  llvm::StringMap<Written> globals;
  bool collision = false;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_STATICDATA_H
