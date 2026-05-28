// Playwright config for completion_process-data-query.
// Runs against the Docker Compose stack (docker-compose.e2e.yml).
//
// Scenario 03 (real BPMN designer UI) hits the main app gateway on :8088;
// scenarios 01/02/04 are protocol-only and use absolute URLs configured in
// the spec (COMPLETION_DIRECT, MOCK_LLM_URL via gateway-pdq).
// All output lands under
// openspec/specs/completion_process-data-query/e2e/results/.
import { defineConfig, devices } from '@playwright/test';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS = path.resolve(__dirname, '../results');

const baseURL = process.env.BASE_URL || process.env.APP_BASE_URL || 'http://localhost:8088';

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
