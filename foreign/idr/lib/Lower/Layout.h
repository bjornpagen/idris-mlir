// Data layout for idr-lower (LOW-DATA-1): how a !idr.data value is spread
// over scalar slots.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/StringMap.h"

namespace idr::lower {

struct Layout {
  mlir::Type tag;                       // null when the type has at most one constructor
  llvm::SmallVector<mlir::Type> slots;
  // For each constructor name: for each field, the slots of its components.
  llvm::StringMap<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

  llvm::SmallVector<mlir::Type> types() const;
  unsigned offset() const { return tag ? 1 : 0; }
};

class Layouts {
public:
  explicit Layouts(mlir::ModuleOp m) : module(m) {}

  // The layout of the data type named `name`, computed once.
  const Layout &get(mlir::StringAttr name);

  // The runtime components of a field or value type.
  llvm::SmallVector<mlir::Type> components(mlir::Type type);

private:
  mlir::ModuleOp module;
  llvm::DenseMap<mlir::StringAttr, Layout> cache;
};

} // namespace idr::lower
