// Playwright config for the completion_process-definition-search E2E suite.
// Runs against the Docker Compose stack (docker-compose.e2e.yml) reached
// through the nginx gateway on :8088. All generated output lands under
// openspec/specs/completion_process-definition-search/e2e/results/.
import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.BASE_URL || 'http://localhost:8088';

export default defineConfig({
    testDir: '.',
    timeout: 240_000,
    expect: { timeout: 30_000 },
    fullyParallel: false,
    workers: 1,
    forbidOnly: !!process.env.CI,
    retries: 0,

    reporter: [
        ['json', { outputFile: '../results/results.json' }],
        ['html', { outputFolder: '../results/html-report', open: 'never' }],
        ['list'],
    ],

    outputDir: '../results/artifacts',

    use: {
        baseURL,
        trace: 'retain-on-failure',
        video: 'retain-on-failure',
        screenshot: 'only-on-failure',
        actionTimeout: 30_000,
        navigationTimeout: 60_000,
    },

    projects: [
        {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] },
        },
    ],
});
