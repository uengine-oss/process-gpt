"""에이전트 메모리 대화 사용자 매뉴얼(.docx) 생성 스크립트.

원본 명세: openspec/specs/completion_agent-memory-chat/spec.md
시각 스타일 기준: .claude/skills/docx-user-manual/STYLE_REFERENCE.py

스크립트와 산출 .docx 는 openspec/specs/completion_agent-memory-chat/docs/ 에 함께 둡니다.
스크린샷은 openspec/specs/completion_agent-memory-chat/e2e/results/screenshots/ 에서 읽습니다.
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


DOCS_DIR = Path(__file__).resolve().parent
SPEC_DIR = DOCS_DIR.parent
SCREENSHOT_DIR = SPEC_DIR / "e2e" / "results" / "screenshots"
OUTPUT_PATH = DOCS_DIR / "completion_agent-memory-chat-user-manual.docx"

DOC_VERSION = "v1.0"
DOC_DATE = date(2026, 5, 22)
ORG_NAME = "Process GPT 서비스팀"
SERVICE_NAME = "Process GPT 메모리 에이전트"
DOC_TITLE = "메모리 에이전트 대화 사용자 매뉴얼"
FONT_NAME = "Malgun Gothic"
PRIMARY_COLOR = "1F4E79"
CAPTION_COLOR = "666666"
TABLE_HEADER_FILL = "D9EAF7"


SCREENSHOTS = {
    "learning_initial": "process-gpt-completion_agent-memory-chat-01-learning-initial.png",
    "learning_input": "process-gpt-completion_agent-memory-chat-01-learning-input.png",
    "learning_result": "process-gpt-completion_agent-memory-chat-01-learning-result.png",
    "duplicate_first": "process-gpt-completion_agent-memory-chat-02-duplicate-first.png",
    "duplicate_second": "process-gpt-completion_agent-memory-chat-02-duplicate-second.png",
    "query_input": "process-gpt-completion_agent-memory-chat-03-query-input.png",
    "query_running": "process-gpt-completion_agent-memory-chat-03-query-running.png",
    "query_answer": "process-gpt-completion_agent-memory-chat-03-query-answer.png",
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


def set_cell_text(cell, text: str, bold: bool = False, center: bool = True) -> None:
    cell.text = ""
    paragraph = cell.paragraphs[0]
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER if center else WD_ALIGN_PARAGRAPH.LEFT
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


def add_lead(doc: Document, text: str) -> None:
    """소제목 형태의 강조 문단."""
    paragraph = doc.add_paragraph()
    run = paragraph.add_run(text)
    set_run_font(run, bold=True, color=PRIMARY_COLOR)


def add_bullets(doc: Document, items: list[str]) -> None:
    for item in items:
        paragraph = doc.add_paragraph(style="List Bullet")
        run = paragraph.add_run(item)
        set_run_font(run)


def add_numbers(doc: Document, items: list[str]) -> None:
    """절차 목록. 항상 1부터 시작하도록 번호를 직접 표기합니다."""
    for idx, item in enumerate(items, start=1):
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.75)
        paragraph.paragraph_format.first_line_indent = Cm(-0.45)
        run = paragraph.add_run(f"{idx}.\t{item}")
        set_run_font(run)


def add_table(doc: Document, headers: list[str], rows: list[list[str]], widths: list[float] | None = None) -> None:
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
            set_cell_text(cells[idx], value, center=(idx == 0 and len(value) <= 12))
    if widths:
        for row in table.rows:
            for idx, width in enumerate(widths):
                row.cells[idx].width = Cm(width)
    doc.add_paragraph()


def add_image(doc: Document, key: str, caption: str, width_in: float = 6.1) -> None:
    path = SCREENSHOT_DIR / SCREENSHOTS[key]
    if not path.exists():
        add_paragraph(doc, f"[화면 예시 누락] {path.name}")
        return
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run()
    run.add_picture(str(path), width=Inches(width_in))
    caption_paragraph = doc.add_paragraph()
    caption_paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption_run = caption_paragraph.add_run(caption)
    set_run_font(caption_run, size=9, color=CAPTION_COLOR)


def add_workflow(
    doc: Document,
    title: str,
    purpose: str,
    preconditions: list[str],
    steps: list[str],
    expected: list[str],
    images: list[tuple[str, str]] | None = None,
) -> None:
    add_heading(doc, title, level=2)
    add_lead(doc, "이럴 때 사용합니다")
    add_paragraph(doc, purpose)
    add_lead(doc, "사용 전 확인")
    add_bullets(doc, preconditions)
    add_lead(doc, "따라 하기")
    add_numbers(doc, steps)
    add_lead(doc, "화면에서 확인할 내용")
    add_bullets(doc, expected)
    for key, caption in images or []:
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
    run = footer.add_run(f"{SERVICE_NAME} 사용자 매뉴얼 | ")
    set_run_font(run, size=9, color=CAPTION_COLOR)
    add_page_number(footer)

    doc.core_properties.title = DOC_TITLE
    doc.core_properties.subject = SERVICE_NAME
    doc.core_properties.author = ORG_NAME
    enable_field_update_on_open(doc)


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
        ],
        [4.0, 12.0],
    )
    doc.add_page_break()


def build_document() -> Document:
    doc = Document()
    configure_document(doc)
    add_cover(doc)

    # 1. 문서 정보 및 변경 이력
    add_heading(doc, "1. 문서 정보 및 변경 이력")
    add_paragraph(doc, "이 문서의 버전과 변경 내역은 아래 표에서 확인할 수 있습니다.")
    add_table(
        doc,
        ["문서 버전", "변경일", "변경 내용", "작성자", "검토자"],
        [[DOC_VERSION, DOC_DATE.isoformat(), "초안 작성", ORG_NAME, "서비스 담당자"]],
        [2.6, 3.0, 8.2, 3.0, 3.0],
    )

    # 2. 목차
    add_heading(doc, "2. 목차")
    add_paragraph(doc, "아래 목차는 Word에서 문서를 열 때 필드를 업데이트하면 페이지 번호가 함께 표시됩니다.")
    add_toc(doc.add_paragraph())
    doc.add_page_break()

    # 3. 개요
    add_heading(doc, "3. 개요")
    add_paragraph(
        doc,
        "메모리 에이전트는 사용자가 알려준 정보를 기억해 두었다가, 이후 질문을 받으면 "
        "그 정보를 찾아 답변해 주는 대화형 도우미입니다. 이 매뉴얼은 메모리 에이전트를 "
        "처음 사용하는 분이 화면에 진입해 정보를 학습시키고 답변을 받는 과정을 "
        "순서대로 따라 할 수 있도록 안내합니다.",
    )
    add_bullets(
        doc,
        [
            "서비스 목적: 자주 쓰는 정보나 규칙을 에이전트에 기억시켜 두고, 필요할 때 질문으로 빠르게 확인합니다.",
            "매뉴얼 목적: 접속과 로그인부터 정보 학습, 질문, 답변 확인, 오류 대응까지 한 번에 따라 할 수 있도록 안내합니다.",
            "기능 범위: 화면 구성, 학습 모드와 질의 모드 사용 흐름, 결과 확인, 오류 대응, 자주 묻는 질문, 질문 작성 팁을 다룹니다.",
        ],
    )

    # 4. 대상 사용자
    add_heading(doc, "4. 대상 사용자")
    add_paragraph(doc, "이 매뉴얼은 메모리 에이전트를 업무에 활용하려는 다음 사용자를 대상으로 합니다.")
    add_table(
        doc,
        ["사용자 구분", "주요 사용 목적", "권장 사용 범위"],
        [
            ["일반 사용자", "필요한 정보를 에이전트에 기억시키고 질문으로 답변을 받습니다.", "학습 모드, 질의 모드"],
            ["분석 사용자", "이미 저장된 정보를 반복 질문으로 확인하고 활용합니다.", "질의 모드 중심"],
            ["검토자", "에이전트가 내놓은 답변과 근거 정보를 확인합니다.", "답변 및 결과 검토"],
        ],
        [3.4, 8.6, 5.0],
    )

    # 5. 사용 전 확인 사항
    add_heading(doc, "5. 사용 전 확인 사항")
    add_paragraph(doc, "메모리 에이전트를 사용하기 전에 아래 항목을 미리 확인하세요.")
    add_bullets(
        doc,
        [
            "계정과 권한: Process GPT에 로그인할 수 있는 계정이 있어야 합니다.",
            "접속 주소: 조직에서 안내한 Process GPT 접속 주소를 준비합니다.",
            "브라우저: 최신 버전의 Chrome 등 표준 웹 브라우저 사용을 권장합니다.",
            "에이전트 준비: 사용할 메모리 에이전트가 왼쪽 '에이전트 동료' 목록에 등록되어 있어야 합니다.",
            "내용 준비: 기억시킬 정보 또는 질문 내용을 한 문장으로 정리해 둡니다.",
            "사용 순서: 질문에 정확한 답을 받으려면 먼저 학습 모드로 정보를 저장한 뒤 질의 모드를 사용합니다.",
        ],
    )

    # 6. 시작하기
    add_heading(doc, "6. 시작하기")
    add_paragraph(doc, "처음 접속부터 첫 메시지를 보내기까지의 기본 절차입니다.")
    add_numbers(
        doc,
        [
            "웹 브라우저에서 조직이 안내한 Process GPT 접속 주소로 이동합니다.",
            "로그인 화면에서 이메일과 비밀번호를 입력하고, 필요한 동의 항목을 선택한 뒤 로그인합니다.",
            "로그인 후 왼쪽 '에이전트 동료' 목록에서 사용할 메모리 에이전트를 선택합니다.",
            "가운데 영역에서 에이전트의 목표, 페르소나, 모델 등 소개 정보를 확인합니다.",
            "가운데 모드 목록에서 사용할 모드(학습 모드 또는 질의 모드)를 선택합니다.",
            "오른쪽 아래 '메시지 입력' 창에 내용을 입력하고 전송 버튼을 눌러 대화를 시작합니다.",
        ],
    )

    # 7. 화면 구성
    add_heading(doc, "7. 화면 구성")
    add_paragraph(
        doc,
        "메모리 에이전트 화면은 왼쪽 동료 목록, 가운데 에이전트 정보와 모드 목록, "
        "오른쪽 대화 영역으로 구성됩니다. 아래 표는 화면의 주요 영역과 역할을 설명합니다.",
    )
    add_table(
        doc,
        ["화면 영역", "역할"],
        [
            ["왼쪽 동료 목록", "대화할 에이전트 동료와 사람 동료를 선택하는 목록입니다."],
            ["가운데 에이전트 정보", "선택한 에이전트의 목표, 페르소나, 모델 등 소개 정보를 보여 줍니다."],
            ["가운데 모드 목록", "대화 모드, 학습 모드, 질의 모드, 액션 모드 중에서 사용할 모드를 선택합니다."],
            ["오른쪽 대화 영역", "주고받은 메시지가 시간 순서대로 표시되는 영역입니다."],
            ["메시지 입력창", "기억시킬 정보나 질문을 입력하는 화면 아래쪽 입력란입니다."],
            ["전송 버튼", "입력한 내용을 에이전트에게 보내는 종이비행기 모양의 버튼입니다."],
            ["첨부 / 음성 버튼", "입력창 옆의 추가 첨부(+) 버튼과 음성 입력 버튼입니다."],
        ],
        [4.5, 11.5],
    )
    add_image(doc, "learning_initial", "그림 1. 메모리 에이전트 화면 구성 — 동료 목록, 에이전트 정보, 모드 목록, 대화 영역")

    add_lead(doc, "모드별 역할")
    add_paragraph(doc, "가운데 모드 목록에서 선택할 수 있는 모드와 용도는 다음과 같습니다.")
    add_table(
        doc,
        ["모드", "용도"],
        [
            ["대화 모드", "에이전트와 일반적인 대화를 나눕니다."],
            ["학습 모드", "에이전트에 정보를 기억시켜 메모리에 저장합니다."],
            ["질의 모드", "저장된 정보를 검색해 그 내용을 반영한 답변을 받습니다."],
            ["액션 모드", "에이전트에 지정된 작업을 실행합니다."],
        ],
        [3.5, 12.5],
    )

    # 8. 주요 사용 흐름
    add_heading(doc, "8. 주요 사용 흐름")
    add_paragraph(
        doc,
        "메모리 에이전트의 대표 사용 흐름은 정보를 기억시키는 학습 모드와, "
        "기억한 정보를 활용해 답변을 받는 질의 모드로 나뉩니다.",
    )

    add_workflow(
        doc,
        "8.1 학습 모드로 정보 저장하기",
        "에이전트가 앞으로 답변에 활용할 정보나 규칙을 기억하도록 저장할 때 사용합니다.",
        [
            "사용할 메모리 에이전트가 동료 목록에 등록되어 있습니다.",
            "기억시킬 정보를 한 문장으로 정리해 두었습니다.",
        ],
        [
            "로그인 후 왼쪽 '에이전트 동료' 목록에서 메모리 에이전트를 선택합니다.",
            "가운데 모드 목록에서 '학습 모드'를 선택합니다.",
            "오른쪽 아래 '메시지 입력' 창에 기억시킬 정보를 한 문장으로 입력합니다.",
            "전송 버튼(종이비행기 아이콘)을 눌러 정보를 보냅니다.",
            "진행 표시가 끝나면 에이전트가 보낸 안내 메시지를 확인합니다.",
        ],
        [
            "입력한 문장이 대화 영역 오른쪽에 사용자 메시지로 표시됩니다.",
            "전송 직후 답변을 생성하는 동안 잠시 진행 표시가 나타납니다.",
            "에이전트가 정보를 기억했음을 알리는 안내 메시지를 왼쪽 말풍선으로 보냅니다.",
            "입력한 정보와 안내 메시지가 시간과 함께 대화 영역에 남습니다.",
        ],
        [
            ("learning_input", "그림 2. 학습할 정보를 입력창에 입력한 상태"),
            ("learning_result", "그림 3. 학습 모드 전송 후 표시되는 안내 메시지"),
        ],
    )

    add_workflow(
        doc,
        "8.2 같은 정보를 다시 학습할 때 확인하기",
        "이미 한 번 알려준 정보를 다시 보낼 때 화면이 어떻게 안내하는지 확인할 때 사용합니다.",
        [
            "학습 모드에서 정보를 한 번 이상 저장한 적이 있습니다.",
            "같은 내용을 다시 보내려고 합니다.",
        ],
        [
            "학습 모드에서 정보를 한 번 전송하고 첫 번째 안내 메시지를 확인합니다.",
            "같은 문장을 '메시지 입력' 창에 다시 입력합니다.",
            "전송 버튼을 눌러 같은 정보를 다시 보냅니다.",
            "두 번째로 도착한 안내 메시지를 확인합니다.",
        ],
        [
            "두 번 모두 사용자 메시지와 에이전트 안내 메시지가 한 쌍으로 대화 영역에 남습니다.",
            "이미 비슷한 정보가 저장되어 있으면 '비슷한 내용이 이미 있어 새로 저장하지 않았습니다'라는 안내가 표시될 수 있습니다.",
            "같은 내용을 여러 번 보내도 동일한 정보가 불필요하게 늘어나지 않습니다.",
        ],
        [
            ("duplicate_first", "그림 4. 첫 번째 학습 후 표시되는 안내"),
            ("duplicate_second", "그림 5. 같은 정보를 다시 보냈을 때 표시되는 안내"),
        ],
    )

    add_workflow(
        doc,
        "8.3 질의 모드로 답변 받기",
        "에이전트에 미리 학습시킨 정보를 바탕으로 질문에 대한 답변을 받을 때 사용합니다.",
        [
            "질문과 관련된 정보가 학습 모드로 먼저 저장되어 있습니다.",
            "확인하고 싶은 내용을 질문 형태로 정리해 두었습니다.",
        ],
        [
            "가운데 모드 목록에서 '질의 모드'를 선택합니다.",
            "'메시지 입력' 창에 알고 싶은 내용을 질문 형태로 입력합니다.",
            "전송 버튼을 눌러 질문을 보냅니다.",
            "답변을 생성하는 동안 표시되는 진행 표시를 확인합니다.",
            "진행 표시가 끝나면 도착한 답변 메시지와 그 아래 근거 정보 카드를 확인합니다.",
        ],
        [
            "답변을 생성하는 동안 입력창 옆에 진행 표시가 나타납니다.",
            "앞서 학습시킨 정보를 반영한 답변이 왼쪽 말풍선으로 표시됩니다.",
            "답변 아래에 답변의 근거가 된 저장 정보가 카드 형태로 함께 표시됩니다.",
            "입력한 질문과 답변이 시간과 함께 대화 영역에 남아 다시 확인할 수 있습니다.",
        ],
        [
            ("query_input", "그림 6. 질의 모드에서 질문을 입력한 상태"),
            ("query_running", "그림 7. 답변을 생성하는 동안 표시되는 진행 표시"),
            ("query_answer", "그림 8. 저장된 정보를 활용한 답변과 근거 정보 카드 확인"),
        ],
    )

    # 9. 화면 항목 및 옵션 설명
    add_heading(doc, "9. 화면 항목 및 옵션 설명")
    add_paragraph(doc, "대화에 사용하는 주요 화면 항목과 입력 방법은 아래와 같습니다.")
    add_table(
        doc,
        ["화면 항목", "사용 여부", "입력 형식", "설명"],
        [
            ["모드 선택", "필수", "학습 모드 / 질의 모드", "정보를 저장하려면 학습 모드, 답변을 받으려면 질의 모드를 선택합니다."],
            ["메시지 입력창", "필수", "자유 입력 문장", "기억시킬 정보 또는 질문을 입력합니다. 한 번에 한 가지 내용을 한 문장으로 작성하면 정확합니다."],
            ["전송 버튼", "필수", "버튼 클릭", "입력을 마친 뒤 종이비행기 아이콘을 눌러 내용을 보냅니다."],
            ["첨부(+) 버튼", "선택", "버튼 클릭", "필요한 경우 추가 항목을 첨부할 때 사용합니다."],
            ["음성 입력 버튼", "선택", "버튼 클릭", "키보드 대신 음성으로 메시지를 입력할 때 사용합니다."],
        ],
        [3.0, 2.2, 3.4, 7.4],
    )

    # 10. 결과 확인
    add_heading(doc, "10. 결과 확인")
    add_paragraph(doc, "메시지를 보낸 뒤 화면에서 확인할 결과 상태는 다음과 같습니다.")
    add_table(
        doc,
        ["사용 모드", "완료 후 확인할 내용"],
        [
            ["학습 모드", "에이전트가 정보를 기억했다는 안내, 또는 이미 비슷한 정보가 있어 새로 저장하지 않았다는 안내가 표시됩니다."],
            ["질의 모드", "학습된 정보를 반영한 답변 메시지와, 그 아래 답변의 근거가 된 저장 정보 카드가 함께 표시됩니다."],
            ["공통", "주고받은 모든 메시지가 시간과 함께 대화 영역에 남아 언제든 다시 확인할 수 있습니다."],
        ],
        [3.0, 13.0],
    )
    add_bullets(
        doc,
        [
            "답변이 표시된 뒤에도 입력창은 그대로 열려 있어 곧바로 다음 정보 학습이나 다음 질문을 이어갈 수 있습니다.",
            "이전 대화 내용은 대화 영역을 위로 스크롤하여 다시 확인할 수 있습니다.",
        ],
    )

    # 11. 오류 및 예외 상황
    add_heading(doc, "11. 오류 및 예외 상황")
    add_paragraph(doc, "사용 중 자주 마주칠 수 있는 상황과 해결 방법입니다.")
    add_table(
        doc,
        ["상황", "원인", "해결 방법"],
        [
            [
                "답변이 한참 동안 표시되지 않습니다.",
                "일시적인 처리 지연이나 네트워크 문제일 수 있습니다.",
                "잠시 기다린 뒤에도 응답이 없으면 화면을 새로고침하고 같은 내용을 다시 전송합니다.",
            ],
            [
                "'비슷한 내용이 이미 있어 새로 저장하지 않았습니다' 안내가 표시됩니다.",
                "같은 정보가 이미 에이전트 메모리에 저장되어 있습니다.",
                "정상적인 안내입니다. 새로운 정보를 추가하려면 다른 내용으로 다시 입력합니다.",
            ],
            [
                "질문했는데 원하는 답을 받지 못했습니다.",
                "질문과 관련된 정보가 아직 학습되지 않았을 수 있습니다.",
                "학습 모드로 관련 정보를 먼저 저장한 뒤 질의 모드에서 다시 질문합니다.",
            ],
            [
                "대화를 시작할 수 없습니다.",
                "왼쪽 목록에서 대화할 에이전트를 선택하지 않았습니다.",
                "왼쪽 '에이전트 동료' 목록에서 메모리 에이전트를 먼저 선택합니다.",
            ],
            [
                "화면이 비어 있거나 로그인 화면으로 돌아갑니다.",
                "로그인 세션이 만료되었을 수 있습니다.",
                "다시 로그인한 뒤 에이전트를 선택해 대화를 이어갑니다.",
            ],
        ],
        [4.2, 4.8, 7.0],
    )

    # 12. 권한 및 역할별 기능 차이
    add_heading(doc, "12. 권한 및 역할별 기능 차이")
    add_paragraph(doc, "사용자 역할에 따라 사용할 수 있는 기능에는 차이가 있을 수 있습니다.")
    add_table(
        doc,
        ["역할", "사용 가능한 기능", "제한 또는 권한 필요 사항"],
        [
            [
                "일반 사용자",
                "학습 모드와 질의 모드로 정보를 저장하고 답변을 받으며, 대화 내용을 확인합니다.",
                "에이전트 자체의 생성·편집·삭제는 제한될 수 있습니다.",
            ],
            [
                "에이전트 관리자",
                "일반 사용 기능에 더해 에이전트 정보 편집과 삭제를 수행할 수 있습니다.",
                "에이전트 편집·삭제는 권한이 있는 사용자만 사용할 수 있습니다.",
            ],
        ],
        [3.2, 7.4, 5.4],
    )
    add_paragraph(
        doc,
        "역할별 권한 설정은 조직 정책에 따라 다를 수 있으므로, 특정 기능이 보이지 않으면 "
        "서비스 관리자에게 문의하세요.",
    )

    # 13. FAQ
    add_heading(doc, "13. FAQ / 자주 묻는 질문")
    add_table(
        doc,
        ["질문", "답변"],
        [
            [
                "학습 모드와 질의 모드는 어떻게 다른가요?",
                "학습 모드는 정보를 기억시켜 저장하는 모드이고, 질의 모드는 기억한 정보를 찾아 그 내용을 반영해 답변하는 모드입니다.",
            ],
            [
                "한 번에 여러 정보를 학습시킬 수 있나요?",
                "한 번에 한 가지 정보를 한 문장으로 보내는 것이 가장 정확합니다. 여러 정보는 나누어 입력하세요.",
            ],
            [
                "학습한 정보를 다른 에이전트도 사용하나요?",
                "아니요. 정보는 학습시킨 해당 에이전트의 메모리에만 저장되어 그 에이전트의 답변에만 활용됩니다.",
            ],
            [
                "같은 정보를 다시 보내면 어떻게 되나요?",
                "이미 비슷한 정보가 저장되어 있으면 새로 저장하지 않고 안내 메시지만 표시될 수 있습니다.",
            ],
            [
                "답변 아래에 표시되는 카드는 무엇인가요?",
                "답변의 근거가 된 저장 정보입니다. 어떤 내용을 바탕으로 답했는지 확인할 수 있습니다.",
            ],
            [
                "질문했는데 답을 받지 못했어요.",
                "질문과 관련된 정보를 학습 모드로 먼저 저장했는지 확인하고, 저장 후 다시 질문해 보세요.",
            ],
        ],
        [5.5, 10.5],
    )

    # 14. 효과적인 질문 작성 팁
    add_heading(doc, "14. 효과적인 질문 작성 팁")
    add_paragraph(doc, "메모리 에이전트에서 원하는 답변을 얻으려면 아래 방법을 참고하세요.")
    add_bullets(
        doc,
        [
            "먼저 학습, 그다음 질문: 답변에 필요한 정보를 학습 모드로 저장한 뒤 질의 모드에서 질문합니다.",
            "한 번에 한 가지만: 한 문장에는 한 가지 정보나 한 가지 질문만 담으면 더 정확한 답을 받습니다.",
            "비슷한 표현 사용: 질문할 때 정보를 학습시킬 때 쓴 단어와 비슷한 표현을 사용하면 검색이 잘 됩니다.",
            "결과가 없을 때: 답이 부족하면 더 일반적인 표현으로 바꾸거나, 관련 정보를 추가로 학습시킨 뒤 다시 질문합니다.",
        ],
    )
    add_lead(doc, "예시")
    add_table(
        doc,
        ["구분", "예시 문장"],
        [
            ["학습 모드 입력 예시", "분기별 영업 보고서는 매월 5일까지 제출한다"],
            ["질의 모드 질문 예시", "분기별 영업 보고서 제출 기한을 알려줘"],
        ],
        [4.5, 11.5],
    )

    return doc


def main() -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    doc = build_document()
    doc.save(OUTPUT_PATH)
    print(f"created: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
