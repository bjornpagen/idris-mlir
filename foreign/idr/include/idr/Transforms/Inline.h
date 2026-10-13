// idr-inline: the force preparation, then MLIR's inliner deciding as MLton
// does. (`inline` is a keyword, so the area's namespace is `inlining`.)
//
// The preparation rewrites forces into calls and builds the functions the
// rewrite needs before any decision or call graph is taken: a function
// built later would be missing from the graph, and the inliner would erase
// what its body still calls.
#ifndef IDR_TRANSFORMS_INLINE_H
#define IDR_TRANSFORMS_INLINE_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

class FuncOp;
class References;

#define GEN_PASS_DECL_IDRINLINE
#include "idr/Transforms/Passes.h.inc"

namespace inlining {

// The functions whose body only forces an argument and returns the value:
// the wrappers ForceAtCapture sees through.
llvm::SmallVector<idr::FuncOp> forceWrappers(mlir::ModuleOp module);

// ForceAtCapture on every closure that names a wrapper; true when it rewrote.
bool forceAtCapture(mlir::ModuleOp module, mlir::SymbolTable &symbols,
                    llvm::ArrayRef<idr::FuncOp> wrappers);

// ForceOfOneConstant on every force of a one-use closure constant the sites
// list; true when it rewrote.
bool forceOfOneConstant(mlir::ModuleOp module, const idr::References &references);

} // namespace inlining
} // namespace idr

#endif // IDR_TRANSFORMS_INLINE_H
