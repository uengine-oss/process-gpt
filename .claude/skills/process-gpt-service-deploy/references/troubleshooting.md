# 운영에서 안 될 때

브라우저 콘솔·네트워크의 실패 요청을 먼저 본다. 응답 모양으로 어디서 막혔는지 가른다.

| 응답 | 뜻 | 볼 것 |
|---|---|---|
| `/<prefix>/` 가 ProcessGPT 화면(HTML 에 `window._env_`) | 게이트웨이가 옛 버전 | Argo CD 는 몇 분 간격이다. 새 게이트웨이에만 있는 응답으로 판별한다. vue3 CI |
| 게이트웨이 500 JSON(`{"path":"/<prefix>/…","status":500}`) | 라우트는 탔지만 Service 에 닿지 못함 | 파드 없음. 이미지 비공개·받기 실패, Service 이름·포트 |
| nginx 502(`error code: 502`) | 화면 파드는 있고 뒤 파드가 없음 | `Recreate` 교체 중, 또는 그 구성요소 미배포(`/lite/office/*` 의 편집기가 그랬다) |
| 524 | 100초 안에 응답 헤더가 없음 | 스트림 헤더를 바로 보내는지 |
| Cloudflare 오류 화면 | 서버의 502 가 가려짐 | 상위 실패를 503 으로 돌려주게 고친 뒤 사유를 본다 |
| 서비스 500, 화면이 빔 | 운영 DB 차이 | [lite.md](lite.md) 3장의 enum 확인. 화면 시작이 요청 하나에서 멈췄는지 |
| `workspace folder not found` 등 파일을 못 찾음 | 파드 간 디스크 | [SKILL.md](../SKILL.md) 의 표 |
| 로그인 없이 API 가 응답한다 | 게이트웨이가 그 경로를 검사하지 않음 | [new-service.md](new-service.md) 4장의 `protectedPaths` |
| 모든 데이터가 `localhost` 테넌트로 | 테넌트 헤더 | [new-service.md](new-service.md) 2장의 `X-Tenant-Id` |
| 예약이 안 돈다 | 콜백 불가 | `PRO_CRON_MODE=server` |
| 받아쓰기·LLM 401 | 공용 키 거절 | litellm-proxy 경유, 모델 제공 여부 |

운영 로그를 볼 수 없으면 추측으로 고치지 않는다. 운영 이미지를 같은 조건(빈 `/data` 등)으로 로컬에 띄워 재현하고, 재현하지 못한 원인은 "미확인"으로 보고한다.
