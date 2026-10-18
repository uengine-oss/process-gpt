"""프로세스 트리 표현.

Inductive Miner 가 만들어 내는 중간 표현. 트리로 만들기 때문에 구조적으로
건전(sound)하다 — 도달 불가 노드나 교착이 생길 수 없다. 이 성질이 LLM 에게
BPMN XML 을 직접 쓰게 하지 않고 이 경로를 택한 이유다.
"""
from __future__ import annotations

from dataclasses import dataclass, field

SEQ = "seq"
XOR = "xor"
AND = "and"
LOOP = "loop"
ACT = "act"
TAU = "tau"  # 보이지 않는 단계(빈 분기)


@dataclass
class Node:
    kind: str
    label: str | None = None
    children: list["Node"] = field(default_factory=list)

    def __repr__(self) -> str:  # 테스트 가독성용
        if self.kind == ACT:
            return f"'{self.label}'"
        if self.kind == TAU:
            return "τ"
        return f"{self.kind}({', '.join(repr(c) for c in self.children)})"

    def activities(self) -> list[str]:
        if self.kind == ACT:
            return [self.label]
        out: list[str] = []
        for c in self.children:
            out.extend(c.activities())
        return out


def act(label: str) -> Node:
    return Node(ACT, label=label)


def tau() -> Node:
    return Node(TAU)


def flatten(node: Node) -> Node:
    """중첩된 동종 연산자를 하나로 접는다. seq(a, seq(b,c)) → seq(a,b,c)"""
    if node.kind in (ACT, TAU):
        return node
    children: list[Node] = []
    for c in (flatten(ch) for ch in node.children):
        if c.kind == node.kind and node.kind in (SEQ, XOR, AND):
            children.extend(c.children)
        else:
            children.append(c)
    # 단일 자식 연산자는 자식으로 대체
    if len(children) == 1 and node.kind in (SEQ, XOR, AND):
        return children[0]
    return Node(node.kind, children=children)
