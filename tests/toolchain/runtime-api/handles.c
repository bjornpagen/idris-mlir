// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* Every entry point that takes a handle, on each kind of handle: null (-1),
 * standard input, output and error (0, 1 and 2), an open file, a closed one,
 * and a directory. One line per entry point gives, for each handle, its
 * result and the saved errno it left when the call changed it (the errno is
 * set to ENOENT before each call, so `kept` means the call left it). Handle
 * numbers are never printed: they are the table's, not the ABI's.
 *
 * Standard input is a file of this program's (its descriptor 0 replaced
 * before the runtime reads it), so what a read of it gives is fixed; what is
 * written to standard output and error goes through the runtime, in order
 * with the lines here, which the runtime writes too. The reading entry
 * points run first and read the open file to its end, then the writing ones;
 * the entry points that close or free a handle each run on fresh handles.
 * Every handle the runtime gives the program is freed, so at the end no cell
 * is live. */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "idris_rt.h"

/* The text of standard input and of the open file. */
static const char content[] = "Ab\ncd\nef\ngh\n";

static char directory[] = "/tmp/idris-rt-handles.XXXXXX";
static char path[sizeof directory + 16];

/* The path of `name` in the program's directory. */
static const char *in(const char *name) {
  snprintf(path, sizeof path, "%s/%s", directory, name);
  return path;
}

static const idris_rt_str *text(const char *s) { return idris_rt_str_from_utf8(s, strlen(s)); }

/* A line of this program's, written through the runtime's standard output. */
static void say(const char *format, ...) {
  char line[1024];
  va_list arguments;
  va_start(arguments, format);
  int n = vsnprintf(line, sizeof line, format, arguments);
  va_end(arguments);
  const idris_rt_str *s = idris_rt_str_from_utf8(line, (size_t)n);
  idris_rt_io_put_str(s);
  idris_rt_str_release(s);
}

/* The saved errno set to ENOENT, by removing what does not exist. */
static void resetErrno(void) {
  const idris_rt_str *none = text(in("none"));
  idris_rt_io_file_remove(none);
  idris_rt_str_release(none);
}

/* What a call left in the saved errno, after resetErrno. */
static const char *errnoLeft(char *room, size_t size) {
  int64_t e = idris_rt_io_errno();
  if (e == ENOENT)
    return "";
  if (e == EBADF)
    return " EBADF";
  snprintf(room, size, " errno %lld", (long long)e);
  return room;
}

/* The handles, by name. */
enum { HANDLES = 7 };
static const char *const names[HANDLES] = {"-1", "0", "1", "2", "file", "closed", "directory"};
typedef struct {
  int64_t at[HANDLES];
} Handles;

/* A string handle as the program sees it: null, or the text it holds, its
 * line ends written \n; the handle is then freed, as base frees one. */
static void stringResult(int64_t handle, char *out, size_t size) {
  if (idris_rt_handle_is_null(handle)) {
    snprintf(out, size, "null");
    return;
  }
  const idris_rt_str *s = idris_rt_handle_string(handle);
  const char *bytes = idris_rt_str_bytes(s);
  size_t at = 0;
  at += (size_t)snprintf(out + at, size - at, "\"");
  for (uint64_t i = 0; i < s->bytes && at + 3 < size; ++i)
    at += (size_t)(bytes[i] == '\n' ? snprintf(out + at, size - at, "\\n")
                                    : snprintf(out + at, size - at, "%c", bytes[i]));
  snprintf(out + at, size - at, "\"");
  idris_rt_str_release(s);
  idris_rt_io_handle_free(handle);
}

/* One entry point on every handle, one line: `call` writes what the call
 * gave into `out`. */
typedef void (*Call)(int64_t handle, char *out, size_t size);
static void row(const char *entry, const Handles *handles, Call call) {
  char line[1024];
  size_t at = (size_t)snprintf(line, sizeof line, "%s:", entry);
  for (int i = 0; i < HANDLES; ++i) {
    char result[256];
    char room[32];
    resetErrno();
    call(handles->at[i], result, sizeof result);
    at += (size_t)snprintf(line + at, sizeof line - at, "%s %s %s%s", i == 0 ? "" : ",", names[i],
                           result, errnoLeft(room, sizeof room));
  }
  say("%s\n", line);
}

/* A byte array of 16 bytes, as Data.Buffer's are, and its two transfers:
 * the signatures of the ABI's buffer entry points. */
static idris_rt_array *buffer;
static int64_t writeBytes(int64_t handle, int64_t offset, int64_t count) {
  return idris_rt_io_write_bytes(handle, buffer, offset, count);
}
static int64_t readBytes(int64_t handle, int64_t offset, int64_t count) {
  return idris_rt_io_read_bytes(handle, buffer, offset, count);
}

