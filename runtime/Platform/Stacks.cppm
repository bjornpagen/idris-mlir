// rt.platform:stacks: running on a stack of the runtime's own.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>

export module rt.platform:stacks;

export namespace rt::platform {

// Runs fn(arg) on a new thread whose stack is the `size` bytes at `stack`,
// and returns once it has; false when no thread could start, and fn did
// not run.
bool runThread(void (*fn)(void *), void *arg, char *stack, size_t size) noexcept;

// Makes the n bytes at p the calling thread's stack for signal handlers.
void useSignalStack(char *p, size_t n) noexcept;

// The process's stack limit in bytes: SIZE_MAX when it has none, 0 when it
// cannot be read.
size_t stackLimit() noexcept;

} // namespace rt::platform
