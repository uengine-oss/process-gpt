/**
 * 체크포인트 재개 기본화 e2e — 로컬 kind 클러스터(resume-e2e) + 로컬 Supabase + 실제 브라우저.
 *
 * 스펙: ../specs/{agent-sdk_workitem-resume-signal, deepagents_workitem-checkpoint-resume,
 *        cli-agent_workitem-session-resume, codex_workitem-resume}
 * 시나리오 문서: ./scenario.md
 *
 * 화면에서 사람이 하는 일(로그인, 프로세스 실행, 결과 확인, 피드백·답변)은 브라우저로 한다.
 * 화면이 보여 줄 수 없는 것(어느 파드가 집었는지, 도구가 몇 번 불렸는지)은 DB 와 kubectl 로 판정한다.
 * 크래시는 운영과 같은 방식으로 낸다: 파드 강제 삭제(deepagents, cli-agent) / 같은 파드에서 컨테이너
 * 프로세스만 SIGKILL(codex — emptyDir 유지).
 */
import { expect, test } from '@playwright/test';
import {
    agentTodo,
    events,
    expectResultShown,
    execIn,
    forceDeletePod,
    killContainerProcess,
    kubectl,
    login,
    openWorkItem,
    podLogs,
    podOf,
    podsOf,
    sql,
    startProcessFromUi,
    todoById,
    until
} from './helpers';

const MIN = 60_000;
const DONE = new Set(['COMPLETED', 'FAILED', 'HUMAN_ASKED', 'CANCELLED']);

async function claimed(procInstId: string) {
    return until('에이전트 작업이 점유된다', () => {
        const t = agentTodo(procInstId);
        return t && t.draft_status === 'STARTED' && t.consumer ? t : undefined;
    }, 3 * MIN);
}

async function finished(todoId: string, timeout = 10 * MIN) {
    return until('작업이 종결된다', () => {
        const t = todoById(todoId);
        return DONE.has(t.draft_status) ? t : undefined;
    }, timeout, 3000);
}

/** 재점유한 워커: claim_count=2 로 STARTED 인 동안의 consumer. */
async function reclaimedBy(todoId: string, timeout = 3 * MIN) {
    return until('다른 실행이 재점유한다(claim_count=2)', () => {
        const t = todoById(todoId);
        return t.claim_count >= 2 && t.consumer ? t : undefined;
    }, timeout, 500);
}

test.describe.configure({ mode: 'serial' });

test.beforeEach(async ({ page }) => {
    await login(page);
});

// ---------------------------------------------------------------------------
test('RS-3.2·RS-6.2 화면에서 초안을 반려하면 kind=revision 으로 저장되고 워커가 revision 으로 받는다', async ({ page }) => {
    const inst = await startProcessFromUi(page, 'resume_e2e_revision',
        '다음 주 화요일 오후 3시 2층 회의실에서 분기 실적 검토 회의를 연다. 참석자는 영업팀장·재무팀장·대표이사, 안건은 매출 목표 달성률과 비용 절감 방안이다.');
    const first = await claimed(inst);
    const draft = await finished(first.id);
    expect(draft.draft_status).toBe('COMPLETED');

    // 결과 화면(에이전트 모니터)에서 피드백을 보낸다
    await openWorkItem(page, first.id);
    const box = page.getByPlaceholder('메시지 입력').first();
    await box.fill('표 형식으로 다시 정리해 주세요. 열은 항목, 내용 두 개입니다.');
    await box.press('Enter');

    const [[kind, content]] = await until('feedback 에 반려가 저장된다', () => {
        const r = sql(`select feedback->-1->>'kind', feedback->-1->>'content' from todolist where id='${first.id}' and jsonb_array_length(coalesce(feedback,'[]'::jsonb))>0`);
        return r.length ? r : undefined;
    }, MIN);
    expect(kind).toBe('revision');
    expect(content).toContain('표 형식');

    const redo = await until('반려로 다시 집힌다', () => {
        const t = todoById(first.id);
        return t.draft_status === 'STARTED' && t.consumer ? t : undefined;
    }, 2 * MIN, 500);
    const done = await finished(first.id);
    expect(done.draft_status).toBe('COMPLETED');
    expect(podLogs(podOf(redo.consumer))).toContain('재개 사유: revision (점유 1회차)');
    const [[out]] = sql(`select draft::text from todolist where id='${first.id}'`);
    expect(out).toContain('|');   // 표로 다시 만들었다

    await openWorkItem(page, first.id);
    await expect(page.getByText(/항목\s*\|/).first()).toBeVisible({ timeout: 60_000 });
});

