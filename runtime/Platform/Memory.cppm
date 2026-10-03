// rt.platform:memory: address space, by the page.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>

export module rt.platform:memory;

export namespace rt::platform {

// The size of a page, which a guard and a region are multiples of.
size_t pageSize() noexcept;

// `size` bytes of address space, readable and writable and committed as
// they are touched, or null when the system grants none that large.
char *reserve(size_t size) noexcept;
// Makes the n bytes at p, whole pages, inaccessible.
bool protect(char *p, size_t n) noexcept;
void release(char *p, size_t size) noexcept;

} // namespace rt::platform
