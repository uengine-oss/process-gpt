/**
 * e2e 도우미 — 화면 조작은 Playwright, 판정은 DB(로컬 Supabase)와 클러스터(kubectl)로 한다.
 */
import { expect, type Page } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import path from 'node:path';

export const NS = 'resume-e2e';
export const CTX = 'kind-kind';
const DB_CONTAINER = process.env.SB_DB_CONTAINER || 'supabase_db_process-gpt-vue3';

export function sh(cmd: string, args: string[], input?: string): string {
    return execFileSync(cmd, args, { encoding: 'utf8', input, maxBuffer: 64 * 1024 * 1024 }).trim();
}

/** 한 줄 = 한 행, 칸은 '\t'. */
export function sql(query: string): string[][] {
    const out = sh('docker', ['exec', '-i', DB_CONTAINER, 'psql', '-U', 'postgres', '-qtAX', '-F', '\t', '-v', 'ON_ERROR_STOP=1'], query);
    return out ? out.split('\n').map((l) => l.split('\t')) : [];
}

export function kubectl(...args: string[]): string {
    return sh('kubectl', ['--context', CTX, '-n', NS, ...args]);
}

export function podLogs(pod: string, opts: { previous?: boolean } = {}): string {
    try {
        return kubectl('logs', pod, ...(opts.previous ? ['--previous'] : []));
    } catch {
        return '';
    }
}

export function podsOf(app: string): string[] {
    return kubectl('get', 'pods', '-l', `app=${app}`, '--field-selector=status.phase=Running', '-o', 'jsonpath={.items[*].metadata.name}')
        .split(/\s+/)
        .filter(Boolean);
}

export async function until<T>(what: string, fn: () => T | undefined | null | false, timeoutMs: number, everyMs = 1000): Promise<T> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
        const v = fn();
        if (v) return v as T;
        if (Date.now() > deadline) throw new Error(`시간 초과: ${what}`);
        await new Promise((r) => setTimeout(r, everyMs));
    }
}

export type Todo = { id: string; status: string; draft_status: string; claim_count: number; consumer: string; proc_inst_id: string };

export function agentTodo(procInstId: string): Todo | undefined {
    const rows = sql(`select id, status, coalesce(draft_status::text,''), coalesce(claim_count,0), coalesce(consumer,''), proc_inst_id
                      from todolist where proc_inst_id='${procInstId}' and activity_id='agent_task' order by start_date desc limit 1`);
    if (!rows.length) return undefined;
    const [id, status, draft_status, claim, consumer, proc_inst_id] = rows[0];
    return { id, status, draft_status, claim_count: Number(claim), consumer, proc_inst_id };
}

export function todoById(id: string): Todo {
    const [[tid, status, draft_status, claim, consumer, proc_inst_id]] = sql(
        `select id, status, coalesce(draft_status::text,''), coalesce(claim_count,0), coalesce(consumer,''), proc_inst_id from todolist where id='${id}'`
    );
    return { id: tid, status, draft_status, claim_count: Number(claim), consumer, proc_inst_id };
}

export function events(todoId: string, type: string): string[] {
    return sql(`select data::text from events where todo_id::text='${todoId}' and event_type::text='${type}' order by timestamp`).map((r) => r[0]);
}

/** consumer 값 "<pod>:<n>" 의 파드 이름. */
export const podOf = (consumer: string) => consumer.split(':')[0];

export const credentials = (): { email: string; password: string } =>
    JSON.parse(readFileSync(path.join(__dirname, '.e2e-credentials.json'), 'utf8'));

export async function login(page: Page) {
    const { email, password } = credentials();
    await page.goto('/auth/login', { waitUntil: 'domcontentloaded' });
    await page.locator('.cp-id input').fill(email);
    await page.locator('.cp-pwd input').fill(password);
    await page.locator('.cp-login').click();
    await expect(page).not.toHaveURL(/\/auth\/login/, { timeout: 60_000 });
}

/**
 * 정의 체계도의 프로세스 상세에서 "실행" → 요청 입력 → "제출 완료".
 * 반환: 새 프로세스 인스턴스 id(화면이 이동한 인스턴스 주소에서 읽는다).
 */
export async function startProcessFromUi(page: Page, procDefId: string, request: string): Promise<string> {
    await page.goto(`/definition-map/sub/${procDefId}`, { waitUntil: 'domcontentloaded' });
    await page.getByRole('button', { name: '실행', exact: true }).click();
    const submit = page.getByRole('button', { name: '제출 완료' });
    await expect(submit).toBeVisible({ timeout: 60_000 });
    const field = page.locator('.v-overlay__content textarea').first();
    await expect(field).toBeVisible();
    await field.fill(request);
    await submit.click();
    await page.waitForURL(/\/instancelist\//, { timeout: 60_000 });
    const m = decodeURIComponent(page.url()).match(/\/instancelist\/([^?]+)/);
    expect(m, page.url()).toBeTruthy();
    return m![1].replace(/_DOT_/g, '.');
}

/** 작업 화면을 열어 에이전트 모니터에 결과(또는 문구)가 보이는지 본다. */
export async function openWorkItem(page: Page, todoId: string) {
    await page.goto(`/todolist/${todoId}`, { waitUntil: 'domcontentloaded' });
    await expect(page.getByText('에이전트 수행').first()).toBeVisible({ timeout: 60_000 });
}

/** kind 노드에서 컨테이너의 메인 프로세스만 SIGKILL — 파드와 emptyDir 는 남고 컨테이너만 다시 뜬다. */
export function killContainerProcess(pod: string, container: string) {
    const id = sh('docker', ['exec', 'kind-control-plane', 'crictl', 'ps', '-q', '--name', `^${container}$`, '--pod',
        sh('docker', ['exec', 'kind-control-plane', 'crictl', 'pods', '-q', '--name', pod])]);
    const pid = sh('docker', ['exec', 'kind-control-plane', 'crictl', 'inspect', '-o', 'go-template', '--template', '{{.info.pid}}', id]);
    expect(Number(pid)).toBeGreaterThan(1);
    sh('docker', ['exec', 'kind-control-plane', 'kill', '-9', pid]);
}

/** 파드 강제 삭제 — 파드 사망. 같은 PVC 를 쓰는 새 파드가 뜬다. */
export function forceDeletePod(pod: string) {
    kubectl('delete', 'pod', pod, '--grace-period=0', '--force', '--wait=false');
}

export function execIn(pod: string, script: string): string {
    try {
        return kubectl('exec', pod, '--', 'sh', '-c', script);
    } catch {
        return '';
    }
}

/** 작업 화면의 "수행 결과" 폼에 결과가 채워져 보이는가(값은 textarea 의 value 라 getByText 로는 안 잡힌다). */
export async function expectResultShown(page: Page, todoId: string, pattern: RegExp) {
    await openWorkItem(page, todoId);
    await expect
        .poll(async () => (await page.locator('textarea').evaluateAll((els) => els.map((e) => (e as HTMLTextAreaElement).value))).join('\n'),
            { timeout: 60_000, message: '수행 결과 폼에 결과가 보인다' })
        .toMatch(pattern);
}
