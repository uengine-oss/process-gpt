"""Process GPT Lite 의 프로세스 마이닝 — GET /patterns · POST /discover 가 쓴다.

Lite 는 메일 한 통을 케이스 하나로 기록하고(handover_events.to_role · artifact_refs 포함),
반복 패턴을 찾아 추천한 뒤 정식 등록 때 자기 저장 경로로 정의를 만든다. 그 흐름이
기대하는 도출 규칙(활동 집합 유사도 묶음, 배타 분기의 기본 흐름, 단계의 역할·도구·스킬,
요청한 쪽 언어의 이름·설명)은 ProcessGPT 식별 화면의 도출(app.miner)과 다르게 발전했다.
그래서 이 패키지에 따로 둔다 — 식별 화면의 결과를 바꾸지 않고, Lite 의 결과도 바꾸지 않는다.

이 패키지도 DB 에 쓰지 않는다. 인증은 server.tenant_scope 를 그대로 거친다.
"""
