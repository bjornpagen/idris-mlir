# idr.fold: what the folders of the string and big ops share, which calls
# the runtime natively (idris_rt.h, whose include directory idris_rt gives);
# the folders themselves, the ops' `fold` hooks, are plain units that import
# it.
idr_library(idr_fold
	MODULES
		Fold.cppm
		Calls.cppm
		Lists.cppm
		Scope.cppm
		Values.cppm
	GLUE
		Bigs.cc
		Heads.cc
		StringOfList.cc
		Strings.cc
	LINKS
		idr_mlir
		idr_ods
		idris_rt
)
