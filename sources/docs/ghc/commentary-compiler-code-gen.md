# Code Generator


This page describes code generator ("codegen") in GHC. It is meant to reflect current state of the implementation. If you notice any inaccuracies please update the page (if you know how) or complain on ghc-devs.

- [Overview of the code generator](commentary/compiler/code-gen/overview)
- [Data types and modules for the code generator](commentary/compiler/new-code-gen-modules)
- [The STG language and how to execute it](commentary/compiler/generated-code)
- [The Cmm language syntax](commentary/compiler/cmm-syntax)
- [List of code-gen stupidities](commentary/compiler/new-code-gen-stupidity) (some, but not all, fixed).
- [Clean-up ideas once the new codegen is in place (i.e. now)](commentary/compiler/new-code-gen/cleanup); not all done.
- [Loopification](commentary/compiler/loopification) i.e. turn tail calls into loops
- [LLVM back end](commentary/compiler/backends/llvm)
- [Hoopl/Cleanup](hoopl/cleanup)
- [Planned Backend Optimizations](commentary/compiler/backend-opt)
- [Details about how we place basic blocks](commentary/compiler/code-layout)

## A brief history of code generator


You might occasionally hear about "old" and "new" code generator. GHC 7.6 and earlier used the old code generator. New code generator was being developed since 2007 and it was [enabled by default on 31 August 2012](/trac/ghc/changeset/832077ca5393d298324cb6b0a2cb501e27209768/ghc) after the release of GHC 7.6.1. The first stable GHC to use the new code generator is 7.8.1 released in early 2014. 


Various historical pages, with still-useful info:

- [Commentary on the old code generator](commentary/compiler/old-code-gen)

- [Status page on the "new code generator"](commentary/compiler/new-code-gen) (now the current one)
- [Replace native code generator with LLVM](commentary/compiler/backends/llvm/replacing-ncg)
- [IntegratedCodeGen](commentary/compiler/integrated-code-gen) One plan is to expand the capability of the pipeline so that it does native code generation too so that existing backends can be discarded.

## Tickets

See the ~"code generation" label.
