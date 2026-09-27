/* measure IN OUT CMD [ARG...]: runs CMD with stdin read from IN and stdout
   written to OUT (stderr is inherited), and prints one line to stdout:

     <wall seconds> <peak RSS in KiB> <exit status>

   The peak RSS is the largest resident set of CMD and of every descendant
   it waited for (wait4's ru_maxrss). A command killed by signal s reports
   status 128+s. The gate's scripts use this instead of time(1), which the
   container does not have. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: measure IN OUT CMD [ARG...]\n");
    return 2;
  }
  int in = open(argv[1], O_RDONLY);
  if (in < 0) { fprintf(stderr, "measure: %s: %s\n", argv[1], strerror(errno)); return 2; }
  int out = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (out < 0) { fprintf(stderr, "measure: %s: %s\n", argv[2], strerror(errno)); return 2; }
  double start = now();
  pid_t pid = fork();
  if (pid < 0) { perror("measure: fork"); return 2; }
  if (pid == 0) {
    dup2(in, 0);
    dup2(out, 1);
    close(in);
    close(out);
    execvp(argv[3], argv + 3);
    fprintf(stderr, "measure: %s: %s\n", argv[3], strerror(errno));
    _exit(127);
  }
  close(in);
  close(out);
  int status;
  struct rusage use;
  while (wait4(pid, &status, 0, &use) < 0) {
    if (errno != EINTR) { perror("measure: wait4"); return 2; }
  }
  double elapsed = now() - start;
  int code = WIFEXITED(status) ? WEXITSTATUS(status)
           : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : 255;
  printf("%.3f %ld %d\n", elapsed, use.ru_maxrss, code);
  return 0;
}