/* The calls. */
static void number(char *o, size_t n, int64_t v) { snprintf(o, n, "%lld", (long long)v); }
static void isNull(int64_t h, char *o, size_t n) { number(o, n, idris_rt_handle_is_null(h)); }
static void readChar(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_read_char(h)); }
static void readLine(int64_t h, char *o, size_t n) { stringResult(idris_rt_io_file_read_line(h), o, n); }
static void readChars2(int64_t h, char *o, size_t n) { stringResult(idris_rt_io_file_read_chars(2, h), o, n); }
static void readChars0(int64_t h, char *o, size_t n) { stringResult(idris_rt_io_file_read_chars(0, h), o, n); }
static void seekLine(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_seek_line(h)); }
static void readBytes8(int64_t h, char *o, size_t n) {
  memset(idris_rt_array_bytes(buffer), '.', 16);
  int64_t got = readBytes(h, 4, 8);
  char seen[17];
  for (int i = 0; i < 16; ++i)
    seen[i] = idris_rt_array_bytes(buffer)[i] == '\n' ? '/' : idris_rt_array_bytes(buffer)[i];
  seen[16] = '\0';
  snprintf(o, n, "%lld [%s]", (long long)got, seen);
}
static void endOfFile(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_eof(h)); }
static void fileError(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_error(h)); }
static void filePoll(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_poll(h)); }
static void isTty(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_is_tty(h)); }
/* A size: the open file's and standard input's are the content's; standard
 * output's and error's grow with what is written, so only its sign shows. */
static void fileSize(int64_t h, char *o, size_t n) {
  int64_t bytes = idris_rt_io_file_size(h);
  if (bytes >= 0 && (h == 1 || h == 2))
    snprintf(o, n, "a size");
  else
    snprintf(o, n, "%lld", (long long)bytes);
}
/* A file time's six fields: valid (a positive time and nanoseconds below
 * 10^9) or -1, as a field each; the file-time handle is then freed. */
static void fields(int64_t time, char *o, size_t n) {
  int64_t (*const field[6])(int64_t) = {idris_rt_io_file_atime_sec, idris_rt_io_file_atime_nsec,
                                        idris_rt_io_file_mtime_sec, idris_rt_io_file_mtime_nsec,
                                        idris_rt_io_file_ctime_sec, idris_rt_io_file_ctime_nsec};
  size_t at = 0;
  for (int i = 0; i < 6; ++i) {
    int64_t v = field[i](time);
    int valid = i % 2 == 0 ? v > 0 : v >= 0 && v < 1000000000;
    at += (size_t)snprintf(o + at, n - at, "%s%s", i == 0 ? "" : "/", valid ? "t" : v == -1 ? "-1" : "?");
  }
}
static void fileTime(int64_t h, char *o, size_t n) {
  int64_t time = idris_rt_io_file_time(h);
  fields(time, o, n);
  idris_rt_io_handle_free(time);
}
/* Each field entry point on the handle itself, which is no file time. */
static void timeFields(int64_t h, char *o, size_t n) { fields(h, o, n); }
static void dirEntry(int64_t h, char *o, size_t n) {
  int64_t entry = idris_rt_io_dir_entry(h);
  snprintf(o, n, "%s", idris_rt_handle_is_null(entry) ? "null" : "a name");
}
static void writeLine(int64_t h, char *o, size_t n) {
  const idris_rt_str *line = text("written by write_line\n");
  snprintf(o, n, "%lld", (long long)idris_rt_io_file_write_line(h, line));
  idris_rt_str_release(line);
}
static void writeEmptyLine(int64_t h, char *o, size_t n) {
  const idris_rt_str *line = text("");
  snprintf(o, n, "%lld", (long long)idris_rt_io_file_write_line(h, line));
  idris_rt_str_release(line);
}
static void writeBytes4(int64_t h, char *o, size_t n) {
  memcpy(idris_rt_array_bytes(buffer), "..wb\n..", 7);
  snprintf(o, n, "%lld", (long long)writeBytes(h, 2, 3));
}
static void fileFlush(int64_t h, char *o, size_t n) { number(o, n, idris_rt_io_file_flush(h)); }

/* After an entry point that may close or free a handle: whether the handle
 * still names an open stream, directory or nothing, by what file_error and
 * dir_entry give (each sets the errno, which the line does not show). */
