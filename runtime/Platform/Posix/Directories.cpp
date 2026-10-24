// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Directories and the current one, on a POSIX system: Linux and macOS
// alike.
#include "Platform/Platform.h"

#include <dirent.h>
#include <errno.h>
#include <stddef.h>
#include <sys/stat.h>
#include <unistd.h>

namespace rt::platform {

Directory *openDirectory(const char *path) noexcept { return opendir(path); }

bool closeDirectory(Directory *directory) noexcept { return closedir(directory) == 0; }

// readdir leaves errno alone at the end, so it is cleared first.
const char *nextEntry(Directory *directory) noexcept {
  errno = 0;
  const dirent *entry = readdir(directory);
  return entry == nullptr ? nullptr : entry->d_name;
}

bool currentDirectory(char *buffer, size_t size) noexcept {
  return getcwd(buffer, size) != nullptr;
}

bool changeDirectory(const char *path) noexcept { return chdir(path) == 0; }

bool createDirectory(const char *path) noexcept {
  return mkdir(path, S_IRWXU | S_IRWXG | S_IRWXO) == 0;
}

bool removeDirectory(const char *path) noexcept { return rmdir(path) == 0; }

} // namespace rt::platform
