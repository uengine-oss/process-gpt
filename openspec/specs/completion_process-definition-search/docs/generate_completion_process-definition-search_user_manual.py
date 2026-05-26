"""프로세스 정의 검색 사용자 매뉴얼 DOCX 생성 스크립트.

스타일 기준: .claude/skills/docx-user-manual/STYLE_REFERENCE.py
근거 자료: openspec/specs/completion_process-definition-search/ 의 spec.md, e2e 시나리오,
실행 요약, 스크린샷. 매뉴얼 본문은 최초 사용자를 위한 제품 안내 문서로 작성한다.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor


SCRIPT_DIR = Path(__file__).resolve().parent
SPEC_DIR = SCRIPT_DIR.parent
SCREENSHOT_DIR = SPEC_DIR / "e2e" / "results" / "screenshots"
OUTPUT_PATH = SCRIPT_DIR / "completion_process-definition-search-user-manual.docx"

DOC_VERSION = "v1.0"
DOC_DATE = date(2026, 5, 22)
ORG_NAME = "Process GPT 서비스팀"
SERVICE_NAME = "Process GPT"
DOC_TITLE = "프로세스 정의 검색 사용자 매뉴얼"
FONT_NAME = "Malgun Gothic"
PRIMARY_COLOR = "1F4E79"
CAPTION_COLOR = "666666"
TABLE_HEADER_FILL = "D9EAF7"


SCREENSHOTS = {
    "initial": "process-gpt-completion_process-definition-search-01-search-initial.png",
    "input": "process-gpt-completion_process-definition-search-01-search-input.png",
    "result": "process-gpt-completion_process-definition-search-01-search-result.png",
    "empty_input": "process-gpt-completion_process-definition-search-02-search-input.png",
    "empty": "process-gpt-completion_process-definition-search-02-search-empty.png",
    "tenant_result": "process-gpt-completion_process-definition-search-03-search-result.png",
}


def set_cell_shading(cell, fill: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    tc_pr.append(shd)


def set_run_font(run, size: int | None = None, bold: bool | None = None, color: str | None = None) -> None:
    run.font.name = FONT_NAME
    run._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = RGBColor.from_string(color)


def set_cell_text(cell, text: str, bold: bool = False, align_left: bool = False) -> None:
    cell.text = ""
    paragraph = cell.paragraphs[0]
    paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT if align_left else WD_ALIGN_PARAGRAPH.CENTER
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    run = paragraph.add_run(text)
    set_run_font(run, size=9, bold=bold)


def add_page_number(paragraph) -> None:
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = "PAGE"
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_end)


def add_toc(paragraph) -> None:
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = r'TOC \o "1-3" \h \z \u'
    fld_separate = OxmlElement("w:fldChar")
    fld_separate.set(qn("w:fldCharType"), "separate")
    placeholder = OxmlElement("w:t")
    placeholder.text = "목차는 Word에서 필드 업데이트 시 페이지 번호와 함께 표시됩니다."
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr)
    run._r.append(fld_separate)
    run._r.append(placeholder)
    run._r.append(fld_end)


def enable_field_update_on_open(doc: Document) -> None:
    settings = doc.settings._element
    update_fields = settings.find(qn("w:updateFields"))
    if update_fields is None:
        update_fields = OxmlElement("w:updateFields")
        settings.append(update_fields)
    update_fields.set(qn("w:val"), "true")


def add_heading(doc: Document, text: str, level: int = 1) -> None:
    paragraph = doc.add_heading(text, level=level)
    for run in paragraph.runs:
        set_run_font(run, bold=True, color=PRIMARY_COLOR)


def add_paragraph(doc: Document, text: str = "", bold: bool = False) -> None:
    paragraph = doc.add_paragraph()
    run = paragraph.add_run(text)
    set_run_font(run, bold=bold if bold else None)


def add_label(doc: Document, text: str) -> None:
    """워크플로 안의 소제목 한 줄."""
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.space_before = Pt(6)
    run = paragraph.add_run(text)
    set_run_font(run, bold=True, color=PRIMARY_COLOR)


def add_bullets(doc: Document, items: list[str]) -> None:
    for item in items:
        paragraph = doc.add_paragraph(style="List Bullet")
        run = paragraph.add_run(item)
        set_run_font(run)


def add_numbers(doc: Document, items: list[str]) -> None:
    """매 호출마다 1번부터 시작하는 절차 목록을 직접 번호로 작성한다."""
    for idx, item in enumerate(items, start=1):
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.75)
        paragraph.paragraph_format.first_line_indent = Cm(-0.45)
        run = paragraph.add_run(f"{idx}.\t{item}")
        set_run_font(run)


def add_table(doc: Document, headers: list[str], rows: list[list[str]],
              widths: list[float] | None = None, body_align_left: bool = True) -> None:
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        set_cell_text(cell, header, bold=True)
        set_cell_shading(cell, TABLE_HEADER_FILL)
    for row in rows:
        cells = table.add_row().cells
        for idx, value in enumerate(row):
            set_cell_text(cells[idx], value, align_left=body_align_left)
    if widths:
        for row in table.rows:
            for idx, width in enumerate(widths):
                row.cells[idx].width = Cm(width)
    doc.add_paragraph()


def add_image(doc: Document, key: str, caption: str) -> bool:
    path = SCREENSHOT_DIR / SCREENSHOTS[key]
    if not path.exists():
        add_paragraph(doc, f"[화면 예시 누락] {path.name}")
        return False
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run()
    run.add_picture(str(path), width=Inches(6.0))
    caption_paragraph = doc.add_paragraph()
    caption_paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption_run = caption_paragraph.add_run(caption)
    set_run_font(caption_run, size=9, color=CAPTION_COLOR)
    return True


def add_cover(doc: Document) -> None:
    for _ in range(5):
        doc.add_paragraph()
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run(SERVICE_NAME)
    set_run_font(run, size=18, bold=True, color=PRIMARY_COLOR)
    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run(DOC_TITLE)
    set_run_font(run, size=28, bold=True)
    doc.add_paragraph()
    add_table(
        doc,
        ["항목", "내용"],
        [
            ["문서 버전", DOC_VERSION],
            ["작성일", DOC_DATE.isoformat()],
            ["작성자/조직", ORG_NAME],
            ["문서 구분", "사용자 참조 매뉴얼"],
            ["대상 서비스", SERVICE_NAME],
            ["대상 기능", "프로세스 정의 검색"],
        ],
        [4.0, 12.0],
        body_align_left=False,
    )
    doc.add_page_break()


def add_scenario(doc: Document, title: str, purpose: str, preconditions: list[str],
                 steps: list[str], expected: list[str],
                 images: list[tuple[str, str]] | None = None) -> None:
    add_heading(doc, title, level=2)
    add_label(doc, "이럴 때 사용합니다")
    add_paragraph(doc, purpose)
    add_label(doc, "사용 전 확인")
    add_bullets(doc, preconditions)
    add_label(doc, "따라 하기")
    add_numbers(doc, steps)
    add_label(doc, "화면에서 확인할 내용")
    add_bullets(doc, expected)
    if images:
        for key, caption in images:
            add_image(doc, key, caption)


def configure_document(doc: Document) -> None:
    section = doc.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(2.0)
    section.right_margin = Cm(2.0)

    styles = doc.styles
    styles["Normal"].font.name = FONT_NAME
    styles["Normal"]._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
    styles["Normal"].font.size = Pt(10.5)
    for style_name, size in [("Heading 1", 16), ("Heading 2", 13), ("Heading 3", 11)]:
        style = styles[style_name]
        style.font.name = FONT_NAME
        style._element.rPr.rFonts.set(qn("w:eastAsia"), FONT_NAME)
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = RGBColor(31, 78, 121)

    footer = section.footer.paragraphs[0]
    footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = footer.add_run(f"{SERVICE_NAME} 프로세스 정의 검색 사용자 매뉴얼 | ")
    set_run_font(run, size=9, color=CAPTION_COLOR)
    add_page_number(footer)

    doc.core_properties.title = DOC_TITLE
    doc.core_properties.subject = f"{SERVICE_NAME} 프로세스 정의 검색"
    doc.core_properties.author = ORG_NAME
    enable_field_update_on_open(doc)


def build_document() -> Document:
    doc = Document()
    configure_document(doc)
    add_cover(doc)

    # 1. 문서 정보 및 변경 이력
    add_heading(doc, "1. 문서 정보 및 변경 이력")
    add_paragraph(doc, "이 문서의 버전과 변경 내용을 정리한 표입니다. 매뉴얼이 갱신되면 아래 표에 이력이 추가됩니다.")
    add_table(
        doc,
        ["문서 버전", "변경일", "변경 내용", "작성자", "검토자"],
        [[DOC_VERSION, DOC_DATE.isoformat(), "프로세스 정의 검색 매뉴얼 초안 작성", ORG_NAME, "서비스 담당자"]],
        [2.4, 2.8, 8.0, 3.4, 3.4],
        body_align_left=False,
    )

    # 2. 목차
    add_heading(doc, "2. 목차")
    add_paragraph(doc, "아래 목차는 Word에서 문서를 열 때 필드를 업데이트하면 페이지 번호가 함께 표시됩니다.")
    add_toc(doc.add_paragraph())
    doc.add_page_break()

    # 3. 개요
    add_heading(doc, "3. 개요")
    add_paragraph(doc, "서비스 목적", bold=True)
    add_paragraph(
        doc,
        "Process GPT는 회사의 업무 절차를 프로세스로 정의하고 실행·관리하는 협업 서비스입니다. "
        "프로세스 정의 검색 기능은 화면 상단의 통합 검색창에 자연어로 입력한 내용과 의미가 비슷한 "
        "프로세스 정의를 찾아 줍니다. 정확한 프로세스 이름을 모를 때도 \"휴가\", \"보고서 작성\"처럼 "
        "찾고 싶은 업무를 평소 말로 입력해 시작하거나 참고할 프로세스를 빠르게 확인할 수 있습니다.",
    )
    add_paragraph(doc, "매뉴얼 목적", bold=True)
    add_paragraph(
        doc,
        "이 매뉴얼은 처음 사용하는 사용자가 통합 검색창에 진입해 질의를 입력하고, 검색 결과를 "
        "이해하고, 결과가 없을 때 대응하는 방법까지 순서대로 따라 할 수 있도록 안내합니다.",
    )
    add_paragraph(doc, "기능 범위", bold=True)
    add_bullets(
        doc,
        [
            "상단 통합 검색창에 자연어 질의를 입력하고 검색을 실행합니다.",
            "입력한 내용과 의미가 비슷한 프로세스 정의 후보를 목록으로 확인합니다.",
            "검색 결과가 없을 때 표시되는 안내 화면을 확인합니다.",
            "검색 결과가 현재 소속 회사의 프로세스 정의로만 한정되는 범위를 이해합니다.",
        ],
    )

    # 4. 대상 사용자
    add_heading(doc, "4. 대상 사용자")
    add_paragraph(doc, "이 매뉴얼은 다음과 같은 사용자를 대상으로 합니다.")
    add_table(
        doc,
        ["사용자 역할", "주요 사용 목적", "권장 사용 범위"],
        [
            ["일반 사용자", "시작할 업무에 맞는 프로세스 정의를 검색해 찾습니다.", "검색 입력과 결과 확인"],
            ["프로세스 설계자", "비슷한 기존 프로세스 정의를 참고해 새 프로세스를 설계합니다.", "검색 입력과 결과 비교"],
            ["검토자", "회사에 어떤 프로세스 정의가 있는지 검색으로 확인합니다.", "검색 결과 검토"],
        ],
        [3.4, 8.6, 4.0],
    )

    # 5. 사용 전 확인 사항
    add_heading(doc, "5. 사용 전 확인 사항")
    add_paragraph(doc, "검색 기능을 사용하기 전에 아래 항목을 확인하세요.")
    add_table(
        doc,
        ["확인 항목", "확인 내용"],
        [
            ["계정", "Process GPT에 로그인할 수 있는 사용자 계정이 있어야 합니다."],
            ["접속 주소", "소속 회사에 발급된 Process GPT 접속 주소(URL)로 접속합니다."],
            ["브라우저", "Chrome 등 최신 웹 브라우저를 사용하는 것을 권장합니다."],
            ["등록된 프로세스 정의",
             "소속 회사에 프로세스 정의가 등록되어 있어야 검색 결과에 후보가 표시됩니다."],
            ["검색어 준비", "찾고 싶은 업무를 \"휴가 신청\", \"출장 정산\"처럼 자연어 문장이나 단어로 준비합니다."],
        ],
        [3.6, 12.4],
    )

    # 6. 시작하기
    add_heading(doc, "6. 시작하기")
    add_paragraph(doc, "처음 검색을 실행하기까지의 기본 흐름은 다음과 같습니다.")
    add_numbers(
        doc,
        [
            "웹 브라우저에서 소속 회사의 Process GPT 접속 주소로 이동합니다.",
            "로그인 화면에서 본인 계정으로 로그인합니다.",
            "로그인 후 표시되는 메인 화면(업무 목록 화면)으로 들어갑니다.",
            "화면 오른쪽 위 헤더 영역에서 돋보기 아이콘이 있는 통합 검색창을 확인합니다.",
            "검색창을 클릭하고 찾고 싶은 업무를 입력한 뒤 Enter 키를 눌러 검색합니다.",
        ],
    )
    add_paragraph(
        doc,
        "검색은 별도의 메뉴 이동 없이 어느 화면에서나 상단 헤더의 통합 검색창으로 바로 실행할 수 있습니다.",
    )

    # 7. 화면 구성
    add_heading(doc, "7. 화면 구성")
    add_paragraph(doc, "로그인 후 처음 만나는 화면의 주요 영역은 다음과 같습니다.")
    add_table(
        doc,
        ["화면 영역", "설명"],
        [
            ["상단 헤더 통합 검색창", "화면 오른쪽 위에 있는 돋보기 아이콘이 포함된 입력창입니다. 프로세스 정의 검색을 시작하는 곳입니다."],
            ["검색 결과 패널", "검색창 아래에 열리는 영역으로, 검색 결과와 안내 메시지를 표시합니다."],
            ["업무 목록 영역", "화면 가운데의 \"진행 중\", \"보류/반송\", \"완료됨\" 업무 카드 영역입니다."],
            ["왼쪽 사이드바", "인스턴스, 에이전트 동료, 사람 동료, 대화목록 등을 보여 주는 영역입니다."],
            ["알림 및 설정", "헤더 오른쪽 끝의 알림 아이콘과 설정 아이콘입니다."],
        ],
        [4.2, 11.8],
    )
    add_image(doc, "initial", "그림 1. 로그인 후 메인 화면 — 오른쪽 위 통합 검색창에서 검색을 시작합니다")

    # 8. 주요 사용 흐름
    add_heading(doc, "8. 주요 사용 흐름")
    add_paragraph(
        doc,
        "대표적인 세 가지 사용 흐름을 순서대로 안내합니다. 각 흐름은 사용 상황, 사용 전 확인, "
        "따라 하기, 화면에서 확인할 내용으로 구성됩니다.",
    )

    add_scenario(
        doc,
        "8.1 비슷한 업무를 자연어로 찾기",
        "시작하거나 참고할 프로세스의 정확한 이름을 모를 때, 찾고 싶은 업무를 평소 말로 입력해 "
        "의미가 비슷한 프로세스 정의 후보를 찾습니다.",
        [
            "Process GPT에 로그인되어 있고 메인 화면이 표시된 상태입니다.",
            "소속 회사에 프로세스 정의가 한 건 이상 등록되어 있습니다.",
        ],
        [
            "상단 헤더의 통합 검색창을 클릭합니다.",
            "찾고 싶은 업무를 자연어로 입력합니다. 예: 휴가",
            "Enter 키를 눌러 검색을 실행합니다.",
            "검색창 아래에 열리는 검색 결과 패널을 확인합니다.",
            "\"유사한 프로세스 정의\" 항목에서 입력 내용과 비슷한 후보 목록을 확인합니다.",
        ],
        [
            "검색 결과 패널이 열리고 \"유사한 프로세스 정의\" 항목이 표시됩니다.",
            "입력 내용과 의미가 비슷한 프로세스 정의가 후보로 나타나며, 후보는 최대 3건까지 표시됩니다.",
            "각 후보에는 프로세스 정의 이름과 한 줄 설명이 함께 표시됩니다.",
            "이름이 정확히 일치하는 프로세스가 있으면 \"프로세스 정의\" 항목에도 함께 표시됩니다.",
        ],
        [
            ("input", "그림 2. 통합 검색창에 찾고 싶은 업무를 자연어로 입력합니다"),
            ("result", "그림 3. 입력 내용과 비슷한 프로세스 정의 후보가 목록으로 표시됩니다"),
        ],
    )

    add_scenario(
        doc,
        "8.2 검색 결과가 없을 때 확인하기",
        "검색어와 맞는 프로세스 정의가 없거나 검색 처리에 일시적인 문제가 있을 때, 화면이 어떻게 "
        "안내되는지 확인합니다.",
        [
            "Process GPT에 로그인되어 있고 메인 화면이 표시된 상태입니다.",
        ],
        [
            "상단 헤더의 통합 검색창을 클릭합니다.",
            "찾고 싶은 업무를 자연어로 입력합니다. 예: 보고서 작성",
            "Enter 키를 눌러 검색을 실행합니다.",
            "검색 결과 패널에 표시되는 안내 메시지를 확인합니다.",
        ],
        [
            "결과가 없을 때는 오류 화면이나 깨진 화면 대신 \"검색 결과가 없습니다.\" 안내가 표시됩니다.",
            "이 경우 \"유사한 프로세스 정의\" 항목은 표시되지 않습니다.",
            "안내가 표시되어도 검색 작업은 그대로 이어 갈 수 있으며, 다른 검색어로 다시 시도할 수 있습니다.",
        ],
        [
            ("empty_input", "그림 4. 다른 검색어를 입력하고 검색을 실행한 모습"),
            ("empty", "그림 5. 검색 처리에 문제가 있어도 오류 없이 결과가 없다는 안내가 표시됩니다"),
        ],
    )

    add_scenario(
        doc,
        "8.3 현재 회사의 프로세스 정의만 확인하기",
        "Process GPT는 여러 회사가 함께 사용하는 서비스입니다. 검색 결과가 본인이 소속된 회사의 "
        "프로세스 정의로만 한정되는지 확인합니다.",
        [
            "본인이 소속된 회사 계정으로 Process GPT에 로그인되어 있습니다.",
        ],
        [
            "상단 헤더의 통합 검색창을 클릭합니다.",
            "찾고 싶은 업무를 자연어로 입력합니다. 예: 프로세스",
            "Enter 키를 눌러 검색을 실행합니다.",
            "검색 결과 패널의 \"유사한 프로세스 정의\" 목록을 확인합니다.",
        ],
        [
            "검색 결과에는 현재 소속 회사에 등록된 프로세스 정의만 표시됩니다.",
            "다른 회사에만 등록된 프로세스 정의는 검색 결과에 나타나지 않습니다.",
            "회사별로 검색 범위가 분리되어 있으므로 다른 회사의 업무 정보가 섞여 보이지 않습니다.",
        ],
        [
            ("tenant_result", "그림 6. 검색 결과에는 현재 소속 회사의 프로세스 정의만 표시됩니다"),
        ],
    )

    # 9. 화면 항목 및 옵션 설명
    add_heading(doc, "9. 화면 항목 및 옵션 설명")
    add_paragraph(doc, "검색에 사용하는 화면 항목과 입력 방법은 다음과 같습니다.")
    add_table(
        doc,
        ["화면 항목", "사용 여부", "입력 형식 / 예시", "설명"],
        [
            ["통합 검색창", "필수", "자연어 단어 또는 문장 / \"휴가\", \"출장 정산\"",
             "찾고 싶은 업무를 입력하는 곳입니다. 정확한 이름이 아니어도 됩니다."],
            ["검색 실행(Enter)", "필수", "키보드 Enter 키",
             "검색창에 입력한 뒤 Enter 키를 눌러야 검색이 실행됩니다."],
            ["\"유사한 프로세스 정의\" 항목", "자동 표시", "최대 3건",
             "입력 내용과 의미가 비슷한 프로세스 정의 후보를 보여 줍니다."],
            ["\"프로세스 정의\" 항목", "자동 표시", "이름 일치 결과",
             "검색어와 이름이 일치하는 프로세스 정의가 있을 때 함께 표시됩니다."],
        ],
        [3.6, 2.4, 4.6, 5.4],
    )
    add_paragraph(
        doc,
        "검색창에 입력만 하고 Enter 키를 누르지 않으면 검색 결과 패널에 "
        "\"검색하고자 하는 키워드 입력 후 엔터를 눌러주세요.\" 안내만 표시됩니다.",
    )

    # 10. 결과 확인
    add_heading(doc, "10. 결과 확인")
    add_paragraph(doc, "검색을 실행한 뒤 검색 결과 패널에서 다음 내용을 확인할 수 있습니다.")
    add_bullets(
        doc,
        [
            "검색 결과 패널 위쪽에 \"검색 결과\" 제목이 표시됩니다.",
            "\"유사한 프로세스 정의\" 항목에 입력 내용과 비슷한 후보가 최대 3건까지 나타납니다.",
            "각 후보는 프로세스 정의 이름과 한 줄 설명으로 구성되어 내용을 빠르게 파악할 수 있습니다.",
            "검색어와 이름이 일치하는 프로세스가 있으면 \"프로세스 정의\" 항목에 추가로 표시됩니다.",
            "결과가 없을 때는 \"검색 결과가 없습니다.\" 안내가 표시됩니다.",
            "검색 결과를 확인한 뒤 검색어를 바꿔 바로 다시 검색할 수 있습니다.",
        ],
    )

    # 11. 오류 및 예외 상황
    add_heading(doc, "11. 오류 및 예외 상황")
    add_paragraph(doc, "검색 중 자주 만나는 상황과 대처 방법입니다.")
    add_table(
        doc,
        ["상황", "원인", "해결 방법"],
        [
            ["\"검색 결과가 없습니다.\"가 표시됨",
             "검색어와 맞는 프로세스 정의가 없거나, 검색 처리에 일시적인 문제가 있는 경우입니다.",
             "검색어를 더 일반적인 단어로 바꾸거나 다른 표현으로 다시 검색합니다."],
            ["\"키워드 입력 후 엔터를 눌러주세요.\" 안내만 표시됨",
             "검색어를 입력했지만 Enter 키를 누르지 않은 경우입니다.",
             "검색창을 클릭해 입력한 뒤 Enter 키를 눌러 검색을 실행합니다."],
            ["원하는 프로세스가 후보에 없음",
             "후보는 의미가 비슷한 순서로 최대 3건까지만 표시됩니다.",
             "업무를 더 구체적으로 표현해 다시 검색하거나 핵심 단어를 바꿔 봅니다."],
            ["다른 회사의 프로세스가 보이지 않음",
             "검색은 소속 회사의 프로세스 정의로만 한정되는 정상 동작입니다.",
             "별도 조치가 필요하지 않습니다. 현재 회사의 프로세스만 검색됩니다."],
        ],
        [4.2, 6.0, 5.8],
    )

    # 12. 권한 및 역할별 기능 차이
    add_heading(doc, "12. 권한 및 역할별 기능 차이")
    add_paragraph(
        doc,
        "프로세스 정의 검색은 로그인한 사용자가 사용하는 공통 기능입니다. 검색 범위는 사용자가 "
        "소속된 회사의 프로세스 정의로 한정됩니다.",
    )
    add_table(
        doc,
        ["역할", "사용 가능 기능", "제한 사항"],
        [
            ["로그인 사용자", "통합 검색창에서 소속 회사의 프로세스 정의를 검색하고 결과를 확인합니다.",
             "다른 회사의 프로세스 정의는 검색되지 않습니다."],
            ["프로세스 설계자", "검색 결과를 참고해 새 프로세스 설계에 활용합니다.",
             "프로세스 등록·편집 권한은 별도 권한 정책을 따릅니다."],
        ],
        [3.4, 7.6, 5.0],
    )
    add_paragraph(
        doc,
        "프로세스 정의의 등록·편집 등 검색 외 기능의 권한은 회사의 권한 정책에 따라 다를 수 있으므로, "
        "필요한 경우 서비스 관리자에게 문의하세요.",
    )

    # 13. FAQ
    add_heading(doc, "13. FAQ / 자주 묻는 질문")
    add_table(
        doc,
        ["질문", "답변"],
        [
            ["프로세스 정의의 정확한 이름을 몰라도 검색할 수 있나요?",
             "네. \"휴가\", \"출장 정산\"처럼 찾고 싶은 업무를 자연어로 입력하면 의미가 비슷한 프로세스 정의를 찾아 줍니다."],
            ["검색 결과는 몇 건까지 표시되나요?",
             "\"유사한 프로세스 정의\" 후보는 의미가 비슷한 순서로 최대 3건까지 표시됩니다."],
            ["\"검색 결과가 없습니다.\"가 나오면 어떻게 하나요?",
             "검색어를 더 일반적인 단어로 바꾸거나 다른 표현으로 다시 검색해 보세요."],
            ["다른 회사의 프로세스도 검색되나요?",
             "아니요. 검색 결과는 본인이 소속된 회사의 프로세스 정의로만 한정됩니다."],
            ["검색이 실행되지 않아요.",
             "검색어를 입력한 뒤 반드시 Enter 키를 눌러야 검색이 실행됩니다."],
        ],
        [6.0, 10.0],
    )

    # 14. 효과적인 질문 작성 팁
    add_heading(doc, "14. 효과적인 질문 작성 팁")
    add_paragraph(doc, "원하는 프로세스 정의를 더 잘 찾기 위한 검색어 작성 팁입니다.")
    add_bullets(
        doc,
        [
            "업무의 핵심을 담은 단어를 사용합니다. 예: \"휴가\", \"구매 요청\", \"출장 경비\"",
            "결과가 너무 많거나 모호하면 \"휴가 신청 승인\"처럼 단어를 더해 범위를 좁힙니다.",
            "결과가 없으면 \"연차\"를 \"휴가\"로 바꾸듯 더 일반적인 표현으로 다시 검색합니다.",
            "한 번에 한 가지 업무를 검색합니다. 여러 업무를 한 검색어에 섞지 않습니다.",
            "후보의 한 줄 설명을 함께 읽어 의도한 프로세스가 맞는지 확인합니다.",
        ],
    )
    add_paragraph(doc, "좋은 검색어와 다시 검색하는 예시는 다음과 같습니다.")
    add_table(
        doc,
        ["상황", "처음 검색어", "다시 검색할 검색어"],
        [
            ["결과가 너무 광범위함", "프로세스", "휴가 신청 승인"],
            ["결과가 없음", "연차원천징수", "휴가"],
            ["업무를 두 가지 섞음", "휴가 그리고 출장 정산", "휴가 신청 (출장 정산은 따로 검색)"],
        ],
        [5.0, 5.0, 6.0],
    )

    return doc


def main() -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    doc = build_document()
    doc.save(OUTPUT_PATH)
    print(f"created: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
