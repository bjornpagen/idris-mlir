// rt.platform:directories: directories and the current one, on a POSIX
// system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <dirent.h>
#include <errno.h>
#include <stddef.h>
#include <sys/stat.h>
#include <unistd.h>

export module rt.platform:directories;

export namespace rt::platform {

// An open directory: the C library's stream of its entries.
using Directory = DIR;

Directory *openDirectory(const char *path) noexcept { return opendir(path); }

bool closeDirectory(Directory *directory) noexcept { return closedir(directory) == 0; }

// The name of the directory's next entry, valid until the next call on it,
// or null at its end or on a failure. readdir leaves errno alone at the end,
// so it is cleared first: lastError is then 0 at the end and the failure's
// otherwise.
const char *nextEntry(Directory *directory) noexcept {
  errno = 0;
  const dirent *entry = readdir(directory);
  return entry == nullptr ? nullptr : entry->d_name;
}

// The current directory's path, with a NUL after it, in the `size` bytes at
// `buffer`; false when it cannot be read, or does not fit (lastError is then
// ERANGE).
bool currentDirectory(char *buffer, size_t size) noexcept {
  return getcwd(buffer, size) != nullptr;
}

bool changeDirectory(const char *path) noexcept { return chdir(path) == 0; }

// A directory that everyone may read, write and search, less the process's
// umask, as mkdir gives any.
bool createDirectory(const char *path) noexcept {
  return mkdir(path, S_IRWXU | S_IRWXG | S_IRWXO) == 0;
}

bool removeDirectory(const char *path) noexcept { return rmdir(path) == 0; }

} // namespace rt::platform
