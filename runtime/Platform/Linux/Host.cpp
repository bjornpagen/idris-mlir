// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a Linux host decides, which only Linux says how to read: a fixed
// reservation that never lands on a mapping, where the address space is
// free, how much memory the process's cgroup lets it reach before the
// kernel's killer ends it, and what the kernel's signal frame takes. Each
// read once, at start, allocating nothing: the kernel's text is parsed here,
// at the boundary, into a number.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <unistd.h>

#include <string_view>

namespace {

constexpr size_t none = SIZE_MAX;

// A path, built in place: the kernel's paths are bounded by PATH_MAX, and
// one that is longer is no cgroup's directory the runtime can read.
class PathText {
public:
  bool set(std::string_view a, std::string_view b) noexcept {
    length = 0;
    return append(a) && append(b);
  }
  bool append(std::string_view part) noexcept {
    if (part.size() >= sizeof text - length)
      return false;
    for (char c : part)
      text[length++] = c;
    text[length] = '\0';
    return true;
  }
  // The directory above, or false at `floor`, the mount's root.
  bool up(size_t floor) noexcept {
    if (length <= floor)
      return false;
    while (length > floor && text[length - 1] != '/')
      --length;
    while (length > floor && text[length - 1] == '/')
      --length;
    text[length] = '\0';
    return true;
  }
  const char *c() const noexcept { return text; }
  std::string_view view() const noexcept { return {text, length}; }

private:
  char text[4096];
  size_t length = 0;
};

// A small file of the kernel's, read whole into `buffer`: false when it
// cannot be read or does not fit.
bool readSmall(const char *path, char *buffer, size_t size, std::string_view &text) noexcept {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return false;
  size_t got = 0;
  for (;;) {
    ssize_t n = read(fd, buffer + got, size - got);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      break;
    got += static_cast<size_t>(n);
    if (got == size)
      break;
  }
  close(fd);
  if (got == size)
    return false;
  text = {buffer, got};
  return true;
}

// A decimal count of bytes, or `none` for the kernel's "max"; false for
// any other text.
bool parseBytes(std::string_view text, size_t &bytes) noexcept {
  while (!text.empty() && (text.back() == '\n' || text.back() == ' '))
    text.remove_suffix(1);
  if (text == "max") {
    bytes = none;
    return true;
  }
  if (text.empty())
    return false;
  size_t value = 0;
  for (char c : text) {
    if (c < '0' || c > '9')
      return false;
    size_t digit = static_cast<size_t>(c - '0');
    if (__builtin_mul_overflow(value, size_t{10}, &value) ||
        __builtin_add_overflow(value, digit, &value))
      value = none;
  }
  bytes = value;
  return true;
}

// The count of bytes a file of the cgroup's holds: `none` for "max", and
// false when the file is missing (its controller off) or holds no count.
bool readBytes(const PathText &directory, std::string_view file, size_t &bytes) noexcept {
  PathText path;
  if (!path.set(directory.view(), file))
    return false;
  char buffer[64];
  std::string_view text;
  return readSmall(path.c(), buffer, sizeof buffer, text) && parseBytes(text, bytes);
}

// The line of `text` that begins with `key`, after the key.
bool field(std::string_view text, std::string_view key, std::string_view &value) noexcept {
  while (!text.empty()) {
    size_t end = text.find('\n');
    std::string_view line = text.substr(0, end);
    if (line.starts_with(key)) {
      value = line.substr(key.size());
      return true;
    }
    if (end == std::string_view::npos)
      break;
    text.remove_prefix(end + 1);
  }
  return false;
}

// The space-separated field `n` of a line, counting from 0.
std::string_view word(std::string_view line, size_t n) noexcept {
  for (; n != 0; --n) {
    size_t space = line.find(' ');
    if (space == std::string_view::npos)
      return {};
    line.remove_prefix(space + 1);
  }
  return line.substr(0, line.find(' '));
}

// Whether `list`, comma-separated, holds `item`.
bool holds(std::string_view list, std::string_view item) noexcept {
  while (!list.empty()) {
    size_t comma = list.find(',');
    if (list.substr(0, comma) == item)
      return true;
    if (comma == std::string_view::npos)
      return false;
    list.remove_prefix(comma + 1);
  }
  return false;
}

// The two versions of cgroups, which name their files apart.
enum class Version : uint8_t { V1, V2 };

// The process's cgroup's directory, of the version mounted, and the
// mount's root, below which the walk up never goes.
struct Group {
  Version version;
  PathText directory;
  size_t floor;
};

// /proc/self/cgroup names the process's group in each hierarchy: `0::path`
// for the unified one (v2), `id:controllers:path` for v1's, the memory
// controller's among them. /proc/self/mountinfo says where that
// hierarchy is mounted and which of its groups the mount's root is: the
// group's directory is the mount point and the path below that root.
bool findGroup(Group &group) noexcept {
  char cgroups[8192];
  std::string_view own;
  if (!readSmall("/proc/self/cgroup", cgroups, sizeof cgroups, own))
    return false;
  std::string_view unified, memory;
  for (std::string_view rest = own; !rest.empty();) {
    size_t end = rest.find('\n');
    std::string_view line = rest.substr(0, end);
    size_t first = line.find(':');
    size_t second = first == std::string_view::npos ? first : line.find(':', first + 1);
    if (second != std::string_view::npos) {
      std::string_view controllers = line.substr(first + 1, second - first - 1);
      std::string_view path = line.substr(second + 1);
      if (line.substr(0, first) == "0" && controllers.empty())
        unified = path;
      else if (holds(controllers, "memory"))
        memory = path;
    }
    if (end == std::string_view::npos)
      break;
    rest.remove_prefix(end + 1);
  }
  if (unified.empty() && memory.empty())
    return false;
  // mountinfo may be long: read in pieces, each line whole in the buffer.
  int fd = open("/proc/self/mountinfo", O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return false;
  char buffer[8192];
  size_t held = 0;
  bool found = false;
  for (;;) {
    ssize_t n = read(fd, buffer + held, sizeof buffer - held);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      break;
    held += static_cast<size_t>(n);
    std::string_view text(buffer, held);
    size_t consumed = 0;
    for (size_t end; !found && (end = text.find('\n', consumed)) != std::string_view::npos;
         consumed = end + 1) {
      std::string_view line = text.substr(consumed, end - consumed);
      size_t dash = line.find(" - ");
      if (dash == std::string_view::npos)
        continue;
      std::string_view type = word(line.substr(dash + 3), 0);
      std::string_view options = word(line.substr(dash + 3), 2);
      std::string_view path;
      if (type == "cgroup2" && !unified.empty()) {
        group.version = Version::V2;
        path = unified;
      } else if (type == "cgroup" && !memory.empty() && holds(options, "memory")) {
        group.version = Version::V1;
        path = memory;
      } else {
        continue;
      }
      std::string_view root = word(line, 3), point = word(line, 4);
      if (root != "/" && path.starts_with(root))
        path.remove_prefix(root.size());
      group.floor = point.size();
      found = group.directory.set(point, path == "/" ? std::string_view{} : path);
    }
    if (found)
      break;
    // A line longer than the buffer is no mount of a cgroup hierarchy.
    if (consumed == 0 && held == sizeof buffer)
      consumed = held;
    for (size_t i = consumed; i < held; ++i)
      buffer[i - consumed] = buffer[i];
    held -= consumed;
  }
  close(fd);
  return found;
}

// The unified hierarchy: the lowest memory.max from the group up to the
// mount's root, which is where the kernel reclaims and then kills; plus
// the swap the group may use, the lowest memory.swap.max on the way, no
// more than the system has; less what the group holds already.
size_t limitV2(Group &group) noexcept {
  size_t memoryMax = none, swapMax = none;
  bool swapCounted = false;
  PathText &at = group.directory;
  PathText leaf = at;
  do {
    size_t bytes;
    if (readBytes(at, "/memory.max", bytes) && bytes < memoryMax)
      memoryMax = bytes;
    if (readBytes(at, "/memory.swap.max", bytes)) {
      swapCounted = true;
      if (bytes < swapMax)
        swapMax = bytes;
    }
  } while (at.up(group.floor));
  if (memoryMax == none)
    return none;
  size_t swap = 0;
  if (swapCounted) {
    struct sysinfo system {};
    size_t systemSwap = sysinfo(&system) == 0
                            ? static_cast<size_t>(system.totalswap) * system.mem_unit
                            : 0;
    swap = swapMax < systemSwap ? swapMax : systemSwap;
  }
  size_t current = 0, swapCurrent = 0;
  (void)readBytes(leaf, "/memory.current", current);
  if (swap != 0)
    (void)readBytes(leaf, "/memory.swap.current", swapCurrent);
  size_t reach = memoryMax + swap;
  size_t held = current + swapCurrent;
  return reach > held ? reach - held : 0;
}

// Version 1: the hierarchical limits memory.stat states for the group, the
// one of memory and swap together where the kernel accounts swap, less
// what the group uses. A limit the kernel calls unlimited is a number past
// any machine's memory.
size_t limitV1(const Group &group) noexcept {
  constexpr size_t unlimited = size_t{1} << 62;
  PathText path;
  char buffer[8192];
  std::string_view stat;
  if (!path.set(group.directory.view(), "/memory.stat") ||
      !readSmall(path.c(), buffer, sizeof buffer, stat))
    return none;
  std::string_view value;
  size_t limit = none, used = 0;
  if (field(stat, "hierarchical_memsw_limit ", value) && parseBytes(value, limit) &&
      limit < unlimited) {
    if (!readBytes(group.directory, "/memory.memsw.usage_in_bytes", used))
      used = 0;
  } else if (field(stat, "hierarchical_memory_limit ", value) && parseBytes(value, limit) &&
             limit < unlimited) {
    if (!readBytes(group.directory, "/memory.usage_in_bytes", used))
      used = 0;
  } else {
    return none;
  }
  return limit > used ? limit - used : 0;
}

} // namespace

namespace rt::platform {

// MAP_FIXED_NOREPLACE refuses a place a mapping holds (EEXIST). A kernel
// before 4.17 takes the flag for a hint and maps elsewhere, which is as
// occupied.
Placed reserveAt(char *at, size_t size) noexcept {
  void *got = mmap(at, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
  if (got == at)
    return Placed::Reserved;
  if (got != MAP_FAILED) {
    munmap(got, size);
    return Placed::Occupied;
  }
  return errno == EEXIST ? Placed::Occupied : Placed::Refused;
}

// The kernel maps new regions downward from below the initial stack, so the
// space above the program's break is free up to them: the heap starts at
// the first aligned address above it and grows up, past whatever it meets.
// User space ends at the power of two above the initial stack, which the
// kernel places at its top; and no further than the process's address-space
// limit (`ulimit -v`), which counts every mapping.
Span heapSpan(size_t alignment) noexcept {
  auto brk = reinterpret_cast<uintptr_t>(sbrk(0));
  uintptr_t base = roundUp(brk, alignment);
  char local = 0;
  uintptr_t stack = reinterpret_cast<uintptr_t>(&local);
  uintptr_t top = uintptr_t{1} << (64 - __builtin_clzll(stack));
  size_t length = top > base ? top - base : 0;
  size_t limit = addressSpaceLimit();
  return {reinterpret_cast<char *>(base), limit < length ? limit : length};
}

size_t commitLimit() noexcept {
  Group group{};
  if (!findGroup(group))
    return none;
  return group.version == Version::V2 ? limitV2(group) : limitV1(group);
}

size_t physicalMemory() noexcept {
  struct sysinfo system {};
  if (sysinfo(&system) != 0)
    return SIZE_MAX;
  return static_cast<size_t>(system.totalram) * system.mem_unit;
}

// The kernel says what its signal frame takes in the auxiliary vector
// (AT_MINSIGSTKSZ, entry 51 of its ABI), which grows with the registers a
// processor saves; a kernel that says nothing takes the C library's
// minimum.
size_t signalStackMinimum() noexcept {
  constexpr unsigned long minimumSignalStackEntry = 51;
  unsigned long kernel = getauxval(minimumSignalStackEntry);
  return kernel != 0 ? static_cast<size_t>(kernel) : static_cast<size_t>(MINSIGSTKSZ);
}

} // namespace rt::platform
