// idr.support:raiseaction: idr-specialize raising a call into a clone that
// takes its consumer, as an action (perform).
export module idr.support:raiseaction;

import idr.mlir;

import :taggedaction;

export namespace idr::support {

// idr-specialize raises a call into a clone that takes its consumer.
struct RaiseAction : TaggedAction<RaiseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-raise";
};

} // namespace idr::support
