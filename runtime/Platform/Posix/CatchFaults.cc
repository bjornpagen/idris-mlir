// Faults on memory caught, on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <signal.h>
#include <stdint.h>

module rt.platform;

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

void rt::platform::catchFaults(void (*onFault)(uintptr_t address)) noexcept {
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
