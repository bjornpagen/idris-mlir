// The evaluation child: fork, a guarded stack as large as the
// address space allows (the runtime's reserved-stack runner), and the
// results pipe.

#include "Eval/Child.h"

#include "idris_rt.h"

#include "llvm/ADT/StringExtras.h"

#include <cerrno>
#include <csignal>
#include <cstring>
#include <ctime>
#include <optional>
#include <sys/wait.h>
#include <unistd.h>

namespace idr::eval {

namespace {

// The child's stack: at most 2^46 bytes of address space, committed as it is
// touched, above a guard of 16 MiB. A metered call's stack budget ends it
// before the guard; a fault on the guard is the machine's limit, exhaustion.
constexpr size_t stackMost = size_t{1} << 46;
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
  if (idris_rt_run_on_stack(runCalls, &work, stackMost, stackGuard, stackExhausted) != 0)
    _exit(IDRIS_RT_EVAL_EXHAUSTED);
  _exit(0);
}

std::string readAll(int fd) {
  std::string all;
  char buffer[1 << 16];
  while (true) {
    ssize_t got = read(fd, buffer, sizeof buffer);
    if (got < 0 && errno == EINTR)
      continue;
    if (got <= 0)
      return all;
    all.append(buffer, static_cast<size_t>(got));
  }
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
  Records records = parse(readAll(results[0]));
  run.results = std::move(records.results);
  std::string reported = readAll(report[0]);
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
