#!/usr/bin/env python3
"""Playwright 녹화(webm) + 장면별 나레이션(wav) 합성 — process-gpt-demo 공용.

원본: services/strategy/docs/ontology-manual/media/assemble_video3.py
(온톨로지 매뉴얼 데모에서 검증됨) — 하드코딩된 경로 대신 CLI 인자를 받도록
일반화한 버전. 각 장면의 나레이션 wav를 해당 장면 시작 시각(start_sec)에
배치해 무음 원본 영상에 mux한다.

입력:
  --video          Playwright 녹화 원본 webm (무음)
  --timing         scenes-timing.json — [{"scene": int, "start_sec": float}]
  --narration-dir  gen_narration_openai.py 출력 디렉터리
                   (durations.json + scene-NN.wav)
  --out            최종 mp4 경로

실행:
  python3 assemble_narrated_video.py --video raw.webm \
      --timing timing.json --narration-dir narration --out final.mp4
"""
import argparse
import json
import os
import subprocess
import sys


def run(cmd):
    print("$", " ".join(cmd[:6]), "…" if len(cmd) > 6 else "")
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def probe(path, *entries):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", ",".join(entries),
         "-of", "json", path], capture_output=True, text=True).stdout
    return json.loads(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--timing", required=True)
    ap.add_argument("--narration-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    timing = json.load(open(args.timing))

    vdur = float(probe(args.video, "format=duration")["format"]["duration"])
    print(f"영상 길이: {vdur:.2f}s")

    inputs, filters, mixlabels = [], [], []
    for i, t in enumerate(sorted(timing, key=lambda x: x["scene"])):
        n = t["scene"]
        wav = os.path.join(args.narration_dir, f"scene-{n:02d}.wav")
        if not os.path.exists(wav):
            print("경고: 누락", wav)
            continue
        delay_ms = int(round(t["start_sec"] * 1000))
        inputs += ["-i", wav]
        in_idx = len(mixlabels) + 1  # 입력 0 은 webm(무음)
        lbl = f"a{i}"
        filters.append(f"[{in_idx}:a]adelay={delay_ms}|{delay_ms}[{lbl}]")
        mixlabels.append(f"[{lbl}]")

    n_in = len(mixlabels)
    if n_in == 0:
        raise SystemExit("나레이션 wav를 하나도 못 찾았습니다 — narration-dir/timing 확인")

    amix = (
        ";".join(filters)
        + ";" + "".join(mixlabels)
        + f"amix=inputs={n_in}:normalize=0:dropout_transition=0[mixed]"
        + f";[mixed]apad,atrim=0:{vdur:.3f},asetpts=N/SR/TB[aout]"
    )

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", args.video] + inputs + [
        "-filter_complex", amix,
        "-map", "0:v:0", "-map", "[aout]",
        "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ac", "2",
        "-movflags", "+faststart",
        args.out]
    run(cmd)
    print("생성:", args.out, f"({os.path.getsize(args.out)/1e6:.1f} MB)")

    fdur = float(probe(args.out, "format=duration")["format"]["duration"])
    streams = probe(args.out, "stream=index,codec_type,codec_name,width,height,sample_rate,channels")["streams"]
    print(f"\n=== ffprobe 요약 ===\n최종 길이: {fdur:.2f}s")
    has_h264 = has_aac = False
    for s in streams:
        if s["codec_type"] == "video":
            has_h264 = s["codec_name"] == "h264"
            print(f"  video: {s['codec_name']} {s.get('width')}x{s.get('height')}")
        else:
            has_aac = s["codec_name"] == "aac"
            print(f"  audio: {s['codec_name']} {s.get('sample_rate')}Hz {s.get('channels')}ch")

    vd = subprocess.run(
        ["ffmpeg", "-i", args.out, "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    mean = next((l.split("mean_volume:")[1].strip() for l in vd.splitlines() if "mean_volume" in l), "?")
    print(f"\nmean_volume: {mean}")
    mean_db = float(mean.replace(" dB", "")) if "dB" in mean else -99

    ok = has_h264 and has_aac and mean_db > -40
    print("\n결과:", "PASS" if ok else "CHECK FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
