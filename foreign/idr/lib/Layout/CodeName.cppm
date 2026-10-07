// idr.layout:codename: the name of the code of a label's closures, which
// idr-lower defines and idr-eval's child looks up.
export module idr.layout:codename;

import idr.mlir;

export namespace idr::layout {

// The name of the code of the label numbered `id`.
std::string codeName(unsigned id) { return ("__idr_code_" + llvm::Twine(id)).str(); }

// The entry a forced suspension's cell points at: it returns the value
// the first force wrote, and it is not a label the reifier looks up.
std::string lazyDoneName(unsigned id) { return ("__idr_lazy_" + llvm::Twine(id)).str(); }

} // namespace idr::layout
