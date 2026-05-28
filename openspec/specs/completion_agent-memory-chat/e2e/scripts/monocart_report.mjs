// Merge raw V8 coverage JSON files into a Monocart browser report.
// The frontend is rebuilt from local repository source via
// openspec/specs/completion_agent-memory-chat/e2e/docker/frontend-coverage.override.yml
// so that Vite-generated sourcemaps (build.sourcemap: true) are served next
// to the bundle. Monocart resolves V8 ranges back through those sourcemaps
// to original .vue / .ts / .js files under services/frontend/src/* and emits
// source-file coverage rows alongside the bundle bytes report.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { CoverageReport } from 'monocart-coverage-reports';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAW = path.resolve(__dirname, '../results/frontend-coverage/raw');
const OUT = path.resolve(__dirname, '../results/frontend-coverage/monocart-report');

const report = new CoverageReport({
    name: 'completion_agent-memory-chat 프론트엔드 source-mapped 커버리지',
    outputDir: OUT,
    reports: [['v8'], ['v8-json'], ['console-summary']],
    // Resolve V8 coverage back through sourcemaps to original source files.
    // Keep both source rows (services/frontend/src/*) and bundle rows so the
    // report retains the historical bundle/V8 evidence while exposing the
    // source-mapped rows that the spec-coverage report consumes.
    sourceFilter: () => true,
    entryFilter: () => true,
    cleanCache: true,
});

const files = fs.readdirSync(RAW).filter((f) => f.endsWith('.json'));
let total = 0;
for (const f of files) {
    try {
        const raw = JSON.parse(fs.readFileSync(path.join(RAW, f), 'utf8'));
        if (Array.isArray(raw)) {
            await report.add(raw);
            total += raw.length;
        }
    } catch (e) {
        console.warn('skip', f, e.message);
    }
}

const summary = await report.generate();
console.log(`merged ${files.length} files / ${total} V8 entries`);
console.log('summary:', JSON.stringify(summary?.summary ?? summary, null, 2).slice(0, 800));
