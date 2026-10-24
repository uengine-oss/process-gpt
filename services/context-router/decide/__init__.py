"""Fast typed decisions: pick one of a few options, with a probability.

Three strategies, tried in order, the first one available wins:

1. ``JudgeModelStrategy`` -- a dedicated decision model (a JEV-style typed-decision
   endpoint, or the bundled ``judge_server`` over an open-weight model).
2. ``LogprobStrategy`` -- the chat LLM, asked for one option letter, read from the
   next-token log-probabilities. One token, a real distribution.
3. ``JsonStrategy`` -- the chat LLM answering in JSON. Works everywhere; the
   confidence it reports is the model's own claim, and is marked as such.
"""

from .base import Decision, Option
from .decider import Decider, from_env

__all__ = ["Decision", "Option", "Decider", "from_env"]
