import hashlib
import unicodedata
from datetime import datetime, timezone
from functools import lru_cache
from uuid import uuid4

from .schemas import CheckRequest, CheckResult, Signal, ThreatResult, UrlInfo
from .urls import BRANDS, DATA, inspect_url, parse_url


@lru_cache(maxsize=1)
def data_versions():
    return {
        "brands": BRANDS["version"],
        "brands_sha256": hashlib.sha256((DATA / "brands.json").read_bytes()).hexdigest(),
        "python_unicode": unicodedata.unidata_version,
        "features": "url-v1",
        "psl_sha256": hashlib.sha256((DATA / "public_suffix_list.dat").read_bytes()).hexdigest(),
        "confusables_sha256": hashlib.sha256((DATA / "confusables.txt").read_bytes()).hexdigest(),
        "unicode_confusables": "17.0.0",
    }


async def check_url(request: CheckRequest, source, model) -> CheckResult:
    p = parse_url(request.url)
    inspection = inspect_url(p)
    prediction = model.predict(p.original)
    threat = (
        await source.check(p.fetch_url)
        if request.use_threat_intelligence
        else ThreatResult(
            status="skipped",
            source=getattr(source, "SOURCE", "Google Safe Browsing"),
        )
    )
    signals = inspection.signals
    limitations = [
        "Chỉ phân tích địa chỉ URL; không xem nội dung trang, tuổi miền, DNS hay chứng chỉ.",
        "Có thể bỏ sót đường link lừa đảo hoặc cảnh báo nhầm. Không có kết quả an toàn tuyệt đối.",
    ]
    if prediction.status != "ready":
        limitations.append(
            "Mô hình học máy chưa sẵn sàng; chưa có đánh giá khả năng phát hiện URL mới."
        )
    elif (getattr(model, "manifest", None) or {}).get(
        "evaluation_protocol"
    ) == "retrospective_collection_date":
        limitations.append(
            "Đây là mô hình thử nghiệm, được đánh giá hồi cứu theo ngày thu dữ liệu; chưa kiểm chứng khả năng phát hiện đường link mới chưa có trong nguồn tin đe doạ."
        )
    evaluation = getattr(model, "evaluation", None)
    if evaluation and evaluation["combined"]["fpr"] > 0.05:
        limitations.append(
            "Mô hình chưa đạt mục tiêu cảnh báo nhầm tối đa 5% trên tập kiểm thử độc lập. Hãy xác minh thêm qua nguồn chính thức."
        )
    if threat.status != "detected":
        descriptions = {
            "not_found": "Nguồn tin đe doạ chưa ghi nhận URL; điều đó không chứng minh URL hợp lệ.",
            "skipped": "Chưa tra nguồn tin đe doạ vì bạn chưa bật tra nguồn.",
            "not_configured": "Nguồn tin đe doạ chưa được cấu hình trên máy chủ.",
            "error": "Nguồn tin đe doạ gặp lỗi; chưa có kết quả tra cứu.",
            "timeout": "Tra nguồn quá thời gian chờ; chưa có kết quả.",
            "quota": "Nguồn tin đe doạ đã giới hạn lượt tra cứu; thử lại sau.",
        }
        limitations.append(descriptions[threat.status])
    if threat.partial:
        limitations.append(
            "Một phần nguồn tin đe doạ chưa trả được kết quả; xem trạng thái từng nguồn trong chi tiết."
        )
    if threat.status == "detected":
        verdict = "high"
        signals.append(
            Signal(
                code="threat_match",
                title="Nguồn tin ghi nhận nguy cơ",
                detail=threat.source
                + " ghi nhận nguy cơ có thể xảy ra: "
                + ", ".join(threat.categories),
                severity="strong",
                source="threat",
            )
        )
    elif prediction.status == "ready":
        # Exactly the same positive policy that is calibrated/evaluated by the ML pipeline.
        verdict = (
            "caution"
            if prediction.alert or any(s.severity == "strong" for s in signals)
            else "no_signs"
        )
    else:
        verdict = "caution" if any(s.severity == "strong" for s in signals) else "insufficient"
    if prediction.status == "ready" and prediction.alert:
        signals.append(
            Signal(
                code="model_alert",
                title="Mô hình phát hiện mẫu URL cần thận trọng",
                detail="Điểm phân loại vượt ngưỡng đã chọn trên validation. "
                "Điểm mô hình không phải xác suất lừa đảo đã hiệu chỉnh.",
                severity="strong",
                source="model",
            )
        )
    if inspection.shortener:
        limitations.append(
            "Chưa xác định URL đích của link rút gọn. Không tự truy cập hay theo chuyển hướng."
        )
        if verdict == "no_signs":
            verdict = "insufficient"
    if verdict == "no_signs" and (
        threat.partial or threat.status in {"error", "timeout", "quota", "not_configured"}
    ):
        verdict = "insufficient"
    titles = {
        "high": "Nguy cơ cao",
        "caution": "Cần thận trọng",
        "no_signs": "Chưa phát hiện dấu hiệu đáng ngờ",
        "insufficient": "Chưa đủ thông tin",
    }
    summaries = {
        "high": "Đường link có thể dẫn đến lừa đảo hoặc nội dung gây hại. Hãy dừng trước khi mở.",
        "caution": "Có dấu hiệu cần xác minh. Hãy đối chiếu qua ứng dụng hoặc trang chính thức.",
        "no_signs": "Chưa phát hiện dấu hiệu đáng ngờ trong phạm vi kiểm tra; vẫn cần xác minh người gửi.",
        "insufficient": "Các kiểm tra hiện có chưa đủ để kết luận. Hãy xác minh trước khi thao tác.",
    }
    return CheckResult(
        id=str(uuid4()),
        checked_at=datetime.now(timezone.utc),
        verdict=verdict,
        title=titles[verdict],
        summary=summaries[verdict],
        url=UrlInfo(**{k: getattr(p, k) for k in UrlInfo.model_fields}),
        signals=signals,
        model=prediction,
        threat=threat,
        redirect={
            "status": "not_requested",
            "detail": "Không truy cập URL gốc hoặc URL đích. Chưa xác minh chuyển hướng.",
        },
        limitations=limitations,
        actions=[
            "Mở ứng dụng chính thức hoặc tự nhập địa chỉ đã biết để kiểm tra.",
            "Không nhập mật khẩu, mã OTP hoặc chuyển tiền khi chưa xác minh.",
            "Nếu vẫn phân vân, chia sẻ kết quả này để nhờ người thân kiểm tra.",
        ],
        versions=data_versions(),
    )
