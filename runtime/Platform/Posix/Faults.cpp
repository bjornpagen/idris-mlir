// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Catching a fault on memory, on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <signal.h>
#include <stdint.h>

namespace {

void (*faultHandler)(uintptr_t) = nullptr;
// The actions the handler replaced: a fault it does not claim goes to them.
struct sigaction previousSegv {};
struct sigaction previousBus {};

// A stack running into its guard is SIGSEGV on Linux and SIGBUS on macOS,
// which reports a fault on a mapped page it may not touch as a bus error;
// both carry the faulting address in si_addr, so both are caught. It runs on
// the signal stack, which idris-mlir sizes by the deepest path from here,
// found by its mark.
IDRIS_RT_HANDLER void onSignal(int signal, siginfo_t *info, void *) {
  faultHandler(reinterpret_cast<uintptr_t>(info->si_addr));
  sigaction(signal, signal == SIGBUS ? &previousBus : &previousSegv, nullptr);
}

} // namespace

namespace rt::platform {

void catchFaults(void (*onFault)(uintptr_t address)) noexcept {
  bool installed = faultHandler != nullptr;
  faultHandler = onFault;
  if (installed)
    return;
  struct sigaction action {};
  action.sa_sigaction = onSignal;
  action.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigemptyset(&action.sa_mask);
  sigaction(SIGSEGV, &action, &previousSegv);
  sigaction(SIGBUS, &action, &previousBus);
}

} // namespace rt::platform
