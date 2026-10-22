// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an active call holds that it no longer needs, as the checked runtime
// keeps it. The lowering opens an account around each activation of a
// function that may hold such bytes (reuse tokens of statically sized cells
// awaiting their construction, its stack cells' shells, values borrowed past
// their last use), with the bound the compiler computed for the function,
// and tells each change of what it holds. A call that held more than its
// bound while a cell was made has broken the frame-limited promise the
// compiler made for it, and the run ends as the runtime's internal error
// naming the function, what it held and its bound: a record of the ending
// table, which the harness compares as data. The runtime every program ships
// with keeps no account: its entries are empty, so once its bitcode joins a
// program they inline to nothing, and check-archive refuses an account in
// it.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::alloc {

// One active call's account: its function, the compiler's bound, what it
// holds now, and how many cells the program had made when that last
// changed, so a cell made since was made while it held that much.
struct PeakAccount {
  const idris_rt_text *function;
  uint64_t bound;
  uint64_t held;
  uint64_t since;

  // What the account holds now was held while a cell was made, so it must
  // be within the bound. Checked when it changes and when the call ends:
  // what a call holds does not change while a callee runs, so every cell
  // made while it held some amount is made before the next of these. A
  // member of the account, as the account is the checked runtime's alone:
  // the runtime that keeps none never reads it, and emits nothing of it.
  void settle() const {
    if (since != cellsMade && held > bound)
      rt::end::end(rt::end::FrameBoundExceeded{function, held, bound});
  }
};

// The accounts of the active calls that keep one, innermost last, in a
// block that grows by doubling. The program is single-threaded.
inline PeakAccount *peakAccounts = nullptr;
inline size_t peakOpen = 0;
inline size_t peakRoom = 0;

} // namespace rt::alloc

// An activation of `function` begins, which may hold up to `bound` bytes it
// no longer needs at any cell the program makes while it is active.
extern "C" [[gnu::always_inline]] void idris_rt_peak_enter(const idris_rt_text *function,
                                                          int64_t bound) {
  if constexpr (rt::alloc::checked) {
    using namespace rt::alloc;
    if (peakOpen == peakRoom) {
      peakRoom = peakRoom == 0 ? 64 : peakRoom * 2;
      size_t bytes = peakRoom * sizeof(PeakAccount);
      peakAccounts = static_cast<PeakAccount *>(
          peakAccounts == nullptr ? allocate(bytes) : reallocate(peakAccounts, bytes));
    }
    peakAccounts[peakOpen++] = {function, static_cast<uint64_t>(bound), 0, cellsMade};
  }
}

// The innermost activation that keeps an account holds `change` more bytes
// it no longer needs (a token taken, a borrow past its last use), or fewer
// where `change` is negative (the token built into, the value released).
extern "C" [[gnu::always_inline]] void idris_rt_peak_held(int64_t change) {
  if constexpr (rt::alloc::checked) {
    using namespace rt::alloc;
    PeakAccount &account = peakAccounts[peakOpen - 1];
    account.settle();
    account.held += static_cast<uint64_t>(change);
    account.since = cellsMade;
  }
}

// The innermost activation that keeps an account ends.
extern "C" [[gnu::always_inline]] void idris_rt_peak_leave(void) {
  if constexpr (rt::alloc::checked) {
    using namespace rt::alloc;
    peakAccounts[--peakOpen].settle();
  }
}
