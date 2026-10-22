// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The memory the host lets a tool use, against which each function's
// e-graph is admitted by the bytes of its arena, whichever pass builds it,
// so the e-graphs in flight at once fit beside one another. The runtime's
// platform layer is the one reader of the host's limits: it reads a
// program's (the cgroup's memory.max on Linux; macOS has none to read),
// and the same reading, under the address-space limit `ulimit -v` sets and
// no more than the host's physical memory, reaches a tool through the
// runtime's C ABI, so no second reading of a cgroup or a limit exists here.
// Read the first time it is asked and kept for the process's life: a limit
// changed while a tool runs is not seen, and no caller pays for a read
// again.
#ifndef IDR_SUPPORT_MEMORY_H
#define IDR_SUPPORT_MEMORY_H

#include "idris_rt.h"

#include <cstdint>

namespace idr::support {

// The host's memory for this process, in bytes. The first call reads it,
// from inside the tool's run on the runtime's stack as every runtime call
// of a tool is; a pass asks it once per run, never per function.
inline std::uint64_t hostMemoryBytes() {
  static const std::uint64_t bytes = idris_rt_host_memory();
  return bytes;
}

} // namespace idr::support

#endif // IDR_SUPPORT_MEMORY_H
