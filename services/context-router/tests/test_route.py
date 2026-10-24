import pytest

from decide.base import Decision
import importlib
route_mod = importlib.import_module("router.route")
from router.route import NEW, route


class FakeDecider:
    def __init__(self, choice, conf, calibrated=True):
        self.d = (choice, conf, calibrated)

    async def decide(self, state, question, options):
        choice, conf, cal = self.d
        keys = [o.key for o in options]
        rest = (1 - conf) / (len(keys) - 1)
        return Decision(choice, {k: conf if k == choice else rest for k in keys}, "fake", 1, cal)


@pytest.fixture(autouse=True)
def history(monkeypatch):
    async def recent(tenant, user, limit=200):
        return [{"conversation_id": "conv-yt", "title": "경제사냥꾼 유튜브", "summary": "최근 영상 3개"},
                {"conversation_id": "conv-trip", "title": "부산 출장", "summary": "숙소 추천"}]
    monkeypatch.setattr(route_mod.store, "recent", recent)


@pytest.mark.asyncio
async def test_confident_pick_continues_that_conversation():
    r = await route(FakeDecider("conv-trip", 0.9), message="해운대 쪽이면 좋겠어", tenant_id="t", user_id="u", current="conv-yt")
    assert r.action == "continue" and r.conversation_id == "conv-trip" and r.context["title"] == "부산 출장"


@pytest.mark.asyncio
async def test_confident_new_opens_a_conversation():
    r = await route(FakeDecider(NEW, 0.95), message="환율 알려줘", tenant_id="t", user_id="u", current="conv-yt")
    assert r.action == "new" and r.conversation_id not in ("conv-yt", "conv-trip")


@pytest.mark.asyncio
async def test_unsure_stays_where_the_user_is():
    r = await route(FakeDecider("conv-trip", 0.45), message="그거 다시", tenant_id="t", user_id="u", current="conv-yt")
    assert r.action == "stay" and r.conversation_id == "conv-yt"


@pytest.mark.asyncio
async def test_self_reported_confidence_needs_a_higher_bar():
    r = await route(FakeDecider("conv-trip", 0.62, calibrated=False), message="그거", tenant_id="t", user_id="u", current="conv-yt")
    assert r.action == "stay"


@pytest.mark.asyncio
async def test_client_contexts_join_the_candidates():
    seen = {}
    class Spy(FakeDecider):
        async def decide(self, state, question, options):
            seen["keys"] = [o.key for o in options]
            return await super().decide(state, question, options)
    await route(Spy("task-1", 0.9), message="그 작업 매일 돌려줘", tenant_id="t", user_id="u", current=None,
                client_contexts=[{"conversation_id": "task-1", "title": "X 핫토픽 팟캐스트 제작", "kind": "task", "active": True}])
    assert seen["keys"][0] == "task-1" and NEW in seen["keys"]
