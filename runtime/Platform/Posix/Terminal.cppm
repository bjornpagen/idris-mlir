// rt.platform:terminal: the terminal of standard input and output, on a POSIX
// system: raw mode through termios, and its size through TIOCGWINSZ, which
// Linux and macOS both define.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

export module rt.platform:terminal;

namespace {

// Standard input's mode before raw mode was first asked for, which
// restoreMode puts back.
struct termios initialMode;
bool modeSaved = false;

} // namespace

export namespace rt::platform {

// Standard input without echo and without line editing, so a read sees each
// byte as it is typed; false when its mode cannot be read or set.
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

// Puts back the mode raw mode replaced; nothing when it never ran.
void restoreMode() noexcept {
  if (modeSaved)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &initialMode);
}

// The terminal's columns and rows, from standard input's terminal or else
// standard output's; false when neither is one.
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
