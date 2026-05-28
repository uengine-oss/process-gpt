// E2E suite: completion_callbot-task-management
// Exercises the real completion service callbot router
// (services/completion/callbot_api.py) through HTTP. The callbot is a
// non-user-facing voice protocol API (the consumer is a Twilio voice
// client), so this suite uses Playwright's `request` fixture rather
// than `page`. The Docker Compose stack provides the real database
// and completion service; only the `db-seed-callbot` one-shot seeds
// deterministic todolist/proc_def/form_def rows.
import { test, expect, request as plRequest } from '@playwright/test';

const CALLER_USER_ID = 'c5c11111-1111-1111-1111-111111111111';
const MISSING_USER_ID = '00000000-0000-0000-0000-000000000000';
const TODO_ROW_ID = 'cbe20001-0000-0000-0000-000000000001';
const IN_PROGRESS_ROW_ID = 'cbe20002-0000-0000-0000-000000000002';
const DONE_ROW_ID = 'cbe20003-0000-0000-0000-000000000003';
const PREV_TASK_ID = 'cbe30001-0000-0000-0000-000000000001';
const TARGET_TASK_ID = 'cbe30002-0000-0000-0000-000000000002';
const MISSING_TASK_ID = '00000000-0000-0000-0000-000000000000';

test.describe.configure({ mode: 'serial' });

test('발신자 식별: 등록 사용자와 익명 발신자에 대해 인사말을 반환한다', async ({ request }) => {
    // 1) 등록 사용자
    const okResp = await request.get(`/complete-callbot/caller-info?user_id=${CALLER_USER_ID}`);
    expect(okResp.status()).toBe(200);
    const ok = await okResp.json();
    expect(ok.success).toBe(true);
    expect(ok.username).toBe('콜봇테스트사용자');
    expect(ok.user_id).toBe(CALLER_USER_ID);
    expect(ok.email).toBe('callbot-e2e@uengine.org');
    expect(ok.tenant_id).toBe('localhost');
    expect(ok.greeting).toContain('콜봇테스트사용자');

    // 2) Anonymous → 하드코딩된 user_id 폴백 또는 기본 인사말
    const anonResp = await request.get('/complete-callbot/caller-info?from_number=client:Anonymous');
    expect(anonResp.status()).toBe(200);
    const anon = await anonResp.json();
    expect(anon.success).toBe(true);
    expect(typeof anon.greeting).toBe('string');
    expect(anon.greeting.length).toBeGreaterThan(0);

    // 3) 미존재 user_id → 200 + 기본 "고객" 인사말
    const guestResp = await request.get(`/complete-callbot/caller-info?user_id=${MISSING_USER_ID}`);
    expect(guestResp.status()).toBe(200);
    const guest = await guestResp.json();
    expect(guest.success).toBe(true);
    expect(guest.username).toBe('고객');
    expect(guest.greeting).toBe('고객님 안녕하세요');
});

test('사용자 할 일 목록 조회와 상태 필터/누락 처리', async ({ request }) => {
    // 1) /user-todolist
    const todoResp = await request.get(`/complete-callbot/user-todolist?user_id=${CALLER_USER_ID}`);
    expect(todoResp.status()).toBe(200);
    const todo = await todoResp.json();
    expect(todo.success).toBe(true);
    expect(Array.isArray(todo.items)).toBe(true);
    expect(todo.count).toBeGreaterThanOrEqual(2);
    for (const item of todo.items) {
        expect(item).toHaveProperty('id');
        expect(item).toHaveProperty('activity_name');
        expect(item).toHaveProperty('status');
    }

    // 2) /tasks?status_filter=active → TODO + IN_PROGRESS만, DONE 제외
    const activeResp = await request.get(
        `/complete-callbot/tasks?user_id=${CALLER_USER_ID}&status_filter=active`,
    );
    expect(activeResp.status()).toBe(200);
    const active = await activeResp.json();
    expect(active.success).toBe(true);
    expect(Array.isArray(active.tasks)).toBe(true);
    const activeIds = active.tasks.map((t) => t.id);
    expect(activeIds).toEqual(expect.arrayContaining([TODO_ROW_ID, IN_PROGRESS_ROW_ID]));
    expect(activeIds).not.toContain(DONE_ROW_ID);
    expect(typeof active.overdue_count).toBe('number');

    // 3) /tasks?status_filter=in_progress
    const inProgResp = await request.get(
        `/complete-callbot/tasks?user_id=${CALLER_USER_ID}&status_filter=in_progress`,
    );
    expect(inProgResp.status()).toBe(200);
    const inProg = await inProgResp.json();
    expect(inProg.success).toBe(true);
    const inProgIds = inProg.tasks.map((t) => t.id);
    expect(inProgIds).toContain(IN_PROGRESS_ROW_ID);
    expect(inProgIds).not.toContain(TODO_ROW_ID);

    // 4) /tasks without user_id → 422
    const missingResp = await request.get('/complete-callbot/tasks');
    expect(missingResp.status()).toBe(422);
});

