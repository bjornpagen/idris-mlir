// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folds of constants made of constants, written once over where a
// constant lives (fold::Where), as the one runtime fold and the guards'
// conditions are: a constructor of constant fields, a closure of constant
// captures, a constructor's tag and field read off a constant, a constant
// read at another type, and what a walk down a constant's chain of one
// constructor reads (a numeral's layers, a list's elements), a cell at a
// time as the place holds it, so neither place makes a constant to walk
// one. A fold may give a value of the program instead, an operand of its op
// or of the op that built one (Folded). Each op's own condition is its
// `meaning`, a template over such a place, defined in Ops/Folds.h; the
// place says how it reads a constant's cells and fields, how it holds a
// part, how it makes the constructor or closure, and which op built a
// value, so the attribute fold and the e-graph ask one condition. The
// attribute place makes the attribute MLIR's fold gives; the e-graph's
// makes a constant of its own, which becomes an attribute only where the
// write-back places it. IdrDialect.h includes this after the attributes
// and types it reads.
#ifndef IDR_IR_FOLD_PARTS_H
#define IDR_IR_FOLD_PARTS_H

#include "idr/IR/Fold.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/OpDefinition.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <variant>

namespace idr::fold {

// A cell of a constant constructor read where its run holds it: cell `at`
// of `run`. Its fields are the cell's own, but for the spine of every cell
// before the last, which is the run's next cell; so a walk along a run of
// any length reads only what the run holds, and makes no attribute.
struct RunCell {
  ConAttr run;
  unsigned at;

  Tag tag() const;
  // The cells of the run after this one, each of its constructor and the
  // spine of the one before: what a walk that only counts them adds at once.
  std::uint64_t after() const;
  // The run's last cell.
  RunCell last() const;
  // Field `index` as the cell holds it; null for the spine of a cell the
  // run goes on past, which is the next cell.
  mlir::Attribute field(unsigned index) const;
  // Field `index` as a cell: the run's next where it is the spine, or the
  // first cell of the constant constructor the cell holds there; none for
  // a field that is no constructor.
  std::optional<RunCell> next(unsigned index) const;
};

// A place whose constants include constructors and closures. A constructor
// constant is read a cell at a time (Cell): its first cell; a cell's tag;
// the cells of its run after it, and the run's last; its field `index` as
// the next cell, where that field is a constructor, and as an element, an
// integer or a string, the string kept by `scope` where the place makes
// one. Its field `index` is also a constant at `type`, where the place
// holds it as one without making a part it does not hold. Besides: whether
// a constant may be a field or a capture of `type` (the leaf rule of a
// constant's parts, `buildable`'s); the constructor of `data` or the
// closure of `callee` made of constants, at `type`; and a constant as one
// at `type`, the same value under another type. A place holds values too
// (Given): a value of the program as the place holds it, which a fold may
// give in place of a constant (`given`, of an operand the op reads, the
// value and what the place knows of it); and the op of a class that built
// a value, with its operands' values (`builtBy<OpT>`, a member template, so
// no concept names it).
template <class W>
concept Composite = Where<W> && requires(W &where, const typename W::Operand &constant,
                                         llvm::ArrayRef<typename W::Operand> parts,
                                         mlir::Type type, unsigned index, const DataType &data,
                                         mlir::FlatSymbolRefAttr callee, mlir::Value value,
                                         const typename W::Cell &cell, Scope &scope) {
  typename W::Given;
  typename W::Cell;
  { where.given(value, constant) } -> std::same_as<typename W::Given>;
  { where.cellOf(constant) } -> std::same_as<std::optional<typename W::Cell>>;
  { where.tagAt(cell) } -> std::same_as<Tag>;
  { where.afterAt(cell) } -> std::same_as<std::uint64_t>;
  { where.lastAt(cell) } -> std::same_as<typename W::Cell>;
  { where.nextAt(cell, index) } -> std::same_as<std::optional<typename W::Cell>>;
  { where.integerAt(cell, index) } -> std::same_as<std::optional<llvm::APInt>>;
  { where.strAt(scope, cell, index) } -> std::same_as<std::optional<const idris_rt_str *>>;
  { where.fieldOf(constant, index, type) } -> std::same_as<std::optional<typename W::Result>>;
  { where.buildable(constant, type) } -> std::same_as<bool>;
  { where.constructor(type, data, parts) } -> std::same_as<std::optional<typename W::Result>>;
  { where.closure(type, callee, parts) } -> std::same_as<std::optional<typename W::Result>>;
  { where.same(type, constant) } -> std::same_as<std::optional<typename W::Result>>;
};

// What a fold gives: a constant it makes, or a value of the program, an
// operand of its op or of an op that built one, as the place holds values.
template <class W>
using Folded = std::variant<typename W::Result, typename W::Given>;

// The op of class `OpT` that built a value, and its operands' values, as the
// place holds them.
template <class W, class OpT>
struct Built {
  OpT op;
  llvm::SmallVector<typename W::Given, 4> operands;
};

// The attribute place of the composite folds, MLIR's own: a constant is an
// attribute, a constant constructor read a cell at a time where its run
// holds it (RunCell), a field read off one is the attribute it holds (a
// run's rest made where it is asked, as MLIR's fold gives a field whole),
// and a constructor or closure
// is the attribute made of its parts, where idr.constant holds it at the
// result's type. A value is the program's own, and the op that built one
// is its defining op.
class InParts : public InAttributes {
public:
  using Given = mlir::Value;
  using Cell = RunCell;

