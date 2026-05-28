// Non-user-facing protocol E2E for completion_notification-push-delivery.
//
// The spec's user-facing value (push delivery to a mobile device) lies
// outside the repository boundary. The repository contract is the FCM
// service REST endpoints + the polling worker. Evidence consists of
// HTTP responses, the captured FCM message JSONL written by
// firebase_patch.py, and DB state changes on `notifications.consumer`.
import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ARTIFACTS = path.resolve(__dirname, '../results/artifacts');
const CAPTURE_FILE = path.join(ARTIFACTS, 'fcm-captures/fcm-messages.jsonl');

const SUPABASE_REST = process.env.SUPABASE_REST_URL || 'http://localhost:54321/rest/v1';
const SERVICE_KEY = process.env.SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const SEEDED_USER = 'e2e-fcm-user@uengine.org';
const SEEDED_TOKEN = 'fake-device-token-e2e-001';
const SEEDED_NOTIFICATION_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001';

function ensureArtifacts() {
    fs.mkdirSync(ARTIFACTS, { recursive: true });
    fs.mkdirSync(path.dirname(CAPTURE_FILE), { recursive: true });
}

function readCaptureLines() {
    if (!fs.existsSync(CAPTURE_FILE)) return [];
    const raw = fs.readFileSync(CAPTURE_FILE, 'utf-8');
    return raw.split(/\r?\n/).filter(Boolean).map(line => JSON.parse(line));
}

function writeArtifact(name, data) {
    ensureArtifacts();
    fs.writeFileSync(path.join(ARTIFACTS, name), JSON.stringify(data, null, 2));
}

async function waitFor(predicate, { timeout = 30_000, interval = 1_000 } = {}) {
    const start = Date.now();
    let last;
    while (Date.now() - start < timeout) {
        try {
            const value = await predicate();
            if (value) return value;
            last = value;
        } catch (e) {
            last = e;
        }
        await new Promise(r => setTimeout(r, interval));
    }
    throw new Error(`waitFor timed out after ${timeout}ms (last=${JSON.stringify(last)})`);
}

test('FCM 서비스 헬스 엔드포인트는 정상 상태와 서비스 이름을 반환한다', async ({ request }) => {
    ensureArtifacts();
    const res = await request.get('/health');
    expect(res.status()).toBe(200);
    const body = await res.json();
    writeArtifact('01-health.json', body);
    expect(body).toEqual({ status: 'healthy', service: 'fcm-service' });
});

test('등록된 사용자는 device_token 을 반환하고 미등록 사용자는 빈 토큰을 반환한다', async ({ request }) => {
    const okRes = await request.get(`/device-token/${encodeURIComponent(SEEDED_USER)}`);
    expect(okRes.status()).toBe(200);
    const okBody = await okRes.json();

    const missingRes = await request.get('/device-token/unknown-fcm-user@uengine.org');
    expect(missingRes.status()).toBe(200);
    const missingBody = await missingRes.json();

    writeArtifact('02-device-token.json', { registered: okBody, unregistered: missingBody });

    expect(okBody).toEqual({ user_id: SEEDED_USER, device_token: SEEDED_TOKEN });
    expect(missingBody.user_id).toBe('unknown-fcm-user@uengine.org');
    // empty token may be null or empty string per spec
    expect([null, '', undefined]).toContain(missingBody.device_token);
});

test('POST /send-notification 은 발신자 제목·결합 본문·data 페이로드로 FCM 메시지를 구성한다', async ({ request }) => {
    const before = readCaptureLines().length;

    const payload = {
        user_id: SEEDED_USER,
        title: '워크아이템 검토 요청',
        body: '오늘까지 회신해주세요',
        type: 'workitem_bmp',
        url: '/todolist/123',
        from_user_id: '프로세스봇',
        data: { extra: 'ok' },
    };
    const res = await request.post('/send-notification', { data: payload });
    expect(res.status()).toBe(200);
    const body = await res.json();
    writeArtifact('03-send-notification-response.json', body);
    expect(body.success).toBe(true);
    expect(typeof body.message).toBe('string');

    const captured = await waitFor(() => {
        const lines = readCaptureLines();
        return lines.length > before ? lines[lines.length - 1] : null;
    }, { timeout: 10_000, interval: 500 });

    expect(captured.token).toBe(SEEDED_TOKEN);
    expect(captured.notification.title).toBe('프로세스봇');
    expect(captured.notification.body).toBe('오늘까지 회신해주세요\n워크아이템 검토 요청');
    expect(captured.data.type).toBe('workitem_bmp');
    expect(captured.data.url).toBe('/todolist/123');
    expect(captured.data.title).toBe('프로세스봇');
    expect(captured.data.body).toBe('오늘까지 회신해주세요\n워크아이템 검토 요청');
    expect(captured.data.extra).toBe('ok');
});

test('consumer 가 비어 있는 알림 행은 폴링 워커가 클레임하고 FCM 으로 전달한다', async ({ request }) => {
    test.setTimeout(90_000);

    // The seed sets consumer=NULL. Re-assert that as the starting state via
    // PostgREST to avoid relying on prior test isolation.
    const restHeaders = SERVICE_KEY
        ? { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` }
        : {};

    if (SERVICE_KEY) {
        const reset = await request.patch(
            `${SUPABASE_REST}/notifications?id=eq.${SEEDED_NOTIFICATION_ID}`,
            {
                headers: { ...restHeaders, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
                data: { consumer: null },
            },
        );
        expect([200, 204]).toContain(reset.status());
    }

    const beforeLines = readCaptureLines().length;

    const result = await waitFor(async () => {
        const captured = readCaptureLines();
        if (captured.length <= beforeLines) return null;
        const matches = captured.filter(
            (m) => m.data && m.data.notification_id === SEEDED_NOTIFICATION_ID,
        );
        if (!matches.length) return null;
        return { msg: matches[matches.length - 1], total: captured.length };
    }, { timeout: 60_000, interval: 1_500 });

    expect(result.msg.token).toBe(SEEDED_TOKEN);
    expect(result.msg.notification.title).toBe('프로세스봇');
    expect(result.msg.notification.body).toBe('담당 업무를 확인하세요\n새 워크아이템');
    expect(result.msg.data.type).toBe('workitem_bmp');
    // handle_new_notification rewrites url to full host form when tenant_id is set.
    expect(result.msg.data.url).toBe('https://e2e-fcm-tenant.process-gpt.io/todolist/abc');
    expect(result.msg.data.notification_id).toBe(SEEDED_NOTIFICATION_ID);

    let consumerSnapshot = null;
    if (SERVICE_KEY) {
        const snap = await request.get(
            `${SUPABASE_REST}/notifications?id=eq.${SEEDED_NOTIFICATION_ID}&select=id,consumer,user_id,tenant_id`,
            { headers: restHeaders },
        );
        if (snap.ok()) {
            const rows = await snap.json();
            consumerSnapshot = rows[0] || null;
            expect(consumerSnapshot.consumer).not.toBeNull();
        }
    }

    writeArtifact('04-consumer-claim.json', {
        captured: result.msg,
        notification: consumerSnapshot,
        note: SERVICE_KEY
            ? '실제 consumer 값은 fcm-service 워커의 hostname(pod id)입니다.'
            : 'SERVICE_ROLE_KEY 미설정으로 PostgREST 확인을 생략했습니다. FCM 캡처 도달만으로 폴링 클레임을 간접 검증합니다.',
    });
});
