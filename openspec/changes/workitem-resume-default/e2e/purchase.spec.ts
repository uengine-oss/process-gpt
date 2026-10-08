/**
 * 업무 시나리오 e2e — 구매 요청 처리(3 태스크)를 세 에이전트 서비스로 각각 끝까지 돌린다.
 *
 *   1. 구매 요청   — 사용자가 화면에서 제출(요청번호·요청자·품목·수량·예산·필요일·사유)
 *   2. 공급사 선정 — 에이전트: 비교표 작성 → 구매 대장(purchase_ledger.csv)에 한 줄 추가 → 선정 보고
 *   3. 발주서 작성 — 에이전트: 선정 결과로 발주서 작성 → 인스턴스 완료
 *
 * 2번에서 대장 줄이 써진 순간 그 실행을 죽인다(deepagents·cli-agent: 파드 삭제, codex: 같은 파드에서
 * 컨테이너 SIGKILL). 재점유한 실행이 2번을 마무리하고 3번까지 진행해 인스턴스가 완료되면,
 * 대장에 이 요청번호가 정확히 한 번 기록됐는지로 "완료된 단계를 다시 하지 않는다" 를 판정한다.
 *
 *   E2E_ORCH=deepagents|cli|codex npx playwright test purchase.spec.ts
 */
import { expect, test, type Page } from '@playwright/test';
import { events, execIn, forceDeletePod, killContainerProcess, login, podLogs, podOf, podsOf, sql, todoById, until } from './helpers';

const MIN = 60_000;
const ORCH = (process.env.E2E_ORCH || 'deepagents') as 'deepagents' | 'cli' | 'codex';
const DEF = `purchase_request_e2e_${ORCH}`;
const APP_LABEL = { deepagents: 'process-gpt-deepagents', cli: 'process-gpt-cli-agent', codex: 'process-gpt-codex-worker' }[ORCH];
const REQ = {
    no: `PR-${ORCH.toUpperCase()}-${Date.now().toString().slice(-6)}`,
    requester: '김민수',
    item: 'A4 복사용지(박스)',
    quantity: '40',
    budget: '500000',
    needBy: '2026-10-21',
    reason: '4분기 사무용품 정기 구매'
};

type Step = { id: string; status: string; draft_status: string; claim_count: number; consumer: string };
function step(inst: string, activity: string): Step | undefined {
    const r = sql(`select id, status, coalesce(draft_status::text,''), coalesce(claim_count,0), coalesce(consumer,'')
                   from todolist where proc_inst_id='${inst}' and activity_id='${activity}' order by start_date desc limit 1`);
    if (!r.length) return undefined;
    const [id, status, draft_status, claim, consumer] = r[0];
    return { id, status, draft_status, claim_count: Number(claim), consumer };
}
const stepDone = (inst: string, activity: string, timeout = 8 * MIN) =>
    until(`${activity} 종결`, () => {
        const t = step(inst, activity);
        return t && ['COMPLETED', 'FAILED', 'HUMAN_ASKED'].includes(t.draft_status) ? t : undefined;
    }, timeout, 2000);

/** 대장 파일(cli-agent: 작업 공간 PVC, codex: 대화 작업 공간)의 이 요청번호 줄. */
function ledgerFileLines(pod: string, inst: string, todoId: string): string[] {
    const path = ORCH === 'cli' ? `/workspace/localhost/${todoId}/purchase_ledger.csv` : `/app/.data/sessions/localhost/${inst}/purchase_ledger.csv`;
    return execIn(pod, `cat ${path} 2>/dev/null`).split('\n').filter((l) => l.startsWith(`${REQ.no},`));
}
/**
 * deepagents: 모델이 대장을 공유 PVC(/workspace → /app/workspace/<tenant>)에 쓰면 그 파일로 세고,
 * 파드별 샌드박스(/)에 쓰면 다른 파드에서 볼 수 없으니 "성공한" 쓰기 도구 호출로 센다.
 * deepagents 의 write_file 은 있는 파일을 덮어쓰지 않아 모델이 실패한 시도를 여러 번 하므로,
 * 결과가 Error 인 호출은 세지 않는다.
 */
function deepagentsLedgerFileLines(): string[] | undefined {
    const pod = podsOf(APP_LABEL)[0];
    const out = execIn(pod, `f=$(grep -rl --include=purchase_ledger.csv '${REQ.no},' /app/workspace 2>/dev/null); [ -n "$f" ] && cat $f`);
    return out ? out.split('\n').filter((l) => l.startsWith(`${REQ.no},`)) : undefined;
}
function ledgerWrites(todoId: string): string[] {
    return events(todoId, 'tool_usage_finished').filter((d) => {
        if (!d.includes('purchase_ledger') || !d.includes(`${REQ.no},`)) return false;
        const result = String((JSON.parse(d) as { result?: unknown }).result ?? '');
        return !/^(Error|bash: )/i.test(result.trim());
    });
}

