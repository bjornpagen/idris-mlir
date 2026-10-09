// rt.io:directories: base's directories (System.Directory): the current
// one, making and removing one, and reading one's entries through a
// directory handle.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <errno.h>
#include <stdint.h>
#include <string.h>

export module rt.io:directories;

import rt.platform;
import :errors;
import :handles;
import :scratch;

// getcwd's: the current directory's absolute path, as a string handle the
// program owns, or null when it cannot be read. A path of any length is
// read whole.
extern "C" int64_t idris_rt_io_dir_current(void) {
  rt::io::Scratch path;
  while (!rt::platform::currentDirectory(path.bytes, path.capacity)) {
    if (rt::platform::lastError() != ERANGE) {
      rt::io::saveError();
      return rt::io::nullHandle;
    }
    path.reserve(path.capacity + 1);
  }
  return rt::io::newString(idris_rt_str_from_bytes(path.bytes, strlen(path.bytes)));
}

// chdir's: 0, or -1 when the path cannot become the current directory.
extern "C" int64_t idris_rt_io_dir_change(const idris_rt_str *path) {
  rt::io::Scratch text;
  if (rt::platform::changeDirectory(rt::io::cText(text, path)))
    return 0;
  rt::io::saveError();
  return -1;
}

// mkdir's, with every permission the process's umask allows: 0, or -1 when
// the directory cannot be made.
extern "C" int64_t idris_rt_io_dir_create(const idris_rt_str *path) {
  rt::io::Scratch text;
  if (rt::platform::createDirectory(rt::io::cText(text, path)))
    return 0;
  rt::io::saveError();
  return -1;
}

// rmdir's: removes the directory at the path, which must be empty. Base
// gives no result, so a failure shows only in the saved errno.
extern "C" void idris_rt_io_dir_remove(const idris_rt_str *path) {
  rt::io::Scratch text;
  if (!rt::platform::removeDirectory(rt::io::cText(text, path)))
    rt::io::saveError();
}

// opendir's: the directory at the path, open for reading its entries, as a
// new directory handle; null when it cannot be opened.
extern "C" int64_t idris_rt_io_dir_open(const idris_rt_str *path) {
  rt::io::Scratch text;
  rt::platform::Directory *stream = rt::platform::openDirectory(rt::io::cText(text, path));
  if (stream == nullptr) {
    rt::io::saveError();
    return rt::io::nullHandle;
  }
  int64_t handle = rt::io::newSlot(rt::io::Kind::Directory);
  rt::io::slotOf(handle)->directory = {stream, rt::io::nullHandle};
  return handle;
}

// Closes a directory, frees its handle, and releases the name of the entry
// it last gave.
extern "C" void idris_rt_io_dir_close(int64_t dir) {
  if (rt::io::openSlot(dir, rt::io::Kind::Directory) != nullptr)
    rt::io::releaseSlot(dir);
}

// readdir's: the name of the directory's next entry, "." and ".." among
// them, in the order the system gives, as a string handle the runtime owns:
// the directory's one entry handle, which the next entry refills and closing
// the directory releases. Null at the end, on a failure, or when the handle
// is not an open directory. The saved errno is readdir's, 0 for an entry and
// at the end, which is how base tells the end from a failure.
extern "C" int64_t idris_rt_io_dir_entry(int64_t dir) {
  rt::io::Slot *slot = rt::io::openSlot(dir, rt::io::Kind::Directory);
  if (slot == nullptr)
    return rt::io::nullHandle;
  const char *name = rt::platform::nextEntry(slot->directory.stream);
  rt::io::saveError();
  if (name == nullptr)
    return rt::io::nullHandle;
  int64_t entry = rt::io::keepString(slot->directory.entry,
                                     idris_rt_str_from_bytes(name, strlen(name)));
  rt::io::slotOf(dir)->directory.entry = entry;
  return entry;
}
