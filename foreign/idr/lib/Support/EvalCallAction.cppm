// idr.support:evalcallaction: idr-eval replacing a closed call by its
// results, as an action (perform).
export module idr.support:evalcallaction;

import idr.mlir;

import :taggedaction;

export namespace idr::support {

// idr-eval replaces a closed call by its results.
struct EvalCallAction : TaggedAction<EvalCallAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-eval-call";
};

} // namespace idr::support
