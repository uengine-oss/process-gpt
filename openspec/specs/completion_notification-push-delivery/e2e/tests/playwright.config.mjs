// Playwright config for completion_notification-push-delivery.
//
// 두 종류의 테스트가 한 스위트에 공존한다:
//   1) fcm-protocol  — FCM 서비스 REST 엔드포인트(`:8666`) 직접 호출. 비-사용자-facing 프로토콜.
//   2) inapp-ui      — 실제 SPA(`gateway` :8088) 로 로그인하여 헤더 벨/드롭다운을 구동. 사용자-facing UI.
import { defineConfig } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');

const FCM_BASE_URL = process.env.FCM_BASE_URL || 'http://localhost:8666';
const FRONTEND_BASE_URL = process.env.FRONTEND_BASE_URL || 'http://localhost:8088';

export default defineConfig({
    testDir: '.',
    timeout: 180_000,
    expect: { timeout: 30_000 },
    fullyParallel: false,
    workers: 1,
    forbidOnly: !!process.env.CI,
    retries: 0,

    reporter: [
        ['json', { outputFile: path.join(RESULTS, 'results.json') }],
        ['html', { outputFolder: path.join(RESULTS, 'html-report'), open: 'never' }],
        ['list'],
    ],

    outputDir: path.join(RESULTS, 'artifacts'),

    use: {
        trace: 'retain-on-failure',
        actionTimeout: 30_000,
    },

    projects: [
        {
            name: 'fcm-protocol',
            testMatch: /completion_notification-push-delivery\.spec\.mjs$/,
            use: {
                baseURL: FCM_BASE_URL,
            },
        },
        {
            name: 'inapp-ui',
            testMatch: /notification-display\.spec\.mjs$/,
            use: {
                baseURL: FRONTEND_BASE_URL,
                viewport: { width: 1440, height: 900 },
            },
        },
    ],
});