// ---------------------------------------------------------------------------
test('RE-1.1 deepagents — 도구 실행 중 파드가 죽어도 다른 파드가 마지막 체크포인트부터 잇고, 끝난 도구는 다시 부르지 않는다', async ({ page }) => {
    expect(podsOf('process-gpt-deepagents').length).toBeGreaterThanOrEqual(2);
    const inst = await startProcessFromUi(page, 'resume_e2e_deepagents', '분기 보고 자료 파일 세 개를 순서대로 만들어 주세요.');
    const todo = await claimed(inst);
    const victim = podOf(todo.consumer);

    // 1단계(step1.txt) 도구가 끝난 순간, 2단계가 끝나기 전에 그 파드를 죽인다
    await until('1단계 도구 완료', () => events(todo.id, 'tool_usage_finished').some((d) => d.includes('step1')), 5 * MIN, 300);
    expect(events(todo.id, 'tool_usage_finished').some((d) => d.includes('step2')), '2단계가 이미 끝나 크래시 지점을 놓쳤다').toBe(false);
    forceDeletePod(victim);

    const re = await reclaimedBy(todo.id);
    const rescuer = podOf(re.consumer);
    expect(rescuer).not.toBe(victim);
    const done = await finished(todo.id);
    expect(done.draft_status).toBe('COMPLETED');
    expect(done.claim_count).toBe(2);

    const log = podLogs(rescuer);
    expect(log).toContain('재개 사유: reclaim (점유 2회차)');
    expect(log).toContain('재점유 — 마지막 체크포인트부터 이어서 실행');
    // 완료된 1단계 도구는 전체 실행에서 한 번만 불렸다(어제 현재 코드: 재점유 시 3/3 재호출)
    const started = events(todo.id, 'tool_usage_started');
    expect(started.filter((d) => d.includes('step1')).length).toBe(1);
    expect(started.some((d) => d.includes('step3'))).toBe(true);

    await expectResultShown(page, todo.id, /step3/);
});

// ---------------------------------------------------------------------------
test('RE-1.3·RE-1.4 cli-agent — 실행 시작 직후 세션을 기록하고, 파드가 죽으면 새 파드가 그 세션으로 이어 step1 을 다시 하지 않는다', async ({ page }) => {
    const inst = await startProcessFromUi(page, 'resume_e2e_cli', '세 단계 기록 작업을 수행해 주세요.');
    const todo = await claimed(inst);
    const victim = podOf(todo.consumer);
    const ws = `/workspace/localhost/${todo.id}`;

    const before = await until('step1 기록', () => {
        const o = execIn(victim, `cat ${ws}/steps.log 2>/dev/null`);
        return o.includes('step1') ? o : undefined;
    }, 5 * MIN, 1000);
    const step1Line = before.split('\n').find((l) => l.startsWith('step1'))!;
    const saved = execIn(victim, `cat ${ws}/.processgpt-session.json`);
    const savedSession = JSON.parse(saved).session_id as string;
    expect(savedSession, '실행 중(완료 전)에 세션 ID 가 이미 기록돼 있다').toBeTruthy();
    expect(todoById(todo.id).draft_status).toBe('STARTED');
    forceDeletePod(victim);

    const re = await reclaimedBy(todo.id, 4 * MIN);
    const rescuer = podOf(re.consumer);
    expect(rescuer).not.toBe(victim);
    const done = await finished(todo.id);
    expect(done.draft_status).toBe('COMPLETED');

    expect(podLogs(rescuer)).toContain('재개 사유: reclaim (점유 2회차)');
    const steps = execIn(rescuer, `cat ${ws}/steps.log`);
    expect(steps.split('\n').filter((l) => l.startsWith('step1')).length, steps).toBe(1);
    expect(steps, 'kill 전에 기록된 step1 이 그대로 남아 있다(작업 공간이 새로 만들어지지 않았다)').toContain(step1Line);
    expect(steps).toContain('step3');
    // 재개 실행이 같은 세션을 이었다: 결과에 실린 세션 = 실행 시작 직후 기록한 세션
    const [[out]] = sql(`select coalesce(output::text, draft::text) from todolist where id='${todo.id}'`);
    expect(out).toContain(savedSession);

    await expectResultShown(page, todo.id, /step3/);
});

// ---------------------------------------------------------------------------
test('RE-1.6 codex — 같은 파드에서 프로세스가 죽었다 다시 뜨면 이어서 지시로 턴을 열어 step1 을 다시 하지 않는다', async ({ page }) => {
    const [pod] = podsOf('process-gpt-codex-worker');
    const restartsBefore = Number(kubectl('get', 'pod', pod, '-o', 'jsonpath={.status.containerStatuses[0].restartCount}'));
    const inst = await startProcessFromUi(page, 'resume_e2e_codex', '세 단계 기록 작업을 수행해 주세요.');
    const todo = await claimed(inst);
    expect(podOf(todo.consumer)).toBe(pod);

    // 작업 공간 = /app/.data/sessions/<tenant>/<대화 키(= 인스턴스 id)>
    const stepsFile = `/app/.data/sessions/localhost/${inst}/steps.log`;
    const before = await until('step1 기록', () => { const o = execIn(pod, `cat ${stepsFile} 2>/dev/null`); return o.includes('step1') ? o : undefined; }, 5 * MIN, 1000);
    const step1Line = before.split('\n').find((l) => l.startsWith('step1'))!;
    killContainerProcess(pod, 'codex');

    const re = await reclaimedBy(todo.id, 4 * MIN);
    expect(podOf(re.consumer)).toBe(pod);   // 같은 파드
    const done = await finished(todo.id);
    expect(done.draft_status).toBe('COMPLETED');
    expect(Number(kubectl('get', 'pod', pod, '-o', 'jsonpath={.status.containerStatuses[0].restartCount}'))).toBe(restartsBefore + 1);

    const log = execIn(pod, 'cat /app/.data/logs/server.log');
    expect(log).toContain('재개 사유: reclaim (점유 2회차)');
    const steps = execIn(pod, `cat ${stepsFile}`);
    expect(steps.split('\n').filter((l) => l.startsWith('step1')).length, steps).toBe(1);
    expect(steps, 'kill 전에 기록된 step1 이 그대로 남아 있다').toContain(step1Line);
    // 같은 thread 를 이었으면 이 대화의 rollout 은 하나다(새 thread 로 떨어지면 둘이 된다)
    const rollouts = execIn(pod, `find /app/.data/codex-homes/localhost/${inst} -name 'rollout-*.jsonl' | wc -l`);
    expect(rollouts.trim(), '재개 턴이 kill 전의 thread 를 이어받았다').toBe('1');
    expect(steps).toContain('step3');

    await expectResultShown(page, todo.id, /step3/);
});

