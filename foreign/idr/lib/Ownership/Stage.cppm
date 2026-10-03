// idr.ownership:stage: the module attribute that marks the owned stage.
export module idr.ownership:stage;

import idr.mlir;

export namespace idr::ownership {

// The module attribute that marks the owned stage, and its value.
inline constexpr llvm::StringLiteral stageAttr = "idr.stage";
inline constexpr llvm::StringLiteral ownedStage = "owned";

} // namespace idr::ownership
