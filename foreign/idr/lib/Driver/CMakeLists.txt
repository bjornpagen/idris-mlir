# idr.driver: idris-mlir-cc, whose `main` (tools/idris-mlir-cc.cc) calls
# it. It reads the runtime's C ABI (idris_rt.h, the reserved-stack runner)
# and the target entry's list of processor features (cpu_features.h), whose
# include directory and definition idris_rt gives. The pipeline's entry
# points (registerIdr, pipelineSteps) are idr_dialect's, which the tool
# links after this library.
idr_library(idr_driver
	MODULES
		Driver.cppm
		BesideObject.cppm
		Cpu.cppm
		Dump.cppm
		Emit.cppm
		Externalize.cppm
		IsPrepared.cppm
		LinkRuntime.cppm
		Main.cppm
		MarkAnnotated.cppm
		Marks.cppm
		Members.cppm
		ModuleFlagString.cppm
		NamesApart.cppm
		NativeRuns.cppm
		Options.cppm
		Prepare.cppm
		PrepareMember.cppm
		PreparedBitcode.cppm
		ReadRuntime.cppm
		Report.cppm
		Retarget.cppm
		Run.cppm
		RunOnLargeStack.cppm
		SameTarget.cppm
		SetTarget.cppm
		WriteOutput.cppm
	LINKS
		idr_mlir
		idr_ods
		idr_target
		idris_rt
)
