from __future__ import annotations

import argparse
import asyncio
import random
import sqlite3
import sys
from pathlib import Path
from urllib.parse import quote

import edge_tts
from send2trash import send2trash


WORDS_SQL = "SELECT DISTINCT word FROM cards ORDER BY word COLLATE NOCASE;"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate Decklet word audio with edge-tts")
    p.add_argument("--db", default="", help="Path to Decklet sqlite DB")
    p.add_argument("--out-dir", default="", help="Output directory for audio files")
    p.add_argument("--word", default="", help="Generate audio for a single word")
    p.add_argument("--text", default="", help="Override spoken text for a single word")
    p.add_argument("--voice", default="en-US-EmmaNeural", help="edge-tts voice")
    p.add_argument("--rate", default="+0%", help="Speech rate, e.g. +0%%, -10%%")
    p.add_argument("--pitch", default="+0Hz", help="Speech pitch, e.g. +0Hz, +2Hz")
    p.add_argument("--lead-in", default=", ", help="Prefix added before each word")
    p.add_argument("--workers", type=int, default=12, help="Parallel requests")
    p.add_argument("--retries", type=int, default=3, help="Retries per word")
    p.add_argument("--limit", type=int, default=0, help="Only process first N words")
    p.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    p.add_argument("--sync", action="store_true", help="Sync cache to DB words")
    p.add_argument("--dry-run", action="store_true", help="Do not generate files")
    p.add_argument("--list-voices", action="store_true", help="Print available voice names and exit")
    return p.parse_args()


def fetch_words(db_path: Path) -> list[str]:
    with sqlite3.connect(str(db_path)) as conn:
        rows = conn.execute(WORDS_SQL).fetchall()
    return [str(r[0]).strip() for r in rows if r and str(r[0]).strip()]


def word_to_filename(word: str) -> str:
    return f"{quote(word, safe='')}.mp3"


def extra_audio_files(out_dir: Path, expected_names: set[str]) -> list[Path]:
    return sorted(path for path in out_dir.glob("*.mp3") if path.is_file() and path.name not in expected_names)


def move_files_to_trash(paths: list[Path], dry_run: bool) -> int:
    moved = 0
    for path in paths:
        if dry_run:
            print(f"trash: {path}")
            moved += 1
            continue
        try:
            send2trash(str(path))
            moved += 1
        except Exception as exc:  # noqa: BLE001
            print(f"failed to trash {path}: {exc}", file=sys.stderr)
    return moved


def print_sync_result(*, total: int, existing: int, planned_generate: int, generated: int, extras: int, trashed: int, failed: int, dry_run: bool) -> None:
    print(
        "SYNC_RESULT "
        f"total={total} "
        f"existing={existing} "
        f"planned_generate={planned_generate} "
        f"generated={generated} "
        f"extras={extras} "
        f"trashed={trashed} "
        f"failed={failed} "
        f"dry_run={1 if dry_run else 0}"
    )


async def list_voices() -> int:
    voices = await edge_tts.list_voices()
    for voice in voices:
        print(voice.get("ShortName", ""))
    return 0


async def generate_one(*, word: str, text: str, out_path: Path, voice: str, rate: str, pitch: str, lead_in: str, retries: int, sem: asyncio.Semaphore) -> tuple[bool, str]:
    async with sem:
        for attempt in range(retries + 1):
            try:
                spoken = f"{lead_in}{text}" if lead_in else text
                communicate = edge_tts.Communicate(text=spoken, voice=voice, rate=rate, pitch=pitch)
                await communicate.save(str(out_path))
                return True, word
            except Exception as exc:  # noqa: BLE001
                if attempt >= retries:
                    return False, f"{word} ({exc})"
                await asyncio.sleep((2**attempt) + random.uniform(0.0, 0.4))
    return False, word


async def run(args: argparse.Namespace) -> int:
    if args.list_voices:
        return await list_voices()

    if not args.out_dir or (not args.db and not args.word):
        print("--out-dir and either --db or --word are required unless --list-voices is used", file=sys.stderr)
        return 2

    out_dir = Path(args.out_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.word:
        words = [args.word.strip()]
    else:
        db_path = Path(args.db).expanduser().resolve()
        if not db_path.exists():
            print(f"DB not found: {db_path}", file=sys.stderr)
            return 2
        words = fetch_words(db_path)

    if args.sync and args.limit > 0:
        print("--sync cannot be used with --limit (to avoid accidental mass deletions)", file=sys.stderr)
        return 2
    if args.sync and args.word:
        print("--sync cannot be used with --word", file=sys.stderr)
        return 2
    if args.limit > 0:
        words = words[: args.limit]

    expected_names = {word_to_filename(word) for word in words}
    extras: list[Path] = []
    trashed = 0
    if args.sync:
        extras = extra_audio_files(out_dir, expected_names)
        print(f"Extra audio files: {len(extras)}")
        trashed = move_files_to_trash(extras, args.dry_run)
        print(f"Moved to trash: {trashed}")

    existing = 0
    pending: list[tuple[str, Path]] = []
    for word in words:
        path = out_dir / word_to_filename(word)
        if path.exists() and not args.overwrite:
            existing += 1
        else:
            pending.append((word, path))

    print(f"Total words: {len(words)}")
    print(f"Already have audio: {existing}")
    print(f"Will generate: {len(pending)}")

    if args.dry_run or not pending:
        if args.sync:
            print_sync_result(
                total=len(words),
                existing=existing,
                planned_generate=len(pending),
                generated=0,
                extras=len(extras),
                trashed=trashed,
                failed=0,
                dry_run=args.dry_run,
            )
        return 0

    sem = asyncio.Semaphore(max(1, args.workers))
    override_text = args.text.strip()
    tasks = [
        generate_one(
            word=word,
            text=override_text or word,
            out_path=path,
            voice=args.voice,
            rate=args.rate,
            pitch=args.pitch,
            lead_in=args.lead_in,
            retries=max(0, args.retries),
            sem=sem,
        )
        for word, path in pending
    ]

    failures = 0
    done = 0
    total = len(tasks)
    for coro in asyncio.as_completed(tasks):
        ok, msg = await coro
        done += 1
        if ok:
            print(f"[{done}/{total}] ok: {msg}")
        else:
            failures += 1
            print(f"[{done}/{total}] fail: {msg}", file=sys.stderr)

    if failures:
        print(f"Done with {failures} failures", file=sys.stderr)
        if args.sync:
            print_sync_result(
                total=len(words),
                existing=existing,
                planned_generate=len(pending),
                generated=len(pending) - failures,
                extras=len(extras),
                trashed=trashed,
                failed=failures,
                dry_run=args.dry_run,
            )
        return 1

    print("Done")
    if args.sync:
        print_sync_result(
            total=len(words),
            existing=existing,
            planned_generate=len(pending),
            generated=len(pending),
            extras=len(extras),
            trashed=trashed,
            failed=0,
            dry_run=args.dry_run,
        )
    return 0


def main() -> int:
    return asyncio.run(run(parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
