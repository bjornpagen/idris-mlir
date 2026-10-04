// The runtime's page-size check, called as idris_rt_start calls it first
// (runtime/Start/Entry.cppm): exits 0, silently, when the page size the
// runtime was built for (IDRIS_RT_PAGE_SIZE) is the system's.
import rt.platform;

int main() {
  rt::platform::checkPageSize();
  return 0;
}
