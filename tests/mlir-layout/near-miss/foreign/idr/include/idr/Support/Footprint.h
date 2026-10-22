// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
namespace idr::footprint::detail {
struct Ledger {
  long held = 0;
  long peak = 0;
};
inline constinit thread_local Ledger ledger;
}
