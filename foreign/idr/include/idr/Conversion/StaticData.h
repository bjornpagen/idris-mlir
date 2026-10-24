// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants the program holds as globals: strings, bigs outside the
// small range, cells of data and memo cells of constant suspensions, the
// cells of constant arrays, `nothing` (the cell poison of a cell pointer
// is), the texts a crash site names (its function and its file), the name
// of each function whose call keeps an account of what it holds, and the
// thread's cursors of the program's homes. idr-lower makes each once, in
// its serial phase, before any function is lowered (makeStatics), and keeps
// the global it made in a table by what the datum is made of, a uniqued
// attribute where one holds it: every reference the functions' lowering
// writes reads the table, so no reference names its datum again. A global
// is named once, when it is made, by its kind and its place in the order
// of making, a reserved name no other symbol has.

#ifndef IDR_CONVERSION_STATICDATA_H
#define IDR_CONVERSION_STATICDATA_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"

#include <concepts>
#include <cstdint>
#include <map>
#include <optional>

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
  // The global's name, which a memref.get_global names.
  mlir::StringAttr global() const { return globalName; }

private:
  ConstantArray(mlir::MemRefType type, mlir::ElementsAttr elements, mlir::StringAttr global)
      : arrayType(type), values(elements), globalName(global) {}

  mlir::MemRefType arrayType;
  mlir::ElementsAttr values;
  mlir::StringAttr globalName;
};

// Whether a global may be written: a memo cell, whose first force writes
// its state and value, is the one static datum that is.
enum class Mutability : std::uint8_t { Constant, Written };

// The word of a big `value` in the small range, as the runtime holds it
// (idris_rt_small_word); none past it, where the big is a static bignum.
// What the making and a reference both read of a big, the one test of its
// size, on its APInt.
std::optional<std::int64_t> smallWordOf(const llvm::APInt &value);

// A natural numeral's value as a big's: unsigned, so read with one bit
// more than its 64, never negative.
llvm::APInt naturalValue(std::uint64_t value);

// The two texts a crash site names: its function's and its file's.
struct SiteTexts {
  mlir::FlatSymbolRefAttr function;
  mlir::FlatSymbolRefAttr file;
};

// Every static datum of one program and the global made for it, by what it
// is made of: a string, a big and a cell by the attribute the context
// uniques, a natural past the small range by its value, a constant array by
// its memref.global's name, a crash site's texts by its site, an account's
// text by its function's name. Filled once, by the making (StaticData), and
// read only after, by every function's lowering at once. A datum a reference
// names that the making did not make is an internal error: the making met
// every constant, crash site, account, constant array and home the
// functions hold.
class Statics {
public:
  mlir::FlatSymbolRefAttr string(mlir::StringAttr value) const;
  // A big or a natural past the small range: its static bignum.
  mlir::FlatSymbolRefAttr big(BigAttr value) const;
  mlir::FlatSymbolRefAttr natural(std::uint64_t value) const;
  // The first cell of the constant constructor `con`'s spine run.
  mlir::FlatSymbolRefAttr cell(ConAttr con) const;
  mlir::FlatSymbolRefAttr array(mlir::StringAttr global) const;
  SiteTexts site(SiteAttr site) const;
  mlir::FlatSymbolRefAttr account(mlir::StringAttr function) const;
  mlir::FlatSymbolRefAttr nothing() const;
  // The per-thread cursors of the program's homes, one slot per home site.
  mlir::FlatSymbolRefAttr homes() const;

private:
  friend class StaticData;

  llvm::DenseMap<mlir::StringAttr, mlir::FlatSymbolRefAttr> strings;
  llvm::DenseMap<BigAttr, mlir::FlatSymbolRefAttr> bigs;
  // Ordered by value: a natural past the small range may be any word, so
  // no value is free to stand for an empty slot.
  std::map<std::uint64_t, mlir::FlatSymbolRefAttr> naturals;
  llvm::DenseMap<ConAttr, mlir::FlatSymbolRefAttr> cells;
  llvm::DenseMap<mlir::StringAttr, mlir::FlatSymbolRefAttr> arrays;
  llvm::DenseMap<SiteAttr, SiteTexts> sites;
  llvm::DenseMap<mlir::StringAttr, mlir::FlatSymbolRefAttr> accounts;
  mlir::FlatSymbolRefAttr nothingCell;
  mlir::FlatSymbolRefAttr homeCursors;
};

// The address of the static datum `global`, made by the making of static
// data: what the lowering writes for every reference to one.
mlir::Value staticAddress(mlir::OpBuilder &b, mlir::Location loc, mlir::FlatSymbolRefAttr global);

