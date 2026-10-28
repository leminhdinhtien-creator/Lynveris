import asyncio
import hashlib
import secrets
import time
from collections import OrderedDict, deque
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .config import Settings
from .database import Base, cleanup, delete_events, engine_for, record_event
from .model import UrlModel
from .schemas import CheckRequest, CheckResult
from .service import check_url
from .threats import GoogleSafeBrowsing
from .urls import UrlError


class RequestGuard:
    """Bounded body, fixed-window per client, no raw IP or body logging."""

    def __init__(self, app, limit):
        self.app, self.limit = app, limit
        self.clients = OrderedDict()
        self.salt = secrets.token_bytes(32)

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["path"] in {"/health", "/ready"}:
            return await self.app(scope, receive, send)
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            body.extend(message.get("body", b""))
            if len(body) > 16384:
                return await JSONResponse({"detail": "Dữ liệu gửi lên quá lớn."}, 413)(
                    scope, receive, send
                )
            if not message.get("more_body", False):
                break
        if scope["method"] != "OPTIONS":
            client = str(scope.get("client", ("unknown",))[0])
            key = hashlib.sha256(self.salt + client.encode()).hexdigest()
            t = time.monotonic()
            times = self.clients.setdefault(key, deque())
            while times and times[0] <= t - 60:
                times.popleft()
            if len(times) >= self.limit:
                return await JSONResponse(
                    {"detail": "Bạn đã kiểm tra nhiều lần. Vui lòng chờ một phút."},
                    429,
                    headers={"Retry-After": "60"},
                )(scope, receive, send)
            times.append(t)
            self.clients.move_to_end(key)
            while len(self.clients) > 4096:
                self.clients.popitem(last=False)
        sent = False

        async def replay():
            nonlocal sent
            if not sent:
                sent = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)


def create_app(settings: Settings | None = None):
    settings = settings or Settings()
    engine = engine_for(settings.database_url)
    source = GoogleSafeBrowsing(settings.google_api_key)
    model = UrlModel(settings.model_directory)

    @asynccontextmanager
    async def lifespan(app):
        if settings.database_url.startswith("sqlite") and settings.auto_create_dev_database:
            Base.metadata.create_all(engine)
        await run_in_threadpool(cleanup, engine)

        async def janitor():
            while True:
                await asyncio.sleep(3600)
                try:
                    await run_in_threadpool(cleanup, engine)
                except SQLAlchemyError:
                    pass

        task = asyncio.create_task(janitor())
        yield
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        engine.dispose()

    app = FastAPI(title="Lynveris API", version="0.1.0", lifespan=lifespan)
    app.state.engine, app.state.source, app.state.model = engine, source, model
    app.add_middleware(RequestGuard, limit=settings.rate_limit_per_minute)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["Content-Type", "X-Deletion-Token"],
    )

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        # Pydantic's default errors echo input; never expose complete pasted messages or secrets.
        return JSONResponse(
            {"detail": "Dữ liệu không hợp lệ. Chỉ gửi một URL, tối đa 4.096 ký tự."}, 422
        )

    @app.get("/health")
    def health():
        return {"status": "ok", "version": "0.1.0"}

    @app.get("/ready")
    def ready():
        try:
            with engine.connect() as db:
                db.execute(text("select 1 from research_events limit 1"))
        except SQLAlchemyError:
            raise HTTPException(503, "Cơ sở dữ liệu chưa sẵn sàng.") from None
        return {
            "status": "ready",
            "model": "ready" if model.pipeline is not None else "unavailable",
            "threat": "configured" if settings.google_api_key else "not_configured",
            "redirects": "disabled",
        }

    @app.post("/v1/check", response_model=CheckResult)
    async def check(request: CheckRequest):
        if request.research_consent and not request.deletion_token:
            raise HTTPException(422, "Cần mã xoá dữ liệu khi bật đóng góp thống kê.")
        try:
            result = await check_url(request, source, model)
        except UrlError as exc:
            raise HTTPException(422, str(exc)) from None
        if request.research_consent:
            try:
                await run_in_threadpool(record_event, engine, result, request.deletion_token)
            except SQLAlchemyError:
                result.limitations.append(
                    "Không lưu được thống kê đã đồng ý; kết quả kiểm tra vẫn hiển thị."
                )
        return result

    @app.delete("/v1/research")
    def erase(x_deletion_token: str = Header(min_length=32, max_length=128)):
        deleted = delete_events(engine, x_deletion_token)
        source.clear_cache()
        return {"deleted": deleted}

    return app


app = create_app()
