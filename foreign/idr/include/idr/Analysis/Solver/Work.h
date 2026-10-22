// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a solve did, counted in its problem's own units (a transfer made, an
// edge or a label read, a value visited), never in time, which the machine
// and its load decide. The pass that runs a solve reports the count as its
// `work` statistic, which the scale relation reads at a program's size and
// at twice it: a solve whose work grows faster than the program is found on
// programs small enough to compile in a test.
//
// A solve counts where it runs, in a plain integer, and each of its units
// (a component, one function's solve) adds its count once, when the unit
// ends. Every unit does the same work whatever the schedule, so the sum is
// the same at any thread count.
#ifndef IDR_ANALYSIS_SOLVER_WORK_H
#define IDR_ANALYSIS_SOLVER_WORK_H

#include <atomic>
#include <cstdint>

namespace idr::solver {

class Work {
public:
  // Adds what one unit of the solve did.
  void add(std::uint64_t steps) { total.fetch_add(steps, std::memory_order_relaxed); }

  // Everything the solve's units added.
  std::uint64_t steps() const { return total.load(std::memory_order_relaxed); }

private:
  std::atomic<std::uint64_t> total{0};
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_WORK_H
