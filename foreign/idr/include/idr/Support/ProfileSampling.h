// Force-included into the Tracy client, in the profile build only, and
// into nothing else. Tracy's Apple sampler suspends the process's threads
// from user mode and needs no privilege, but it refuses to start unless the
// process runs as root, for the sake of behaving as the kernel tracers of
// other systems do; without it a capture has a time span and no call
// stacks. The one check reads geteuid, declared here first, so the macro
// below changes that call and no declaration. No other system's client
// calls geteuid.
#include <unistd.h>
#undef geteuid
#define geteuid() 0
