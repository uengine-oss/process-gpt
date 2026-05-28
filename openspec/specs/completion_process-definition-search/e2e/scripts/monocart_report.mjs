// Merge raw V8 coverage JSON files into a Monocart browser report.
// Reads raw V8 dumps from results/frontend-coverage/raw/ (written by
// Playwright's page.coverage.startJSCoverage in the suite spec) and
// resolves byte ranges back through the Vite-built sourcemaps (dist/**/*.map)
// to original .vue / .ts / .js files under services/frontend/src/*.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { CoverageReport } from 'monocart-coverage-reports';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RAW = path.resolve(__dirname, '../results/frontend-coverage/raw');
const OUT = path.resolve(__dirname, '../results/frontend-coverage/monocart-report');

const report = new CoverageReport({
    name: 'completion_process-definition-search 프론트엔드 source-mapped 커버리지',
    outputDir: OUT,
    reports: [['v8'], ['v8-json'], ['console-summary']],
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
