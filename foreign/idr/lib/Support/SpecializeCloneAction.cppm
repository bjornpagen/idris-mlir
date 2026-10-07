// idr.support:specializecloneaction: idr-specialize redirecting a call to a
// clone of its callee, as an action (perform).
export module idr.support:specializecloneaction;

import idr.mlir;

import :taggedaction;

export namespace idr::support {

// idr-specialize redirects a call to a clone of its callee.
struct SpecializeCloneAction : TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
};

} // namespace idr::support
