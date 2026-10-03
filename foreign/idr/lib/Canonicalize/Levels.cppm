// idr.canonicalize:levels: region-simplify's values, by name.
export module idr.canonicalize:levels;

import idr.mlir;

using namespace mlir;

export namespace idr::canonicalize {

// The level `name` names (disabled, normal or aggressive), or none.
std::optional<GreedySimplifyRegionLevel> regionLevel(llvm::StringRef name) {
  return llvm::StringSwitch<std::optional<GreedySimplifyRegionLevel>>(name)
      .Case("disabled", GreedySimplifyRegionLevel::Disabled)
      .Case("normal", GreedySimplifyRegionLevel::Normal)
      .Case("aggressive", GreedySimplifyRegionLevel::Aggressive)
      .Default(std::nullopt);
}

} // namespace idr::canonicalize
