from __future__ import annotations

import string
from dataclasses import dataclass, field
from typing import Protocol

LETTERS = string.ascii_uppercase


@dataclass(frozen=True)
class Option:
    key: str
    label: str
    hint: str = ""


@dataclass
class Decision:
    choice: str
    probabilities: dict[str, float]
    strategy: str
    latency_ms: int
    #: True when the number comes from token probabilities (or a judge model), False when
    #: the model merely stated it (JSON). Callers should not threshold a stated number the
    #: same way as a measured one.
    calibrated: bool = True
    model: str = ""
    notes: list[str] = field(default_factory=list)

    @property
    def confidence(self) -> float:
        return self.probabilities.get(self.choice, 0.0)

    def as_dict(self) -> dict:
        return {
            "choice": self.choice,
            "confidence": round(self.confidence, 4),
            "probabilities": {k: round(v, 4) for k, v in self.probabilities.items()},
            "strategy": self.strategy,
            "calibrated": self.calibrated,
            "model": self.model,
            "latency_ms": self.latency_ms,
            "notes": self.notes,
        }


class Strategy(Protocol):
    name: str

    async def decide(self, state: str, question: str, options: list[Option]) -> Decision | None:
        """A decision, or None when this strategy cannot serve (not configured, not supported)."""


def lettered(options: list[Option]) -> list[tuple[str, Option]]:
    if len(options) > len(LETTERS):
        raise ValueError(f"at most {len(LETTERS)} options")
    return list(zip(LETTERS, options))


def prompt_for(state: str, question: str, options: list[Option], *, answer_line: str) -> str:
    lines = [state.strip(), "", question.strip(), ""]
    for letter, o in lettered(options):
        lines.append(f"{letter}) {o.label}" + (f" — {o.hint}" if o.hint else ""))
    lines += ["", answer_line]
    return "\n".join(lines)
