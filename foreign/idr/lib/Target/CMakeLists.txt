# idr.target: the module's target and LLVM's pipeline for it; the glue of
# idr-target, which writes the target, is a plain unit.
idr_library(idr_target
	MODULES
		Target.cppm
		Optimize.cppm
		TargetOptions.cppm
		Vectors.cppm
	GLUE
		Pass.cc
	LINKS
		idr_mlir
)
