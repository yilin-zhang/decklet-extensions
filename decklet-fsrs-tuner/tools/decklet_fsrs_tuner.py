"""Fine-tune FSRS parameters from a Decklet review-log JSONL file.

The review log is produced by `decklet-review-log.el` and lives at
`~/.emacs.d/decklet/review-log.jsonl` by default. This script parses
it, filters out voided records, groups effective ratings by
`card_id`, and hands the per-card review histories to py-fsrs's
`Optimizer` to produce an optimized 21-float parameter vector that
can be plugged back into Decklet via `decklet-fsrs-parameters`.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Fine-tune FSRS parameters from a Decklet review-log JSONL file",
    )
    p.add_argument("--log", required=True, help="Path to review-log.jsonl")
    p.add_argument("--output", required=True, help="Path to write the optimized parameters JSON")
    p.add_argument(
        "--min-reviews",
        type=int,
        default=400,
        help="Minimum effective (non-voided) reviews required (default: 400)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse the log and print summary stats but skip the optimizer",
    )
    return p.parse_args()


def read_log(path: Path) -> tuple[list[dict], set[int]]:
    """Return (rated-records, voided-ids) from the JSONL log at PATH.

    Malformed lines and unknown kinds are skipped with a warning.
    """
    rated: list[dict] = []
    voided: set[int] = set()
    with path.open("r", encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                rec = json.loads(stripped)
            except json.JSONDecodeError as exc:
                print(f"{path}:{lineno}: skipped malformed line: {exc}", file=sys.stderr)
                continue
            kind = rec.get("kind")
            if kind == "rated":
                rated.append(rec)
            elif kind == "void":
                target = rec.get("voids")
                if isinstance(target, int):
                    voided.add(target)
            # "rename" and unknown kinds are ignored: card_id is stable
            # across renames so the optimizer doesn't need rename hints.
    return rated, voided


def effective_rated(rated: list[dict], voided: set[int]) -> list[dict]:
    """Return rated records whose id is not present in VOIDED."""
    return [r for r in rated if r.get("id") not in voided]


def group_by_card(records: list[dict]) -> dict[int, list[dict]]:
    """Group records by `card_id`, chronologically sorted by `t`."""
    by_card: dict[int, list[dict]] = defaultdict(list)
    for rec in records:
        card_id = rec.get("card_id")
        if not isinstance(card_id, int):
            continue
        by_card[card_id].append(rec)
    for recs in by_card.values():
        recs.sort(key=lambda r: r.get("t", ""))
    return by_card


def parse_iso_utc(s: str) -> datetime:
    """Parse an ISO-8601 UTC timestamp emitted by `decklet--now`.

    Decklet writes trailing-Z form (`2026-04-09T20:15:00Z`); older
    Pythons' `fromisoformat` doesn't accept Z, so rewrite to
    `+00:00` first.
    """
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def build_review_logs(by_card: dict[int, list[dict]]):
    """Build a flat list of py-fsrs ReviewLog objects across all cards.

    py-fsrs >= 6 expects a flat `list[ReviewLog]`; the Optimizer
    groups internally by `card_id`.  Imported lazily so the rest of
    this module is usable without the heavy `fsrs` dependency —
    handy for unit tests and dry runs.
    """
    from fsrs import Rating, ReviewLog  # type: ignore

    rating_map = {
        1: Rating.Again,
        2: Rating.Hard,
        3: Rating.Good,
        4: Rating.Easy,
    }

    result: list = []
    for card_id, records in by_card.items():
        for rec in records:
            grade = rec.get("grade")
            if not isinstance(grade, int):
                continue
            rating = rating_map.get(grade)
            if rating is None:
                continue
            try:
                ts = parse_iso_utc(rec["t"])
            except (KeyError, ValueError):
                continue
            result.append(
                ReviewLog(
                    card_id=card_id,
                    rating=rating,
                    review_datetime=ts,
                    review_duration=None,
                )
            )
    return result


def compute_parameters(review_logs) -> list[float]:
    """Run py-fsrs Optimizer and return the 21-float parameter list."""
    from fsrs import Optimizer  # type: ignore

    optimizer = Optimizer(review_logs)
    params = optimizer.compute_optimal_parameters()
    return [float(x) for x in params]


def main() -> int:
    args = parse_args()
    log_path = Path(args.log).expanduser().resolve()
    out_path = Path(args.output).expanduser().resolve()

    if not log_path.exists():
        print(f"Log file not found: {log_path}", file=sys.stderr)
        return 2

    rated, voided = read_log(log_path)
    effective = effective_rated(rated, voided)
    by_card = group_by_card(effective)
    print(
        f"Read {len(rated)} rated, {len(voided)} voided, "
        f"{len(effective)} effective across {len(by_card)} cards"
    )

    if len(effective) < args.min_reviews:
        print(
            f"Only {len(effective)} effective reviews; need at least "
            f"{args.min_reviews} for meaningful tuning. "
            f"Pass --min-reviews N to override.",
            file=sys.stderr,
        )
        return 3

    if args.dry_run:
        print("Dry run: skipping optimizer")
        return 0

    try:
        review_logs = build_review_logs(by_card)
    except ImportError as exc:
        print(f"decklet-fsrs-tuner requires py-fsrs (`uv sync` first): {exc}", file=sys.stderr)
        return 2

    if not review_logs:
        print("No usable reviews after filtering", file=sys.stderr)
        return 3

    print(f"Running py-fsrs Optimizer on {len(review_logs)} ReviewLogs...")
    parameters = compute_parameters(review_logs)

    payload = {
        "parameters": parameters,
        "metrics": {
            "effective_reviews": len(effective),
            "cards": len(by_card),
            "voided": len(voided),
        },
        "log_file": str(log_path),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2)
        fh.write("\n")
    print(
        f"TUNE_RESULT effective={len(effective)} cards={len(by_card)} "
        f"voided={len(voided)} output={out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
