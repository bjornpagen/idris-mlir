// What a natural nothing else bounds is.
module idr.ranges;

import idr.mlir;

idr::ranges::Bounds idr::ranges::natural() noexcept { return {0, std::nullopt}; }
