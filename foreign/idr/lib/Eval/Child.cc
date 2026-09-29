// The evaluation child: fork, a guarded stack as large as the
// address space allows, and the results pipe.

#include "Eval/Child.h"

#include "idris_rt.h"

#include "llvm/ADT/StringExtras.h"

#include <cerrno>
#include <csignal>
#include <cstring>
#include <ctime>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

namespace idr::eval {

namespace {

// The child's stack: `size` bytes at `base`, the lowest `guard` of them
// inaccessible. Pages are committed when first touched.
struct Stack {
  char *base = nullptr;
  size_t size = 0;
  size_t guard = size_t{1} << 24;
};

// The child's own failure, an internal error.
constexpr int childFailed = 5;

// Where a fault means the stack is exhausted; read by the signal handler.
uintptr_t guardLow = 0;
uintptr_t guardHigh = 0;

bool reserve(Stack &stack) {
  for (size_t size = size_t{1} << 46; size >= size_t{1} << 26; size >>= 1) {
    void *base = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (base == MAP_FAILED)
      continue;
    stack.base = static_cast<char *>(base);
    stack.size = size;
    return mprotect(base, stack.guard, PROT_NONE) == 0;
  }
  return false;
}

// A fault on the guard is exhaustion; any other fault is an internal error, so
// the handler steps aside and the fault repeats with the default action.
void onFault(int signal, siginfo_t *info, void *) {
  auto address = reinterpret_cast<uintptr_t>(info->si_addr);
  if (address >= guardLow && address < guardHigh)
    _exit(IDRIS_RT_EVAL_EXHAUSTED);
  struct sigaction fallback{};
  fallback.sa_handler = SIG_DFL;
  sigaction(signal, &fallback, nullptr);
}

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
  llvm::ArrayRef<bool> metered;
  Budget budget;
  size_t first;
  llvm::function_ref<llvm::SmallVector<std::string>(size_t, llvm::ArrayRef<uint64_t>)> reify;
  int out;
};

// Each call's record: "<nanoseconds> <count>\n", then "<length>\n<text>" per
// result.
void *runCalls(void *argument) {
  auto &work = *static_cast<Work *>(argument);
  static char alternate[1 << 16];
  stack_t altStack{};
  altStack.ss_sp = alternate;
  altStack.ss_size = sizeof alternate;
  sigaltstack(&altStack, nullptr);
  struct sigaction action{};
  action.sa_sigaction = onFault;
  action.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigaction(SIGSEGV, &action, nullptr);
  sigaction(SIGBUS, &action, nullptr);
  for (size_t i = work.first; i < work.entries.size(); ++i) {
    llvm::SmallVector<uint64_t> slots(work.words[i]);
    uint64_t start = now();
    if (work.metered[i])
      idris_rt_eval_meter(work.budget.ticks, work.budget.bytes, work.budget.stack);
    work.entries[i](slots.data());
    idris_rt_eval_unmetered();
    uint64_t elapsed = now() - start;
    llvm::SmallVector<std::string> texts = work.reify(i, slots);
    std::string record = (llvm::Twine(elapsed) + " " + llvm::Twine(texts.size()) + "\n").str();
    for (const std::string &text : texts)
      record += (llvm::Twine(text.size()) + "\n" + text).str();
    writeAll(work.out, record);
  }
  return nullptr;
}

[[noreturn]] void child(Work &work, int report) {
  idris_rt_eval_begin(report);
  Stack stack;
  if (!reserve(stack))
    _exit(IDRIS_RT_EVAL_EXHAUSTED);
  guardLow = reinterpret_cast<uintptr_t>(stack.base);
  guardHigh = guardLow + stack.guard;
  pthread_attr_t attributes;
  pthread_t thread;
  if (pthread_attr_init(&attributes) != 0 ||
      pthread_attr_setstack(&attributes, stack.base + stack.guard, stack.size - stack.guard) != 0 ||
      pthread_create(&thread, &attributes, runCalls, &work) != 0 ||
      pthread_join(thread, nullptr) != 0)
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

// The records, as far as they are complete.
llvm::SmallVector<Result> parse(llvm::StringRef records) {
  llvm::SmallVector<Result> results;
  while (!records.empty()) {
    auto [head, rest] = records.split('\n');
    auto [time, count] = head.split(' ');
    Result result;
    unsigned texts = 0;
    if (time.getAsInteger(10, result.nanoseconds) || count.getAsInteger(10, texts))
      return results;
    for (unsigned t = 0; t < texts; ++t) {
      auto [length, body] = rest.split('\n');
      size_t n = 0;
      if (length.getAsInteger(10, n) || body.size() < n)
        return results;
      result.texts.push_back(body.take_front(n).str());
      rest = body.drop_front(n);
    }
    results.push_back(std::move(result));
    records = rest;
  }
  return results;
}

} // namespace

Run runInChild(llvm::ArrayRef<Jit::Entry> entries, llvm::ArrayRef<size_t> words,
               llvm::ArrayRef<bool> metered, Budget budget, size_t first,
               llvm::function_ref<llvm::SmallVector<std::string>(size_t, llvm::ArrayRef<uint64_t>)>
                   reify) {
  Run run;
  int results[2], report[2];
  if (pipe(results) != 0 || pipe(report) != 0) {
    run.status = Run::Status::Failed;
    run.message = "no pipe for the evaluation child: " + std::string(strerror(errno));
    return run;
  }
  Work work{entries, words, metered, budget, first, reify, results[1]};
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
  run.results = parse(readAll(results[0]));
  std::string reported = readAll(report[0]);
  close(results[0]);
  close(report[0]);
  int status = 0;
  while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
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
  if (WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL) {
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
