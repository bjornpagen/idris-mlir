/* The runtime's link check. runtime/CMakeLists.txt links every
 * member of the runtime archive into this program, as an executable of
 * the target (its entry's executable flags) with no C++ library and no
 * unwinder: a reference to the C++
 * runtime is an undefined symbol, so the link, and the build, fail. */
int main(void) { return 0; }
