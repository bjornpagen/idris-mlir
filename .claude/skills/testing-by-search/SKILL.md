---
name: testing-by-search
description: Use when writing, reviewing, auditing or deleting a test in idris-mlir. The owner's testing guideline, verbatim: assertions that check only the contract (Winters), search against an oracle (matklad), and the representation, distribution and perception of that search. Read it in full before touching a test; every subagent that writes or audits tests reads it too, beside representation-first.
---

# Testing by search: the contract, the oracle, the search

The owner's binding lens for every test, read beside `representation-first`.
Bad tests are not spared: a test that checks more than the contract, checks
nothing, or cannot fail is deleted, and the owner prefers deleting a test
that does not work to maintaining it.

How it meets this repository's rules (AGENTS.md):
- **The oracle.** AGENTS.md forbids comparing against Idris's Chez backend
  or stock evaluator: Chez is no oracle. The oracles this repository may
  use are the ones the guideline names that are ours: a specification
  turned into a checker (the runtime's documented semantics, `Sem.idr`,
  the pass contracts of `idr-expect` and `--idr-contracts`), a second
  implementation we own (two forms of one closed expression, `Fuzz.idr`;
  clang's C in `bench/`, for outputs), and universal oracles (the
  verifier after every pass, the sanitizers, `universal: holds`).
- **Expected files are specifications.** A golden transcript is right only
  where the contract fully determines it (Winters: exact comparison is
  brittle only when it checks what the contract leaves open). A transcript
  that pins SSA names, clone numbers, op order or a pass's incidental
  output is brittle, and AGENTS.md already says so.

The guideline follows, verbatim.

---

## How to read this

Most testing that gets written today is *example-based*: a list of fixed inputs paired with their expected outputs. An AI asked to "write tests" will produce dozens of these. They are easy to write and often nearly worthless, because they only check the handful of cases someone thought to list, and they tend to break when nothing is actually wrong.

There is a different tradition. Instead of listing examples, you state a *property* that should hold for all inputs, and let a machine search for an input that breaks it. This document builds up that tradition from the ground, one idea at a time.

A good anchor to keep in mind throughout:

> Testing of this kind is the empirical cousin of a type system. A type checker verifies a property for every possible value, at compile time. A search-based test checks a property by generating many values and looking for a counterexample. Both are limited by the same thing: they can only check what you have taught them to express and to notice.

The reader is assumed to be comfortable with types, including dependent types, and to have seen a little Idris. The code samples are written in Idris 2 as sketches to make ideas concrete; they are illustrative and have not been compiled.

The journey begins and ends with two short articles. We read them once at the start, work through everything they imply, and read them again at the end, when they look different. A final section points at a deeper mathematical structure underneath the whole subject, as something to pursue next rather than a conclusion.

---

## 1. The two articles

### 1.1 Winters: a test should check only what the contract promises

