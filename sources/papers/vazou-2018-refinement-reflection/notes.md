# Formalizing PBE


RJ TODO

17:795  Explain the meaning of the \oplus_1 and \bowtie
 operators.
 [DONE?]

18:866  Possibly remind the reader that \lfloor e \rfloor is
 defined at start of Section 5.1.
  [DONE]

18:868  Explain that \lfloor R \rfloor is defined in Section 6.
  [DONE]

19:906  If \Phi_{i+1} \subseteq \Phi a typo?
 Going by the text, it should be \Phi_{i+1} \subseteq \Phi_i.
  [DONE]

20:976 “and that if two” --> “such that if two”
  [DONE]

22:1076 “Next” --> “Finally”
  [DONE?] -- not sure which "next"

22:1108 “If \bar{t_0} \equiv \bar{x_0} for some
 variables \bar{x_0}” I don’t understand. What
 do the x_0 correspond to? Why do we need this
 restriction?
 [DONE]


23:1095  Help! I’m lost.
 Where is f bound? What does it range over?
 In the next definition, it becomes clear that
 f ranges over names bound in \Psi. But it is
 bad if I can’t read the paper in order.

 Even worse, how can you have
   f(e_1,...,e_n) < e_i ?
 That suggests that e_i is a subterm of itself!


Ryan's Volume Related Requests

* Why is 2.3 there ?
* What does PBE really buy you? (intution about "equational proofs")
* Completeness (PBE) = always erase your =. chain?
* Completeness (HOL) = punchline discussion

"It is readily apparent that PBE's
combination of proof search working
hand-in-glove with SMT-based theory
reasoning makes proving the result
relatively trivial.
%
Of course, the decades-worth of tactics,
libraries and proof scripts available in
Coq, Agda, Isabelle etc. enable large
scale proof engineering that is well
beyond what is currently possible with
our approach.
%
We merely use this example it to illustrate
that reflection and SMT-based proof search
bring powerful, complete new tools for
specification and verification."

(We  Proof By Logical Evaluation
strategy may, like  omega, be encoded as a tactic.)**

The "clean intuition" is wrong;
yes one proves termination with
no infinite chains (is standard)
but the chains here are not
concrete computations but
a symbolic procedure that
has nothing to do with
the concrete semantics.

It is trivial to encode
unfolding with triggers
BUT that diverges EVEN
with terminating
functions. Why?


In short; what you're
really saying is not
so much that the
proof is standard
as I need to better
explain in the paper
WHY it is non standard :)

We will keep all the other stuff if we want get this paper accepted ... however please add a NOTE so I can add some text explaining the structure of the termination proof and why all those other pieces are important. (In a nutshell they are there to show how PBE is an "abstract interpretation" of the concrete executions)

