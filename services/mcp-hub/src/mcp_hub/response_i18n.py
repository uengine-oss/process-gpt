"""Locale-aware response rewriting.

The hub produces Korean display strings of its own: conformance rule text and grades,
integration-standard guidance, and connection/validation error messages. When a client
asks for English -- via ``Accept-Language`` or ``?lang=en`` -- those strings are
rewritten on the way out. Only string leaves change; the payload shape is untouched.
"""
import json
import os

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "i18n_ko_en.json"), encoding="utf-8") as fp:
    _MAP = json.load(fp)

# Longest first, so a phrase is never half-rewritten by one of its own substrings.
_PAIRS = sorted(_MAP.items(), key=lambda kv: -len(kv[0]))
# Only longer keys are safe to rewrite *inside* a larger string: a bare "월" would
# otherwise turn "1개월 이내" into "1개Month 이내". Short keys still match whole strings.
_LONG_PAIRS = [(korean, english) for korean, english in _PAIRS if len(korean) >= 3]


def _has_hangul(text: str) -> bool:
    return any("가" <= ch <= "힣" for ch in text)


def wants_english(request) -> bool:
    """An explicit ?lang= wins; otherwise fall back to the browser's Accept-Language."""
    lang = request.query_params.get("lang")
    if lang:
        return lang.lower().startswith("en")
    header = request.headers.get("accept-language", "")
    return header.split(",")[0].strip().lower().startswith("en")


def translate(value):
    if isinstance(value, str):
        if not _has_hangul(value):
            return value
        exact = _MAP.get(value.strip())
        if exact is not None:
            return value.replace(value.strip(), exact)
        for korean, english in _LONG_PAIRS:
            if korean in value:
                value = value.replace(korean, english)
        return value
    if isinstance(value, list):
        return [translate(item) for item in value]
    if isinstance(value, dict):
        return {key: translate(item) for key, item in value.items()}
    return value


class LocaleResponseMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        if not wants_english(request):
            return response
        if not response.headers.get("content-type", "").startswith("application/json"):
            return response

        body = b"".join([chunk async for chunk in response.body_iterator])
        headers = dict(response.headers)
        headers.pop("content-length", None)
        try:
            payload = json.loads(body)
        except (ValueError, UnicodeDecodeError):
            # Not something we can safely rewrite - pass it through untouched.
            return Response(content=body, status_code=response.status_code,
                            headers=headers, media_type=response.media_type)

        rewritten = json.dumps(translate(payload), ensure_ascii=False).encode("utf-8")
        return Response(content=rewritten, status_code=response.status_code,
                        headers=headers, media_type="application/json")
