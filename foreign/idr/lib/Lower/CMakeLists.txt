# idr.lower: idr-lower and idr-tail-calls; the pass glue (the
# TableGen-declared bases of both) is plain units that import it. Cells and
# static data follow the runtime's C ABI (idris_rt.h), and idr-lower states
# the CPU features the target enables in the target entry's terms
# (cpu_features.h), both of whose include directory idris_rt gives.
idr_library(idr_lower
	MODULES
		Lower.cppm
		ArrayView.cppm
		Arrays.cppm
		Buffers.cppm
		Bigs.cppm
		BuildBox.cppm
		Cells.cppm
		Closures.cppm
		Counting.cppm
		CrashMessage.cppm
		Facts.cppm
		Fields.cppm
		Frame.cppm
		IdrPattern.cppm
		Loops.cppm
		Lowering.cppm
		Matches.cppm
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
		TailCalls/Pass.cc
	LINKS
		idr_mlir
		idr_ods
		idr_graph
		idr_layout
		idris_rt
)