Put another way your "clean intuition" applies to single concrete inputs: f i will terminate on any INDIVIDUAL i. However in symbolic land we are working with potentially INFINITE sets of i -- each of which would terminate individually -- but we need to show that our COLLECTIVE procedure will also terminate. Note that the naive approach of enumerating each i and running it obviously does not terminate; that's why we have to carefully formalize the notion of "execution" at a logical level and use transparency to connect the two worlds.
```

Btw, the reason that the eq-proofs are NOT
*fully bidirectional* (i.e. using @nikivazou ‘s
transitive-right rule) is something like this.
I am worried that if we allow bidirectional
proofs, you can end up with proofs that
look like:

```Renv, Penv |- f(MAGIC) ==> e1
Renv, Penv |- f(MAGIC) ==> e2
-----------------------------
Renv, Penv |- e1 = e2
```

(where `==>` is the uni-directional unfolding/equality) and
`MAGIC` is some magical instantiation that is nowhere to
be found in `Renv` or `Penv` (i.e. does not get found by PBE).

I’m having a hard time constructing such an `f` … but I *also* don’t know
how to prove it doesn’t exist :slightly_smiling_face: (edited)


==> t


    const x y == y |- x == const y x

```
pbe(Renv, Penv, e1 r e2) = loop(0, Penv /\ v1=e1 /\ v2 = e2)
  where
    loop(i, Penv_i)
      | Penv_i |- v1 r v2    = True
      | Penv' \subseteq Penv = False
      | otherwise            = loop(i+1, Penv')
      where
        Penv'                = Penv_i \cup Unfold(Renv, Penv_i)
```



const x y == y

=. x == y
=.  
  => const x y = x
  => const  
  x == const


## TODO

- [] Draft Intro
- [] Overview
- [] Formal Sections 3-4 (lambdaR, lambdaS)
- [] Formal Sections 5-6 (nat-ded encoding)
- [] Eval

## Language

## Semantics

## Algorithm


IF

    G, f(x) = a |- u = v

THEN

    exists t in G, u, v s.t.

    G |- t = f(x)  


Suppose

  1. f(x)  in G then t := f(x) ...

  2. f(x) !in G

IF    G, a = b |- u = v but not (G |- u = v)
THEN  a, b occur as sub-terms of G, u, v

COUNTEREXAMPLE

  Let G := {t = x}, a := f(x), b:= c, u := f(t), v := c

     t = x
  ------------     
  f(t) == f(x)     f(x) = c
  -------------------------
    f(t) = c


ANISH Proof :BASE CASE MISSING: the case where

  Cf(p) . a = b  

  where p : u = v

  so we have Cf(p) : f(u) = f(v)

But use the INVARIANT

  Cf: u -> v only if u, v are "subterms" of G,u,v,a,b


INVARIANT COMPATIBLE with functor law?

  f(u) == f(v)   f(v) == f(r)


COROLLARY:

IF    G, f(x) = b | u = v
THEN  f(x) in G,u,v  OR  f(t) in G,u,v s.t. G |- t = x


## ALTERNATE FORMULATION

--------------------------------------------------------------------------------

### DEFINITION : Bounded Instantiation

Unfold(Renv, G) = [f(e) = b(e) | for all f(e) < G, E s.t. G |- c(e)]

BInst(Renv, G, n) creates a tree of depth n unfoldings for subterms of G.

BInst(Renv, G, 0)   = G

BInst(Renv, G, n+1) = Gn ++ Unfold(Renv, Gn)
  where
    Gn                = BInst(Renv, G, n)

FIXPOINT

  G_0 = G
  G_1 = G_0     ++ Unfold(Renv, G_0)
  G_2 = G_1     ++ Unfold(Renv, G_1)  
  G_i = G_{i-1} ++ Unfold(Renv, G_{i-1})


PBE (Renv, G, E, E')
  | G, v = E |- v = E' = True
  | G' \subseteq G     = False
  | otherwise          = PBE (REnv, G', E, E')
    where
      G'               = G ++ unfold(Renv, G /\ v=E)

Unfold(Renv, G) = [f(e) = b(e) | for all f(e) < G, E s.t. G |- c(e)]

PBE (REnv, G, E, E')    = loop i {G, v = E}
  where
    loop i G
      | G |- v = E'     = True
      | G' \subseteq G  = False
      | otherwise       = loop (i+1) G'
      where
        G'              = G ++ unfold(Renv, G)

THEOREM: [Termination]

  Exists n s.t. BInst(Renv, G, E, n) = BInst(REnv, G, E, n + 1).

COROLLARY: [PBE-Complete]



--------------------------------------------------------------------------------

### DEFINITION : Equational Proof

    Unfold(REnv, Penv, e1), v = e1 |- v = e2
    Renv, Penv |-_{n-1} e2 =. ... en *** QED :: { e2 == en }
    --------------------------------------------------------------------
    Renv, Penv |-_{n} e1 =. e2 =. e3 =. ... =. en *** QED : { e1 == en }



    -----------------------------
    _, _ |-_{0} e *** QED :: { e = e}

--------------------------------------------------------------------------------

### LEMMA: [Equational Proof]

  Renv, Penv |- e1 ... en *** QED : {e1 = en}

  iff forall i = 1 ... n-1 Unfold(Renv, Penv ei), v = ei  |- vi = e_{i+1}

                        --   BInst(Renv, Penv /\ vi = ei, 1) |- vi = e_{i+1}

Proof: By definition.

--------------------------------------------------------------------------------

### LEMMA: [ONE-Cong-Clos]

  IF    G, v = E |- v = E'  (where v not in G, e1, e2)
  THEN  for every f(t') < E'
          exists a f(t) < G, E
            s.t. G |- t = t'

PROOF [SKETCH(Y)!]
  Consider the CC graph, and argue that as v and E' are linked,
  each f(t') sub-term inside E' must either be in G, E so t = t'
  or if different, must be linked to to some existing f(t) subterm
  either directly (i.e. f(t')) or via congruence (i.e. G |- t = t')

  Formally by induction on structure of E'.

  Only way to "link" v to E' is to link E to E'
        split cases on
          var (done -- no f(...))
          same-fun-as-E
          diff-fun-as-E (use transitivity to link to existing same-fun in G)


--------------------------------------------------------------------------------
### LEMMA: [MANY-Cong-Clos]

  Let   Gn =  BInst(Renv, Penv /\ v = E, n)
  IF    Gn |- v = E'
  THEN  for every f(t') < E'
          exists f(t) < Gn, E
            s.t. Gn |- t = t'

Proof: Induction on n.
  case n = 0    :  
    should be just ONE-CC.

  case n = k+1  :
    G_k     = BInst(Renv, Penv, E, k)
    G_{k+1} = G_k ++ Unfold(Renv, G_k, E)

    Consider any E' s.t.

      G_{k+1}, v = E |- v = E'

    i.e.

      G_k, Unfold(Renv, G_k, E), v = E |- v = E'

    Let G = G_k, Unfold(Renv, G_k, E)

    Consider any f(t') < E' and apply ONE-CC to complete proof.  


--------------------------------------------------------------------------------

### THEOREM: [Bounded-Proofs]

  IF  exists Renv, Penv |-_{n} ... *** QED : { E = E'}

  THEN BInst(Renv, Penv, v = E, n) |- v = E'


PROOF: By induction on n.

 case n = 0.     duh.

 case n = k + 1. Suppose we have

    Renv, Penv |-_{k+1} E ... E'

 that is exists some Ek s.t.

    Renv, Penv |-_{k} E ... Ek =. E'                ... (1)

    Penv, Unfold(REnv, Penv, Ek), v = Ek |- v = E'  ... (2)

 that is by IH

    G_k, v = E |- Ek                                ... (1')

    where Gk = BInst(Renv, Penv, E, k)

 NEXT: Lets show that
       IF   f(t') = b(t') in Unfold(Renv, Penv, Ek)

            -- BECAUSE f(t') < Ek s.t. Penv |- c(t')  

       THEN BInst(Renv, Penv, E, k+1) |- f(t') = b(t')   ... (3)

            -- BECAUSE by lemma [MANY-CC] exists f(t) < Gk, E s.t. Gk |- t = t'
            -- BECAUSE Penv \subset Gk and Penv |- c(t') => G_k |- c(t)
            -- HENCE f(t) = b(t) in G_k+1
            -- HENCE G_k+1 |- t = t' /\ f(t) = b(t) and so by congruence closure
            -- HENCE G_k+1 |- f(t') = b(t')


As a consequence of (3) we have

  G_{k+1}, v = E |- Unfold(REnv, Penv /\ v = Ek)

  where G_{k+1} = G_k ++ unfold(Renv, G_k /\ v = E)

Thus, by (2) and modus ponens

  G_{k+1}, v = E |- v = E'

Completing the proof. END.

--------------------------------------------------------------------------------

### THEOREM: [PBE]

PBE(REnv, Penv, E, E')

IFF

exists n s.t. BInst(Renv, Penv, E, n), v = E |- v = E'

PROOF: PBE is the least-fixed-point of BInst.

--------------------------------------------------------------------------------

### COROLLARY: [COMPLETE Equational Reasoning]

PBE(Renv, Penv, E, E')

IFF

exists eq-proof Renv, Penv |-{n} ... *** QED : { e == e' }
