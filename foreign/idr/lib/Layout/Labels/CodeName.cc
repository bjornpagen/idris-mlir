// The name of the code of a label's closures.
module idr.layout;

import idr.mlir;

std::string idr::layout::codeName(unsigned id) { return ("__idr_code_" + llvm::Twine(id)).str(); }
