# What any library may use and that names nothing of the dialect: the
# components of a graph, the actions a pass performs, and the profile
# instrumentation, which adds nothing without TRACY_ENABLE.
# Support/ProfileAlloc.cpp is no unit of this library: the profile build
# compiles it into the tools alone (foreign/idr/CMakeLists.txt).
set(LLVM_OPTIONAL_SOURCES ProfileAlloc.cpp)
add_mlir_library(IdrSupport
	Scc.cpp
	Actions.cpp
	Profile.cpp

	EXCLUDE_FROM_LIBMLIR
	DISABLE_INSTALL

	LINK_LIBS PUBLIC
	MLIRIR
	MLIRPass
	MLIRSupport
)
