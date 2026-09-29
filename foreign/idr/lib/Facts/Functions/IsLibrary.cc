// `idr.library`.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

bool facts::isLibrary(func::FuncOp fn) { return fn->hasAttr("idr.library"); }
