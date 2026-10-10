# Snapshot: Futhark documentation excerpts

- **Upstream:** `diku-dk/futhark` on GitHub, `docs/` (rendered at https://futhark.readthedocs.io/).
- **Revision:** `304c56ff73c48f1842ed3971fe19805a3a85c766` (the same pin as `code/futhark/`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/diku-dk/futhark/304c56ff73c48f1842ed3971fe19805a3a85c766/<path>`.
- **Paths:** relative to the repository root (so `docs/language-reference.rst`).
- **Files:** 5 (plus this file).
- **Licence:** ISC (`LICENSE`, copied from the repository root; the docs carry no separate licence).
- **Topic:** Array languages and typed array programming.

**What is here, and why.**

- `docs/language-reference.rst`: the normative description of size types (Size Types, Unknown
  sizes, Size coercion, Causality restriction, size-lifted type parameters), in-place updates,
  alias analysis and the consumption rules for higher-order functions.
- `docs/performance.rst`: the user-facing cost model (fusion, flattening, what is parallel).
- `docs/glossary.rst`: definitions of the compiler's vocabulary (consumption, aliases, sizes, SOAC).
- `docs/versus-other-languages.rst`: Futhark's own comparison with other languages.
- `LICENSE`.

**How to fetch more:** as in `code/futhark/SNAPSHOT.md`, with `p=docs/<file>.rst`.

## File manifest

Every stored file except this one: 5 files, 110,359 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
d029ffa271dcee84cc883fb9e83744f703401e2abb097b8ef084fff0674d935b        767  LICENSE
48d71ae9f77b3cabb94cef65549430982b763feb287eac02db2624eb982a4613      15975  docs/glossary.rst
7a619ddd444953803745da0909cbf37ef4b8a6bed0279e82afabf17601108213      68505  docs/language-reference.rst
af7c140b7467d0a90bfa616832ab73394211bd05fa7c347376b68868418946b4      16867  docs/performance.rst
ace07951f52268ec7c768cf2c6fa49cba608d177e250130308da643ebcd576d5       8245  docs/versus-other-languages.rst
```
