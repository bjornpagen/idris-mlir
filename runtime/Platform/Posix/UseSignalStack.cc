// The stack signal handlers run on, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <signal.h>
#include <stddef.h>

module rt.platform;

void rt::platform::useSignalStack(char *p, size_t n) noexcept {
  stack_t alternate{};
  alternate.ss_sp = p;
  alternate.ss_size = n;
  sigaltstack(&alternate, nullptr);
}