async function submitRequest(page: Page): Promise<string> {
    await page.goto(`/definition-map/sub/${DEF}`, { waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: '실행', exact: true }).click();
    const submit = page.getByRole('button', { name: '제출 완료' });
    await expect(submit).toBeVisible({ timeout: 60_000 });
    // 실행 대화상자. 왼쪽 "역할 지정" 에도 '요청자' 칸이 있어 폼 쪽(.last())을 쓴다.
    const form = page.locator('.v-overlay__content').filter({ has: submit });
    const values: Record<string, string> = {
        요청번호: REQ.no, 요청자: REQ.requester, 품목: REQ.item, 수량: REQ.quantity,
        '예산(원)': REQ.budget, 필요일: REQ.needBy, '구매 사유': REQ.reason
    };
    for (const [label, v] of Object.entries(values)) await form.getByLabel(label, { exact: true }).last().fill(v);
    await submit.click();
    await page.waitForURL(/\/instancelist\//, { timeout: 60_000 });
    return decodeURIComponent(page.url()).match(/\/instancelist\/([^?]+)/)![1].replace(/_DOT_/g, '.');
}

test(`PUR ${ORCH} — 공급사 선정 중 대장 기록 직후 실행이 죽어도 대장은 한 번, 발주서까지 끝나 인스턴스 완료`, async ({ page }) => {
    test.setTimeout(30 * MIN);
    await login(page);
    const inst = await submitRequest(page);
    test.info().annotations.push({ type: 'instance', description: inst }, { type: 'request_no', description: REQ.no });

    // 2) 공급사 선정 — 대장 줄이 써진 순간 그 실행을 죽인다
    const sel = await until('공급사 선정 점유', () => {
        const t = step(inst, 'select_supplier');
        return t && t.draft_status === 'STARTED' && t.consumer ? t : undefined;
    }, 5 * MIN, 500);
    const victim = podOf(sel.consumer);
    await until('대장 기록', () =>
        ORCH === 'deepagents'
            ? ledgerWrites(sel.id).length > 0 || (deepagentsLedgerFileLines()?.length ?? 0) > 0
            : ledgerFileLines(victim, inst, sel.id).length > 0,
    6 * MIN, 300);
    expect(todoById(sel.id).draft_status, '대장 기록 뒤 아직 실행 중이어야 크래시 지점이 의미 있다').toBe('STARTED');
    if (ORCH === 'codex') killContainerProcess(victim, 'codex');
    else forceDeletePod(victim);

    const re = await until('재점유(claim_count=2)', () => {
        const t = todoById(sel.id);
        return t.claim_count >= 2 && t.consumer ? t : undefined;
    }, 4 * MIN, 500);
    const rescuer = podOf(re.consumer);
    if (ORCH === 'codex') expect(rescuer).toBe(victim);
    else expect(rescuer).not.toBe(victim);
    const selDone = await stepDone(inst, 'select_supplier');
    expect(selDone.draft_status, '공급사 선정이 끝난다').toBe('COMPLETED');
    expect(selDone.claim_count).toBe(2);
    const log = ORCH === 'codex' ? execIn(rescuer, 'cat /app/.data/logs/server.log') : podLogs(rescuer);
    expect(log).toContain('재개 사유: reclaim (점유 2회차)');

    // 업무 판정: 구매 대장에 이 요청번호가 정확히 한 번
    if (ORCH === 'deepagents') {
        const lines = deepagentsLedgerFileLines();
        if (lines) expect(lines.length, `대장 줄(PVC): ${JSON.stringify(lines)}`).toBe(1);
        else expect(ledgerWrites(sel.id).length, '대장을 쓴 성공한 도구 호출 수').toBe(1);
    } else {
        const pod = podsOf(APP_LABEL)[0];
        const lines = ledgerFileLines(pod, inst, sel.id);
        expect(lines.length, `대장 줄: ${JSON.stringify(lines)}`).toBe(1);
    }

    // 3) 발주서 작성 → 인스턴스 완료
    const order = await stepDone(inst, 'draft_purchase_order');
    expect(order.draft_status, '발주서 작성이 끝난다').toBe('COMPLETED');
    const [[orderOut]] = sql(`select coalesce(output::text, draft::text) from todolist where id='${order.id}'`);
    expect(orderOut).toContain(REQ.no);
    await until('인스턴스 완료', () => {
        const r = sql(`select status from bpm_proc_inst where proc_inst_id='${inst}'`);
        return r.length && r[0][0] === 'COMPLETED' ? true : undefined;
    }, 5 * MIN, 3000);

    // 화면: 발주서 작업이 완료로 표시되고, 완료된 작업은 결과를 표로 보여 준다
    await page.goto(`/todolist/${order.id}`, { waitUntil: 'domcontentloaded' });
    await expect(page.getByText('COMPLETED', { exact: true }).first()).toBeVisible({ timeout: 60_000 });
    await expect(page.locator('td, th').filter({ hasText: REQ.no }).first()).toBeVisible({ timeout: 60_000 });
});
