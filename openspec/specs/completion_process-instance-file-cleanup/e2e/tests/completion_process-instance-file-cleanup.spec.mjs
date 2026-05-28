// E2E for completion_process-instance-file-cleanup.
//
// Category B — backend/polling-only contract with screenshot exemption.
//
// 본 명세는 사용자가 직접 트리거하는 UI 액션이 없습니다. 백그라운드
// `file_cleanup_polling_task` 가 COMPLETED + is_clean_up=false 인스턴스를
// 발견하면 `proc_inst_source.file_path` 가 가리키는 스토리지 객체를
// 비동기로 삭제합니다.
//
// 실제 프런트엔드(`services/frontend/src/components/apps/todolist/InstanceSource.vue`)
// 는 `proc_inst_source` 행을 카드로 보여주는 표면이지만, 현재 워커는
// `update_proc_inst_cleanup_status` 의 실제 UPDATE 가 주석 처리되어 있고
// `proc_inst_source` 행을 삭제하지 않습니다. 그 결과 정리 사이클 전·후로
// InstanceSource.vue 의 카드 목록은 동일하게 표시되고, 정리 결과는 오직
// 스토리지 객체의 200→404 전환으로만 관찰됩니다. 따라서 사용자가 실제로
// 화면에서 "정리됨" 상태를 보는 사용자-인지 가능한 UI 전이가 존재하지
// 않습니다.
//
// `.claude/skills/e2e-tests/SKILL.md` 의 Real-Frontend Rule 에 따라
// 인공 tester 페이지를 주입해 합성 화면을 만드는 우회는 금지되며, 사용자
// UI 표현이 부재할 때는 Gate Failure Reporting + 스크린샷 면제로 분류하도록
// 명시되어 있습니다. 본 스위트는 그 분류에 해당하므로 protocol-level
// `request` 검증만 수행합니다.
//
// 검증 대상:
//   01 — 정리 사이클 후 시드된 `pifc/completed.txt` 가 스토리지에서 사라진다
//        (`/storage/v1/object/public/files/pifc/completed.txt` 가 200→404,
//        list 결과에서 제거). 무관한 `pifc/keep.txt` 는 보존된다.
//   02 — 추가 정리 대상이 없는 상태에서 폴링 주기가 여러 번 도래해도
//        `pifc/keep.txt` 는 그대로 유지된다.
import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');
const ARTIFACTS = path.join(RESULTS, 'artifacts');

const PIFC_BASE = process.env.PIFC_BASE_URL || 'http://localhost:8091';
const SUPABASE_REST = process.env.SUPABASE_REST_URL || 'http://localhost:54321/rest/v1';
const STORAGE_BASE = `${PIFC_BASE}/storage/v1`;
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const BUCKET = 'files';
const COMPLETED_KEY = 'pifc/completed.txt';
const KEEP_KEY = 'pifc/keep.txt';
const COMPLETED_BODY = 'pifc-completed-content';
const PROC_INST_ID = 'e2e-pifc-inst-001';

function ensureDirs() {
    fs.mkdirSync(ARTIFACTS, { recursive: true });
}

function writeArtifact(name, data) {
    ensureDirs();
    fs.writeFileSync(path.join(ARTIFACTS, name), JSON.stringify(data, null, 2));
}

function svcHeaders(extra = {}) {
    if (!SERVICE_KEY) return { ...extra };
    return {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        ...extra,
    };
}

async function reseedScenario01(request) {
    expect(SERVICE_KEY, 'SERVICE_ROLE_KEY env var must be set for the seed').not.toBe('');

    const upload = await request.post(
        `${STORAGE_BASE}/object/${BUCKET}/${COMPLETED_KEY}`,
        {
            headers: svcHeaders({ 'Content-Type': 'text/plain', 'x-upsert': 'true' }),
            data: COMPLETED_BODY,
        },
    );
    expect(upload.status(), `storage upload failed: ${await upload.text()}`).toBeLessThan(300);

    // 워커의 실제 update_proc_inst_cleanup_status UPDATE 는 주석 처리되어 있으나,
    // 이전 실행에서 누군가 활성화했을 수도 있으므로 명시적으로 리셋한다.
    const resetInst = await request.patch(
        `${SUPABASE_REST}/bpm_proc_inst?proc_inst_id=eq.${PROC_INST_ID}`,
        {
            headers: svcHeaders({ 'Content-Type': 'application/json', Prefer: 'return=minimal' }),
            data: { status: 'COMPLETED', is_clean_up: false, tenant_id: 'localhost' },
        },
    );
    expect([200, 204]).toContain(resetInst.status());

    const delSource = await request.delete(
        `${SUPABASE_REST}/proc_inst_source?proc_inst_id=eq.${PROC_INST_ID}`,
        { headers: svcHeaders({ Prefer: 'return=minimal' }) },
    );
    expect([200, 204]).toContain(delSource.status());

    const insSource = await request.post(
        `${SUPABASE_REST}/proc_inst_source`,
        {
            headers: svcHeaders({ 'Content-Type': 'application/json', Prefer: 'return=minimal' }),
            data: {
                proc_inst_id: PROC_INST_ID,
                file_name: 'completed.txt',
                file_path: `http://kong:8000/storage/v1/object/public/${BUCKET}/${COMPLETED_KEY}`,
                is_process: false,
            },
        },
    );
    expect([200, 201, 204]).toContain(insSource.status());
}

