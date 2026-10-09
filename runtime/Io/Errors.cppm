// rt.io:errors: the errno base reads after a call that failed (System.Errno,
// System.File's FileError), saved by the runtime when the call fails, so
// that nothing the runtime does in between can change it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

export module rt.io:errors;

import rt.platform;

namespace rt::io {

// The errno of the last failing call. A call that succeeds leaves it.
inline int64_t savedErrno = 0;

// The call that just failed left its errno with the C library.
void saveError() { savedErrno = rt::platform::lastError(); }

// The call failed for a reason of the runtime's, named as C names it.
void fail(int code) { savedErrno = code; }

} // namespace rt::io

// The saved errno, as the C library numbers it on the target.
extern "C" int64_t idris_rt_io_errno(void) { return rt::io::savedErrno; }

// The saved errno as System.File's FileError reads it: 2 for ENOENT, 3 for
// EACCES, 4 for EEXIST, and any other errno plus 5, which base reads back as
// GenericFileError of that errno. 0 and 1, base's read and write errors,
// are numbers no errno gives.
extern "C" int64_t idris_rt_io_file_errno(void) {
  switch (rt::io::savedErrno) {
  case ENOENT:
    return 2;
  case EACCES:
    return 3;
  case EEXIST:
    return 4;
  default:
    return rt::io::savedErrno + 5;
  }
}

// strerror's text of an error number, a new string. The text is the C
// library's, and differs between targets.
extern "C" const idris_rt_str *idris_rt_io_strerror(int64_t code) {
  const char *text = rt::platform::errorText(static_cast<int>(code));
  return idris_rt_str_from_bytes(text, strlen(text));
}
