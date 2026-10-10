# Snapshot: Apache Parquet documentation site (file-format pages)

- **Upstream:** `apache/parquet-site` on GitHub (rendered at https://parquet.apache.org/docs/).
- **Revision:** `main` at `14a991210815076568d0f334c36cf1db71d13c70` (2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/apache/parquet-site/14a991210815076568d0f334c36cf1db71d13c70/<path>`
  (spaces in paths URL-encoded as `%20`).
- **Paths:** relative to the repository root (so `content/en/docs/File Format/nestedencoding.md`;
  the directory names contain spaces, as upstream's do).
- **Files:** 10 (plus this file).
- **Licence:** Apache-2.0 (`LICENSE`).
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.** The rendered site's short pages on the concepts the task names: the
"Nested Encoding" page (`File Format/nestedencoding.md`) and "Nulls" (`File Format/nulls.md`),
the file-format, metadata, data-page and column-chunk pages, `Concepts/_index.md` (glossary),
`Overview/motivation.md`, and the blog-post list. Most of the format pages on the site are
stubs that include the `parquet-format` repository's Markdown (`docs/parquet-format/`), which is
the authoritative text; these pages are kept because the nested-encoding and nulls pages are
the site's canonical statements and are short.

## File manifest

Every stored file except this one: 10 files, 19,672 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 "<path>"` from this folder.

```
SHA-256                                                           bytes  path
796b4eb8cc161e13bb00f7945c1229b5170a4bf2ab33d63b5261bf4486e3e33c      11410  LICENSE
3c4ccf0a9bd7118286c219966f4a757e79b5376a81a9184656d3a86a70373b91       1284  content/en/docs/Concepts/_index.md
fc8b45e76c99ba9e9b179cbfcf8c04571eb2bf999111b2833166111cb028b89a       1049  content/en/docs/File Format/Data Pages/_index.md
ce311e70e282c6167115bbf96dea47348e266dbb912ff97831c649ad0fd0431a        931  content/en/docs/File Format/Data Pages/columnchunks.md
20c0793bbf98582a924aaf195fcbd2b575b315a407b0ebe608a02a76ae7a3487       1336  content/en/docs/File Format/_index.md
e5bd5ae598c752b9271badf07b7599b71a17bb742e308db36821c54e2822615c        843  content/en/docs/File Format/metadata.md
1224fc51e6f24f8d48dc6cf591f4eefb781485c389c6e2fcbfb7facd90c63f59        691  content/en/docs/File Format/nestedencoding.md
2e8c8db78fd60a2ef0b3e41fa6ae24fc5535601d76fe6f610ac3eb97f4d43487        334  content/en/docs/File Format/nulls.md
a09a8e1b4652d55718f8f0d50a1ede7bb7f8b1742a3358a759cee6597e162735        537  content/en/docs/Learning Resources/Blog Posts/_index.md
6f21e3f5f334e2bc217abe35ff403d623c416142ee4da61cdea03e1ef63ebcff       1257  content/en/docs/Overview/motivation.md
```
