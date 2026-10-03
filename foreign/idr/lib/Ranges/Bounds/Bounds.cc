// Whether bounds fit a small.
module idr.ranges;

import idr.mlir;

bool idr::ranges::Bounds::fits() const noexcept { return lo && hi; }
