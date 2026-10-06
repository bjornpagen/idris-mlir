// idr.eval:child: running a round's calls in a child process.
// idris-mlir-cc runs MLIR single-threaded; elsewhere a module pass runs
// alone, so any threads of MLIR's pool wait idle, holding no lock the child
// needs, when it forks. The child runs the calls on a stack reserved as large
// as the address space allows, with a guard below it, and writes what it
// reads of each call's results to a pipe, as byte strings the caller
// chooses. A crash the runtime reports ends the
// child; the calls before it have their results and the caller forks again
// for the rest, and so does a call that spends its budget. Every call runs
// metered, within a budget of ticks, arena bytes and stack of its own,
// counted, so the same call spends the same on every machine.
//
// What the child does after fork holds on every target entry's system: it
// allocates (glibc's, musl's and libSystem's malloc all reinitialize their
// locks in a fork child), starts one thread, on a stack it maps, and runs
// code the parent's JIT finished mapping before it forked; it ends with
// _exit, so nothing the parent registered runs. It uses no framework that
// Darwin forbids after fork without exec (CoreFoundation, libdispatch's
// queues, XPC), and libSystem gives the child its own task port, so a
// mach_vm call (snmalloc's) maps into the child, not the parent.
module;
// The runtime's evaluation entry points and exit statuses, and the system's
// processes, pipes, signals and clocks: C, and macros, which no import
// carries.
#include "idris_rt.h"

#include <cerrno>
#include <csignal>
#include <cstring>
#include <ctime>
#include <poll.h>
#include <sys/wait.h>
#include <unistd.h>

export module idr.eval:child;

import idr.mlir;

import :jit;

export namespace idr::eval {

// What the child read of one call's results, and how long the call ran.
struct Result {
  uint64_t nanoseconds = 0;
  llvm::SmallVector<std::string> texts;
};

struct Run {
  enum class Status {
    // Every call ran.
    Done,
    // A call crashed; `message` is what the runtime reported.
    Crashed,
    // The machine refused memory or stack, or killed the child.
    Exhausted,
    // A call spent its budget.
    OverBudget,
    // Anything else: an internal error, described by `message`.
    Failed,
  };
  // The results of the calls from the first one, in order; the call after
  // the last of them is the one the status is about.
  llvm::SmallVector<Result> results;
  Status status = Status::Done;
  std::string message;
};

// What a call may spend: ticks (one where code enters a function or goes
// round a loop), bytes of arena, bytes of stack.
struct Budget {
  uint64_t ticks;
  uint64_t bytes;
  uint64_t stack;
};

} // namespace idr::eval

