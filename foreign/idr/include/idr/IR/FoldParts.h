// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folds of constants made of constants, written once over where a
// constant lives (fold::Where), as the one runtime fold and the guards'
// conditions are: a constructor of constant fields, a closure of constant
// captures, a constructor's tag and field read off a constant, and a
// constant read at another type. Each op's own condition is its `meaning`,
// a template over such a place, defined in Ops/Folds.h; the place says how
// it reads a constant's constructor and fields, how it holds a part, and
// how it makes the constructor or closure, so the attribute fold and the
// e-graph ask one condition. The attribute place makes the attribute MLIR's
// fold gives; the e-graph's makes a constant of its own, which becomes an
// attribute only where the write-back places it.
#ifndef IDR_IR_FOLD_PARTS_H
#define IDR_IR_FOLD_PARTS_H

#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/ArrayRef.h"

#include <concepts>
#include <optional>

namespace idr {
class ConAttr;
class DataType;
} // namespace idr

namespace idr::fold {

// A place whose constants include constructors and closures: the tag of the
// constructor a constant is, and its field `index` as a constant at `type`,
// where the place holds it as one without making a part it does not hold;
// whether a constant may be a field or a capture of `type` (the leaf rule
// of a constant's parts, `buildable`'s); the constructor of `data` or the
// closure of `callee` made of constants, at `type`; and a constant as one
// at `type`, the same value under another type.
template <class W>
concept Composite = Where<W> && requires(W &where, const typename W::Operand &constant,
                                         llvm::ArrayRef<typename W::Operand> parts,
                                         mlir::Type type, unsigned index, const DataType &data,
                                         mlir::FlatSymbolRefAttr callee) {
  { where.tagOf(constant) } -> std::same_as<std::optional<Tag>>;
  { where.fieldOf(constant, index, type) } -> std::same_as<std::optional<typename W::Result>>;
  { where.buildable(constant, type) } -> std::same_as<bool>;
  { where.constructor(type, data, parts) } -> std::same_as<std::optional<typename W::Result>>;
  { where.closure(type, callee, parts) } -> std::same_as<std::optional<typename W::Result>>;
  { where.same(type, constant) } -> std::same_as<std::optional<typename W::Result>>;
};

// The attribute place of the composite folds, MLIR's own: a constant is an
// attribute, a field read off a constant constructor is the attribute it
// holds (a run's rest made where it is asked), and a constructor or closure
// is the attribute made of its parts, where idr.constant holds it at the
// result's type.
class InParts : public InAttributes {
public:
  explicit InParts(mlir::MLIRContext *context) : InAttributes(context), context(context) {}

  std::optional<Tag> tagOf(mlir::Attribute constant) const;
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

private:
  mlir::MLIRContext *context;
};

// Where idr.constant holds a constructor of `data`, or a closure, at `type`:
// the type's data type is `data` itself, or the type carries labels; and,
// either way, it stands as static data does there. The one statement of
// where each stands, which the attributes' own checks and the e-graph's
// constants, which hold no attribute, ask.
bool constructorStandsAt(const DataType &data, mlir::Type type);
bool closureStandsAt(mlir::Type type);

// Field `index` of a constant constructor where the attribute holds it as
// one: any field of a single cell, and any but the spine of a run's first;
// null for a run's spine, whose rest no attribute holds until one is made.
mlir::Attribute fieldHeld(ConAttr constant, unsigned index);

} // namespace idr::fold

#endif // IDR_IR_FOLD_PARTS_H
