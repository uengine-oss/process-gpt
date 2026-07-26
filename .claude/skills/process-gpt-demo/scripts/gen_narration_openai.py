#!/usr/bin/env python3
"""OpenAI TTS 나레이션 생성 — process-gpt-demo 공용 (모든 시나리오에서 재사용).

원본: services/strategy/docs/ontology-manual/media/gen_narration_openai3.py
(온톨로지 매뉴얼 데모에서 검증됨) — 하드코딩된 SCENE_TEXT 대신 narration
script JSON을 입력으로 받도록 일반화한 버전.

입력: narration.json — [{"scene": 1, "text": "..."}, ...]
출력: <out-dir>/scene-NN.wav + <out-dir>/durations.json

사용:
  python3 gen_narration_openai.py --script narration.json \
      --out-dir demo-recordings/<name>/narration --voice marin

키: --env-file로 지정한 .env의 OPENAI_API_KEY (기본
/Users/uengine/process-gpt/.env). 값 자체는 절대 출력하지 않는다.
"""
import argparse
import json
import os
import subprocess
import sys

MODEL = "gpt-4o-mini-tts"
FALLBACK_MODEL = "tts-1-hd"
DEFAULT_INSTRUCTIONS = (
    "차분하고 명확한 한국어 제품 데모 나레이션. 친근하지만 전문적인 톤, "
    "자연스러운 쉼과 리듬감, 과장 없이 담백하게."
)


def load_key(env_file):
    with open(env_file) as f:
        for line in f:
            if line.startswith("OPENAI_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
                if key and key not in ("dream-flow",):
                    return key
    raise SystemExit(f"OPENAI_API_KEY not found (or placeholder) in {env_file}")


def dur_of(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True).stdout.strip()
    return round(float(out), 3)


# tts-1 / tts-1-hd only support this fixed voice set (gpt-4o-mini-tts supports
# many more, e.g. "marin") -- map to a close equivalent when falling back.
FALLBACK_VOICE_MAP = {"marin": "alloy"}
FALLBACK_VOICES = {"nova", "shimmer", "echo", "onyx", "fable", "alloy", "ash", "sage", "coral"}


def synth(client, text, path, voice, instructions):
    try:
        with client.audio.speech.with_streaming_response.create(
            model=MODEL, voice=voice, input=text,
            instructions=instructions, response_format="wav",
        ) as resp:
            resp.stream_to_file(path)
        return MODEL
    except Exception as e:
        fallback_voice = voice if voice in FALLBACK_VOICES else FALLBACK_VOICE_MAP.get(voice, "alloy")
        print(f"  ! {MODEL} 실패({str(e)[:80]}) -> {FALLBACK_MODEL}/{fallback_voice} 폴백")
        with client.audio.speech.with_streaming_response.create(
            model=FALLBACK_MODEL, voice=fallback_voice, input=text,
            response_format="wav",
        ) as resp:
            resp.stream_to_file(path)
        return FALLBACK_MODEL


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True, help="narration script JSON path")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--voice", default="marin")
    ap.add_argument("--instructions", default=DEFAULT_INSTRUCTIONS)
    ap.add_argument("--env-file", default="/Users/uengine/process-gpt/.env")
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    from openai import OpenAI
    client = OpenAI(api_key=load_key(args.env_file))

    scenes = json.load(open(args.script))
    durations = []
    for s in scenes:
        idx = f"{s['scene']:02d}"
        p = os.path.join(args.out_dir, f"scene-{idx}.wav")
        used = synth(client, s["text"], p, args.voice, args.instructions)
        d = dur_of(p)
        durations.append({"scene": s["scene"], "file": f"scene-{idx}", "duration": d})
        print(f"[{idx}] voice={args.voice} model={used} dur={d:.2f}s")

    dj = os.path.join(args.out_dir, "durations.json")
    with open(dj, "w") as f:
        json.dump(durations, f, ensure_ascii=False, indent=2)
    total = sum(d["duration"] for d in durations)
    print(f"\n완료 -> {dj}  (총 {total:.1f}s, {total/60:.2f}분, voice={args.voice})")


if __name__ == "__main__":
    main()