namespace idr::eval {

namespace {

// The child's stack: twice the largest stack budget of the calls it runs,
// committed as it is touched, above a guard of 16 MiB. A metered call's
// stack budget ends it before the guard: the meter checks the stack where
// the call's code enters a function or goes round a loop, so it overshoots
// by at most a frame and the runtime functions that frame calls, and
// reading its results back recurses once per cell of at most a mebibyte
// of them, both far less than a budget. A fault on the guard is the
// machine's limit, exhaustion. The reservation is no larger: mapping and
// unmapping one costs time in proportion to its size, on every fork.
// idris_rt_run_on_stack rounds both up to the system's page; neither is a
// page size, and nothing here assumes one.
size_t stackFor(llvm::ArrayRef<Budget> budgets) {
  uint64_t most = 0;
  for (const Budget &budget : budgets)
    if (budget.stack > most)
      most = budget.stack;
  return static_cast<size_t>(2 * most);
}
constexpr size_t stackGuard = size_t{1} << 24;

// The child's own failure, an internal error.
constexpr int childFailed = 5;

[[noreturn]] void stackExhausted() { _exit(IDRIS_RT_EVAL_EXHAUSTED); }

void writeAll(int fd, llvm::StringRef bytes) {
  while (!bytes.empty()) {
    ssize_t written = write(fd, bytes.data(), bytes.size());
    if (written < 0 && errno == EINTR)
      continue;
    if (written <= 0)
      _exit(childFailed);
    bytes = bytes.drop_front(static_cast<size_t>(written));
  }
}

uint64_t now() {
  timespec t{};
  clock_gettime(CLOCK_MONOTONIC, &t);
  return static_cast<uint64_t>(t.tv_sec) * 1000000000u + static_cast<uint64_t>(t.tv_nsec);
}

struct Work {
  llvm::ArrayRef<Jit::Entry> entries;
  llvm::ArrayRef<size_t> words;
  llvm::ArrayRef<Budget> budgets;
  size_t first;
  llvm::function_ref<llvm::SmallVector<std::string>(size_t, llvm::ArrayRef<uint64_t>)> reify;
  int out;
};

// Each call's record: "<nanoseconds> <count>\n", then "<length>\n<text>" per
// result.
void runCalls(void *argument) {
  auto &work = *static_cast<Work *>(argument);
  for (size_t i = work.first; i < work.entries.size(); ++i) {
    llvm::SmallVector<uint64_t> slots(work.words[i]);
    uint64_t start = now();
    const Budget &budget = work.budgets[i];
    idris_rt_eval_meter(budget.ticks, budget.bytes, budget.stack);
    work.entries[i](slots.data());
    idris_rt_eval_unmetered();
    uint64_t elapsed = now() - start;
    llvm::SmallVector<std::string> texts = work.reify(i, slots);
    std::string record = (llvm::Twine(elapsed) + " " + llvm::Twine(texts.size()) + "\n").str();
    for (const std::string &text : texts)
      record += (llvm::Twine(text.size()) + "\n" + text).str();
    writeAll(work.out, record);
  }
}

[[noreturn]] void child(Work &work, int report) {
  idris_rt_eval_begin(report);
  if (idris_rt_run_on_stack(runCalls, &work, stackFor(work.budgets.drop_front(work.first)),
                            stackGuard, stackExhausted) != 0)
    _exit(IDRIS_RT_EVAL_EXHAUSTED);
  _exit(0);
}

// Everything the child writes to its two pipes, read from both as it comes:
// a child that blocks writing one (a crash report longer than the pipe
// holds, which is 16 KiB on Darwin) while the parent waits for the other to
// end would hold both processes for ever.
struct Streams {
  std::string results;
  std::string report;
};

Streams readBoth(int results, int report) {
  Streams streams;
  std::string *into[2] = {&streams.results, &streams.report};
  pollfd fds[2] = {{results, POLLIN, 0}, {report, POLLIN, 0}};
  char buffer[1 << 16];
  int open = 2;
  while (open > 0) {
    if (poll(fds, 2, -1) < 0) {
      if (errno == EINTR)
        continue;
      return streams;
    }
    for (int i = 0; i < 2; ++i) {
      if (fds[i].fd < 0 || (fds[i].revents & (POLLIN | POLLHUP | POLLERR)) == 0)
        continue;
      ssize_t got = read(fds[i].fd, buffer, sizeof buffer);
      if (got < 0 && errno == EINTR)
        continue;
      if (got <= 0) {
        // A negative descriptor is one poll leaves out.
        fds[i].fd = -1;
        --open;
        continue;
      }
      into[i]->append(buffer, static_cast<size_t>(got));
    }
  }
  return streams;
}

// The complete records at the start of the bytes the child wrote, and
// whether they are all of it: every line of a record ends in its newline,
// and every text is as long as its length says, so a record cut short is
// never read as a shorter one.
struct Records {
  llvm::SmallVector<Result> results;
  bool complete = true;
};

// The next line of `rest`, without its newline, if it has one.
std::optional<llvm::StringRef> takeLine(llvm::StringRef &rest) {
  size_t end = rest.find('\n');
  if (end == llvm::StringRef::npos)
    return std::nullopt;
  llvm::StringRef line = rest.take_front(end);
  rest = rest.drop_front(end + 1);
  return line;
}

std::optional<Result> takeRecord(llvm::StringRef &rest) {
  std::optional<llvm::StringRef> head = takeLine(rest);
  if (!head)
    return std::nullopt;
  auto [time, count] = head->split(' ');
  Result result;
  unsigned texts = 0;
  if (time.getAsInteger(10, result.nanoseconds) || count.getAsInteger(10, texts))
    return std::nullopt;
  for (unsigned t = 0; t < texts; ++t) {
    std::optional<llvm::StringRef> length = takeLine(rest);
    size_t n = 0;
    if (!length || length->getAsInteger(10, n) || rest.size() < n)
      return std::nullopt;
    result.texts.push_back(rest.take_front(n).str());
    rest = rest.drop_front(n);
  }
  return result;
}

Records parse(llvm::StringRef bytes) {
  Records records;
  while (!bytes.empty()) {
    std::optional<Result> result = takeRecord(bytes);
    if (!result) {
      records.complete = false;
      return records;
    }
    records.results.push_back(std::move(*result));
  }
  return records;
}

} // namespace

} // namespace idr::eval

