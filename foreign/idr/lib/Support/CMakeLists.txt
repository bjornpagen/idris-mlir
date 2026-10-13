# What any library may use and that names nothing of the dialect: the
# components of a graph, the actions a pass performs, and the profile
# instrumentation, which records nothing until a tool starts a trace.
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
