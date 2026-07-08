const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  ImageRun, AlignmentType, LevelFormat, HeadingLevel, BorderStyle,
  WidthType, ShadingType, PageBreak, TableOfContents, PageNumber,
  Header, Footer,
} = require("docx");

const IMG = path.join(__dirname, "images");
const OUT = path.join(__dirname, "process-gpt-analytic-사용자매뉴얼.docx");

const NAVY = "0F172A", CYAN = "0891B2", VIOLET = "7C3AED", GREY = "64748B";
const img = (f) => new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { before: 120, after: 80 },
  children: [new ImageRun({
    type: "png",
    data: fs.readFileSync(path.join(IMG, f)),
    transformation: { width: 600, height: 375 },
    altText: { title: f, description: f, name: f },
  })],
});
const caption = (t) => new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 200 },
  children: [new TextRun({ text: t, italics: true, size: 18, color: GREY })],
});
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] });
const p = (t) => new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: t, size: 22 })] });
const bullet = (t) => new Paragraph({ numbering: { reference: "b", level: 0 }, spacing: { after: 60 }, children: [new TextRun({ text: t, size: 22 })] });
const step = (t) => new Paragraph({ numbering: { reference: "s", level: 0 }, spacing: { after: 60 }, children: [new TextRun({ text: t, size: 22 })] });

// API table helper
function apiTable(rows) {
  const border = { style: BorderStyle.SINGLE, size: 1, color: "CBD5E1" };
  const borders = { top: border, bottom: border, left: border, right: border };
  const hdr = (t) => new TableCell({
    borders, width: { size: t === "" ? 0 : 0, type: WidthType.DXA },
    shading: { fill: NAVY, type: ShadingType.CLEAR },
    margins: { top: 60, bottom: 60, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text: t, bold: true, color: "FFFFFF", size: 20 })] })],
  });
  const cell = (t, w, mono) => new TableCell({
    borders, width: { size: w, type: WidthType.DXA },
    margins: { top: 60, bottom: 60, left: 120, right: 120 },
    children: [new Paragraph({ children: [new TextRun({ text: t, size: 19, font: mono ? "Consolas" : "Arial" })] })],
  });
  const W = [1500, 4260, 3600];
  const headerRow = new TableRow({ tableHeader: true, children: [
    new TableCell({ borders, width: { size: W[0], type: WidthType.DXA }, shading: { fill: NAVY, type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 }, children: [new Paragraph({ children: [new TextRun({ text: "Method", bold: true, color: "FFFFFF", size: 20 })] })] }),
    new TableCell({ borders, width: { size: W[1], type: WidthType.DXA }, shading: { fill: NAVY, type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 }, children: [new Paragraph({ children: [new TextRun({ text: "엔드포인트", bold: true, color: "FFFFFF", size: 20 })] })] }),
    new TableCell({ borders, width: { size: W[2], type: WidthType.DXA }, shading: { fill: NAVY, type: ShadingType.CLEAR }, margins: { top: 60, bottom: 60, left: 120, right: 120 }, children: [new Paragraph({ children: [new TextRun({ text: "설명", bold: true, color: "FFFFFF", size: 20 })] })] }),
  ]});
  const bodyRows = rows.map((r, i) => new TableRow({ children: [
    cell(r[0], W[0], true), cell(r[1], W[1], true), cell(r[2], W[2], false),
  ].map((c) => { if (i % 2 === 1) c.options.shading = { fill: "F1F5F9", type: ShadingType.CLEAR }; return c; })}));
  return new Table({ width: { size: 9360, type: WidthType.DXA }, columnWidths: W, rows: [headerRow, ...bodyRows] });
}

const styles = {
  default: { document: { run: { font: "Arial", size: 22 } } },
  paragraphStyles: [
    { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
      run: { size: 32, bold: true, color: NAVY, font: "Arial" },
      paragraph: { spacing: { before: 320, after: 160 }, outlineLevel: 0,
        border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: CYAN, space: 4 } } } },
    { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
      run: { size: 26, bold: true, color: VIOLET, font: "Arial" },
      paragraph: { spacing: { before: 220, after: 120 }, outlineLevel: 1 } },
  ],
};

