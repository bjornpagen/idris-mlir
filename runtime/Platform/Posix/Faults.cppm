// rt.platform:faults: catching a fault on memory, on a POSIX system: Linux
// and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <signal.h>
#include <stdint.h>

export module rt.platform:faults;

namespace {

void (*faultHandler)(uintptr_t) = nullptr;
// The actions the handler replaced: a fault it does not claim goes to them.
struct sigaction previousSegv {};
struct sigaction previousBus {};

// A stack running into its guard is SIGSEGV on Linux and may be SIGBUS on
// macOS, so both are caught.
void onSignal(int signal, siginfo_t *info, void *) {
  faultHandler(reinterpret_cast<uintptr_t>(info->si_addr));
  sigaction(signal, signal == SIGBUS ? &previousBus : &previousSegv, nullptr);
}

} // namespace

export namespace rt::platform {

// From now on a fault on memory calls onFault with the faulting address, on
// the thread's signal stack; when onFault returns, the fault gets the action
// it had before this call, as if it were never caught. onFault may only make
// async-signal-safe calls. The first call installs it, and later ones
// replace onFault.
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
