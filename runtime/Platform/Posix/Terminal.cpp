// The terminal of standard input and output, on a POSIX system: raw mode
// through termios, and its size through TIOCGWINSZ, which Linux and macOS
// both define.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <stdint.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

namespace {

// Standard input's mode before raw mode was first asked for, which
// restoreMode puts back.
struct termios initialMode;
bool modeSaved = false;

} // namespace

namespace rt::platform {

bool rawMode() noexcept {
  struct termios mode {};
  if (tcgetattr(STDIN_FILENO, &mode) != 0)
    return false;
  if (!modeSaved) {
    initialMode = mode;
    modeSaved = true;
  }
  mode.c_lflag &= ~static_cast<tcflag_t>(ECHO | ICANON);
  return tcsetattr(STDIN_FILENO, TCSAFLUSH, &mode) == 0;
}

void restoreMode() noexcept {
  if (modeSaved)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &initialMode);
}

bool terminalSize(int64_t &columns, int64_t &rows) noexcept {
  struct winsize size {};
  if (ioctl(STDIN_FILENO, TIOCGWINSZ, &size) != 0 &&
      ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0)
    return false;
  columns = size.ws_col;
  rows = size.ws_row;
  return true;
}

} // namespace rt::platform
