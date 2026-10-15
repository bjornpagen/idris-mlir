// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants idr-lower writes as globals: strings, bigs outside the
// small range, boxes, among them the memo cells of constant thunks, the
// messages of crashes, and the cells of constant arrays. Each is named from
// its content, `__idr.<kind>.<hash>`, so a name says what the global holds
// and never when it was written: two functions lowered on two threads that
// write the same constant write the same global, and the program keeps one.
// A content is digested from its bytes, or from the canonical text of its
// attributes and types, which no printing flag reaches.

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

#include <string>
#include <utility>

namespace idr::conversion {

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
  // data. Usable in code and in the initializer of a global.
  llvm::SmallVector<mlir::Value> constant(mlir::OpBuilder &b, mlir::Location loc,
                                          mlir::Attribute value, mlir::Type type);

  // The static cell of the constant array `global`: its header, then its
  // data.
  mlir::Value constantArray(mlir::OpBuilder &b, mlir::Location loc,
                            mlir::memref::GlobalOp global);

  // What Runtime::merge reads: the globals written, by name, each with the
  // digest of the content its name was made from; and the names of the
  // static memo cells.
  struct Written {
    mlir::LLVM::GlobalOp global;
    Digest key;
  };
  const llvm::StringMap<Written> &written() const { return globals; }
  const llvm::StringSet<> &memoCells() const { return cafs; }

  // Whether two contents met under one name, which was reported at the op.
  bool collided() const { return collision; }

private:
  // A datum's name and the digest of the content it is made from.
  struct Named {
    std::string name;
    Digest key;
  };
  // The name of a datum of `kind` whose content is `key`, interned: a name
  // already given to another content is reported at `loc`.
  Named intern(mlir::Location loc, llvm::StringRef kind, Digest key);
  // The name of the box `con` of `type`.
  Named boxName(mlir::Location loc, ConAttr con, mlir::Type type);
  // The names of the cells of the run `con` of `type`, first to last.
  llvm::SmallVector<Named> runNames(mlir::Location loc, ConAttr con, mlir::Type type);
  // "caf" for a static memo cell of constructor `tag` of `data`, "box" for
  // any other.
  llvm::StringRef kindOf(DataType data, unsigned tag) const;
  // What a field of `type` holding `value` contributes to its cell's content:
  // a scalar as its canonical digest, an unboxed sum as its constructor and
  // fields, a reference as the name of what it points at.
  std::string fieldKey(mlir::Location loc, mlir::Attribute value, mlir::Type type);
  // A cell's content: its type, its constructor and its fields' contents.
  static Digest cellKey(mlir::Type type, const Ctor &ctor, llvm::ArrayRef<std::string> fields);

  llvm::SmallVector<mlir::Value> unboxed(mlir::OpBuilder &b, mlir::Location loc, ConAttr con);
  mlir::LLVM::GlobalOp box(mlir::Location loc, ConAttr con, mlir::Type type);
  mlir::LLVM::GlobalOp run(mlir::Location loc, ConAttr con, mlir::Type type);
  static bool isMemoCell(const layout::Cell &cell);
  // The global `name`, or null when it is not yet written.
  mlir::LLVM::GlobalOp find(llvm::StringRef name) const;
  mlir::LLVM::GlobalOp global(llvm::StringRef name, Digest key, mlir::Type type, bool isConstant,
                              unsigned alignment,
                              llvm::function_ref<mlir::Value(mlir::OpBuilder &)> init);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Location loc, mlir::Type structType,
                   mlir::ValueRange members);
  // The static cell of the constructor `tag` laid out as `cell`, each
  // field's components given by `components`.
  mlir::LLVM::GlobalOp
  staticCell(const Named &named, const layout::Cell &cell, unsigned tag,
             llvm::function_ref<llvm::SmallVector<mlir::Value>(mlir::OpBuilder &, unsigned field)>
                 components);
  mlir::Value string(mlir::OpBuilder &b, mlir::Location loc, llvm::StringRef bytes);
  mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, BigAttr value);

  mlir::Location at;
  const Layouts &layouts;
  // Where the globals are built until the merge.
  mlir::OwningOpRef<mlir::ModuleOp> scratch;
  // Each name given, with the content it was made from.
  ContentNames names;
  // The boxes already named, since a box's name reaches every datum it
  // holds.
  llvm::DenseMap<std::pair<mlir::Attribute, mlir::Type>, Named> boxNames;
  llvm::StringMap<Written> globals;
  llvm::StringSet<> cafs;
  bool collision = false;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_STATICDATA_H
