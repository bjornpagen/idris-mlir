# idr.target: the module's target and LLVM's pipeline for it; the glue of
# idr-target, which writes the target, is a plain unit.
idr_library(idr_target
	MODULES
		Target.cppm
		Pipeline.cppm
		Vectors.cppm
	UNITS
		Pipeline/Optimize.cc
		Pipeline/TargetOptions.cc
		Vectors/VectorBits.cc
	GLUE
		Pass.cc
	LINKS
		idr_mlir
)