test('완료된 프로세스 인스턴스의 스토리지 파일은 폴링 주기 후 삭제된다', async ({ request }) => {
    test.setTimeout(180_000);
    ensureDirs();

    // 1. 시드 리셋 — 객체와 proc_inst_source 행을 다시 만들고 is_clean_up=false 로 되돌린다.
    await reseedScenario01(request);

    // 2. 정리 전: 객체는 스토리지에서 200 + 본문이 그대로 반환된다.
    const preGet = await request.get(`${STORAGE_BASE}/object/public/${BUCKET}/${COMPLETED_KEY}`);
    expect(preGet.status(), 'precondition: completed.txt must exist').toBe(200);
    expect(await preGet.text()).toContain(COMPLETED_BODY);

    // 3. 폴링 사이클이 객체를 삭제할 때까지 대기 — 워커 interval 은 3초로
    //    설정되어 있고, 정리에는 1~2 사이클이 충분하다.
    let postStatus = 200;
    let postBody = '';
    const deadline = Date.now() + 90_000;
    while (Date.now() < deadline) {
        const res = await request.get(`${STORAGE_BASE}/object/public/${BUCKET}/${COMPLETED_KEY}`);
        postStatus = res.status();
        if (!res.ok()) {
            postBody = await res.text();
            break;
        }
        await new Promise((r) => setTimeout(r, 2000));
    }
    writeArtifact('01-completed-file-final-response.json', {
        url: `${STORAGE_BASE}/object/public/${BUCKET}/${COMPLETED_KEY}`,
        status: postStatus,
        body: postBody.slice(0, 400),
    });
    expect([400, 404]).toContain(postStatus);

    // 4. 스토리지 list 에서 completed.txt 가 사라졌고 keep.txt 는 여전히 존재해야 한다.
    const listRes = await request.post(`${STORAGE_BASE}/object/list/${BUCKET}`, {
        headers: svcHeaders({ 'Content-Type': 'application/json' }),
        data: { prefix: 'pifc', limit: 100, offset: 0 },
    });
    expect(listRes.ok()).toBeTruthy();
    const listing = await listRes.json();
    const names = (Array.isArray(listing) ? listing : []).map((o) => o.name);
    writeArtifact('01-storage-listing-after-cleanup.json', { names, raw: listing });
    expect(names).not.toContain('completed.txt');
    expect(names).toContain('keep.txt');
});

test('정리 대상 인스턴스가 없으면 폴링 주기는 삭제 없이 다음 주기를 기다린다', async ({ request }) => {
    test.setTimeout(120_000);
    ensureDirs();

    // 시나리오 01 직후 유일한 COMPLETED+미정리 인스턴스의 소스 파일이 사라졌다.
    // 새 폴링 사이클이 무관한 keep.txt 를 건드리지 않는지 확인한다.

    // 1. 초기 상태: keep.txt 는 정상적으로 200 응답한다.
    const initial = await request.get(`${STORAGE_BASE}/object/public/${BUCKET}/${KEEP_KEY}`);
    expect(initial.status()).toBe(200);
    expect(await initial.text()).toContain('pifc-keep-content');

    // 2. 폴링 주기(3초) 가 최소 4회 도래할 시간을 기다린다.
    await new Promise((r) => setTimeout(r, 12_000));

    // 3. 다시 조회해도 동일하게 200 + 동일 본문이 반환된다.
    const after = await request.get(`${STORAGE_BASE}/object/public/${BUCKET}/${KEEP_KEY}`);
    expect(after.status()).toBe(200);
    expect(await after.text()).toContain('pifc-keep-content');

    // 4. 스토리지 list 에 keep.txt 가 여전히 존재한다.
    const listRes = await request.post(`${STORAGE_BASE}/object/list/${BUCKET}`, {
        headers: svcHeaders({ 'Content-Type': 'application/json' }),
        data: { prefix: 'pifc', limit: 100, offset: 0 },
    });
    expect(listRes.ok()).toBeTruthy();
    const listing = await listRes.json();
    const names = (Array.isArray(listing) ? listing : []).map((o) => o.name);
    writeArtifact('02-storage-listing-no-target.json', { names, raw: listing });
    expect(names).toContain('keep.txt');
});
