// The static shape of a value: what is known of it where it is built, over
// the runtime leaves it holds.
//
// A pattern is a hole (a runtime leaf), a constant, or a constructor or
// closure over the patterns of its operands. A shape is taken once per
// argument of a call, with its leaves; the clone is rebuilt from the
// pattern alone, each hole standing for the parameter that holds its leaf,
// so that what the key says and what the clone computes cannot differ.
#pragma once

#include "Specialize/Quantity.h"
#include "idr/Idr.h"

#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <variant>
#include <vector>

namespace idr::specialize {

struct Pattern;

// A runtime leaf: which leaf of its key it is, counting the key's holes in
// order, and how often the clone may use it: the product of the quantities
// on its way down from the parameter, through fields and captures.
struct Hole {
  unsigned index;
  Quantity quantity;
};

struct Constant {
  mlir::Attribute value;
};

struct Con {
  mlir::SymbolRefAttr ctor; // `@T::@C`
  std::vector<Pattern> fields;
};

struct Closure {
  mlir::FlatSymbolRefAttr callee;
  std::vector<Pattern> captures;
};

struct Pattern {
  std::variant<Hole, Constant, Con, Closure> node;
  mlir::Type type;
  // Where the value was built: the ops that rebuild it are reported there.
  mlir::LocationAttr loc;

  bool isHole() const { return std::holds_alternative<Hole>(node); }
};

// The leaf `value`, used `quantity` times, as hole `index`.
Pattern leafOf(mlir::Value value, unsigned index, Quantity quantity);

// The pattern of `value`, which is used `quantity` times: its runtime
// leaves are appended to `leaves`, and its holes numbered from the size
// `leaves` had. Poison is no value, so it is a leaf, as is a value of erased
// type: erased is not constant.
Pattern shapeOf(mlir::Value value, Quantity quantity, llvm::SmallVectorImpl<mlir::Value> &leaves);

// Whether `value` is closed: a constant, or a constructor or closure of
// closed values.
bool isClosed(mlir::Value value);

// Whether `pattern` has structure: a constructor or a closure, as a node
// or as a constant. A lone scalar is none: a number specialized on would
// make a clone per value, where LLVM weighs constant arguments better.
bool hasStructure(const Pattern &pattern);

// `pattern` with its holes numbered from `next`, which advances past them.
void renumber(Pattern &pattern, unsigned &next);

// How long a chain of clones that each take a proper part of the value can
// be: its constructors and closures, and the value of a big, which counts
// down by one. Scalars take no part apart.
uint64_t unrollSize(const Pattern &pattern);

// The pattern as a key: a typed attribute, whose labels are names and not
// symbol uses, so that a key keeps no function alive. A constructor or
// closure constant is keyed as the node it folds from, so that both key the
// same clone.
mlir::Attribute keyOf(const Pattern &pattern);

// The value `pattern` stands for, rebuilt at `b`, each hole taken from
// `holes` by its number.
mlir::Value rebuild(mlir::OpBuilder &b, const Pattern &pattern,
                    llvm::ArrayRef<mlir::Value> holes);

// The functions `pattern` names as closure labels.
void labels(const Pattern &pattern, llvm::SmallVectorImpl<mlir::FlatSymbolRefAttr> &out);

} // namespace idr::specialize
