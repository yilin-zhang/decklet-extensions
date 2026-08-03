from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterable

from send2trash import send2trash


MANIFEST_VERSION = 1
CONFIDENCE_VALUES = {"high", "medium", "low", "approved"}
CARDS_SQL = """
SELECT card_id, word, COALESCE(hint, ''), COALESCE(back, '')
FROM cards
WHERE archived_at IS NULL
ORDER BY word COLLATE NOCASE
"""
CARD_INDEX_SQL = """
SELECT card_id, word
FROM cards
WHERE archived_at IS NULL
ORDER BY word COLLATE NOCASE
"""


def now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat()


def empty_manifest() -> dict[str, Any]:
    return {"version": MANIFEST_VERSION, "cards": {}}


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        return empty_manifest()
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("version") != MANIFEST_VERSION or not isinstance(data.get("cards"), dict):
        raise ValueError(f"Unsupported manifest format: {path}")
    return data


def save_manifest(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextmanager
def manifest_lock(path: Path):
    digest = hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]
    lock_path = Path(tempfile.gettempdir()) / f"decklet-kokoro-{digest}.lock"
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def fetch_cards(db_path: Path, *, include_context: bool = True) -> list[dict[str, Any]]:
    uri = f"file:{db_path.resolve()}?mode=ro"
    with sqlite3.connect(uri, uri=True) as connection:
        rows = connection.execute(CARDS_SQL if include_context else CARD_INDEX_SQL).fetchall()
    cards = [{"card_id": int(row[0]), "word": str(row[1])} for row in rows]
    if include_context:
        for card, row in zip(cards, rows, strict=True):
            card.update(hint=str(row[2]), back=str(row[3]))
    return cards


def fetch_card(db_path: Path, card_id: int | None, word: str | None) -> dict[str, Any]:
    uri = f"file:{db_path.resolve()}?mode=ro"
    if card_id is not None:
        clause = "card_id = ?"
        target_value: int | str = card_id
    else:
        clause = "word = ?"
        target_value = word or ""
    query = f"""
        SELECT card_id, word, COALESCE(hint, ''), COALESCE(back, '')
        FROM cards
        WHERE archived_at IS NULL AND {clause}
        ORDER BY card_id
        LIMIT 1
    """
    with sqlite3.connect(uri, uri=True) as connection:
        row = connection.execute(query, (target_value,)).fetchone()
    if row is None:
        target = f"card ID {card_id}" if card_id is not None else f"word {word!r}"
        raise ValueError(f"No active Decklet card for {target}")
    return {
        "card_id": int(row[0]),
        "word": str(row[1]),
        "hint": str(row[2]),
        "back": str(row[3]),
    }


def audio_path(out_dir: Path, card_id: int) -> Path:
    return out_dir / f"{card_id}.mp3"


def lang_code(accent: str) -> str:
    return {"en-us": "a", "en-gb": "b"}[accent]


def phonemize(text: str, accent: str) -> str:
    from kokoro import KPipeline

    pipeline = KPipeline(
        lang_code=lang_code(accent),
        repo_id="hexgrad/Kokoro-82M",
        model=False,
    )
    parts = [result.phonemes for result in pipeline(text, voice=None) if result.phonemes]
    if not parts:
        raise ValueError(f"Could not phonemize {text!r}")
    return " ".join(parts)


def load_pipeline(model_dir: Path, accent: str, device: str):
    import torch
    from kokoro import KModel, KPipeline

    config = model_dir / "config.json"
    weights = model_dir / "kokoro-v1_0.pth"
    for path in (config, weights):
        if not path.exists():
            raise FileNotFoundError(f"Missing Kokoro model file: {path}")
    if device == "mps":
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
        if not torch.backends.mps.is_available():
            raise RuntimeError("MPS requested but unavailable")
    model = KModel(
        repo_id="hexgrad/Kokoro-82M",
        config=str(config),
        model=str(weights),
    ).to(device).eval()
    return KPipeline(
        lang_code=lang_code(accent),
        repo_id="hexgrad/Kokoro-82M",
        model=model,
    )