  explicit InParts(mlir::MLIRContext *context) : InAttributes(context), context(context) {}

  mlir::Value given(mlir::Value value, mlir::Attribute) const { return value; }

  template <class OpT>
  std::optional<Built<InParts, OpT>> builtBy(mlir::Value value, mlir::Attribute) const {
    auto op = value.getDefiningOp<OpT>();
    if (!op)
      return std::nullopt;
    return Built<InParts, OpT>{op, llvm::SmallVector<mlir::Value, 4>(op->getOperands())};
  }

  std::optional<mlir::Attribute> fieldOf(mlir::Attribute constant, unsigned index,
                                         mlir::Type type) const;
  bool buildable(mlir::Attribute constant, mlir::Type type) const {
    return constant && fold::buildable(constant, type);
  }
  std::optional<mlir::Attribute> constructor(mlir::Type type, const DataType &data,
                                             llvm::ArrayRef<mlir::Attribute> fields) const;
  std::optional<mlir::Attribute> closure(mlir::Type type, mlir::FlatSymbolRefAttr callee,
                                         llvm::ArrayRef<mlir::Attribute> captures) const;
  std::optional<mlir::Attribute> same(mlir::Type type, mlir::Attribute constant) const;

  std::optional<RunCell> cellOf(mlir::Attribute constant) const;
  Tag tagAt(const RunCell &cell) const { return cell.tag(); }
  std::uint64_t afterAt(const RunCell &cell) const { return cell.after(); }
  RunCell lastAt(const RunCell &cell) const { return cell.last(); }
  std::optional<RunCell> nextAt(const RunCell &cell, unsigned index) const {
    return cell.next(index);
  }
  std::optional<llvm::APInt> integerAt(const RunCell &cell, unsigned index) const {
    return fold::integerOf(cell.field(index));
  }
  std::optional<const idris_rt_str *> strAt(Scope &scope, const RunCell &cell,
                                            unsigned index) const {
    return fold::strOf(scope, cell.field(index));
  }

private:
  mlir::MLIRContext *context;
};

// What the attribute place's fold gives, as MLIR's fold hook returns it.
inline mlir::OpFoldResult foldResultOf(const std::optional<Folded<InParts>> &folded) {
  if (!folded)
    return {};
  if (const auto *constant = std::get_if<mlir::Attribute>(&*folded))
    return *constant;
  return std::get<mlir::Value>(*folded);
}

// Where idr.constant holds a constructor of `data`, or a closure, at `type`:
// the type's data type is `data` itself, or the type carries labels; and,
// either way, it stands as static data does there. The one statement of
// where each stands, which the attributes' own checks and the e-graph's
// constants, which hold no attribute, ask.
bool constructorStandsAt(const DataType &data, mlir::Type type);
bool closureStandsAt(mlir::Type type);

// The successor layers of a constant numeral of `data`, read a run at a
// time, however long: each successor's one field is the next layer, until
// a cell of the constructor with no field, its zero. None for a value that
// is no constant.
template <Composite W>
std::optional<std::uint64_t> numeralLayers(const W &where, const typename W::Operand &numeral,
                                           DataType data) {
  std::uint64_t layers = 0;
  std::optional<typename W::Cell> at = where.cellOf(numeral);
  while (at && !data.ctor(where.tagAt(*at)).fields.empty()) {
    layers += 1 + where.afterAt(*at);
    at = where.nextAt(where.lastAt(*at), 0);
  }
  if (!at)
    return std::nullopt;
  return layers;
}

// The cells a constant list of `shape` holds its elements in, in order,
// read cell by cell however long its runs; none for a value that is no
// constant list.
template <Composite W>
std::optional<footprint::Vector<typename W::Cell>>
elementCells(const W &where, const typename W::Operand &list, families::ListShape shape) {
  footprint::Vector<typename W::Cell> cells;
  for (std::optional<typename W::Cell> at = where.cellOf(list); at;
       at = where.nextAt(*at, 1 - shape.element)) {
    if (where.tagAt(*at) == shape.nil)
      return cells;
    cells.push_back(*at);
  }
  return std::nullopt;
}

} // namespace idr::fold

#endif // IDR_IR_FOLD_PARTS_H
