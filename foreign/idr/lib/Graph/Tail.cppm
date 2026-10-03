// idr.graph:tail: tail position, where what an op computes is what its
// function returns, and tail position modulo a constructor, where it is a
// field of the constructor the function returns.
export module idr.graph:tail;

import idr.mlir;
import idr.dialect;

export namespace idr::graph {

// Whether the results of `op` pass unchanged to its function's return: the
// op right after it is the terminator and passes exactly them, and is the
// function's return or the yield of a match in tail position itself. A self
// call there becomes the next iteration of a loop in the same frame
// (idr-tail-loops), and a call of another function on the caller's cycle
// of calls a tail call (idr-tail-calls).
bool inTailPosition(mlir::Operation *op);

// Whether `terminator` ends a tail position and passes on exactly the
// results of the op before it.
bool passesOnPrevious(mlir::Operation *terminator);

// Whether `op` calls `fn` itself.
bool isSelfCall(mlir::Operation *op, mlir::func::FuncOp fn);

// The fields of the box an idr.con or idr.reuse builds.
mlir::OperandRange fieldsOf(mlir::Operation *op);

// A tail modulo constructor: the self call whose result is field `index`
// of the constructor `built`, which the block's terminator passes on. The
// result may enter or leave a grade on its way to the field (`grades`,
// nearest the field first): a grade has no runtime form, and goes with
// the call.
struct Modulo {
  mlir::func::CallOp call;
  mlir::Operation *built;
  unsigned index;
  llvm::SmallVector<mlir::Operation *, 2> grades;
};

// The tail modulo constructor of `block` in `fn`: the constructor right
// before its terminator, and a self call in the block, with only ops between
// them that neither touch memory nor can fail, which the call then moves
// past, whose one result reaches a field of the constructor.
std::optional<Modulo> moduloAt(mlir::Block &block, mlir::func::FuncOp fn);

// Whether `call` is the self call of a tail modulo constructor, in a block
// in tail position: idr-trmc writes its result into the constructor the
// block returns, which it builds before the call.
bool inTailPositionModuloConstructor(mlir::func::CallOp call);

} // namespace idr::graph
