#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

function parseArgs(argv) {
  const args = {
    suite: '',
    suiteRoot: '',
    spec: '',
    output: '',
    writeSummary: false,
    allowMissingResults: false
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--suite') args.suite = argv[++i] || '';
    else if (arg === '--suite-root') args.suiteRoot = argv[++i] || '';
    else if (arg === '--spec') args.spec = argv[++i] || '';
    else if (arg === '--output') args.output = argv[++i] || '';
    else if (arg === '--write-summary') args.writeSummary = true;
    else if (arg === '--allow-missing-results') args.allowMissingResults = true;
    else if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    }
  }

  if (!args.suite || !args.suiteRoot) {
    printUsage();
    process.exit(2);
  }

  return args;
}

function printUsage() {
  console.log(`Usage:
  node .claude/skills/e2e-tests/scripts/evaluate_spec_coverage.mjs \\
    --suite <suite-slug> \\
    --suite-root openspec/specs/<spec-name>/e2e \\
    [--spec openspec/specs/<spec-name>/spec.md] \\
    [--output openspec/specs/<spec-name>/e2e/results/coverage-summary.json] \\
    [--write-summary] \\
    [--allow-missing-results]

Checks OpenSpec Requirement/Scenario traceability against the E2E coverage matrix,
Playwright test declarations, Playwright results, and screenshot evidence.`);
}

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function readJson(file) {
  return JSON.parse(readText(file));
}