Titus Winters, in *How I Learned To Stop Writing Brittle Tests* ([Google Testing Blog](https://testing.googleblog.com/2024/04/how-i-learned-to-stop-writing-brittle.html)), defines a **brittle test** as one that fails for an innocuous reason rather than a real defect. His example checks the contents of a hash set in one particular order:

```cpp
// Brittle: depends on hash iteration order, which is not part of the contract.
EXPECT_THAT(GetValuesFromConfig(Config()), ElementsAre(29, 17, 31));

// Resilient: checks set membership, which is the contract.
EXPECT_THAT(GetValuesFromConfig(Config()), UnorderedElementsAre(17, 29, 31));
```

The idea underneath is worth stating carefully. A test is an assertion, and an assertion is a property the output must satisfy. A brittle test asserts a property *stronger* than the contract: it distinguishes outputs that the contract treats as the same. The contract here is a set, but the test checks a list. The repair is to assert the weaker, correct property, the one that treats order as irrelevant.

Winters adds a second observation that matters more than it first appears: a brittle test is a signal that the available **testing vocabulary** is too weak. People write order-dependent assertions because the easy tool checks order. Give them `UnorderedElementsAre`, and the brittleness goes away. The failure is in the tools, not the author.

One detail foreshadows everything after. His test is named `DefaultConfigsArePrime`, but it checks three specific numbers. The property he actually cares about is "every value is prime." If you write *that*, the assertion no longer mentions any particular input, which means you could feed it a thousand generated inputs. Expressive assertions are the precondition for generated tests.

### 1.2 matklad: build an oracle, then search

Aleksey Kladov, in *Finding Bugs* ([matklad.github.io](https://matklad.github.io/2026/09/19/finding-bugs.html)), writes a small fuzzer. It generates a random regular expression and a random input string, runs both through two different regex implementations (`regex` and `regex_lite`), and checks that they agree. It rediscovers a known bug and finds a second one.

The central technique has a name: an **oracle**, a source of the known-correct answer. Here the oracle is a second implementation. If the two disagree, one is wrong. matklad's framing is that building an oracle is part of the job of designing a testable system, not an afterthought.

His generator contains several ideas we will return to, so it is worth listing them plainly:

- Generate **small** inputs. Bugs usually come from a few features interacting, not from huge inputs.
- Build the **alphabet** of characters from the existing unit tests.
- **Randomize the generator's own settings** on each run, so different runs explore different kinds of input.
- When a bug slips past the fuzzer, treat that as a **bug in the fuzzer** first: improve the fuzzer until it can find that bug and its relatives, and only then fix the code.

### 1.3 The two articles are two halves of one idea

Winters cares about the **assertion**: check exactly what the contract promises, no more. matklad cares about the **search**: generate many inputs and compare against an oracle.

They appear to conflict. Winters warns against comparing exact outputs; matklad compares exact outputs. The resolution is the key to the whole subject. Exact comparison is brittle only when it checks something the contract leaves unspecified. For regex matching, the contract fully determines the answer, so exact equality *is* the contract. The two articles are not in tension; they are the two things a good test needs. The rest of this document is what lies between and around them.

---

## 2. Why a search needs feedback

Start with a bug hidden behind a four-character check.

```c
void parse(const char *s, size_t n) {
    if (n >= 4 && s[0] == 'F')
      if (s[1] == 'U')
        if (s[2] == 'Z')
          if (s[3] == 'Z')
            crash();
}
```

A fuzzer that generates random bytes must guess all four characters at once. The probability per attempt is

$$\left(\frac{1}{256}\right)^{4} \approx \frac{1}{4.3 \times 10^{9}}.$$

For practical purposes it never happens. The fuzzer is blind: an input beginning with `F` got closer to the bug, but the fuzzer cannot tell, so it throws that input away along with the rest.

**Coverage-guided fuzzing** (as in AFL and libFuzzer) fixes exactly this. The compiler inserts a counter at every branch, so after each run the fuzzer can see which branches were taken. The loop becomes:

1. Keep a collection of interesting inputs, the **corpus**.
2. Pick one and **mutate** it slightly (flip a byte, insert a few bytes).
3. **Run** it and record which branches fired.
4. If it reached a branch no earlier input reached, **add it to the corpus**. Otherwise discard it.

On `parse`, this changes everything. An input starting with `F` passes the first check, which is a new branch, so it is saved. Mutating *that* input only needs to get the second byte right, roughly a 1-in-256 event, and it too is saved. And so on. The cost falls from guessing four bytes jointly to guessing them one at a time:

$$256^{4} \;\longrightarrow\; \text{about } 4 \times 256.$$

Feedback has turned an exponential search into a roughly linear one. That single change is why coverage-guided fuzzing works at all.

It is worth noticing that this loop is a genetic algorithm. The corpus is a population, mutation is mutation, keeping-what-is-new is selection, and gluing two inputs together (which real fuzzers do) is crossover. One twist distinguishes it from ordinary optimization: the thing being rewarded is **novelty**, not a score. The fuzzer is exploring the program, not climbing toward a single target.

---

## 3. When feedback goes blind: cliffs

The feedback trick has a precise failure mode. Rewrite the same bug as a single comparison:

```c
if (*(uint32_t *)s == 0x5A5A5546) crash();   // the four bytes "FUZZ" read as one integer
```

Now there is only one branch. Either the whole value matches or it does not. An input of `FUZA` lights up no more of the program than `AAAA` does. There is no partial credit, so the staircase has collapsed back into a cliff, and we are back to one in four billion.

Real programs are full of these: magic numbers in file headers, string comparisons against keywords, version checks. Three standard techniques restore a signal, and each one works by giving the fuzzer back some visibility.

**Dictionaries.** The constant `0x5A5A5546` sits in the compiled program. Extract constants and strings from the binary and let the fuzzer paste them into inputs. Now it only has to discover *where* the value goes, not *what* it is.

**Comparison splitting.** A compiler pass rewrites the single comparison into a chain of one-byte comparisons:

```c
if ((x & 0xFF) == 0x46)
  if (((x >> 8) & 0xFF) == 0x55)
    if (((x >> 16) & 0xFF) == 0x5A)
      if ((x >> 24) == 0x5A)
        crash();
```

The behavior is unchanged, but there are four branches again, so the staircase returns.

**Comparison logging.** The instrumentation records both operands of every comparison at runtime. If the fuzzer sees that its input contained `AAAA` and that value was compared against `FUZZ`, it guesses that those input bytes flow into the comparison and tries the substitution directly. This works because input bytes often reach a comparison unchanged.

Now make the cliff genuinely hard:

```c
if (crc32(s, n) == 0x5A5A5546) crash();
```

All three tricks fail. A dictionary value pasted into the input does not help, because the comparison is against the *hash* of the input. Splitting the final comparison gives partial credit on the hash's output, but the credit is fake: a hash is designed so that changing one input bit changes about half the output bits, so progress never sticks. And the logged operand (the hash value) appears nowhere in the input, so there is nothing to substitute.

The honest response is to stop asking the fuzzer to solve this. Either remove the check in the fuzzing build:

```c
#ifndef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
if (crc32(s, n) != expected) return ERROR;
#endif
```

or generate inputs with a program that computes the correct checksum itself, so every input is valid by construction.

> The general rule: feedback-driven search works only when a small change to the input produces a small, visible change in progress. When the path from input to the check scrambles the input, feedback cannot help, and you must supply the structure some other way.

That last phrase, *supply the structure*, is the subject of the next section.

---

## 4. Representation: what the search can express

### 4.1 Generating from a type is a search of its own

If we want inputs that are valid by construction, the natural idea for someone with type-driven instincts is to derive them from a type. This works, but it comes with a sharp catch: producing a value of a given type is itself a search, and that search ranges from trivial to impossible. A short ladder makes the range concrete.

```idris
-- Easy: enumerate 0, 1, 2, ... and you reach 12 almost at once.
(n : Nat ** n * n = 144)

-- Plentiful, but filtering is hopeless. A random list of length n is sorted
-- with probability about 1/n!. Generating element by element, each one no
-- smaller than the last, succeeds every time.
data Sorted : List Nat -> Type where
  SNil  : Sorted []
  SOne  : Sorted [x]
  SCons : LTE x y -> Sorted (y :: ys) -> Sorted (x :: y :: ys)

-- Empty: no such n exists, so a naive search never terminates.
(n : Nat ** n + 1 = 0)

-- Inhabited, but finding a witness is as hard as breaking SHA-256.
(xs : List Bits8 ** sha256 xs = target)

-- Nobody knows: whether this search halts is the halting problem.
(k : Nat ** HaltsWithin prog k)
```

The lesson from the `Sorted` rung is the one that matters for testing: the *same* type is trivial or impossible depending on whether you **construct** values directly or **generate and filter**. Fuzzing lives on this rung. Valid inputs are abundant, but they are a vanishing fraction of all byte strings, so a generator must build them rather than stumble onto them. (The SHA-256 rung, by the way, is exactly the checksum cliff from the previous section, seen from the type side.)

### 4.2 A worked example: a small network fuzzer

Ned Williamson's well-known *SockPuppet* work took Apple's kernel network stack, ran it in ordinary userspace so it was fast and debuggable, and fuzzed it not with random packets but with random *programs*: sequences of socket operations such as open, set an option, connect, disconnect, close. This found a serious use-after-free bug.

He described those programs with a protobuf grammar. A grammar like that is context-free, which means it can express the *shape* of a program but not a constraint like "this command must refer to a socket that is actually open." So most generated programs refer to sockets that do not exist, and the usual fix is a small hack in the test harness that quietly reinterprets a bad socket number into a valid one.

For a type-driven reader, that hack is a smell: it means a real constraint is missing from the representation. We can put it where it belongs, by indexing each command with the number of open sockets before and after it runs.

```idris
data Opt = NoDelay | Linger | MinMTU

-- Cmd n m : a command legal when n sockets are open, leaving m open afterward.
data Cmd : (before : Nat) -> (after : Nat) -> Type where
  Socket     : Cmd n (S n)                 -- opens one more
  SetOpt     : Fin n -> Opt -> Cmd n n     -- must name one of the n open sockets
  Connect    : Fin n -> Cmd n n
  Disconnect : Fin n -> Cmd n n            -- disconnected, but still open
  Close      : Fin (S n) -> Cmd (S n) n    -- needs at least one; removes it

-- A program is a chain where each command's "after" is the next one's "before".
data Prog : (open : Nat) -> Type where
  Done : Prog n
  (::) : Cmd n m -> Prog m -> Prog n
```

The type `Fin n` is "a number less than n," so `SetOpt` can only name a socket that exists. When no sockets are open, `Fin 0` has no values at all, so `SetOpt` is not *rejected*, it is simply impossible to write. The one command that can start a program is `Socket`. The context-sensitive constraint the grammar could not express is now carried by the type.

### 4.3 A subtle trap: do not type away the bug

Look again at `Disconnect`. It leaves the socket open (`Cmd n n`) rather than removing it. Why?

Because that is precisely the shape the SockPuppet bug needed. After a disconnect, the socket was still a valid, open file descriptor, but the kernel had already freed some internal state belonging to it. A later `SetOpt` on that still-open socket touched the freed memory. The sequence "disconnect, then set an option" was perfectly legal at the API level. The bug was that the kernel mishandled a legal history.

This yields a design rule that runs against the type-driven reflex:

> Encode the invariants of your **test harness**, not the expected behavior of the **system under test**. The `Fin n` index enforces a harness invariant (never name a socket we did not open). If instead you encoded the kernel's intended contract (say, "only set options on connected sockets"), you would make the buggy sequence impossible to generate, and the fuzzer could never find the bug. For code you trust, precise types are a virtue. For input handed to code you are trying to break, over-precise types are the same as not testing.

### 4.4 Represent the invalid cases too, by name

The `Fin n` index guarantees we never hand the kernel a nonexistent socket. But that also means the kernel's error-handling code, double-close handling, and reuse logic never run during fuzzing. Those are exactly where bugs hide. We get them back not with a hack, but by making the invalid cases first-class parts of the representation.

```idris
data Desc : (open : Nat) -> (closed : Nat) -> Type where
  Live  : Fin o -> Desc o c     -- a socket we currently hold open
  Stale : Fin c -> Desc o c     -- one we closed earlier (tests reuse / use-after-close)
  Wild  : Int   -> Desc o c     -- any raw integer: -1, 0, 99999, ...
```

The difference between this and the modulo hack is *who is deciding*. The hack silently turned nonsense into something valid, so you could neither ask for a bad descriptor on purpose nor tell from a crash that one was involved. With `Desc`, asking for a bad descriptor is a deliberate, named, countable choice: a crashing program literally contains `SetOpt (Stale 0) Linger`, which you can read straight off the failing input.

> The principle, which recurs throughout: **represent intentions, not bytes.** Every kind of input you want to exercise, including the invalid and malicious ones, should be something you can name, count, and later weight.

---

## 5. Distribution: what the search tries often

A type says which inputs are *possible*. It says nothing about which are *likely*. That second question belongs entirely to the generator, and it is easy to get wrong without noticing.

Consider decoding a raw number into one of several choices by a simple "keep subtracting until it fits" scheme. Large random numbers all land on the last option. A generator built that way has a strong, invisible bias toward whatever happens to be listed last, chosen by nobody. This is the usual way fuzzers end up with bad distributions: by accident, as a side effect of a convenient encoding.

The fix is to make the distribution an explicit value, so you can see it and change it.

```idris
record Weights where
  constructor MkWeights
  socket, setOpt, connect, disconnect, close : Nat
  live, stale, wild : Nat
```

matklad's "randomize the generator's own settings each run" now has a clean form, and has a name: **swarm testing**. Each run first draws a random `Weights`, then generates a program using it. One run might be almost all opens and closes; another might be ninety percent stale descriptors. Each run explores a different lopsided corner of the space, and corners are where bugs cluster. (Roboticists call the same move, randomizing the simulator's own parameters, *domain randomization*.)

Swarm testing has one classic pitfall worth seeing, because it is instructive. Suppose a run randomly sets the weight of `Socket` to zero. At the start, with no sockets open, `Socket` is the *only* legal command, yet its weight says "never." A naive weighted chooser would be asked to pick from a total weight of zero, which is undefined: there is no valid draw. matklad guards against exactly this by always giving one feature (literal characters) a nonzero weight.

For a type-driven reader there are two satisfying ways to handle it. First, a generator that pattern-matches on the state can simply make a forced move without consulting the weights at all, which is what the empty-socket case does. Second, you can give the random draw itself a type that cannot be satisfied when every weight is zero:

```idris
total' : Vect n Nat -> Nat
total' []        = 0
total' (w :: ws) = w + total' ws

-- To draw, the caller must produce a value of `Fin (total' ws)`.
-- When every weight is zero, `total' ws = 0`, and `Fin 0` is empty:
-- there is simply nothing to pass in, so the degenerate case cannot be ignored.
weighted : (ws : Vect n Nat) -> Fin (total' ws) -> Fin n
```

The type does not decide *what* should happen when all weights are zero; that is a modeling choice (fall back to uniform, add one to every weight, or reject the configuration). What the type does is force you to make that choice explicitly rather than crash.

---

## 6. Perception: what the search counts as progress

### 6.1 The limits of branch coverage

Go back to the feedback loop. It keeps an input when the input reaches a *new branch*. But "new branch" is only one possible definition of progress, and it has a clear failure mode. Imagine a small maze game whose input is a string of moves:

```c
void step(char c) {
    switch (c) { case 'U': y--; break; case 'D': y++; break;
                 case 'L': x--; break; case 'R': x++; break; }
    if (maze[y][x] == '#') die();
    if (maze[y][x] == 'G') win();
}
```

After the fuzzer has tried each of the four moves and bumped into a wall once, every further input hits the same branches. Walking five squares deeper into the maze looks identical, to the branch counters, to standing still. The real progress lives in the values of `x` and `y`, which branch coverage does not see. So the fuzzer reverts to blind random search, and a maze that needs fifty correct moves is hopeless.

The network fuzzer has the same shape. A `SetOpt` on a fresh socket and a `SetOpt` on a disconnected one run largely the same code, so they hit the same branches, even though only the second is near the bug. The important difference lives in the kernel's internal state, which branch coverage cannot observe.

### 6.2 Coverage is a choice of features

The deeper framing: after each run, the fuzzer reduces the run to a set of **features**, and keeps the input if it produced a feature not seen before. Branches are one choice of feature, popular only because the compiler can insert them automatically. You are free to choose better ones. A tool like IJON lets you annotate the program to treat, say, the maze position as a feature, after which every newly reached square is progress and the maze becomes a staircase again.

Choosing features is a craft, and granularity is the whole of it:

| feature definition | outcome |
| --- | --- |
| just the command kind | too coarse; saturates after a handful of inputs, then blind |
| `(command kind, socket state)` | about right; a small set of meaningful situations |
| the entire command sequence | too fine; every input looks new, so the corpus floods and the search is random again |

There is a pleasant payoff here. The socket state machine we deliberately refused to put into the command *types* in section 4.3 belongs here instead, as a feature.

> Types **constrain**, and features **steer**. A constraint removes programs from the search entirely, so it is only safe for the harness's own invariants. A feature removes nothing; it only rewards reaching a new situation, so it is the right home for your model of how the system *ought* to behave. The same socket state machine would have hidden the bug as a type, but guides the search toward it as a feature.

### 6.3 The same shape appears in reinforcement learning

This is worth pausing on, because it shows the ideas are not specific to fuzzing.

- A **sparse reward**, where the payoff comes only at the very end, is the maze problem. Reinforcement-learning agents struggled for years with the game *Montezuma's Revenge* for the same reason the fuzzer struggles with the maze: no intermediate signal to climb.
- **Count-based exploration**, giving an agent a bonus for reaching rarely visited states, is the fuzzer's "keep it if it is new." Choosing which states count is choosing a reward.
- The **noisy-TV problem**, in which a curiosity-driven agent gets stuck watching random static because static always looks novel, is the too-fine feature. It is a form of reward hacking: the optimizer satisfies the measure instead of the goal.
- **Go-Explore**, the method that cracked *Montezuma's Revenge*, keeps an archive of reached states, returns to one, and explores onward from it. That is the fuzzer's corpus loop, almost line for line, down to the need to tune how finely states are distinguished.

Two honest differences keep the analogy from being overstated. Reinforcement learning usually trains a reusable *policy* that generalizes to new situations, whereas a fuzzer keeps only an archive of concrete inputs. And a fuzzer may replay any saved input exactly, a luxury standard RL does not assume. Fuzzing is closer to the exploration half of RL with the learning half removed.

---

## 7. The oracle, revisited

A search can only find a bug if something recognizes the bug when it appears. That something is the oracle, and the family is small and worth naming:

- **A second implementation.** matklad's `regex` versus `regex_lite`. Any disagreement is a bug in one of them.
- **A specification turned into a checker.** Section 9 builds one of these from documentation.
- **A universal oracle.** A tool like AddressSanitizer turns a silent memory error into an immediate crash, which is how the SockPuppet use-after-free was caught.

This connects back to types. In a memory-safe language such as Idris, the crash-style bugs mostly disappear, and what remains are logic errors that quietly produce wrong answers. There is no sanitizer for "wrong answer." So in a typed setting, the quality of your testing is almost entirely the quality of your oracle, which is matklad's point exactly.

One more thread ties several of these examples together. The most effective testing setups are usually *co-designed* with the system: SockPuppet running the kernel in userspace to make it fast and replayable, the compile-time switch that disables a checksum, a database exposing internal state so an external checker can inspect it. Making a system testable is a design activity, not something bolted on later.

---

## 8. When is the search finished?

Fuzzing does not make steady progress. It plateaus, then suddenly bursts: in the maze, the fuzzer wanders fruitlessly until one input grabs the key, after which every square "with the key" is new territory. So "nothing new for hours" is weak evidence, and we would like something sharper.

There is a classical tool, from an unexpected field. An ecologist who has trapped many animals asks: what is the chance the next one is a species never seen before? Map animals to inputs and species to features, and the question becomes "what is the chance the next input does something new?" The estimate, due to Alan Turing and I. J. Good, is strikingly simple:

$$P(\text{next input is new}) \;\approx\; \frac{f_1}{n},$$

where $n$ is the number of inputs run and $f_1$ is the number of features seen *exactly once*. The intuition is a leave-one-out experiment: pretend each input you already ran had been the last one. It would have counted as "new" precisely when its feature appears nowhere else, that is, when it is one of the $f_1$ singletons.

This gives a real stopping rule: stop when the estimated chance of a new discovery drops below what more computing time is worth, and report the remaining estimate as a residual risk instead of saying "it ran overnight."

But the estimate must be read with great care, and the cautionary tale is the Thanksgiving turkey. The turkey, fed every morning for a thousand days, grows more confident each day that mornings are safe, right up to the morning it is not. Good and Turing's estimate answers a narrow question honestly: *given this fixed process, and these categories, how much probability sits in categories I have not yet seen?* The turkey's mistake is treating that narrow answer as an answer to "am I safe?" Three gaps separate the two, and each is a lesson we have already met:

| gap | the turkey | the fuzzer |
| --- | --- | --- |
| the process can change | the farmer has a plan | grabbing the key opens a new region |
| the categories can be too coarse | "fed" does not distinguish the day of the axe | the bug hides inside a feature already seen many times |
| some things are absent, not rare | "axe" never appears in the daily data | some inputs the representation cannot express at all |

The middle row is how a bug survives a saturated feature map. The network bug is not a *new* feature; it lives inside `(SetOpt, Disconnected)`, which the fuzzer has seen hundreds of times. The estimate rightly says "no new feature is coming soon," and that is simply a different statement from "no bug remains." It follows that these numbers measure the pair **(generator, feature definition)**, never the program itself: refine the features, and the same inputs yield a different estimate.

A natural objection from a computer scientist: why does any probability apply to a deterministic program? Because the randomness is *ours*. The generator defines a genuine probability distribution over inputs, so statements about that distribution are rigorous. This is the same move that makes randomized algorithms respectable; the Miller–Rabin primality test answers the fully deterministic question "is $n$ prime?" with a provable error bound, because the randomness is in the test, not the number.

There is, however, a crucial difference between Miller–Rabin and fuzzing. Miller–Rabin rests on a theorem: every composite number is exposed by at least three-quarters of the possible tests, so the thing you are hunting is guaranteed to be *common* under random sampling. Fuzzing has no such guarantee. A bug can occupy an arbitrarily tiny slice of the generator's distribution, or none of it. This is the honest boundary of the whole approach, and it separates two traditions:

- **Worst-case** reasoning establishes a property for *every* input: types, proofs, complexity bounds.
- **Distributional** reasoning establishes a property for inputs *drawn from a distribution*: randomized algorithms, hashing, fuzzing.

In place of a worst-case theorem, fuzzing leans on a heuristic, the **small-scope hypothesis**: most bugs have a small counterexample. It is not a law; it is an observation about the kinds of mistakes people make (the empty list, the one-element list, two things that happen to be equal). You can lean on it more deliberately in two ways. You can *exhaust* the small cases: checking every input up to some small size turns "no bug at this size" into a genuine theorem, a proof inside a box with a heuristic about what is outside the box. And you can *move a bug into the box*: a ring buffer that only fails when its index wraps around at capacity 4096 will never wrap in a twenty-operation test, so you shrink the capacity for testing until the wrap happens at a small size. (Shrinking a constant changes the program, so the disciplined version is to randomize the constant across runs rather than fix it small.)

---

## 9. Specifications as oracles, and model-based testing

So far the oracle has been a second implementation or a sanitizer. There is another source, and it closes the loop back to Winters: the **specification** itself, turned into something a machine can explore.

A recent example comes from the Turso project, a rewrite of SQLite. The ideas generalize well beyond it.

### 9.1 A state machine you can search: Quint

Quint is a specification language based on the temporal logic of actions (the logic behind TLA+). You describe a system as a state machine: its state, the actions that change it, and the properties that must hold. This should feel familiar; it is the `Cmd`/`Prog` model from section 4 without a real system underneath.

```quint
module sockets {
  type SockState = Fresh | Connected | Disconnected
  var socks: int -> SockState
  var next_fd: int

  action open = all {
    socks'   = socks.put(next_fd, Fresh),
    next_fd' = next_fd + 1,
  }

  action disconnect = {
    nondet fd = socks.keys().oneOf()      // some existing socket, unspecified which
    all { socks' = socks.set(fd, Disconnected), next_fd' = next_fd }
  }

  action step = any { open, disconnect /* , ... */ }
}
```

The important word is `nondet`, a choice point, exactly like the "pick one option" step in our generator. And here is the leverage: the *same* specification can be driven in different ways. Explored at random, it behaves like a property-based test. Explored exhaustively up to some number of steps, it behaves like the "check all small inputs" idea from the previous section. Reasoned about as an inductive invariant, it becomes a proof. One description of the system, several strengths of checking, chosen by how the choices are resolved.

### 9.2 How this finds real bugs

A contributor to Turso used Quint to model SQLite's documented C interface, one contract at a time, and in doing so found more than ten bugs in SQLite itself, which is among the most heavily tested software in existence. The pipeline, reconstructed from the write-up:

1. **Read** one documented contract. For example, the documentation says that a certain "load a database image" call must report "busy" if the database is currently being read. A human chooses which contract to look at.
2. **Model** just enough state to express that contract.
3. **Search** the model for a short scenario that reaches the interesting situation. A common trick is to assert a deliberately false property ("this situation never arises") so the checker hands back a counterexample: the shortest sequence of steps that reaches it. Here, that was: open, create a table, serialize, start a read, then make the call during the read.
4. **Translate** each abstract step into real API calls, filling in the details the model ignored (which table, which data) with simple defaults.
5. **Check** that the real system actually entered each state the model claimed (the real database offers a way to ask whether a read is in progress). Otherwise the test can silently check nothing.
6. **Compare** the real result against what the model expected. The model expected "busy." The real database crashed.

Quint never ran SQLite. It produced the scenario and the expected answer; running the scenario against the real system revealed the bug. When the results disagree without a crash, there are three suspects, not one: the model, the code, or the documentation (one of their findings turned out to be an error in the documentation).

### 9.3 Searching code-space versus spec-space

This explains something a pure fuzzer cannot do. A coverage-guided fuzzer steers toward code that *exists*; it follows branches it can count. But a bug can be a check that is *missing* entirely, in which case there is no branch to reward and no coverage signal to follow. You cannot steer toward code that is not there. A specification can, because the documentation names the situation the code was supposed to handle, and the model aims straight at it.

|  | coverage-guided fuzzing | model-based testing |
| --- | --- | --- |
| explores | the code's behavior | the specification's situations |
| "interesting" decided by | an automatic feature function | a property a human selected |
| typical output | many inputs, filtered by novelty | one short scenario per target |
| characteristic blind spot | missing code, since there is no branch for it | details the model leaves out |

A natural question for a type-driven reader: why not write the model in Idris and prove the properties? For sequential systems you largely can, and you gain precision and real proofs. What a model checker like Quint's backend adds is *automation of the search*: it will look for a proof or a counterexample on its own, within a restricted logic where that search is feasible, and when it fails it hands you a concrete trace rather than leaving you stuck on an unproven goal. Idris checks the proofs you write; a model checker goes looking for them. For a sequential, deterministic artifact such as a compiler, an Idris generator with a reference oracle is close to ideal; a model checker earns its place when concurrency and timing enter, which is the subject of section 11.

---

## 10. Claims attached to the code: contracts

A second recent tool, Aristo, takes the opposite arrangement. Instead of a separate model, it attaches a claim in English directly above a function:

```rust
#[aristo::assume("lo <= hi")]
#[aristo::intent("returns a value within [lo, hi] for any input",
                 verify = "neural", id = "clamp_in_range")]
pub fn clamp(value: i64, lo: i64, hi: i64) -> i64 { ... }
```

To a type-driven reader this is a dependent type written in prose. The `assume` is a precondition, the `intent` is a postcondition, and the pair is the familiar Hoare triple: given the precondition, the function guarantees the postcondition. In Idris it would be a type:

```idris
clamp : (v, lo, hi : Int) -> {auto 0 ok : LTE lo hi}
     -> (r : Int ** (LTE lo r, LTE r hi))
```

Two features are worth noting. First, each claim carries a chosen *rigor*: it can be mere documentation, checked by an AI reviewer, checked against a test suite, or, at the strongest setting, checked by property-based testing up to a formal proof. This is a dial where a type system offers only one setting. Second, the tool watches for *drift*: it records a fingerprint of the function alongside the claim and flags the claim as unverified when the code changes. That drift-detection is something a type system gives for free, since every compile rechecks every type.

For a claim about a single function, this is a weaker, less precise version of a dependent type, and that is a fair criticism. Its real value shows for *protocol* claims that span many functions and many executions, such as "data must be flushed to disk before a transaction is reported as durable." No single function's signature can express that. At its strongest setting the tool builds a model of the whole protocol and searches its interleavings, which is how it caught a durability bug in Turso that enormous amounts of randomized testing had missed. That bug had slipped through for two reasons we can now name precisely: the randomized tests never generated the exact fault in the exact mode where it mattered (it was *absent*, not merely rare), and in most runs the flush happened anyway for unrelated reasons (the bug was *masked inside a situation the tests had seen many times*). A search over *all* interleavings is not fooled by either.

Where you control the design, the type-driven move is still the stronger one: encode the rule as a typestate so the illegal sequence does not compile.

```idris
data Durability = Dirty | Synced
export data Commit : Durability -> Type

fsync         : (1 _ : Commit Dirty)  -> IO (Commit Synced)
reportDurable : (1 _ : Commit Synced) -> IO ()
```

Reporting a dirty commit simply would not type-check, and the linear use (`1 _`) prevents keeping a stale `Dirty` handle to report through some other path. The reason tools like Aristo exist at all is that most real systems were not designed this way, and retrofitting a contract onto an existing function is far cheaper than restructuring it around a typestate. The rigorous members of this family, for readers who want them, are refinement-type and contract systems such as Liquid Haskell, Dafny, and Verus.

---

## 11. Timing as a hidden input: deterministic simulation

Every bug so far has been reproducible: run the same input, get the same result. A large class of bugs is not. Two clients each read a counter and write back one more than they read:

```
A reads 0  →  B reads 0  →  A writes 1  →  B writes 1      (an update is silently lost)
```

The defect is in neither client alone; it is in the *interleaving*. And the interleaving depends on thread scheduling, network delays, disk timing, and crashes, none of which the test controls. So the bug appears once in a million runs and vanishes when you try to reproduce it.

The reframing is the one a type-driven reader will reach for immediately: these are **hidden inputs**. The program's behavior depends on the commands you supplied *and* on a stream of environmental decisions you never wrote down. A fuzzer controlling only the commands is controlling half the input.

So bind the other half. Deterministic simulation testing replaces every source of nondeterminism, the scheduler, the network, the disk, the clock, with a simulated version whose every decision comes from a single seed:

```idris
data EnvChoice = RunTask TaskId
               | Deliver MsgId | Drop MsgId | Delay MsgId Nat
               | Crash NodeId  | FsyncFails | AdvanceClock Nat

simulate : (seed : Bits64) -> Workload -> Trace    -- same seed, same trace, exactly
```

This is the choice-stream generator from section 4, pointed at the environment. The lost-update race is now just one particular sequence of scheduling choices, and the payoffs are large. Every failure is a seed you can replay deterministically, so the heisenbug problem disappears. The simulated clock jumps forward instead of waiting, so hours of simulated activity run in seconds. And the environment can be made adversarial on purpose: drop messages, crash nodes, make a flush fail, each a named `EnvChoice` with a weight, randomized per run exactly as swarm testing randomizes input weights. This is how systems like FoundationDB, TigerBeetle, and Turso are tested, and it has to be designed in from the start, since every interaction with the outside world must pass through an interface the simulator can replace.

Binding the variable is the easy part; the depth of the field is in what follows. The number of interleavings is astronomical, so naive random scheduling finds deep bugs poorly, and there are smarter strategies (one explores only one schedule per class of equivalent interleavings; another assigns random priorities and comes with a provable lower bound on finding a shallow bug, a genuine witness theorem of the Miller–Rabin kind). The simulated disk encodes assumptions about what real disks can do, and any assumption kinder than reality hides bugs. And judging whether a concurrent execution was even *correct* is its own hard problem. Those are the natural starting points for a second part.

---

## 12. Reading the two articles again

With the machinery in hand, the opening articles look different.

Winters' brittle test is now clearly a test whose assertion is *stronger than the contract*, distinguishing outputs the contract treats as equal. His deeper point, that brittleness signals a gap in the testing vocabulary, turned out to recur everywhere: the modulo hack in the socket harness signaled a gap in the representation; matklad's rule about fixing the fuzzer first treats an escaped bug as a gap in the search. A testing failure is information about the testing infrastructure, not only about the code.

matklad's small fuzzer, reread, is a catalog of this document: small inputs (the small-scope hypothesis), an alphabet drawn from the tests (a dictionary), randomized per-run settings (swarm testing), a nonzero floor on one weight (the zero-weight trap), and an oracle in the form of a second implementation. And his closing reassurance, that none of this requires exotic machinery, is a fair counterweight to the type-heavy treatment here: we built the sharpened, type-indexed version, but every essential idea survives in a plain generator with a random number source. Types make the representation precise and let you prove a few key invariants outright; they are not what makes the search work.

The apparent conflict between the two articles was the seed of the whole subject, and it resolves cleanly. Exact comparison is brittle only when it checks something the contract leaves open. **Winters governs the oracle; matklad governs the search; and almost everything else is representation (what you can express), perception (what you can notice), and distribution (what you try often).**

---

## 13. A thread to pull next: the shape underneath

One pattern kept recurring without being named, and it is a good place to point rather than to conclude.

Consider the set of states a system can reach. It is the smallest set that contains the start states and is closed under taking one more step, a *least fixed point* of the "add everything one step away" operation. The two kinds of assurance in this document sit on opposite sides of it. A fuzzer only ever visits reachable states, so it approaches that set **from below**: it can exhibit a bug, but never certify its absence. A proof, by contrast, looks for a property that holds at the start and is preserved by every step, which brackets the reachable set **from above**: if that property excludes all bad states, none of the reachable ones are bad. An *inductive invariant* is exactly such a property, and the recurring difficulty, "the fuzzer never saw it fail, but is the invariant actually preserved by every transition?", is the difference between approaching from below and proving from above.

Other pieces rhyme with this. The feature functions of section 6 are *abstractions* of the state space, and whether an abstraction is sound, whether checking the abstract version really covers all the concrete cases it stands for, is a precise relationship between two ordered structures. The granularity choice, from too coarse to too fine, is a position in a lattice of partitions. Even the behavior of concurrent systems, in section 11, is naturally described with partial orders on events.

These are not loose analogies. There is a well-developed mathematics, lattice and order theory and its use in abstract interpretation, that gives the *geometry* of this entire subject: reachable states as a fixed point, testing as approaching it from below, proof as bracketing it from above, abstractions as structure-preserving maps between ordered sets. What that mathematics deliberately does *not* give you is the *strategy*, the question of which states to explore first with limited time, which is the whole craft of fuzzing and the home of everything probabilistic here. That division, between the geometry of what is reachable and the strategy of how to search it, is where a second part would begin.