// ---------------------------------------------------------------------------
test('RE-2.1·RS-6.1 cli-agent — 권한 때문에 멈추면 질문 카드에 답하고, 같은 세션으로 답 원문을 들고 이어 간다', async ({ page }) => {
    const inst = await startProcessFromUi(page, 'resume_e2e_cli_hitl', '승인 기록을 남겨 주세요.');
    const todo = await claimed(inst);
    const asked = await finished(todo.id, 5 * MIN);
    expect(asked.draft_status, 'cli-agent 가 사람에게 묻고 멈춘다(HUMAN_ASKED)').toBe('HUMAN_ASKED');
    const pod = podOf(todo.consumer);
    const pending = JSON.parse(execIn(podsOf('process-gpt-cli-agent')[0], `cat /workspace/localhost/${todo.id}/.processgpt-pending.json`));

    // 화면의 질문 카드에 답한다
    const answer = '허용합니다. 계속 진행하세요';
    await openWorkItem(page, todo.id);
    const card = page.locator('.human-query-input').last();
    await expect(card.locator('.query-question')).toContainText('requires approval', { timeout: 60_000 });
    await card.getByPlaceholder('답변을 입력하세요').fill(answer);
    await card.getByRole('button', { name: '확인' }).click();
    const [[kind]] = await until('feedback 에 답이 저장된다', () => {
        const r = sql(`select feedback->-1->>'kind' from todolist where id='${todo.id}' and draft_status::text<>'HUMAN_ASKED'`);
        return r.length ? r : undefined;
    }, MIN);
    expect(kind).toBe('human_answer');

    await finished(todo.id);
    const logs = podsOf('process-gpt-cli-agent').map((p) => podLogs(p)).join('\n');
    expect(logs).toContain('재개 사유: human_answer');
    const transcript = execIn(podsOf('process-gpt-cli-agent')[0], `grep -rl "${answer}" /workspace/localhost/${todo.id}/.agent-home 2>/dev/null | head -1`);
    expect(transcript, '답 원문이 멈춘 세션의 transcript 에 들어갔다').toContain(pending.session_id);
    expect(pod).toBeTruthy();
});

// ---------------------------------------------------------------------------
test('RE-4.1 deepagents — DB_* 가 설정됐는데 체크포인트 저장소에 붙을 수 없으면 기동하지 않는다', async () => {
    const name = 'deepagents-bad-checkpointer';
    kubectl('delete', 'pod', name, '--ignore-not-found', '--wait=true');
    const overrides = JSON.stringify({
        spec: {
            restartPolicy: 'Never',
            containers: [{
                name, image: 'pgpt-e2e/deepagents:e2e', imagePullPolicy: 'Never',
                envFrom: [{ configMapRef: { name: 'e2e-config' } }],
                env: [
                    { name: 'DB_PORT', value: '1' },              // 접속할 수 없는 포트
                    { name: 'DEEPAGENTS_PROCESS_POLLING', value: 'false' },
                    { name: 'DB_PASSWORD', value: 'x' }
                ]
            }]
        }
    });
    kubectl('run', name, '--image=pgpt-e2e/deepagents:e2e', '--restart=Never', `--overrides=${overrides}`);
    const phase = await until('파드가 끝난다', () => {
        const p = kubectl('get', 'pod', name, '-o', 'jsonpath={.status.phase}');
        return p === 'Failed' || p === 'Succeeded' ? p : undefined;
    }, 3 * MIN, 2000);
    const code = kubectl('get', 'pod', name, '-o', 'jsonpath={.status.containerStatuses[0].state.terminated.exitCode}');
    const log = podLogs(name);
    kubectl('delete', 'pod', name, '--wait=false');
    expect(phase).toBe('Failed');
    expect(code).toBe('1');
    expect(log).toContain('기동을 중단한다');
    expect(log).not.toContain('ProcessGPT Agent Server START');
});