const numbering = { config: [
  { reference: "b", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 620, hanging: 320 } } } }] },
  { reference: "s", levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 620, hanging: 320 } } } }] },
]};

// ---- Title page ----
const titlePage = [
  new Paragraph({ spacing: { before: 2600 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: "Process GPT Analytic", bold: true, size: 60, color: NAVY })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 120 }, children: [new TextRun({ text: "프로세스 실행 데이터 분석 대시보드", size: 34, color: CYAN })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: "사용자 매뉴얼", size: 30, color: GREY })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 2400 }, children: [new TextRun({ text: "ETL · 백엔드 · 대시보드", size: 22, color: GREY })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 200 }, children: [new TextRun({ text: "services/analytic  |  버전 1.0", size: 20, color: GREY })] }),
  new Paragraph({ children: [new PageBreak()] }),
];

// ---- TOC ----
const tocPage = [
  new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("목차")] }),
  new TableOfContents("목차", { hyperlink: true, headingStyleRange: "1-2" }),
  new Paragraph({ children: [new PageBreak()] }),
];

const body = [
  // 1. Overview
  h1("1. 개요"),
  p("Process GPT Analytic은 Process GPT 플랫폼의 프로세스 실행 데이터를 기반으로 분석 대시보드를 제공하는 서비스입니다. 크게 두 개의 역할을 담당합니다."),
  bullet("ETL: 운영(OLTP) 데이터베이스의 프로세스 인스턴스·태스크·사용량 데이터를 OLAP 스타 스키마(dw)로 주기적으로 변환·적재합니다."),
  bullet("백엔드 API: 적재된 데이터를 대시보드, 퍼포먼스 분석, 피벗, 자연어 질의, 타임라인 화면에 제공합니다."),
  p("본 매뉴얼은 각 화면의 사용법을 실제 실행 데이터를 이용한 화면 캡처와 함께 설명합니다."),
  h2("구성 요소"),
  bullet("프론트엔드: Vue 3 기반 SPA (대시보드 · 피벗 · 자연어 질의 · 타임라인 · 퍼포먼스)"),
  bullet("백엔드: FastAPI (분석 API · ETL 실행/스케줄러 · Text2SQL)"),
  bullet("데이터: PostgreSQL의 dw 스키마 (차원 8종 · 팩트 3종)"),

  // 2. Dashboard
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("2. 대시보드")] }),
  p("대시보드는 프로세스 실행 현황을 한눈에 보여주는 시작 화면입니다. 좌측 메뉴에서 [대시보드]를 선택하면 진입합니다."),
  img("01_dashboard.png"),
  caption("그림 2-1. 대시보드 — 프로세스 인스턴스/태스크 요약, Task 분포, 월별 처리량, 최근 인스턴스"),
  h2("주요 지표"),
  bullet("프로세스 인스턴스: 전체 인스턴스 수와 완료/진행 건수"),
  bullet("전체 Tasks: 전체 태스크 수와 평균 처리시간"),
  bullet("Agent Tasks / Human Tasks: 수행자 유형별 태스크 분포 (도넛 차트)"),
  bullet("월별 처리량: Agent와 Human 태스크의 월별 추이 (라인 차트)"),
  bullet("최근 프로세스 인스턴스: 인스턴스별 프로세스명·상태·시작시각·소요시간, [타임라인] 바로가기"),
  h2("사용 방법"),
  step("우측 상단의 [새로고침]을 눌러 최신 ETL 적재 결과를 반영합니다."),
  step("최근 인스턴스 표에서 [타임라인 >]을 클릭하면 해당 인스턴스의 상세 타임라인으로 이동합니다."),

  // 3. Performance
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("3. 퍼포먼스 분석")] }),
  p("퍼포먼스 화면은 AI 에이전트와 사람 작업자의 성능을 나란히 비교합니다. 좌측 메뉴 [퍼포먼스]에서 진입합니다."),
  img("02_performance.png"),
  caption("그림 3-1. 퍼포먼스 분석 — Agent vs Human 성능 비교, F1 Score 추이, 월별 Task 처리량"),
  h2("비교 지표"),
  bullet("TASK 처리량 · 평균 처리시간 · 평균 F1 Score · 에러 건수를 수행자 유형별로 표시"),
  bullet("F1 Score 추이: 기간별 정확도 추이 차트"),
  bullet("월별 Task 처리량: Agent/Human 월별 처리량 막대 차트"),
  h2("필터"),
  step("상단 [필터] 영역에서 연도·분기를 선택해 기간을 좁힐 수 있습니다."),
  step("[필터 초기화]로 전체 기간 보기로 되돌립니다."),

  // 4. Pivot
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("4. 피벗 테이블")] }),
  p("피벗 테이블은 태스크 데이터를 다차원으로 자유롭게 집계하는 도구입니다. 좌측 메뉴 [피벗 테이블]에서 진입합니다."),
  img("03_pivot.png"),
  caption("그림 4-1. 피벗 테이블 — 차원/측정값을 ROWS·COLUMNS·MEASURES 영역으로 구성"),
  h2("구성 방법"),
  step("좌측 DIMENSIONS/MEASURES 목록에서 원하는 항목을 ROWS(행), COLUMNS(열), MEASURES(측정값) 영역으로 드래그합니다."),
  step("측정값에는 집계함수(COUNT/SUM/AVG/MAX/MIN)를 지정할 수 있습니다."),
  step("[Execute]를 눌러 집계 결과 표를 생성합니다. [Show SQL]로 실제 실행된 SQL을 확인할 수 있습니다."),
  step("[Reset]으로 구성을 초기화합니다."),
  p("예: 행에 '활동명', 측정값에 'Task 건수(COUNT)'를 지정하면 활동별 처리 건수 표가 생성됩니다."),

  // 5. Natural query
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("5. 자연어 질의")] }),
  p("자연어 질의는 사람이 쓰는 문장을 SQL로 변환해 데이터를 조회하는 기능입니다(Text2SQL). 좌측 메뉴 [자연어 질의]에서 진입합니다."),
  img("04_query.png"),
  caption("그림 5-1. 자연어 질의 — 자연어 질문을 SQL로 변환·실행하고 결과와 설명 제공"),
  h2("질의 예시"),
  bullet("\"2025년 1분기 각 프로세스별 평균 처리시간을 알려줘\""),
  bullet("\"에이전트와 사람의 월별 Task 건수를 비교해줘\""),
  bullet("\"가장 많은 에러가 발생한 활동 Top 5\""),
  bullet("\"각 사용자별 완료한 Task 수\""),
  h2("사용 방법"),
  step("질문 입력창에 자연어 질문을 입력하고 실행합니다."),
  step("시스템이 생성한 SQL, 실행 결과, AI 설명을 확인합니다."),
  p("참고: 이 기능은 OpenAI API 키(OPENAI_API_KEY) 설정이 필요합니다. 대시보드·피벗·타임라인 등 다른 기능은 키 없이도 동작합니다."),

  // 6. Timeline
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("6. 타임라인")] }),
  p("타임라인은 특정 프로세스 인스턴스의 태스크 실행 흐름을 Gantt 형태로 시각화합니다. 좌측 메뉴 [타임라인]에서 진입하거나, 대시보드의 [타임라인 >] 링크로 이동합니다."),
  img("05_timeline.png"),
  caption("그림 6-1. 타임라인 — 민원 처리 프로세스 인스턴스의 활동별 처리시간 Gantt 뷰"),
  h2("주요 정보"),
  bullet("상단: 인스턴스명, 상태, 전체 소요시간(Lead Time), 태스크/이벤트 수"),
  bullet("좌측 트리: 활동(민원 접수 → 검토 → 처리 → 결과 회신) 계층 구조"),
  bullet("중앙 Gantt: 활동별 처리시간 막대와 대기시간"),
  bullet("우측 Detail: 노드 선택 시 해당 태스크의 수행자·도구·시간 상세"),
  h2("사용 방법"),
  step("상단 [Select an instance...]에서 인스턴스를 선택합니다."),
  step("Gantt 막대나 트리 노드를 클릭하면 우측 Detail에 상세 정보가 표시됩니다."),
  step("[Lead Time] 토글로 리드타임 표시를 켜고 끌 수 있습니다."),

  // 7. API reference
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("7. 백엔드 API 요약")] }),
  p("화면이 사용하는 주요 백엔드 API입니다. 기본 경로는 /api 이며, 프론트엔드는 리버스 프록시를 통해 백엔드로 요청을 전달합니다."),
  h2("ETL"),
  apiTable([
    ["POST", "/api/etl/run", "ETL을 백그라운드로 즉시 실행"],
    ["GET", "/api/etl/status", "실행 여부·마지막 실행 시각·결과 조회"],
    ["POST", "/api/etl/scheduler/start", "주기적 ETL 스케줄러 시작"],
    ["POST", "/api/etl/scheduler/stop", "스케줄러 중지"],
  ]),
  h2("대시보드 · 분석"),
  apiTable([
    ["GET", "/api/dashboard/summary", "인스턴스·태스크·사용량 요약 통계"],
    ["GET", "/api/analytics/agent-vs-human", "Agent 대 Human 성능 비교"],
    ["GET", "/api/analytics/process-performance", "프로세스별 사이클 타임 통계"],
    ["GET", "/api/analytics/bottleneck", "활동별 병목 분석"],
    ["GET", "/api/analytics/monthly-trend", "월별 처리량 추이"],
    ["GET", "/api/instances", "최근 프로세스 인스턴스 목록"],
  ]),
  h2("피벗 · 질의 · 타임라인"),
  apiTable([
    ["POST", "/api/pivot", "행/열/측정값 기반 동적 피벗 집계"],
    ["POST", "/api/query/natural", "자연어 질문 → SQL 변환·실행"],
    ["GET", "/api/schema", "dw 스키마 테이블·컬럼 정보"],
    ["GET", "/api/dashboard/timeline/{id}", "인스턴스별 태스크 타임라인"],
  ]),

  // 8. Verification appendix
  new Paragraph({ pageBreakBefore: true, heading: HeadingLevel.HEADING_1, children: [new TextRun("부록. 동작 검증 결과")] }),
  p("본 매뉴얼의 화면은 로컬 Process GPT 환경의 실제 프로세스 실행 데이터로 ETL·백엔드·프론트엔드를 구동해 캡처했습니다."),
  bullet("ETL: 운영 스키마(bpm_proc_inst 65건, todolist 81건)를 dw 스타 스키마로 적재 → 인스턴스 65건, 태스크 81건 적재 확인(원본 건수와 일치)."),
  bullet("적재된 차원: 테넌트 2, 사용자 1, 프로세스 정의 2(휴가신청·민원 처리), 활동 13, 도구 8."),
  bullet("백엔드: 대시보드/분석/피벗/타임라인 API 모두 HTTP 200과 실데이터 응답 확인."),
  bullet("프론트엔드: 5개 화면 모두 실데이터로 정상 렌더링(대시보드·퍼포먼스·피벗·자연어질의·타임라인)."),
  p("참고: 현재 운영 스키마에는 사용량(usage) 테이블이 없어 LLM 사용량/비용 지표는 0으로 표시됩니다."),
];

const doc = new Document({
  styles, numbering,
  sections: [
    { properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } },
      children: [...titlePage, ...tocPage, ...body],
      footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [
        new TextRun({ text: "Process GPT Analytic 사용자 매뉴얼   ·   ", size: 16, color: GREY }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, color: GREY }),
      ] })] }) },
    },
  ],
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(OUT, buf); console.log("saved", OUT); });