test('작업 상세 조회: 폼 스키마와 참조 폼 / 미존재 시 404', async ({ request }) => {
    // 1) 성공: form_schema + reference_forms (inputData 필터링)
    const okResp = await request.get(`/complete-callbot/task/${TARGET_TASK_ID}`);
    expect(okResp.status()).toBe(200);
    const ok = await okResp.json();
    expect(ok.success).toBe(true);
    expect(ok.task.id).toBe(TARGET_TASK_ID);
    expect(ok.task.activity_name).toBe('콜봇 처리 대상');
    expect(ok.task.instruction).toContain('발신자');
    expect(Array.isArray(ok.task.checkpoints)).toBe(true);
    expect(ok.task.checkpoints).toEqual(expect.arrayContaining(['이름 확인', '연락처 확인']));

    expect(Array.isArray(ok.form_schema)).toBe(true);
    const fieldKeys = ok.form_schema.map((f) => f.key);
    expect(fieldKeys).toEqual(expect.arrayContaining(['customer_name', 'phone']));

    expect(Array.isArray(ok.reference_forms)).toBe(true);
    expect(ok.reference_forms.length).toBeGreaterThanOrEqual(1);
    const refForm = ok.reference_forms.find((r) => r.activity_id === 'act_prev');
    expect(refForm).toBeDefined();
    expect(refForm.data).toHaveProperty('prev_form');
    expect(refForm.data.prev_form.field_a).toBe('이전값');
    // inputData가 prev_form.field_a 만 명시했으므로 unrelated_form은 필터링되어 빠진다.
    expect(refForm.data).not.toHaveProperty('unrelated_form');

    // 2) 미존재 → 404
    const missResp = await request.get(`/complete-callbot/task/${MISSING_TASK_ID}`);
    expect(missResp.status()).toBe(404);
    const miss = await missResp.json();
    expect(JSON.stringify(miss)).toContain('Task not found');
});

test('작업 필드 수정: PATCH로 폼 데이터 병합', async ({ request }) => {
    // 1) 첫 PATCH: customer_name + phone (formHandler:target_form 자동 wrap)
    const r1 = await request.patch(`/complete-callbot/task/${TARGET_TASK_ID}`, {
        data: { customer_name: '홍길동', phone: '010-0000-0000' },
    });
    expect(r1.status()).toBe(200);
    const j1 = await r1.json();
    expect(j1.success).toBe(true);
    expect(j1.output).toHaveProperty('target_form');
    expect(j1.output.target_form.customer_name).toBe('홍길동');
    expect(j1.output.target_form.phone).toBe('010-0000-0000');

    // 2) 두 번째 PATCH: phone만 갱신 → customer_name은 보존되어야 함
    const r2 = await request.patch(`/complete-callbot/task/${TARGET_TASK_ID}`, {
        data: { phone: '010-1111-2222' },
    });
    expect(r2.status()).toBe(200);
    const j2 = await r2.json();
    expect(j2.success).toBe(true);
    expect(j2.output.target_form.customer_name).toBe('홍길동');
    expect(j2.output.target_form.phone).toBe('010-1111-2222');

    // 3) 최종 GET으로 한 번 더 확인
    const detail = await request.get(`/complete-callbot/task/${TARGET_TASK_ID}`);
    expect(detail.status()).toBe(200);
    const dj = await detail.json();
    expect(dj.current_data.target_form.customer_name).toBe('홍길동');
    expect(dj.current_data.target_form.phone).toBe('010-1111-2222');
});

test('작업 제출: 상태 SUBMITTED 전이로 폴링 대상 진입', async ({ request }) => {
    // 1) 제출 성공
    const okResp = await request.post(`/complete-callbot/task/${TARGET_TASK_ID}/submit`);
    expect(okResp.status()).toBe(200);
    const ok = await okResp.json();
    expect(ok.success).toBe(true);
    expect(ok.task_id).toBe(TARGET_TASK_ID);
    expect(ok.status).toBe('SUBMITTED');
    expect(ok.message).toContain('Polling service');

    // 2) GET으로 상태 재확인
    const detail = await request.get(`/complete-callbot/task/${TARGET_TASK_ID}`);
    expect(detail.status()).toBe(200);
    const dj = await detail.json();
    expect(dj.task.status).toBe('SUBMITTED');

    // 3) 미존재 task → 404
    const missResp = await request.post(`/complete-callbot/task/${MISSING_TASK_ID}/submit`);
    expect(missResp.status()).toBe(404);
    const miss = await missResp.json();
    expect(JSON.stringify(miss)).toContain('Task not found');
});
