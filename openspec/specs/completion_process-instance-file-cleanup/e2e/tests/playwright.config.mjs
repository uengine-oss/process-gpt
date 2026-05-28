// Playwright config for completion_process-instance-file-cleanup.
// User-facing scenarios browse storage URLs through the spec-local
// gateway-pifc (host :8091), backed by a real supabase storage container
// and a polling worker that runs ONLY file_cleanup_polling_task.
import { defineConfig } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');

const baseURL = process.env.PIFC_BASE_URL || 'http://localhost:8091';

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
        baseURL,
        trace: 'retain-on-failure',
        actionTimeout: 30_000,
        viewport: { width: 1280, height: 800 },
        screenshot: 'only-on-failure',
    },

    projects: [
        {
            name: 'pifc',
            use: {},
        },
    ],
});
