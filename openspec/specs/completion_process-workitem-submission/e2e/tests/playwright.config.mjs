// Playwright config for completion_process-workitem-submission.
// Runs against the Docker Compose stack via gateway-wis on :8090.
import { defineConfig, devices } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');

const baseURL = process.env.BASE_URL || 'http://localhost:8090';

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
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
    actionTimeout: 30_000,
    navigationTimeout: 60_000,
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
});