def resolve_voice(model_dir: Path, voice: str) -> Path:
    path = Path(voice).expanduser()
    if not path.is_absolute():
        path = model_dir / "voices" / f"{voice.removesuffix('.pt')}.pt"
    if not path.exists():
        raise FileNotFoundError(f"Missing Kokoro voice file: {path}")
    return path.resolve()


def silence_filter(threshold: str, keep: float) -> str:
    return (
        "silenceremove=start_periods=1:start_duration=0.01:"
        f"start_threshold={threshold}:start_silence={keep}"
    )


def write_mp3(audio, destination: Path, ffmpeg: str, trim_threshold: str, trim_keep: float) -> None:
    import soundfile as sf

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="decklet-kokoro-", dir=destination.parent) as temp_dir:
        wav_path = Path(temp_dir) / "audio.wav"
        mp3_path = Path(temp_dir) / "audio.mp3"
        sf.write(wav_path, audio.numpy(), 24000)
        subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(wav_path),
                "-af",
                silence_filter(trim_threshold, trim_keep),
                "-codec:a",
                "libmp3lame",
                "-q:a",
                "2",
                str(mp3_path),
            ],
            check=True,
        )
        os.replace(mp3_path, destination)


def synthesize(
    *,
    pipeline,
    word: str,
    pronunciation: str | None,
    voice_path: Path,
    speed: float,
    destination: Path,
    ffmpeg: str,
    trim_threshold: str,
    trim_keep: float,
) -> str:
    if pronunciation:
        results = pipeline.generate_from_tokens(pronunciation, voice=str(voice_path), speed=speed)
    else:
        results = pipeline(word, voice=str(voice_path), speed=speed)
    chunks = list(results)
    if len(chunks) != 1 or chunks[0].audio is None:
        raise RuntimeError(f"Expected one audio chunk for {word!r}, got {len(chunks)}")
    write_mp3(chunks[0].audio, destination, ffmpeg, trim_threshold, trim_keep)
    return chunks[0].phonemes


def valid_record(record: dict[str, Any] | None, word: str, accent: str | None = None) -> bool:
    return bool(
        record
        and record.get("word") == word
        and record.get("status") == "valid"
        and (accent is None or record.get("accent") == accent)
    )


def candidate_reason(
    card: dict[str, Any],
    record: dict[str, Any] | None,
    output: Path,
    accent: str | None = None,
) -> str | None:
    if record and record.get("word") != card["word"]:
        return "stale"
    if not record or record.get("status") != "valid":
        return "missing-manifest"
    if accent is not None and record.get("accent") != accent:
        return "accent-changed"
    if not output.exists():
        return "missing-audio"
    return None


def mark_stale(record: dict[str, Any], word: str) -> None:
    record["previous_word"] = record.get("word")
    record["word"] = word
    record["status"] = "stale"
    record["updated_at"] = now_iso()


def make_record(
    *,
    word: str,
    accent: str,
    pronunciation: str,
    source: str,
    confidence: str,
    status: str = "valid",
) -> dict[str, Any]:
    return {
        "word": word,
        "accent": accent,
        "pronunciation": pronunciation,
        "source": source,
        "confidence": confidence,
        "status": status,
        "updated_at": now_iso(),
    }


def command_scan(args: argparse.Namespace) -> int:
    cards = fetch_cards(args.db)
    manifest = load_manifest(args.manifest)
    records = manifest["cards"]
    count = 0
    for card in cards:
        key = str(card["card_id"])
        record = records.get(key)
        output = audio_path(args.out_dir, card["card_id"])
        reason = candidate_reason(card, record, output, args.accent)
        if reason is None:
            continue
        count += 1
        payload = {**card, "reason": reason, "record": record, "audio_path": str(output)}
        print(json.dumps(payload, ensure_ascii=False))
    print(f"SCAN_RESULT candidates={count}", file=sys.stderr)
    return 0


