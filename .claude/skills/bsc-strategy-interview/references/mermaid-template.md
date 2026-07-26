# Mermaid.js 전략맵 출력 형식

최종 승인 전, 검증을 통과한 전략맵을 아래 형식을 따라 생성한다. Miro, Eraser,
Notion, Obsidian 등 Mermaid 마크다운 문법을 지원하는 협업 도구에 그대로
붙여넣으면 렌더링되도록 문법을 정확히 지킨다.

## 표준 템플릿

```mermaid
graph BT
    %% 방향은 반드시 BT(Bottom-to-Top)를 사용한다 — 화살표 소스(L1, L2 ...)가
    %% 아래쪽에, 화살표 타깃(F1, F2 ...)이 위쪽에 배치되어 전통적인 전략맵처럼
    %% 맨 위에 재무적 결과, 맨 아래에 성장 인프라 역량이 오도록 만든다.
    %% (TD를 쓰면 반대로 학습·성장이 위, 재무가 아래로 뒤집혀 렌더링되니 금지)
    %% 스타일 정의 영역
    classDef financial fill:#EBF5FB,stroke:#2980B9,stroke-width:2px,color:#1B4F72;
    classDef customer fill:#E8F8F5,stroke:#117A65,stroke-width:2px,color:#0E6251;
    classDef process fill:#FEF9E7,stroke:#D35400,stroke-width:2px,color:#7E5109;
    classDef learning fill:#FDEDEC,stroke:#C0392B,stroke-width:2px,color:#78281F;

    %% 노드 정의 영역
    subgraph 재무적 결과 성과 (Financial Perspective)
        F1(F1: <재무 목표 1>):::financial
        F2(F2: <재무 목표 2>):::financial
    end

    subgraph 고객 관계 가치 (Customer Perspective)
        C1(C1: <고객 목표 1>):::customer
        C2(C2: <고객 목표 2>):::customer
    end

    subgraph 내부 운영 효율 (Internal Process Perspective)
        P1(P1: <프로세스 목표 1>):::process
        P2(P2: <프로세스 목표 2>):::process
    end

    subgraph 성장 인프라 역량 (Learning & Growth Perspective)
        L1(L1: <성장 목표 1>):::learning
        L2(L2: <성장 목표 2>):::learning
    end

    %% 인과적 연쇄 화살표 매핑 (학습·성장 → 프로세스 → 고객 → 재무 단방향만)
    L1 --> P1
    L2 --> P1

    P1 --> C1
    P2 --> C1

    C1 --> F1
    C2 --> F2

    %% 링크 선 스타일링
    linkStyle default stroke:#7F8C8D,stroke-width:2px;
```

## 작성 규칙

- 각 노드 ID는 관점 앞 글자(F/C/P/L) + 순번으로 부여한다 (F1, F2, C1, C2 ...).
- 노드 텍스트는 [validation-checklist.md](validation-checklist.md) 2번 규칙에
  따라 일회성 태스크가 아닌 전략 목표 문장으로 작성하고, 가능하면 목표 수치를
  포함한다 (예: "ARR 구독 매출 증가율 30% 달성").
- 화살표는 반드시 학습·성장 → 내부 프로세스 → 고객 → 재무 방향으로만 그린다.
  역행 화살표, 순환 구조는 절대 포함하지 않는다.
- 그래프 방향은 항상 `graph BT`로 고정한다. 화살표의 논리적 방향(학습·성장 →
  재무)은 그대로 유지하면서, 시각적으로는 재무적 결과가 맨 위, 성장 인프라
  역량이 맨 아래에 배치되는 전통적 전략맵 레이아웃을 만들기 위함이다.
- 모든 노드는 최소 1개 이상의 화살표로 연결되어야 한다 (고립 노드 금지).
- classDef 색상 팔레트는 고정 유지한다 (재무=파랑, 고객=초록, 프로세스=주황,
  학습·성장=빨강) — 경영진 보고 자료 간 일관성을 위해서다.

## Mermaid 코드와 함께 제공할 부속 자료

Mermaid 코드만 단독으로 제공하지 않는다. 항상 다음을 함께 묶어 전달한다:

1. Mermaid 코드 블록 (위 형식)
2. 각 노드(F1, F2, C1 ...)에 대응하는 선행 지표·후행 지표 표
   (예: | 노드 | 목표 | 후행 KPI | 선행 KPI | 담당 오너(미정 시 공란) |)
3. [SKILL.md](../SKILL.md)의 "최종 산출물" 섹션에 명시된 실행 권고사항 3가지
