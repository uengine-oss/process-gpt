#!/usr/bin/env python3
"""Validate OpenSpec-driven E2E output structure."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REQUIRED_COVERAGE_HEADINGS = [
    "# ",
    "## 범위",
    "## 시나리오 목록",
    "## 요구사항 커버리지",
    "## 명세 시나리오 커버리지",
    "## 미검증 및 보류 항목",
    "## 체크리스트",
]

REQUIRED_SCENARIO_HEADINGS = [
    "# E2E 시나리오 ",
    "## 메타데이터",
    "## 목적",
    "## 사전 조건",
    "## 테스트 데이터 및 Stub",
    "## 절차",
    "## 기대 결과",
    "## 커버하는 요구사항",
    "## 산출물",
]

REQUIRED_SUMMARY_HEADINGS = [
    "# ",
    "## 실행 메타데이터",
    "## 입력",
    "## 결과",
    "## 산출물",
    "## 검증",
    "## 알려진 공백",
]

SCENARIO_DOC_RE = re.compile(r"`((?:0[1-9]|[1-9][0-9])-[a-z0-9][a-z0-9-]*\.md)`")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", required=True, help="Suite slug, for example text2sql")
    parser.add_argument(
        "--scenario-root",
        help="Root containing suite scenario documentation",
    )
    parser.add_argument(
        "--result-root",
        help="Root containing suite Playwright reports",
    )
    parser.add_argument(
        "--test-root",
        help="Root containing suite Playwright tests",
    )
    parser.add_argument(
        "--require-results",
        action="store_true",
        help="Fail when results.json or html-report/index.html is missing",
    )
    return parser.parse_args()


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8-sig")


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def check_headings(path: Path, headings: list[str], errors: list[str]) -> str:
    text = read_text(path)
    for heading in headings:
        require(heading in text, f"{path}: missing heading {heading!r}", errors)
    return text


def validate(args: argparse.Namespace) -> int:
    repo = Path.cwd()
    scenario_dir = repo / args.scenario_root / args.suite
    result_dir = repo / args.result_root / args.suite
    test_dir = repo / args.test_root / args.suite
    test_file = test_dir / f"{args.suite}.spec.mjs"

    errors: list[str] = []
    warnings: list[str] = []

    coverage = scenario_dir / "00-coverage-matrix.md"
    summary = scenario_dir / "execution-summary.md"

    require(scenario_dir.is_dir(), f"missing scenario directory: {scenario_dir}", errors)
    require(coverage.is_file(), f"missing coverage matrix: {coverage}", errors)
    require(summary.is_file(), f"missing execution summary: {summary}", errors)
    require(test_file.is_file(), f"missing Playwright spec: {test_file}", errors)

    referenced_docs: set[str] = set()
    if coverage.is_file():
        coverage_text = check_headings(coverage, REQUIRED_COVERAGE_HEADINGS, errors)
        referenced_docs = set(SCENARIO_DOC_RE.findall(coverage_text))
        require(bool(referenced_docs), f"{coverage}: no scenario documents referenced", errors)

    if scenario_dir.is_dir():
        scenario_docs = sorted(
            path.name
            for path in scenario_dir.glob("[0-9][0-9]-*.md")
            if path.name != "00-coverage-matrix.md"
        )
        for doc_name in scenario_docs:
            doc_path = scenario_dir / doc_name
            check_headings(doc_path, REQUIRED_SCENARIO_HEADINGS, errors)

        missing_docs = sorted(referenced_docs.difference(scenario_docs))
        extra_docs = sorted(set(scenario_docs).difference(referenced_docs))
        for doc_name in missing_docs:
            errors.append(f"{coverage}: references missing scenario document {doc_name}")
        for doc_name in extra_docs:
            warnings.append(f"{scenario_dir / doc_name}: not listed in coverage matrix")

    if summary.is_file():
        check_headings(summary, REQUIRED_SUMMARY_HEADINGS, errors)

    results_json = result_dir / "results.json"
    html_report = result_dir / "html-report" / "index.html"
    if args.require_results:
        require(results_json.is_file(), f"missing JSON report: {results_json}", errors)
        require(html_report.is_file(), f"missing HTML report: {html_report}", errors)
    else:
        if not results_json.is_file():
            warnings.append(f"JSON report not found: {results_json}")
        if not html_report.is_file():
            warnings.append(f"HTML report not found: {html_report}")

    for warning in warnings:
        print(f"WARN: {warning}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"OK: E2E output contract validated for suite {args.suite}")
    return 0


if __name__ == "__main__":
    raise SystemExit(validate(parse_args()))
