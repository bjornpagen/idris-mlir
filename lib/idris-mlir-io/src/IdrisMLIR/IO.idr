||| The trusted IO module of the idris-mlir profile (docs/architecture/02-profile.md,
||| PROF-IO-*). The only place `%foreign` is allowed. Every primitive also has
||| a Chez implementation with the same semantics (SEM-IO-*), so programs run
||| on the stock Chez backend for differential testing (TEST-DIFF-1).
module IdrisMLIR.IO

import public Builtin
import public PrimIO

%default total

export infixl 1 >>=, >>

||| SEM-IO-2: the UTF-8 encoding of the string, on standard output.
%foreign "scheme:(lambda (s) (put-string (current-output-port) s))"
prim__idrPutStr : String -> PrimIO ()

||| SEM-IO-2: the UTF-8 encoding of the character.
%foreign "scheme:(lambda (c) (put-char (current-output-port) c))"
prim__idrPutChar : Char -> PrimIO ()

||| SEM-IO-3: the next character of standard input; '\0' at the end.
%foreign "scheme:(lambda () (begin (flush-output-port (current-output-port)) (let ((c (get-char (current-input-port)))) (if (eof-object? c) #\\nul c))))"
prim__idrGetChar : PrimIO Char

||| SEM-IO-5: ends the process with status n mod 256 after writing pending output.
%foreign "scheme:(lambda (n) (begin (flush-output-port (current-output-port)) (exit (modulo n 256))))"
prim__idrExit : Int -> PrimIO ()

export
pure : a -> IO a
pure x = io_pure x

export
(>>=) : IO a -> (a -> IO b) -> IO b
(>>=) act k = io_bind act k

export
(>>) : IO () -> Lazy (IO b) -> IO b
(>>) act next = io_bind act (\_ => next)

export
putStr : String -> IO ()
putStr s = fromPrim (prim__idrPutStr s)

export
putStrLn : String -> IO ()
putStrLn s = putStr (prim__strAppend s "\n")

export
putChar : Char -> IO ()
putChar c = fromPrim (prim__idrPutChar c)

export
getChar : IO Char
getChar = fromPrim prim__idrGetChar

export
exit : Int -> IO ()
exit n = fromPrim (prim__idrExit n)
