// Playwright config for the completion_callbot-task-management suite.
// Runs HTTP-only protocol tests against the Docker Compose completion
// service. The callbot API is a non-user-facing protocol API (the voice
// callbot client is the consumer), so this suite uses the `request`
// fixture rather than `page` to drive scenarios. No frontend is involved.
import { defineConfig } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');

const baseURL = process.env.CALLBOT_BASE_URL || 'http://localhost:8000';

export default defineConfig({
    testDir: '.',
    timeout: 60_000,
    expect: { timeout: 15_000 },
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
        baseURL,
        trace: 'retain-on-failure',
        actionTimeout: 15_000,
    },
});