def command_set(args: argparse.Namespace) -> int:
    card = fetch_card(args.db, args.card_id, args.word)
    pronunciation = phonemize(card["word"], args.accent) if args.auto else args.pronunciation.strip()
    if not pronunciation:
        raise ValueError("--pronunciation is required unless --auto is used")
    manifest = load_manifest(args.manifest)
    manifest["cards"][str(card["card_id"])] = make_record(
        word=card["word"],
        accent=args.accent,
        pronunciation=pronunciation,
        source=args.source,
        confidence=args.confidence,
    )
    save_manifest(args.manifest, manifest)
    print(json.dumps({"card_id": card["card_id"], "word": card["word"], "pronunciation": pronunciation},
                     ensure_ascii=False))
    return 0


def command_set_batch(args: argparse.Namespace) -> int:
    cards = fetch_cards(args.db, include_context=False)
    by_id = {card["card_id"]: card for card in cards}
    manifest = load_manifest(args.manifest)
    updated = 0
    with args.input.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            if not line.strip():
                continue
            item = json.loads(line)
            card = by_id.get(int(item["card_id"]))
            if card is None:
                raise ValueError(f"Line {line_number}: no active card ID {item['card_id']}")
            pronunciation = str(item["pronunciation"]).strip()
            confidence = str(item["confidence"])
            if not pronunciation:
                raise ValueError(f"Line {line_number}: pronunciation is empty")
            if confidence not in CONFIDENCE_VALUES:
                raise ValueError(f"Line {line_number}: invalid confidence {confidence!r}")
            manifest["cards"][str(card["card_id"])] = make_record(
                word=card["word"],
                accent=str(item.get("accent", args.accent)),
                pronunciation=pronunciation,
                source=str(item["source"]),
                confidence=confidence,
            )
            updated += 1
    if updated:
        save_manifest(args.manifest, manifest)
    print(f"SET_BATCH_RESULT updated={updated}")
    return 0


def command_generate(args: argparse.Namespace) -> int:
    card = fetch_card(args.db, args.card_id, args.word)
    manifest = load_manifest(args.manifest)
    key = str(card["card_id"])
    record = manifest["cards"].get(key)
    explicit = args.pronunciation.strip() or None
    if explicit:
        pronunciation = explicit
        source = "manual"
        confidence = "approved"
    elif valid_record(record, card["word"], args.accent):
        pronunciation = record.get("pronunciation")
        source = record.get("source", "manifest")
        confidence = record.get("confidence", "unknown")
    else:
        pronunciation = None
        source = "auto-g2p"
        confidence = "unreviewed"
    pipeline = load_pipeline(args.model_dir, args.accent, args.device)
    voice_path = resolve_voice(args.model_dir, args.voice)
    generated_pronunciation = synthesize(
        pipeline=pipeline,
        word=card["word"],
        pronunciation=pronunciation,
        voice_path=voice_path,
        speed=args.speed,
        destination=audio_path(args.out_dir, card["card_id"]),
        ffmpeg=args.ffmpeg,
        trim_threshold=args.trim_threshold,
        trim_keep=args.trim_keep,
    )
    manifest["cards"][key] = make_record(
        word=card["word"],
        accent=args.accent,
        pronunciation=pronunciation or generated_pronunciation,
        source=source,
        confidence=confidence,
    )
    save_manifest(args.manifest, manifest)
    print(f"GENERATE_RESULT card_id={card['card_id']} word={json.dumps(card['word'])}")
    return 0


