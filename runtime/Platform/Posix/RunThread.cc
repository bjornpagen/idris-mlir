// A thread on a stack of the runtime's own, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <pthread.h>
#include <stddef.h>

module rt.platform;

namespace {

struct Thread {
  void (*fn)(void *);
  void *arg;
};

void *startThread(void *argument) {
  auto &thread = *static_cast<Thread *>(argument);
  thread.fn(thread.arg);
  return nullptr;
}

} // namespace

bool rt::platform::runThread(void (*fn)(void *), void *arg, char *stack, size_t size) noexcept {
  Thread thread{fn, arg};
  pthread_attr_t attributes;
  if (pthread_attr_init(&attributes) != 0)
    return false;
  pthread_t id;
  bool started = pthread_attr_setstack(&attributes, stack, size) == 0 &&
                 pthread_create(&id, &attributes, startThread, &thread) == 0;
  pthread_attr_destroy(&attributes);
  if (started)
    pthread_join(id, nullptr);
  return started;
}