function normalize(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function ensureFile(file, label, errors) {
  if (!fs.existsSync(file)) {
    errors.push(`missing ${label}: ${file}`);
    return false;
  }
  return true;
}

function parseSpec(text) {
  const requirements = [];
  let currentRequirement = null;

  for (const line of text.split(/\r?\n/)) {
    const requirement = line.match(/^### Requirement:\s*(.+)$/);
    if (requirement) {
      currentRequirement = normalize(requirement[1]);
      requirements.push({ name: currentRequirement, scenarios: [] });
      continue;
    }

    const scenario = line.match(/^#### Scenario:\s*(.+)$/);
    if (scenario && currentRequirement) {
      requirements.at(-1).scenarios.push(normalize(scenario[1]));
    }
  }

  return requirements;
}

function splitMarkdownRow(line) {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map((cell) => normalize(cell.replace(/`/g, '')));
}

function tableRowsAfterHeading(text, heading) {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === heading);
  if (start === -1) return [];

  const rows = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.startsWith('## ') && rows.length > 0) break;
    if (!line.trim().startsWith('|')) continue;
    if (/^\|\s*-+/.test(line)) continue;
    rows.push(splitMarkdownRow(line));
  }

  return rows.slice(1);
}

function parseTestTitles(text) {
  const titles = [];
  const regex = /\btest\s*\(\s*(['"`])([\s\S]*?)\1\s*,/g;
  let match;
  while ((match = regex.exec(text))) {
    titles.push(normalize(match[2].replace(/\s*@allure\.[^\s]+/g, '')));
  }
  return titles;
}

function collectResultSpecs(suites, acc = []) {
  for (const suiteItem of suites || []) {
    for (const spec of suiteItem.specs || []) {
      acc.push({
        title: normalize(spec.title),
        ok: Boolean(spec.ok),
        tests: spec.tests || []
      });
    }
    collectResultSpecs(suiteItem.suites, acc);
  }
  return acc;
}

function collectScreenshotPaths(text) {
  const paths = new Set();
  const regex = /`([^`]*results\/screenshots\/[^`]+\.png)`/g;
  let match;
  while ((match = regex.exec(text))) {
    paths.add(match[1].replaceAll('/', path.sep));
  }
  return [...paths];
}

function ratio(covered, total) {
  if (total === 0) return 100;
  return Number(((covered / total) * 100).toFixed(2));
}

function averageCoveragePercent(items) {
  const applicable = items.filter((item) => item.coveragePercent !== null && item.coveragePercent !== undefined);
  if (applicable.length === 0) return 100;
  const total = applicable.reduce((sum, item) => sum + Number(item.coveragePercent || 0), 0);
  return Number((total / applicable.length).toFixed(2));
}

function loadExistingSummary(outputPath) {
  if (!fs.existsSync(outputPath)) return {};
  try {
    return readJson(outputPath);
  } catch {
    return {};
  }
}

function coverageSection(existingSection) {
  const files = existingSection?.files || [];
  return {
    ...(existingSection || {}),
    files,
    coveragePercent: files.length > 0
      ? (existingSection.coveragePercent ?? averageCoveragePercent(files))
      : null
  };
}

function overallCoveragePercent(sections) {
  const values = sections
    .map((section) => section?.coveragePercent)
    .filter((value) => typeof value === 'number' && Number.isFinite(value));
  if (values.length === 0) return null;
  return Number((values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(2));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = process.cwd();
  const suiteRoot = path.resolve(root, args.suiteRoot);
  const specPath = path.resolve(root, args.spec || path.join(args.suiteRoot, '..', 'spec.md'));
  const scenarioDir = path.join(suiteRoot, 'scenarios');
  const resultDir = path.join(suiteRoot, 'results');
  const matrixPath = path.join(scenarioDir, '00-coverage-matrix.md');
  const summaryPath = path.join(scenarioDir, 'execution-summary.md');
  const testPath = path.join(suiteRoot, 'tests', `${args.suite}.spec.mjs`);
  const resultsPath = path.join(resultDir, 'results.json');
  const outputPath = path.resolve(root, args.output || path.join(args.suiteRoot, 'results', 'coverage-summary.json'));

  const errors = [];
  ensureFile(specPath, 'OpenSpec spec', errors);
  ensureFile(matrixPath, 'coverage matrix', errors);
  ensureFile(summaryPath, 'execution summary', errors);
  ensureFile(testPath, 'Playwright spec', errors);
  if (!args.allowMissingResults) ensureFile(resultsPath, 'Playwright results.json', errors);

  if (errors.length > 0) {
    for (const error of errors) console.error(`ERROR: ${error}`);
    process.exit(1);
  }

  const specRequirements = parseSpec(readText(specPath));
  const matrixText = readText(matrixPath);
  const summaryText = readText(summaryPath);
  const testText = readText(testPath);
  const resultJson = fs.existsSync(resultsPath) ? readJson(resultsPath) : { suites: [] };

  const requirementRows = tableRowsAfterHeading(matrixText, '## 요구사항 커버리지');
  const scenarioRows = tableRowsAfterHeading(matrixText, '## 명세 시나리오 커버리지');
  const testTitles = parseTestTitles(testText);
  const resultSpecs = collectResultSpecs(resultJson.suites);
  const screenshotPaths = collectScreenshotPaths(summaryText);

  const specScenarios = specRequirements.flatMap((requirement) =>
    requirement.scenarios.map((scenario) => ({ requirement: requirement.name, scenario }))
  );

  const requirementItems = specRequirements.map((requirement) => {
    const row = requirementRows.find((candidate) => candidate[1] === requirement.name);
    const covered = Boolean(row?.[3] && row[3] !== '-');
    return {
      requirement: requirement.name,
      covered,
      coveragePercent: covered ? 100 : 0,
      e2eScenarios: row?.[3] || '',
      note: row?.[4] || ''
    };
  });

  const scenarioItems = specScenarios.map((item) => {
    const row = scenarioRows.find((candidate) => candidate[1] === item.requirement && candidate[2] === item.scenario);
    const mappedScenario = row?.[3] || '';
    const testSurface = row?.[4] || '';
    const covered = Boolean(mappedScenario && mappedScenario !== '-');
    return {
      requirement: item.requirement,
      scenario: item.scenario,
      covered,
      coveragePercent: covered ? 100 : 0,
      e2eScenario: mappedScenario,
      verificationSurface: testSurface
    };
  });

  const testItems = testTitles.map((title) => {
    const result = resultSpecs.find((candidate) => candidate.title === title);
    const passed = Boolean(result?.ok);
    return {
      title,
      declared: true,
      presentInResults: Boolean(result),
      passed,
      coveragePercent: passed ? 100 : 0
    };
  });

  const screenshotItems = screenshotPaths.map((screenshotPath) => {
    const absolutePath = path.isAbsolute(screenshotPath)
      ? screenshotPath
      : path.join(root, screenshotPath);
    return {
      path: screenshotPath.replaceAll(path.sep, '/'),
      exists: fs.existsSync(absolutePath),
      coveragePercent: fs.existsSync(absolutePath) ? 100 : 0
    };
  });

  const coveredRequirements = requirementItems.filter((item) => item.covered).length;
  const coveredScenarios = scenarioItems.filter((item) => item.covered).length;
  const testsInResults = testItems.filter((item) => item.presentInResults).length;
  const passedTests = testItems.filter((item) => item.passed).length;
  const existingScreenshots = screenshotItems.filter((item) => item.exists).length;

  const gates = [
    {
      name: 'requirements_covered_100',
      passed: coveredRequirements === specRequirements.length,
      detail: `${coveredRequirements}/${specRequirements.length} requirements covered`
    },
    {
      name: 'spec_scenarios_covered_100',
      passed: coveredScenarios === specScenarios.length,
      detail: `${coveredScenarios}/${specScenarios.length} spec scenarios covered`
    },
    {
      name: 'all_declared_tests_have_results',
      passed: args.allowMissingResults || testsInResults === testTitles.length,
      detail: `${testsInResults}/${testTitles.length} declared tests found in results`
    },
    {
      name: 'all_declared_tests_passed',
      passed: args.allowMissingResults || passedTests === testTitles.length,
      detail: `${passedTests}/${testTitles.length} declared tests passed`
    },
    {
      name: 'all_referenced_screenshots_exist',
      passed: existingScreenshots === screenshotItems.length,
      detail: `${existingScreenshots}/${screenshotItems.length} referenced screenshots exist`
    }
  ];

  const passed = gates.every((gate) => gate.passed);
  const traceability = {
    status: passed ? 'passed' : 'failed',
    coveragePercent: averageCoveragePercent([
      ...requirementItems,
      ...scenarioItems,
      ...testItems,
      ...screenshotItems
    ]),
    metrics: {
      requirements: {
        total: specRequirements.length,
        covered: coveredRequirements,
        percent: ratio(coveredRequirements, specRequirements.length)
      },
      specScenarios: {
        total: specScenarios.length,
        covered: coveredScenarios,
        percent: ratio(coveredScenarios, specScenarios.length)
      },
      playwrightTests: {
        declared: testTitles.length,
        presentInResults: testsInResults,
        passed: passedTests,
        failedOrMissing: testTitles.length - passedTests
      },
      screenshots: {
        referenced: screenshotItems.length,
        existing: existingScreenshots,
        missing: screenshotItems.filter((item) => !item.exists).map((item) => item.path)
      }
    },
    gates,
    requirements: requirementItems,
    items: scenarioItems.map((item) => ({
      ...item,
      aiNote: item.covered
        ? '명세 시나리오가 E2E 시나리오에 매핑되어 있습니다.'
        : '명세 시나리오가 E2E 시나리오에 매핑되지 않았습니다.'
    })),
    tests: testItems,
    screenshots: screenshotItems
  };

  const existingSummary = loadExistingSummary(outputPath);
  const backend = coverageSection(existingSummary.backend);
  const frontend = coverageSection(existingSummary.frontend);

  const coverageSummary = {
    suite: args.suite,
    spec: path.relative(root, specPath).replaceAll(path.sep, '/'),
    generatedAt: new Date().toISOString(),
    traceability,
    backend,
    frontend,
    overallCoveragePercent: overallCoveragePercent([traceability, backend, frontend]),
    gaps: existingSummary.gaps || [],
    aiJudgment: {
      status: passed ? 'sufficient' : 'insufficient',
      summary: passed
        ? 'OpenSpec 요구사항과 명세 시나리오가 E2E 산출물에 모두 연결되어 있습니다.'
        : 'OpenSpec 요구사항 또는 명세 시나리오 중 E2E 산출물에 연결되지 않은 항목이 있습니다.'
    }
  };

  if (args.writeSummary) {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, `${JSON.stringify(coverageSummary, null, 2)}\n`);
  }

  console.log(`# ${args.suite} OpenSpec traceability gate`);
  console.log('');
  console.log(`- gate: ${passed ? 'PASS' : 'FAIL'}`);
  console.log(`- requirements: ${coveredRequirements}/${specRequirements.length} (${traceability.metrics.requirements.percent}%)`);
  console.log(`- spec scenarios: ${coveredScenarios}/${specScenarios.length} (${traceability.metrics.specScenarios.percent}%)`);
  console.log(`- playwright tests: ${passedTests}/${testTitles.length} passed`);
  console.log(`- screenshots: ${existingScreenshots}/${screenshotItems.length} referenced files exist`);
  if (args.writeSummary) console.log(`- summary: ${path.relative(root, outputPath).replaceAll(path.sep, '/')}`);
  console.log('');
  console.log('## Gate Details');
  for (const gate of gates) {
    console.log(`- ${gate.passed ? 'PASS' : 'FAIL'} ${gate.name}: ${gate.detail}`);
  }

  process.exitCode = passed ? 0 : 1;
}

main();