def command_batch(args: argparse.Namespace) -> int:
    cards = fetch_cards(args.db, include_context=False)
    manifest = load_manifest(args.manifest)
    pending = []
    for card in cards:
        record = manifest["cards"].get(str(card["card_id"]))
        output = audio_path(args.out_dir, card["card_id"])
        usable = valid_record(record, card["word"], args.accent)
        if (usable and (args.overwrite or not output.exists())) or (
            args.auto_missing and not usable
        ):
            pending.append((card, record, output))
    if args.dry_run:
        for card, _, output in pending:
            print(json.dumps({"card_id": card["card_id"], "word": card["word"], "audio_path": str(output)},
                             ensure_ascii=False))
        print(f"BATCH_RESULT planned={len(pending)} generated=0 failed=0 dry_run=1")
        return 0
    if not pending:
        print("BATCH_RESULT planned=0 generated=0 failed=0 dry_run=0")
        return 0
    pipeline = load_pipeline(args.model_dir, args.accent, args.device)
    voice_path = resolve_voice(args.model_dir, args.voice)
    generated = 0
    failed = 0
    unsaved_records = 0
    for index, (card, record, output) in enumerate(pending, start=1):
        try:
            use_record = valid_record(record, card["word"], args.accent)
            generated_pronunciation = synthesize(
                pipeline=pipeline,
                word=card["word"],
                pronunciation=record["pronunciation"] if use_record else None,
                voice_path=voice_path,
                speed=args.speed,
                destination=output,
                ffmpeg=args.ffmpeg,
                trim_threshold=args.trim_threshold,
                trim_keep=args.trim_keep,
            )
            if not use_record:
                manifest["cards"][str(card["card_id"])] = make_record(
                    word=card["word"],
                    accent=args.accent,
                    pronunciation=generated_pronunciation,
                    source="auto-g2p",
                    confidence="unreviewed",
                )
                unsaved_records += 1
            generated += 1
            print(f"[{index}/{len(pending)}] ok: {card['word']}")
            if unsaved_records >= 250:
                save_manifest(args.manifest, manifest)
                unsaved_records = 0
        except Exception as error:  # noqa: BLE001
            failed += 1
            print(f"[{index}/{len(pending)}] fail: {card['word']} ({error})", file=sys.stderr)
    if unsaved_records:
        save_manifest(args.manifest, manifest)
    print(
        f"BATCH_RESULT planned={len(pending)} generated={generated} "
        f"failed={failed} dry_run=0"
    )
    return 1 if failed else 0


def trash_paths(paths: Iterable[Path]) -> int:
    count = 0
    for path in paths:
        if path.exists():
            send2trash(str(path))
            count += 1
    return count


