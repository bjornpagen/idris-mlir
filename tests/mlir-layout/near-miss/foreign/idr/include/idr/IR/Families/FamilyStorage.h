// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
#include <atomic>
#include <cstdint>
namespace idr::detail {
class KeptDigest {
private:
  mutable std::atomic<uint64_t> low{0}, high{0};
};
}
