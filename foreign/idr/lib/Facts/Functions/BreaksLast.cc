// `idr.break_last`.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

bool facts::breaksLast(func::FuncOp fn) { return fn->hasAttr("idr.break_last"); }