def command_remove(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    removed = 0
    for card_id in args.card_id:
        if manifest["cards"].pop(str(card_id), None) is not None:
            removed += 1
    trashed = trash_paths(audio_path(args.out_dir, card_id) for card_id in args.card_id)
    if removed:
        save_manifest(args.manifest, manifest)
    print(f"REMOVE_RESULT records={removed} trashed={trashed}")
    return 0


def command_stale(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest)
    if len(args.card_id) != len(args.word):
        raise ValueError("Each --card-id must have one corresponding --word")
    records = 0
    audio = []
    for card_id, word in zip(args.card_id, args.word, strict=True):
        record = manifest["cards"].get(str(card_id))
        if record:
            mark_stale(record, word)
            records += 1
        audio.append(audio_path(args.out_dir, card_id))
    if records:
        save_manifest(args.manifest, manifest)
    trashed = trash_paths(audio)
    print(f"STALE_RESULT records={records} trashed={trashed}")
    return 0


def command_sync(args: argparse.Namespace) -> int:
    cards = {
        card["card_id"]: card
        for card in fetch_cards(args.db, include_context=False)
    }
    manifest = load_manifest(args.manifest)
    records = manifest["cards"]
    removed = 0
    stale = 0
    trash = []
    for key in list(records):
        card_id = int(key)
        card = cards.get(card_id)
        if card is None:
            records.pop(key)
            removed += 1
            trash.append(audio_path(args.out_dir, card_id))
        elif records[key].get("word") != card["word"]:
            mark_stale(records[key], card["word"])
            stale += 1
            trash.append(audio_path(args.out_dir, card_id))
    trashed = 0 if args.dry_run else trash_paths(trash)
    if (removed or stale) and not args.dry_run:
        save_manifest(args.manifest, manifest)
    missing_audio = sum(
        1
        for card_id, card in cards.items()
        if valid_record(records.get(str(card_id)), card["word"])
        and not audio_path(args.out_dir, card_id).exists()
    )
    print(
        f"SYNC_RESULT removed={removed} stale={stale} "
        f"trashed={trashed} missing_audio={missing_audio}"
    )
    args.auto_missing = True
    args.overwrite = False
    return command_batch(args)


def add_common_paths(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--db", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)


def add_card_target(parser: argparse.ArgumentParser) -> None:
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--card-id", type=int)
    group.add_argument("--word")


def add_runtime(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--accent", choices=("en-us", "en-gb"), default="en-us")
    parser.add_argument("--device", choices=("mps", "cpu"), default="mps")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--trim-threshold", default="-55dB")
    parser.add_argument("--trim-keep", type=float, default=0.03)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local Kokoro TTS integration for Decklet")
    subparsers = parser.add_subparsers(dest="command", required=True)

    scan = subparsers.add_parser("scan")
    add_common_paths(scan)
    scan.add_argument("--accent", choices=("en-us", "en-gb"), default="en-us")
    scan.set_defaults(handler=command_scan)

    set_command = subparsers.add_parser("set")
    add_common_paths(set_command)
    add_card_target(set_command)
    set_command.add_argument("--pronunciation", default="")
    set_command.add_argument("--auto", action="store_true")
    set_command.add_argument("--accent", choices=("en-us", "en-gb"), default="en-us")
    set_command.add_argument("--source", required=True)
    set_command.add_argument("--confidence", choices=("high", "medium", "low", "approved"),
                             required=True)
    set_command.set_defaults(handler=command_set)

    set_batch = subparsers.add_parser("set-batch")
    add_common_paths(set_batch)
    set_batch.add_argument("--input", type=Path, required=True)
    set_batch.add_argument("--accent", choices=("en-us", "en-gb"), default="en-us")
    set_batch.set_defaults(handler=command_set_batch)

    generate = subparsers.add_parser("generate")
    add_common_paths(generate)
    add_card_target(generate)
    add_runtime(generate)
    generate.add_argument("--pronunciation", default="")
    generate.set_defaults(handler=command_generate)

    batch = subparsers.add_parser("batch")
    add_common_paths(batch)
    add_runtime(batch)
    batch.add_argument("--overwrite", action="store_true")
    batch.add_argument("--auto-missing", action="store_true")
    batch.add_argument("--dry-run", action="store_true")
    batch.set_defaults(handler=command_batch)

    remove = subparsers.add_parser("remove")
    remove.add_argument("--manifest", type=Path, required=True)
    remove.add_argument("--out-dir", type=Path, required=True)
    remove.add_argument("--card-id", type=int, action="append", required=True)
    remove.set_defaults(handler=command_remove)

    stale = subparsers.add_parser("stale")
    stale.add_argument("--manifest", type=Path, required=True)
    stale.add_argument("--out-dir", type=Path, required=True)
    stale.add_argument("--card-id", type=int, action="append", required=True)
    stale.add_argument("--word", action="append", required=True)
    stale.set_defaults(handler=command_stale)

    sync = subparsers.add_parser("sync")
    add_common_paths(sync)
    add_runtime(sync)
    sync.add_argument("--dry-run", action="store_true")
    sync.set_defaults(handler=command_sync)

    phonemize_command = subparsers.add_parser("phonemize")
    phonemize_command.add_argument("--text", required=True)
    phonemize_command.add_argument("--accent", choices=("en-us", "en-gb"), default="en-us")
    phonemize_command.set_defaults(
        handler=lambda args: print(phonemize(args.text, args.accent)) or 0
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        manifest = getattr(args, "manifest", None)
        if manifest is None:
            return args.handler(args)
        with manifest_lock(manifest):
            return args.handler(args)
    except Exception as error:  # noqa: BLE001
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
