// A pool whose strategy names a stack size runs a task that needs more stack
// than any default gives (8 MiB on Darwin, the usual 8 MiB elsewhere): it
// prints "ok" with the patch, and overflows its thread's stack without it.
// Built against the toolchain's LLVMSupport:
//   clang++ -std=c++17 stack-size.cpp $(llvm-config --cxxflags --ldflags --libs support)
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/Threading.h"
#include <cstdio>

static int deep() {
  volatile char frame[12 * 1024 * 1024];
  frame[0] = 1;
  frame[sizeof(frame) - 1] = 1;
  return frame[0] + frame[sizeof(frame) - 1];
}

int main() {
  llvm::ThreadPoolStrategy strategy = llvm::hardware_concurrency(1);
  strategy.StackSizeInBytes = 16 * 1024 * 1024;
  llvm::StdThreadPool pool(strategy);
  int sum = 0;
  pool.async([&sum] { sum = deep(); });
  pool.wait();
  std::puts(sum == 2 ? "ok" : "wrong");
  return sum == 2 ? 0 : 1;
}
