module Eager

-- Each computation below is evaluated though nothing uses its value, as
-- eager evaluation evaluates it: an unused let, an argument an inlined
-- function ignores, a constructor's field a match ignores, a pattern let,
-- and the effectful argument of a recursive call in a function that is an
-- identity on its other argument. A delayed argument nothing forces is not.

say : String -> ()
say s = unsafePerformIO (putStrLn s)

unusedLet : () -> Nat
unusedLet () = let x = say "let" in 1

%inline
first : a -> b -> a
first x _ = x

ignoredArg : () -> Nat
ignoredArg () = first 2 (say "argument")

ignoredField : () -> Nat
ignoredField () = case (say "field", the Nat 3) of (_, y) => y

patternLet : () -> Nat
patternLet () = let () = say "pattern" in 4

ident : Nat -> () -> Nat
ident Z u = Z
ident (S k) u = S (ident k (say "recursive"))

lazily : Lazy Nat -> Nat
lazily _ = 6

main : IO ()
main = do printLn (unusedLet ())
          printLn (ignoredArg ())
          printLn (ignoredField ())
          printLn (patternLet ())
          printLn (ident 2 ())
          printLn (lazily (fst (the Nat 0, say "delayed")))