static void state(int64_t h, char *o, size_t n) {
  if (idris_rt_io_file_error(h) == 0)
    snprintf(o, n, "a stream");
  else if (!idris_rt_handle_is_null(idris_rt_io_dir_entry(h)))
    snprintf(o, n, "a directory");
  else
    snprintf(o, n, "closed");
}
/* A closing entry point: what the handle is after it, and the errno it left;
 * the errno is set to ENOENT again for the line, which state changed. */
static void closing(void (*entry)(int64_t), int64_t h, char *o, size_t n) {
  entry(h);
  char room[32];
  char left[32];
  snprintf(left, sizeof left, "%s", errnoLeft(room, sizeof room));
  state(h, o, n);
  size_t at = strlen(o);
  snprintf(o + at, n - at, "%s", left);
  resetErrno();
}
static void fileClose(int64_t h, char *o, size_t n) { closing(idris_rt_io_file_close, h, o, n); }
static void dirClose(int64_t h, char *o, size_t n) { closing(idris_rt_io_dir_close, h, o, n); }
static void handleFree(int64_t h, char *o, size_t n) { closing(idris_rt_io_handle_free, h, o, n); }

/* A file at `name` holding the content, opened in `mode`. */
static int64_t openWith(const char *name, const char *mode) {
  FILE *f = fopen(in(name), "w");
  fputs(content, f);
  fclose(f);
  const idris_rt_str *p = text(in(name));
  const idris_rt_str *m = text(mode);
  int64_t handle = idris_rt_io_file_open(p, m);
  idris_rt_str_release(p);
  idris_rt_str_release(m);
  return handle;
}

/* The handles, fresh: an open file, a closed one and a directory. The
 * directory's first entry is read before the file is closed, so that the
 * slot its name takes is never the closed file's. */
static Handles fresh(void) {
  Handles h = {{-1, 0, 1, 2, openWith("file", "r+"), openWith("closed", "r"), -1}};
  const idris_rt_str *d = text(in("directory"));
  h.at[6] = idris_rt_io_dir_open(d);
  idris_rt_str_release(d);
  idris_rt_io_dir_entry(h.at[6]);
  idris_rt_io_file_close(h.at[5]);
  return h;
}

/* What is left of fresh handles, closed. */
static void done(const Handles *h) {
  idris_rt_io_file_close(h->at[4]);
  idris_rt_io_dir_close(h->at[6]);
}

int main(void) {
  if (mkdtemp(directory) == NULL)
    return 2;
  mkdir(in("directory"), 0700);
  int input = open(in("input"), O_RDWR | O_CREAT | O_TRUNC, 0600);
  if (input < 0 || write(input, content, sizeof content - 1) != (ssize_t)(sizeof content - 1) ||
      lseek(input, 0, SEEK_SET) != 0 || dup2(input, 0) != 0)
    return 2;
  close(input);
  buffer = idris_rt_array_new(16, idris_rt_info(1, 0, IDRIS_RT_KIND_ARRAY));

  Handles h = fresh();
  say("handles: -1, standard input, output and error, a file, a closed file, a directory\n");
  row("handle_is_null", &h, isNull);
  /* Reading: standard input and the file each hold the content. */
  row("file_read_char", &h, readChar);
  row("file_read_line", &h, readLine);
  row("file_read_chars 2", &h, readChars2);
  row("file_read_chars 0", &h, readChars0);
  row("file_seek_line", &h, seekLine);
  row("read_bytes 8 at 4", &h, readBytes8);
  row("eof", &h, endOfFile);
  row("file_error", &h, fileError);
  row("file_poll", &h, filePoll);
  row("file_is_tty", &h, isTty);
  row("file_size", &h, fileSize);
  row("file_time", &h, fileTime);
  row("file time fields", &h, timeFields);
  row("dir_entry", &h, dirEntry);
  row("dir_entry again", &h, dirEntry);
  /* Writing: the file is at its end. */
  row("file_write_line", &h, writeLine);
  row("file_write_line of nothing", &h, writeEmptyLine);
  row("write_bytes 3 at 2", &h, writeBytes4);
  row("file_flush", &h, fileFlush);
  done(&h);
  /* Closing and freeing, each on fresh handles. */
  h = fresh();
  row("file_close, then", &h, fileClose);
  done(&h);
  h = fresh();
  row("dir_close, then", &h, dirClose);
  done(&h);
  h = fresh();
  row("handle_free, then", &h, handleFree);
  done(&h);

  idris_rt_dec(buffer);
  const char *files[] = {"file", "closed", "input"};
  for (size_t i = 0; i < sizeof files / sizeof files[0]; ++i)
    unlink(in(files[i]));
  rmdir(in("directory"));
  rmdir(directory);
  idris_rt_main_return();
  return 0;
}
