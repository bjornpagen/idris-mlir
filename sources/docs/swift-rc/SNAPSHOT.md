# Snapshot: Swift's non-atomic retain entry

- **Upstream:** `stdlib/public/runtime/HeapObject.cpp` at tag `swift-6.2-RELEASE`, https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/runtime/HeapObject.cpp.
- **Fetched:** 2026-10-07.
- **File:** `HeapObject.cpp`.
- **Licence:** Apache-2.0 with Runtime Library Exception, as the file header states.

The file is the shipped entry points `swift_retain` and `swift_nonatomic_retain`. Choi, Shull, and Torrellas (PACT 2018) is a separate modification of this runtime; it is stored at `papers/choi-2018-biased-rc/`.
