#!/usr/bin/env python3
"""Build the source-candidate package manifest without invoking Lean or LaTeX."""

from __future__ import annotations

import datetime
import hashlib
import json
import pathlib

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "PACKAGE-MANIFEST.json"
STALE_PDF = "main_compressed.pdf"
AUTHOR_GRAPH = "712e1c6849da7dcae46a910cf53a59a85c799d482f9635229eb51cf5a6a42f9b"
LATEX_GRAPH = "73bf16fb9cc0cc92f00a2f2fe47791c084ac01780b784ef1dd3db33ee00d4e9e"
FORMAL_GRAPH = "1ea8b2d58e1f4c3c007f8da46f77c7818d716b21bf418929ea9f9ecb8bef5afa"


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_hash(value: object) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def graph_entry(relative: str) -> dict[str, str]:
    return {"path": relative, "sha256": sha256_file(ROOT / relative)}


def excluded(relative: pathlib.PurePosixPath) -> bool:
    if relative.as_posix() in {MANIFEST.name, STALE_PDF}:
        return True
    if any(part in {".lake", "__pycache__", "tmp"} for part in relative.parts):
        return True
    name = relative.name
    return name.endswith(
        (
            ".pyc",
            ".olean",
            ".ilean",
            ".aux",
            ".bbl",
            ".blg",
            ".fdb_latexmk",
            ".fls",
            ".log",
            ".out",
            ".synctex.gz",
            ".toc",
        )
    )


def formal_graph() -> tuple[list[dict[str, str]], str]:
    tcb = json.loads((ROOT / "formal/tcb-manifest.json").read_text(encoding="utf-8"))
    package = tcb["package"]
    entries = [
        {"path": item["path"], "sha256": sha256_file(ROOT / item["path"])}
        for item in package["source_files"] + package["configuration_files"]
    ]
    return entries, canonical_hash(entries)


def main() -> None:
    registry = yaml.safe_load(
        (ROOT / "formal/formal-units.yaml").read_text(encoding="utf-8")
    )
    author_entries = [
        graph_entry(item["path"]) for item in registry["source_snapshot"]["files"]
    ]
    author_hash = canonical_hash(author_entries)
    latex_entries = author_entries + [
        graph_entry("formal/formal-statement-index.tex"),
        graph_entry("figures/raw_edit_repair_coverage_relabel.png"),
        graph_entry("llncs.cls"),
        graph_entry("splncs04.bst"),
    ]
    latex_hash = canonical_hash(latex_entries)
    formal_entries, formal_hash = formal_graph()
    expected = {
        "author_source_graph": AUTHOR_GRAPH,
        "self_contained_latex_graph": LATEX_GRAPH,
        "formal_source_config_graph": FORMAL_GRAPH,
    }
    actual = {
        "author_source_graph": author_hash,
        "self_contained_latex_graph": latex_hash,
        "formal_source_config_graph": formal_hash,
    }
    if actual != expected:
        raise RuntimeError(f"source identity mismatch: expected {expected}, got {actual}")

    inventory: list[dict[str, object]] = []
    for path in sorted(ROOT.rglob("*")):
        if path.is_symlink():
            raise RuntimeError(f"symlinks are not permitted: {path}")
        if not path.is_file():
            continue
        relative = pathlib.PurePosixPath(path.relative_to(ROOT).as_posix())
        if excluded(relative):
            continue
        inventory.append(
            {
                "path": relative.as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
        )

    value = {
        "schema_version": "4.0",
        "generated_at_utc": datetime.datetime.now(
            datetime.timezone.utc
        ).isoformat(timespec="seconds"),
        "package_name": (
            "Typed_Flexible_Arity_Slotted_EGraphs_"
            "arxiv-ready_source-candidate.zip"
        ),
        "package_kind": "ARXIV_READY_SOURCE_CANDIDATE_WITH_FORMAL_SUPPLEMENT",
        "status": "CORRESPONDENCE_CLOSED_PENDING_CURRENT_LEAN_AND_PDF_GATES",
        "submission_readiness": {
            "source_candidate_assembled": True,
            "current_lean_builds_executed": False,
            "current_latex_build_executed": False,
            "current_page_boundary_verified": False,
            "current_all_page_pdf_qa_executed": False,
            "stale_input_pdf_included": False,
        },
        "source_identities": {
            "author_source_file_count": len(author_entries),
            "author_source_graph_sha256": author_hash,
            "self_contained_latex_file_count": len(latex_entries),
            "self_contained_latex_graph_sha256": latex_hash,
            "formal_source_config_file_count": len(formal_entries),
            "formal_source_config_graph_sha256": formal_hash,
            "active_chart_sha256": sha256_file(
                ROOT / "figures/raw_edit_repair_coverage_relabel.png"
            ),
        },
        "correspondence": {
            "status": "CORRESPONDENCE_CLOSED",
            "process_id": "bounded-arxiv-correspondence-2026-09-02",
            "review_rounds_executed": 1,
            "fresh_independent_passes": 2,
            "active_mapping_coverage": "146/146",
            "named_environment_coverage": "27/27",
            "snapshot_id": (
                "8f7729dfd0f97230f30039b1a66553c65a2df0c9e7643bac47e084c2de3be203"
            ),
            "normalization_contract_sha256": (
                "9b4a84e6b492a65bed6c9446b1c3c9e255e21277caba9cc9d8c31d713c873bc6"
            ),
            "current_review_sha256": sha256_file(
                ROOT / "formal/correspondence-review.json"
            ),
        },
        "supplemental_trace_witness": {
            "path": "formal/TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean",
            "sha256": sha256_file(
                ROOT
                / "formal/TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean"
            ),
            "repository_commit": "f5dbc1a04e10b61e39e6fe1b0fe8d5b236728625",
            "repository_git_blob_sha1": "48528272445b6fa81ebd6c1f30680cd285751b5f",
            "active_claim_count_delta": 0,
        },
        "assurance_boundary": {
            "paper_lean_correspondence": "CLOSED",
            "paper_formal_closure": "PENDING_CURRENT_CLEAN_LEAN_BUILDS",
            "abstract_kernel_closure": "PENDING_CURRENT_CLEAN_LEAN_BUILDS",
            "artifact_refinement": "PARTIAL",
            "experimental_replay": "PARTIAL",
            "current_latex_and_pdf_qa": "NOT_EXECUTED",
            "permitted_public_label": "NO_FORMAL_CLOSURE_CLAIM",
        },
        "immutability": {
            "java_changes": 0,
            "experimental_result_changes": 0,
            "figure_changes": 0,
            "bibliography_content_changes": 0,
        },
        "explicit_exclusions": [
            "PACKAGE-MANIFEST.json from its own hashed inventory",
            "stale main_compressed.pdf",
            "formal/.lake/** and compiled Lean products",
            "LaTeX auxiliary, log, recorder, and synchronization products",
            "Python caches",
            "Java sources and experimental result files",
            "publication actions",
        ],
        "manifest_self_excluded": True,
        "inventory": {"file_count": len(inventory), "files": inventory},
    }
    MANIFEST.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
