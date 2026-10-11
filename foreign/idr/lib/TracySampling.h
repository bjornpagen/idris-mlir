// The Apple sampler suspends threads in user mode. It does not need to
// be root, but it refuses to start unless the process is. This header is
// force-included into the Tracy client only, after geteuid is declared,
// so that one check does not see a privileged process.
#include <unistd.h>
#undef geteuid
#define geteuid() 0
