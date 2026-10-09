# idr.lower: idr-lower, idr-entry, idr-meter and idr-tail-calls; the pass
# glue (the TableGen-declared bases of each) is plain units that import it.
# Cells and static data follow the runtime's C ABI (idris_rt.h), and
# idr-entry states the CPU features the target enables in the target entry's
# terms (cpu_features.h), both of whose include directory idris_rt gives.
idr_library(idr_lower
	MODULES
		Lower.cppm
		ArrayView.cppm
		Arrays.cppm
		Buffers.cppm
		Bigs.cppm
		BuildBox.cppm
		Cells.cppm
		Checks.cppm
		Closures.cppm
		Counting.cppm
		CrashMessage.cppm
		Entry.cppm
		Facts.cppm
		Fields.cppm
		Frame.cppm
		IdrPattern.cppm
		Loops.cppm
		Lowering.cppm
		Matches.cppm
		Meter.cppm
		PassThroughMemory.cppm
		Patterns.cppm
		ReturnRegisters.cppm
		Runtime.cppm
		RuntimeCalls.cppm
		Scalars.cppm
		StackCell.cppm
		StaticData.cppm
		Strings.cppm
		TailCalls.cppm
		TailPosition.cppm
		Words.cppm
	GLUE
		Pass.cc
		Entry/Pass.cc
		Meter/Pass.cc
		TailCalls/Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_layout
		idris_rt
)
