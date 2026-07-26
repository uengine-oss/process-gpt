# 데모 녹화 + TTS 내레이션

모든 데모 시나리오(1~4, 실행되는 것)는 기본적으로 Playwright 영상 녹화를
남기고, 가능하면 TTS 내레이션까지 입힌 최종본을 만든다. 검증된 패턴 —
`services/strategy/docs/ontology-manual/media/`의 온톨로지 매뉴얼 데모
제작 과정을 일반화한 것이다(하드코딩된 장면 텍스트 대신 이 스킬의
`scripts/`가 CLI 인자로 받는다).

> **저장 위치는 항상 저장소 루트의 `demo-recordings/`다 — 다른 위치에
> 남기지 않는다.** 최종 영상은 `demo-recordings/<scenario-name>-narrated.mp4`
> (또는 무음이면 `<scenario-name>.mp4`)로 루트 바로 아래에 두고, 원본
> webm·스크린샷·narration wav 같은 중간 산출물은
> `demo-recordings/<scenario-name>/` 서브폴더 아래에 둔다. 실행 중인
> 작업 디렉터리가 어디든(`services/frontend`에서 Playwright를 띄우는 등)
> 출력 경로는 절대경로 또는 저장소 루트 기준 상대경로로 명시해서 반드시
> `demo-recordings/`로 귀결시킨다. 예시: `demo-recordings/vacation-request-demo/`
> (raw webm, screenshots, narration) + `demo-recordings/vacation-request-demo-narrated.mp4`
> (최종본) — 2026-07-20 실제 데모 실행 산출물.

## 0. 진행 여부/TTS 엔진 확인

시나리오 실행 시작 전에:

1. 영상 녹화는 기본으로 켠다(사용자가 명시적으로 끄라고 하지 않는 한).
2. `.env`(`/Users/uengine/process-gpt/.env`, 또는 프로젝트에 맞는 경로)에
   `OPENAI_API_KEY`가 **실제 값**(플레이스홀더 아님)으로 있는지 확인한다:
   ```bash
   grep '^OPENAI_API_KEY=' /Users/uengine/process-gpt/.env | cut -d= -f2- | grep -qv '^dream-flow$' && echo has-key
   ```
   (키 값 자체는 절대 화면에 출력하지 말 것 — 존재 여부만 확인)
3. 실제 키가 있으면 **AskUserQuestion으로 OpenAI TTS 내레이션을 입힐지
   물어본다** (기본값: 예). 없으면 무음 영상만 남기거나, 사용자가 다른
   TTS 엔진/수동 자막을 지정하면 그에 맞춘다.

## 1. Playwright 녹화 (무음 원본)

브라우저 컨텍스트 생성 시 `recordVideo`를 켠다:

```javascript
const context = await browser.newContext({
  recordVideo: { dir: 'demo-recordings/<scenario-name>/raw', size: { width: 1920, height: 1080 } }
});
const page = await context.newPage();
const t0 = Date.now();  // 장면 타이밍 기준점
```

시나리오 문서(scenario-N-*.md)의 각 주요 단계를 진행하면서, 그 단계가
**실제로 시작되는 시점**을 `t0` 기준 초 단위로 기록해 둔다(다음 단계에서
쓸 `scenes-timing.json` 재료). 브라우저를 닫으면(`context.close()`) webm
파일이 `demo-recordings/<scenario-name>/raw/`에 생성된다 — 파일명을
`demo-raw.webm`으로 정리한다.

```json
// demo-recordings/<scenario-name>/scenes-timing.json
[
  { "scene": 1, "start_sec": 0.0 },
  { "scene": 2, "start_sec": 12.4 },
  { "scene": 3, "start_sec": 28.9 }
]
```

## 2. 내레이션 스크립트 작성 (에이전트가 직접 씀)

하드코딩된 대본이 아니라, **실제로 이번 데모 실행에서 벌어진 일**을
장면별로 짧게 서술한다(1~4문장, 한국어, 시연 톤). 시나리오 문서의 "데모 후
보고" 항목(생성된 proc_def id, 폼 필드, 활동 전이 등 실측값)을 그대로
녹여서 쓴다 — 매번 값이 달라지므로 재사용 가능한 고정 텍스트를 만들지
말 것.

```json
// demo-recordings/<scenario-name>/narration.json
[
  { "scene": 1, "text": "휴가 신청 프로세스를 채팅으로 생성합니다. 사원이 신청서를 쓰면 상사가 승인 또는 반려를 결정하는 분기를 명시적으로 요청했습니다." },
  { "scene": 2, "text": "생성된 프로세스 정의는 proc_def 테이블에 실제로 저장됩니다. 지금 화면에 보이는 BPMN 다이어그램이 그 결과입니다." }
]
```

## 3. TTS 합성

```bash
python3 .claude/skills/process-gpt-demo/scripts/gen_narration_openai.py \
  --script demo-recordings/<scenario-name>/narration.json \
  --out-dir demo-recordings/<scenario-name>/narration \
  --voice marin
```

- 기본 모델은 `gpt-4o-mini-tts`(실패 시 `tts-1-hd` 자동 폴백), voice
  기본값 `marin` — 온톨로지 매뉴얼 데모에서 검증된 조합. 다른 보이스를
  원하면 `--voice`로 바꾼다.
- 출력: `narration/scene-NN.wav` + `narration/durations.json`.

## 4. 합성 (무음 영상 + 나레이션 → 최종 mp4)

```bash
python3 .claude/skills/process-gpt-demo/scripts/assemble_narrated_video.py \
  --video demo-recordings/<scenario-name>/raw/demo-raw.webm \
  --timing demo-recordings/<scenario-name>/scenes-timing.json \
  --narration-dir demo-recordings/<scenario-name>/narration \
  --out demo-recordings/<scenario-name>-narrated.mp4
```

스크립트가 끝에 자체 검증까지 한다 — h264/aac 코덱 확인, 최종 길이,
`mean_volume`(-40dB 초과면 무음 아님)까지 찍고 `PASS`/`CHECK FAILED`를
출력한다. `CHECK FAILED`가 나오면 원인(코덱/무음/타이밍 오프)을 먼저
확인하고 사용자에게 보고 없이 넘어가지 않는다.

## 5. TTS를 안 쓰는 경우

키가 없거나 사용자가 원치 않으면 1번(무음 webm)까지만 하고, ffmpeg로
h264 mp4 변환만 해서 `demo-recordings/<scenario-name>.mp4`로 남긴다:

```bash
ffmpeg -y -i demo-recordings/<scenario-name>/raw/demo-raw.webm \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  demo-recordings/<scenario-name>.mp4
```

## 6. 데모 후 보고에 추가할 항목

- 최종 영상 경로(`demo-recordings/...`)와 길이
- 내레이션 유무 및 사용 voice/model
- `assemble_narrated_video.py`의 PASS/FAIL 결과
