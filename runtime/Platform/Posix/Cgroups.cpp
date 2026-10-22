// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How much memory a Linux host's cgroup lets a process reach before the
// kernel's killer ends it, as the host's files state it: the process's
// group, its hierarchy's mount, the group's limits up to that mount, and
// the system's swap. A reader of files alone, every one under a root, so
// it is the same code on every target: Linux's host reads its own files
// under the filesystem's root, and a test reads trees it planted under
// another on any of the four. Read once, at start, allocating nothing:
// the kernel's text is parsed here, at the boundary, into a number.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
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

// The next bytes of `fd`, up to `size`, as read gives them: a signal that
// interrupts the read is no answer, so the read is asked again.
ssize_t readSome(int fd, char *buffer, size_t size) noexcept {
  ssize_t n;
  do
    n = read(fd, buffer, size);
  while (n < 0 && errno == EINTR);
  return n;
}

// A small file of the kernel's, read whole into `buffer`: false when it
// cannot be read or does not fit.
bool readSmall(const char *path, char *buffer, size_t size, std::string_view &text) noexcept {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return false;
  // Read until the file ends, a read fails, or the buffer is full.
  size_t got = 0;
  for (ssize_t n; got < size && (n = readSome(fd, buffer + got, size - got)) > 0;)
    got += static_cast<size_t>(n);
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
// group's directory is the mount point and the path below that root. Each
// is read under `root`, and so is the mount point.
bool findGroup(std::string_view root, Group &group) noexcept {
  char cgroups[8192];
  std::string_view own;
  PathText at;
  if (!at.set(root, "/proc/self/cgroup") || !readSmall(at.c(), cgroups, sizeof cgroups, own))
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
  if (!at.set(root, "/proc/self/mountinfo"))
    return false;
  int fd = open(at.c(), O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return false;
  char buffer[8192];
  size_t held = 0;
  bool found = false;
  // Read until the file ends, a read fails, or the group's mount is found.
  // Every read has room: what stays of a full buffer is an unfinished line,
  // dropped below when it fills the buffer alone.
  for (ssize_t n; (n = readSome(fd, buffer + held, sizeof buffer - held)) > 0;) {
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
      std::string_view mountRoot = word(line, 3), point = word(line, 4);
      if (mountRoot != "/" && path.starts_with(mountRoot))
        path.remove_prefix(mountRoot.size());
      group.floor = root.size() + point.size();
      found = group.directory.set(root, point) &&
              group.directory.append(path == "/" ? std::string_view{} : path);
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

// The system's swap, /proc/meminfo's `SwapTotal:` in kibibytes, read under
// `root`; 0 where it cannot be read.
size_t systemSwap(std::string_view root) noexcept {
  PathText path;
  char buffer[8192];
  std::string_view text, value;
  if (!path.set(root, "/proc/meminfo") || !readSmall(path.c(), buffer, sizeof buffer, text) ||
      !field(text, "SwapTotal:", value))
    return 0;
  while (!value.empty() && value.front() == ' ')
    value.remove_prefix(1);
  constexpr std::string_view unit = " kB";
  size_t kibibytes = 0, bytes = 0;
  if (!value.ends_with(unit) ||
      !parseBytes(value.substr(0, value.size() - unit.size()), kibibytes))
    return 0;
  return __builtin_mul_overflow(kibibytes, size_t{1024}, &bytes) ? none : bytes;
}

// The unified hierarchy: the lowest memory.max from the group up to the
// mount's root, which is where the kernel reclaims and then kills; plus
// the swap the group may use, the lowest memory.swap.max on the way, no
// more than the system has; less what the group holds already.
size_t limitV2(std::string_view root, Group &group) noexcept {
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
    size_t system = systemSwap(root);
    swap = swapMax < system ? swapMax : system;
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

size_t cgroupLimit(const char *root) noexcept {
  Group group{};
  if (!findGroup(root, group))
    return none;
  return group.version == Version::V2 ? limitV2(root, group) : limitV1(group);
}

} // namespace rt::platform
