// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a solve did, counted in its problem's own units (a transfer made, an
// edge or a label read, a value visited), never in time, which the machine
// and its load decide. The pass that runs a solve reports the count as its
// `work` statistic, which the scale relation reads at a program's size and
// at twice it: a solve whose work grows faster than the program is found on
// programs small enough to compile in a test.
//
// A count is a plain integer, added to only by the thread that holds it:
// no state of ours is shared between threads. A solve whose units run in
// parallel keeps each unit's count in that unit's own slot and adds their
// sum once every unit has returned (Schedule.h). Every unit does the same
// work whatever the schedule, so the sum is the same at any thread count.
#ifndef IDR_ANALYSIS_SOLVER_WORK_H
#define IDR_ANALYSIS_SOLVER_WORK_H

#include <cstdint>

namespace idr::solver {

class Work {
public:
  // A count is one solve's: a copy would split what it counted.
  Work() = default;
  Work(const Work &) = delete;
  Work &operator=(const Work &) = delete;

  // Adds what one unit of the solve did.
  void add(std::uint64_t steps) { total += steps; }

  // Everything the solve's units added.
  std::uint64_t steps() const { return total; }

private:
  std::uint64_t total = 0;
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_WORK_H
