// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A solve that a budget may stop writes top for every function it did not
// finish, so its answer stays sound and the program is only less
// optimized: a budgeted problem whose lattice has no top is no problem the
// solver layer takes. The same problem with a top is one.

#include "idr/Analysis/Solver/Summarize.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Id.h"

enum class Top : unsigned char { Absent, Present };

// A lattice of one mark, with a top or without.
template <Top T>
struct Mark {
  unsigned char set = 0;

  static Mark bottom() { return {}; }
  static Mark top()
    requires(T == Top::Present)
  {
    return {1};
  }
  static constexpr unsigned height = 1;
  idr::Changed join(const Mark &other) {
    if (other.set <= set)
      return idr::Changed::No;
    set = other.set;
    return idr::Changed::Yes;
  }
  friend bool operator==(const Mark &, const Mark &) = default;
};

template <Top T>
struct Reach {
  using Summary = Mark<T>;
  using Policy = idr::Budgeted;
  idr::Budgeted budget{8};
  Mark<T> transfer(const idr::solver::ProgramGraph &, idr::solver::FunctionId,
                   const idr::IndexVector<idr::solver::FunctionId, Mark<T>> &) const;
};

static_assert(idr::solver::SummaryProblem<Reach<Top::Present>>);
// expected-error@+1 {{a budgeted solve writes top for what it did not finish}}
static_assert(idr::solver::SummaryProblem<Reach<Top::Absent>>,
              "a budgeted solve writes top for what it did not finish");
