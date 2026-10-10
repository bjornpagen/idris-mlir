# Snapshot addendum: MLIR array-stack ODS (merge into `code/mlir/SNAPSHOT.md`)

This adds 38 files to the existing `code/mlir/` snapshot; it duplicates none of its 94.
Merge this section into `code/mlir/SNAPSHOT.md` (and the file count, 94 to 132) when the
staged library is applied; the snapshot's upstream, revision, paths and licence are
unchanged.

- **Upstream:** `llvm/llvm-project`, the `mlir/` component.
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642` (`mlir`
  subtree `ec52aa1c2a6f38a131b8edffc6390e1c60cbc4e0`), the repository's LLVM pin, the same
  revision as the rest of this snapshot.
- **Fetched:** 2026-10-09, from the bootstrap's clone: each file taken with
  `git -C .toolchain/llvm-project cat-file blob 7208ba24…:mlir/<path>`. Nothing was
  downloaded.
- **Paths:** relative to `llvm-project/mlir/` (so `include/mlir/...`, and
  `python/mlir/...` for the one OpDSL file).
- **Files added:** 38.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** F, G (topic: Array languages and typed array programming).

**What was taken and why.** The ODS definitions of the dialects a typed array language
lowers onto, whose generated documentation (`Dialects/TensorOps.md`, `SparseTensorOps.md`,
`SCFDialect.md`, `ShardOps.md`, `LinalgOps.md` and the like) is not in `docs/mlir/`
because upstream generates it from these files:

- Linalg: `Dialect/Linalg/IR/{LinalgBase,LinalgEnums,LinalgInterfaces,LinalgOps,
  LinalgStructuredOps,LinalgRelayoutOps}.td` (`linalg.generic`, `map`, `reduce`,
  `transpose`, `broadcast`, `elementwise`, `contract`, `matmul`, `pack`/`unpack`, the
  structured-op interfaces); `Dialect/Linalg/Passes.td`;
  `Dialect/Linalg/TransformOps/{LinalgTransformOps,LinalgMatchOps}.td` (tile, fuse,
  pad, pack, vectorize as transform ops); `python/mlir/dialects/linalg/opdsl/ops/core_named_ops.py`
  (the OpDSL source of the named ops).
- Tensor: `Dialect/Tensor/IR/{TensorBase,TensorOps}.td` (`extract_slice`,
  `insert_slice`, `parallel_insert_slice`, `expand_shape`, `collapse_shape`, `pad`,
  `concat`, `generate`, `empty`, `gather`, `scatter`).
- Bufferization: `Dialect/Bufferization/IR/{BufferizationBase,BufferizationOps,
  BufferizableOpInterface,BufferViewFlowOpInterface,BufferDeallocationOpInterface,
  AllocationOpInterface,BufferizationTypeInterfaces}.td`,
  `Dialect/Bufferization/IR/BufferizableOpInterface.h` (the `BufferizationOptions` hooks: `allocationFn`, `memCpyFn`, type converters), `Dialect/Bufferization/Transforms/Passes.td`,
  `Dialect/Bufferization/TransformOps/BufferizationTransformOps.td`.
- Vector: `Dialect/Vector/IR/{VectorAttributes,VectorOps}.td`,
  `Dialect/Vector/TransformOps/VectorTransformOps.td`.
- SparseTensor: `Dialect/SparseTensor/IR/{SparseTensorBase,SparseTensorAttrDefs,
  SparseTensorTypes,SparseTensorOps}.td`, `Dialect/SparseTensor/Transforms/Passes.td`.
- Shard (formerly Mesh): `Dialect/Shard/IR/{ShardBase,ShardOps}.td`,
  `Dialect/Shard/Interfaces/ShardingInterface.td`, `Dialect/Shard/Transforms/Passes.td`
  (`sharding-propagation`, `shard-simplify`, `shard-partition`),
  `Dialect/Shard/Transforms/ReshardingPartitionDoc.md`.
- SCF: `Dialect/SCF/IR/{SCFOps,DeviceMappingInterface}.td` (`scf.forall`,
  `scf.forall.in_parallel`, `scf.parallel`), `Dialect/SCF/TransformOps/SCFTransformOps.td`.

The interfaces these ops implement (`TilingInterface`, `DestinationStyleOpInterface`,
`SubsetOpInterface`, `ValueBoundsOpInterface`, `ParallelCombiningOpInterface`, ...) are
already in this snapshot under `include/mlir/Interfaces/`.

**How to fetch more.** Any other file at the pin:
`git -C .toolchain/llvm-project cat-file blob 7208ba24ca2894729cd394475a00d2a7b605e642:mlir/<path>`,
or `https://raw.githubusercontent.com/llvm/llvm-project/7208ba24ca2894729cd394475a00d2a7b605e642/mlir/<path>`.
The implementations named in the notes (One-Shot Bufferize, `shard-partition`, the
sparsifier, the Linalg vectorizer, the ShardToMPI conversion) are under `mlir/lib/` at the
same revision and are not vendored, following this snapshot's pointer policy.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `include/mlir/Dialect/Linalg/IR/LinalgBase.td` | 3134 | `c50cc90a96d12346191538fbb4ab4513f3d6fa59d65527c13a46a556631e35c4` |
| `include/mlir/Dialect/Linalg/IR/LinalgEnums.td` | 5406 | `2b3eda076378179acd0e0ad683f0aa5d6d928473e2d18e20c01cd249ac8575f2` |
| `include/mlir/Dialect/Linalg/IR/LinalgInterfaces.td` | 28216 | `5150303d019f08ddc62b630306d3ba9afc5c192ba89c2fb5141c98b3bbc81788` |
| `include/mlir/Dialect/Linalg/IR/LinalgOps.td` | 12962 | `c24ff56b5ae78cb1444b47ee7bea5159a59f77a6cb3c197a66c1a3bd1405653f` |
| `include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td` | 55401 | `4992f7bf57d037fac5e8ba8f7cf9b3e11b00fbde93f1966558eca10d76b99b96` |
| `include/mlir/Dialect/Linalg/IR/LinalgRelayoutOps.td` | 19753 | `3ac22eb738edbdcf77f374df52bddadf4076fe6cb80663e8ebd47479cfab2c47` |
| `include/mlir/Dialect/Linalg/Passes.td` | 11003 | `8ddba8ca34a6663a53acd8585c2150dac82cb3c667e3ba943fb9fa5d4dec4fde` |
| `include/mlir/Dialect/Linalg/TransformOps/LinalgTransformOps.td` | 135763 | `80e2610f4a788a725c80e8aa1c131ff468e69f2b174f7bc04378c036b94f88c6` |
| `include/mlir/Dialect/Linalg/TransformOps/LinalgMatchOps.td` | 25648 | `fa2a0b3d715f30736bbc71708cc2be497c5d303a82d8bc01c3cb042edce8c781` |
| `python/mlir/dialects/linalg/opdsl/ops/core_named_ops.py` | 49156 | `7cba180e83280404792e8a1b4a137f2ce19e9b69cae70e1fd544249ab99b33a0` |
| `include/mlir/Dialect/Tensor/IR/TensorBase.td` | 2681 | `708a67185293149bbbe6faed6eb9a2e996580b731b098fc7cdbf181de06febd2` |
| `include/mlir/Dialect/Tensor/IR/TensorOps.td` | 72440 | `e67c196b8b855429c2644eabfb452930aff8931ff4ec1c17600877bbc52c9d2e` |
| `include/mlir/Dialect/Bufferization/IR/BufferizationBase.td` | 3738 | `c698f9e85682d6b4be44bef5b69bea86f88f15247f728ce87accb58144912b67` |
| `include/mlir/Dialect/Bufferization/IR/BufferizationOps.td` | 22514 | `ca7b6ca3c9168276c5fe04f3707c9edafb02ec1e612798f83fbee7ad9bc5b531` |
| `include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.td` | 29360 | `bb67324b3fbbb5b24ddfce09fe32128cabc8828b8161b1751d547436ea1405ff` |
| `include/mlir/Dialect/Bufferization/IR/BufferViewFlowOpInterface.td` | 2842 | `a55d6704624b038c6c9fc12c762b2d76dd3c1d125fb0fcdf3faa6fa6be757c05` |
| `include/mlir/Dialect/Bufferization/IR/BufferDeallocationOpInterface.td` | 3589 | `3ae4bd2b4cae8c7e27ad61c1ae86bd4fb2ab1f5cffb5c84e2575a347cc0840ed` |
| `include/mlir/Dialect/Bufferization/IR/AllocationOpInterface.td` | 3417 | `561de25dcd2425231318ae629a3f4bd2f6aa3a8301627b403d195dd522624a41` |
| `include/mlir/Dialect/Bufferization/Transforms/Passes.td` | 29844 | `e61c18e40e3d1fe92f9a6863c382274af864f2a1ca5096178301904e5e4afe3d` |
| `include/mlir/Dialect/Bufferization/TransformOps/BufferizationTransformOps.td` | 7776 | `2e68a83f8cd282ab88ff175efe28fb151cfb14cf92424d8724268c181cb81313` |
| `include/mlir/Dialect/Vector/IR/VectorAttributes.td` | 3583 | `1cc8ccc8aa6d19dc60efe0aa1660a7ce17fe7ab3d494d357056dbb4e7045c122` |
| `include/mlir/Dialect/Vector/IR/VectorOps.td` | 125702 | `1ce6127588320ccbccf620ff98fedf0c4c08cbb03f7bf9ed3080702a616ea411` |
| `include/mlir/Dialect/Vector/TransformOps/VectorTransformOps.td` | 21877 | `2159c50a2c18530087c5cd559c05625fcc92398db86f7a273e514a37b4023220` |
| `include/mlir/Dialect/SparseTensor/IR/SparseTensorBase.td` | 5415 | `9af1be1f8cf6061bcd774118789ec1acf58216feca4e68424cde64f9a2efe5a0` |
| `include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td` | 28705 | `665f0243b7194beb3a9fdeb9106bacb95b55ecabed0fb3e16cd9dd867688a175` |
| `include/mlir/Dialect/SparseTensor/IR/SparseTensorTypes.td` | 6158 | `774b267a42543b3e9f56327c0e85f5636d543e36993e6e08f4a4468f18509aac` |
| `include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td` | 76210 | `00d073c906532f81a4fef71de2460f76759fcbe0f23a0ff8a6e1328a345c67fe` |
| `include/mlir/Dialect/SparseTensor/Transforms/Passes.td` | 24849 | `6bdc965b464f277f92674832fdc530f5933bd591d4f51d9685c5b3e3b7bab58d` |
| `include/mlir/Dialect/Shard/IR/ShardBase.td` | 3259 | `33d311f95b64d1ec221ad9cc4248ded816431f2d0b402f2833b57a257adf224c` |
| `include/mlir/Dialect/Shard/IR/ShardOps.td` | 41009 | `9a25c19359b9c51939dc92c3c7c6db1c6ccdd98a4924b5590e77c82357c39886` |
| `include/mlir/Dialect/Shard/Interfaces/ShardingInterface.td` | 7334 | `d33af37e12a6d04d53fbb0b9f35a61acac859e06d108ee0c174284eea2635e32` |
| `include/mlir/Dialect/Shard/Transforms/Passes.td` | 4654 | `79582b94e7b33ae3299ad9703155f7efd7dc870d0b576b0135bf245008013b6a` |
| `include/mlir/Dialect/Shard/Transforms/ReshardingPartitionDoc.md` | 18027 | `ae40dacc9cdf9b5e0a7fea227c1df6269f65c93391e5701ed359c8d67ae0d5df` |
| `include/mlir/Dialect/SCF/IR/SCFOps.td` | 49923 | `b713a7eb972e9a46a12d8bdb0c26782b1085934cbd9fc52631b2de4e67f37155` |
| `include/mlir/Dialect/SCF/IR/DeviceMappingInterface.td` | 4422 | `402ab07aced932c0b4ee8bdade15a72cd7ce53fa05f04a494da48fd2d7b35f31` |
| `include/mlir/Dialect/SCF/TransformOps/SCFTransformOps.td` | 22057 | `376620fb06482fdc33261df06ec3d1514198ffcff94b7486cab4e1280b4abf25` |
| `include/mlir/Dialect/Bufferization/IR/BufferizationTypeInterfaces.td` | 1829 | `af35eab08fba5fc9690812c1ea0e86e34bfda426317f0d9bf0822ab93ef76fc6` |
| `include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h` | 31442 | `e4cdc01d6d5fe89547ccc1dedfabc18bceca42f232565823cb83ecbb61009bdf` |
