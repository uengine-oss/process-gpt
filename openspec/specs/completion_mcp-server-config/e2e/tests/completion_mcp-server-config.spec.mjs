// E2E suite: completion_mcp-server-config
// Verifies the non-user-facing protocol contract for `GET /mcp-tools`
// served by services/completion through the in-repository request path
// (browser host -> nginx gateway :8088 -> completion FastAPI :8000).
// Per the User-Action Rule's carve-out for non-user-facing protocol
// tests, this suite drives both scenarios with Playwright's `request`
// API instead of browser UI clicks: the spec does not describe a UI
// workflow and no frontend page currently consumes /mcp-tools.
import { test, expect, request } from '@playwright/test';
import { execSync } from 'node:child_process';

const COMPLETION_CONTAINER =
    process.env.E2E_COMPLETION_CONTAINER || 'process-gpt-e2e-completion';
const MCP_PATH_IN_CONTAINER =
    process.env.E2E_MCP_PATH_IN_CONTAINER || '/usr/src/app/mcp.json';
const MCP_BACKUP_IN_CONTAINER =
    process.env.E2E_MCP_BACKUP_IN_CONTAINER || '/usr/src/app/mcp.json.e2e-backup';

function dockerExec(cmd) {
    return execSync(
        `docker exec ${COMPLETION_CONTAINER} sh -c ${JSON.stringify(cmd)}`,
        { stdio: ['ignore', 'pipe', 'pipe'] }
    ).toString();
}

async function fetchMcpTools(apiRequest) {
    return apiRequest.get('/completion/mcp-tools', {
        failOnStatusCode: false,
        headers: { Accept: 'application/json' },
    });
}

async function waitForBackendReady(apiRequest, expectedStatus = 200, attempts = 20) {
    for (let i = 0; i < attempts; i += 1) {
        try {
            const res = await fetchMcpTools(apiRequest);
            if (res.status() === expectedStatus) return res;
        } catch {
            // ignore
        }
        await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error(
        `gateway -> completion /mcp-tools did not return ${expectedStatus} after ${attempts} attempts`
    );
}

test.describe.serial('completion_mcp-server-config', () => {
    test('GET /mcp-tools 응답이 mcpServers 카탈로그를 반환한다', async ({
        request: apiRequest,
    }) => {
        const res = await fetchMcpTools(apiRequest);
        expect(res.status(), 'HTTP 상태 코드 200').toBe(200);

        const contentType = res.headers()['content-type'] || '';
        expect(contentType.toLowerCase()).toContain('application/json');

        const body = await res.json();
        expect(
            body && typeof body === 'object' && !Array.isArray(body),
            '응답 본문은 mcpServers 객체여야 한다'
        ).toBe(true);

        const keys = Object.keys(body);
        expect(keys.length, '카탈로그 항목이 1개 이상이어야 한다').toBeGreaterThan(0);

        // 모든 항목은 stdio(command+args) 또는 url(type+url+transport) 형식 중 하나여야 한다.
        const violations = [];
        let stdioCount = 0;
        let urlCount = 0;
        for (const [name, entry] of Object.entries(body)) {
            if (!entry || typeof entry !== 'object') {
                violations.push(`${name}: not an object`);
                continue;
            }
            const isStdio =
                typeof entry.command === 'string' && Array.isArray(entry.args);
            const isUrl =
                typeof entry.type === 'string' &&
                typeof entry.url === 'string' &&
                typeof entry.transport === 'string';
            if (isStdio) stdioCount += 1;
            else if (isUrl) urlCount += 1;
            else
                violations.push(
                    `${name}: 형식이 stdio(command+args)도 url(type+url+transport)도 아님`
                );
        }
        expect(violations, '모든 항목이 두 형식 중 하나에 부합해야 함').toEqual([]);
        expect(stdioCount, 'stdio 형식 항목이 최소 1개').toBeGreaterThan(0);
        expect(urlCount, 'URL 전송 형식 항목이 최소 1개').toBeGreaterThan(0);

        // spec.md에서 예시로 든 식별자가 보존되는지 점검 (mcp.json 변경 회귀 방지).
        expect(body.git, 'git stdio 항목 존재').toBeTruthy();
        expect(body.git.command).toBe('uvx');
        expect(body.gitmcp, 'gitmcp URL 항목 존재').toBeTruthy();
        expect(body.gitmcp.type).toBe('url');
        expect(body.gitmcp.transport).toBe('sse');
    });

    test('mcp.json 손상 시 404 Failed to load MCP config 응답을 반환한다', async ({
        request: apiRequest,
    }) => {
        // 0) 시작 전에 항상 정상 상태를 보장하기 위해 백업이 남아 있으면 먼저 복구
        try {
            dockerExec(
                `[ -f ${MCP_BACKUP_IN_CONTAINER} ] && mv -f ${MCP_BACKUP_IN_CONTAINER} ${MCP_PATH_IN_CONTAINER} || true`
            );
        } catch {
            // ignore
        }

        // 1) 원본 백업
        dockerExec(`cp ${MCP_PATH_IN_CONTAINER} ${MCP_BACKUP_IN_CONTAINER}`);

        try {
            // 2) 분기 A — JSON 손상
            dockerExec(
                `printf '%s' 'this-is-not-json' > ${MCP_PATH_IN_CONTAINER}`
            );
            let res = await fetchMcpTools(apiRequest);
            expect(
                res.status(),
                '손상된 JSON에 대해 404를 반환해야 한다'
            ).toBe(404);
            let body = await res.json();
            expect(typeof body.detail).toBe('string');
            expect(body.detail.startsWith('Failed to load MCP config')).toBe(
                true
            );

            // 3) 분기 B — 파일 부재
            dockerExec(
                `mv ${MCP_PATH_IN_CONTAINER} ${MCP_PATH_IN_CONTAINER}.missing`
            );
            res = await fetchMcpTools(apiRequest);
            expect(
                res.status(),
                '파일 부재에 대해 404를 반환해야 한다'
            ).toBe(404);
            body = await res.json();
            expect(typeof body.detail).toBe('string');
            expect(body.detail.startsWith('Failed to load MCP config')).toBe(
                true
            );
        } finally {
            // 4) 사후 정리 — 백업으로 원본 복구
            dockerExec(
                `rm -f ${MCP_PATH_IN_CONTAINER} ${MCP_PATH_IN_CONTAINER}.missing && mv -f ${MCP_BACKUP_IN_CONTAINER} ${MCP_PATH_IN_CONTAINER}`
            );
        }

        // 5) 복구 검증 — 다시 200이 돌아오는지 확인
        const finalRes = await waitForBackendReady(apiRequest, 200, 20);
        expect(finalRes.status()).toBe(200);
    });
});
