// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
#include <atomic>
#include <cstdint>
namespace idr::detail {
struct FamilyAttrStorage {
  mutable std::atomic<uint64_t> asked{0};
};
}