// The components of the constant `value` of type `type`, in code or in the
// initializer of a global: a scalar's LLVM constant, an unboxed sum's words,
// a small big's word, and the address of the static datum `statics` holds
// for a string, a big outside the small range, a cell (a memo cell among
// them) and poison of a cell pointer. The one reading of a constant's
// static form, which the lowering and a static cell's fields both use.
llvm::SmallVector<mlir::Value> constantComponents(mlir::OpBuilder &b, mlir::Location loc,
                                                  const Layouts &layouts, const Statics &statics,
                                                  mlir::Attribute value, mlir::Type type);

// The maker of every static datum of one program, used once, by
// makeStatics, serially. What a datum holds is met before it is made and
// named when it is met, so the cells of a constant constructor, whose
// initializers name the data their fields hold, are made last (`made`),
// once every datum is named; any other datum holds none and is made when
// it is met. A datum met again is the one made the first time.
class StaticData {
public:
  // The maker of `program`'s static data, `nothing` made first: poison of
  // a cell pointer may stand anywhere a function is lowered.
  StaticData(mlir::Operation *program, const Layouts &layouts, unsigned headerBytes);

  // The datum of the constant `value` of type `type`, if it is one, and the
  // data it holds, each met once, from a list of what is left to meet.
  void constant(mlir::Attribute value, mlir::Type type);
  // The static cell of `array`: its header, then its data.
  void constantArray(const ConstantArray &array);
  // The texts of a crash site.
  void site(SiteAttr site);
  // The text of the name of a function that keeps an account.
  void account(mlir::StringAttr function);
  // The per-thread cursor of each of `sites` homes, each null until its
  // first put: the memory of a shard is its thread's.
  void homes(unsigned sites);

  // Every cell run met, made now that every datum is named; then the table.
  Statics made() &&;

private:
  // A constant held by what is being met, at the type of its place: what
  // is left to meet.
  struct Held {
    mlir::Attribute value;
    mlir::Type type;
  };
  // The cells of a constant constructor, one per cell of its spine run,
  // named when it is met and made by `made`.
  struct Run {
    ConAttr con;
    llvm::SmallVector<mlir::FlatSymbolRefAttr> cells;
  };

  // The cell poison of a cell pointer is.
  void nothing();
  // The run of `con`, named, its fields pushed onto `left`.
  void run(ConAttr con, llvm::SmallVectorImpl<Held> &left);
  // The globals of `run`, each cell's initializer naming what it holds.
  void cells(const Run &run);
  void string(mlir::StringAttr value);
  void big(BigAttr value);
  void natural(std::uint64_t value);
  // The bignum of `value`, a big past the small range: its header, its
  // signed count of limbs and its limbs.
  mlir::FlatSymbolRefAttr bignum(const llvm::APInt &value);
  // The text of `bytes`, made the first time its bytes are met.
  mlir::FlatSymbolRefAttr text(llvm::StringRef bytes);

  // A new global's name: `kind`, and its place in the order of making.
  mlir::FlatSymbolRefAttr name(llvm::StringRef kind);

  // The global `symbol`, made with its initializer by `init`.
  template <std::invocable<mlir::OpBuilder &> Init>
  void global(mlir::FlatSymbolRefAttr symbol, mlir::Type type, Mutability mutability,
              unsigned alignment, Init &&init) {
    mlir::OpBuilder b = mlir::OpBuilder::atBlockBegin(&program->getRegion(0).front());
    auto datum = mlir::LLVM::GlobalOp::create(b, at, type, mutability == Mutability::Constant,
                                              mlir::LLVM::Linkage::Private, symbol.getValue(),
                                              mlir::Attribute(), alignment);
    b.createBlock(&datum.getInitializerRegion());
    mlir::LLVM::ReturnOp::create(b, at, mlir::Value(init(b)));
  }
  // A static cell's header, the first two members of its struct: count 0,
  // the runtime's mark of a cell no count frees, and the info word.
  llvm::SmallVector<mlir::Value> header(mlir::OpBuilder &b, layout::CellInfo info);
  mlir::Value pack(mlir::OpBuilder &b, mlir::Type structType, mlir::ValueRange members);

  mlir::Operation *program;
  const Layouts &layouts;
  unsigned headerBytes;
  mlir::Location at;
  Statics table;
  // Every text made, by its bytes: a crash site holds its texts as its own
  // strings, no uniqued attribute of their own, so equal texts of two sites
  // are told equal here, once per site.
  llvm::StringMap<mlir::FlatSymbolRefAttr> texts;
  llvm::SmallVector<Run> runs;
  // The globals named so far: the next one's place in the order of making.
  unsigned named = 0;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_STATICDATA_H