export namespace idr::eval {

// Why this process may not run the code its JIT wrote, or nothing when it
// may. The probe, a function of that code that returns at once, runs in a
// child of its own: a system that refuses to run what a process wrote
// kills the process that tries (Darwin's hardened runtime does, with
// SIGKILL, though mprotect made the pages executable), and every call would
// otherwise read as killed for want of memory. One probe that ran tells for
// the whole process. When no child can start, it tells nothing, and the
// run that follows says why.
std::optional<std::string> refusesJitCode(Jit::Entry probe) {
  static bool runs = false;
  if (runs)
    return std::nullopt;
  pid_t pid = fork();
  if (pid == 0) {
    probe(nullptr);
    _exit(0);
  }
  if (pid < 0)
    return std::nullopt;
  int status = 0;
  while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
  }
  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    runs = true;
    return std::nullopt;
  }
  std::string ended = WIFSIGNALED(status)
                          ? "was killed by signal " + std::to_string(WTERMSIG(status))
                          : "exited with status " + std::to_string(WEXITSTATUS(status));
  std::string why =
      "unsupported (executable memory): compile-time evaluation cannot run here: a function its "
      "JIT compiled, which returns at once, " +
      ended +
      ". The JIT maps its code writable, then executable and never writable again, and this "
      "system refuses to run it";
  if (llvm::Triple(llvm::sys::getProcessTriple()).isOSDarwin())
    why += ". Under macOS's hardened runtime, a process may run such code only with the "
           "entitlement com.apple.security.cs.allow-unsigned-executable-memory "
           "(com.apple.security.cs.allow-jit covers MAP_JIT memory, which LLVM's JIT does not "
           "map): sign idris-mlir-cc without the hardened runtime, or with that entitlement";
  return why + " (or compile with --no-eval)";
}

// Runs entries[first...] in a child. `words[i]` is the number of 8-byte
// result slots entry i fills; entry i runs within `budgets[i]`;
// `reify(i, slots)` turns the slots into the byte strings sent for them, in
// the child.
Run runInChild(llvm::ArrayRef<Jit::Entry> entries, llvm::ArrayRef<size_t> words,
               llvm::ArrayRef<Budget> budgets, size_t first,
               llvm::function_ref<llvm::SmallVector<std::string>(size_t, llvm::ArrayRef<uint64_t>)>
                   reify) {
  Run run;
  int results[2], report[2];
  if (pipe(results) != 0 || pipe(report) != 0) {
    run.status = Run::Status::Failed;
    run.message = "no pipe for the evaluation child: " + std::string(strerror(errno));
    return run;
  }
  Work work{entries, words, budgets, first, reify, results[1]};
  pid_t pid = fork();
  if (pid == 0) {
    close(results[0]);
    close(report[0]);
    child(work, report[1]);
  }
  close(results[1]);
  close(report[1]);
  if (pid < 0) {
    close(results[0]);
    close(report[0]);
    run.status = Run::Status::Failed;
    run.message = "no evaluation child: " + std::string(strerror(errno));
    return run;
  }
  Streams streams = readBoth(results[0], report[0]);
  Records records = parse(streams.results);
  run.results = std::move(records.results);
  std::string reported = std::move(streams.report);
  close(results[0]);
  close(report[0]);
  int status = 0;
  while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
  }
  // A child that was killed may have been writing a record, and the call
  // it is about did not finish; any other child writes whole records or
  // none, so a record cut short is an internal error.
  bool killed = WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL;
  if (!records.complete && !killed) {
    run.status = Run::Status::Failed;
    run.message = "the evaluation child's results end in a record cut short";
    return run;
  }
  if (WIFEXITED(status)) {
    switch (WEXITSTATUS(status)) {
    case 0:
      run.status = Run::Status::Done;
      return run;
    case IDRIS_RT_EVAL_CRASHED:
      run.status = Run::Status::Crashed;
      run.message = llvm::StringRef(reported).rtrim("\n").str();
      return run;
    case IDRIS_RT_EVAL_EXHAUSTED:
      run.status = Run::Status::Exhausted;
      run.message = "the machine refused memory or stack";
      return run;
    case IDRIS_RT_EVAL_OVER_BUDGET:
      run.status = Run::Status::OverBudget;
      run.message = "it spent its budget";
      return run;
    default:
      run.status = Run::Status::Failed;
      run.message = "the evaluation child exited with status " + std::to_string(WEXITSTATUS(status));
      return run;
    }
  }
  if (killed) {
    run.status = Run::Status::Exhausted;
    run.message = "the evaluation was killed, as the kernel kills a process when memory runs out";
    return run;
  }
  run.status = Run::Status::Failed;
  run.message = "the evaluation child ended with signal " +
                std::to_string(WIFSIGNALED(status) ? WTERMSIG(status) : 0);
  return run;
}

} // namespace idr::eval
