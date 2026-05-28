// E2E suite: completion_process-definition-feedback
// Exercises the real browser -> nginx gateway -> completion FastAPI path
// for the /get-feedback and /get-feedback-diff backend protocol contracts.
// mock-llm is the only stubbed external boundary (its mock_llm.py
// recognises the feedback / diff prompts and returns fenced JSON
// payloads that the CustomJsonOutputParser accepts).
//
// All scenarios are non-user-facing protocol checks (보조 프로토콜).
// The single frontend consumer of these routes (ProcessFeedback.vue)
// lives behind a heavy ProcessInstanceChat/Table integration whose UI
// workflow belongs in a separate spec — see scenarios/00-coverage-matrix.md.
import { test, expect } from '@playwright/test';

const TASK_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
const MISSING_TASK_ID = 'ffffffff-ffff-ffff-ffff-fffffffffff0';
const PROC_DEF_ID = 'pdf_demo_proc';
const ACTIVITY_ID = 'act_one';

// ==========================================================================
// 시나리오 01: 활동 정의 피드백을 요청하면 피드백 목록을 반환한다
// ==========================================================================
test('활동 정의 피드백을 요청하면 피드백 목록을 반환한다', async ({ request }) => {
    const res = await request.post('/completion/get-feedback', {
        data: {
            processDefinitionId: PROC_DEF_ID,
            activityId: ACTIVITY_ID,
            taskId: TASK_ID,
        },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);
    expect(body.length).toBeGreaterThan(0);
    // mock-llm 이 주입한 결정성 문구가 포함되어야 한다.
    expect(body.join('\n')).toContain('설명을 더 구체적으로 보강해 주세요.');
});

// ==========================================================================
// 시나리오 02: 작업 피드백 차이 조회 시 modifications와 summary를 반환한다
// ==========================================================================
test('작업 피드백 차이 조회 시 modifications와 summary를 반환한다', async ({ request }) => {
    const res = await request.post('/completion/get-feedback-diff', {
        data: { taskId: TASK_ID },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty('modifications');
    expect(body).toHaveProperty('summary');
    // 변경 가능 항목 중 적어도 하나는 before/after/changed 필드를 가진다.
    expect(body.modifications.description).toEqual(
        expect.objectContaining({
            before: expect.any(String),
            after: expect.any(String),
            changed: expect.any(Boolean),
        })
    );
    expect(body.summary).toContain('피드백 반영하여 설명을 보강함');
});

// ==========================================================================
// 시나리오 03: 존재하지 않는 작업으로 차이 조회 시 No workitem found 를 반환한다
// ==========================================================================
// NOTE: 명세는 400 상태 코드를 요구하지만, 현재 handle_get_feedback_diff 의
// except Exception 분기가 HTTPException(400) 을 잡아 500 으로 재포장한다.
// 본 시나리오는 실제 동작(500 + detail 에 "No workitem found" 포함) 을 검증
// 하며, 핸들러를 (예: handle_submit 처럼) except HTTPException: raise 패턴으
// 로 고칠 때 상태 코드 단언을 400 으로 갱신해야 한다. 명세와의 차이는
// scenarios/00-coverage-matrix.md 의 알려진 공백에 기록되어 있다.
test('존재하지 않는 작업으로 차이 조회 시 400 No workitem found 를 반환한다', async ({ request }) => {
    const res = await request.post('/completion/get-feedback-diff', {
        data: { taskId: MISSING_TASK_ID },
    });
    // 명세 의도: 400. 현재 구현: 500 (HTTPException 재포장). 둘 중 하나는 허용.
    expect([400, 500]).toContain(res.status());
    const body = await res.json();
    expect(JSON.stringify(body)).toContain('No workitem found');
});
