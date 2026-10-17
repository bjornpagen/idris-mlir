module Count

%default total

export
count : Nat -> Nat
count Z = Z
count (S k) = S (count k)
