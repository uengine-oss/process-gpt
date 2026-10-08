import { defineConfig } from '@playwright/test';

// 화면은 클러스터의 게이트웨이(./port-forward.sh → localhost:18088)로만 들어간다.
// 호스트 이름이 localhost 여야 화면이 테넌트 localhost 로 동작한다.
export default defineConfig({
    testDir: '.',
    testMatch: /.*\.spec\.ts/,
    // 시나리오는 같은 워커 풀(클러스터)을 공유하고 파드를 죽이므로 순서대로 하나씩 돈다.
    workers: 1,
    fullyParallel: false,
    retries: 0,
    timeout: 15 * 60_000,
    expect: { timeout: 30_000 },
    outputDir: 'test-results',
    reporter: [['list'], ['json', { outputFile: 'results/e2e-results.json' }]],
    use: {
        baseURL: process.env.E2E_BASE_URL || 'http://localhost:18088',
        viewport: { width: 1440, height: 900 },
        screenshot: 'on',
        video: 'retain-on-failure',
        trace: 'retain-on-failure',
        locale: 'ko-KR',
        actionTimeout: 30_000,
        navigationTimeout: 60_000
    }
});
