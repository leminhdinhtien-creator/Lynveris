"""Manual masked local input. Never log the key or place it on a command line."""

import asyncio
import json
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from lynveris.local_setup import update_google_key
from lynveris.threats import GoogleSafeBrowsing

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / ".verification/google-key-setup.json"


def main():
    STATUS.write_text('{"status":"waiting_for_local_key"}', encoding="utf-8")
    window = tk.Tk()
    window.title("Lynveris — Google Safe Browsing API key")
    window.geometry("650x300")
    window.attributes("-topmost", True)
    frame = ttk.Frame(window, padding=20)
    frame.pack(fill="both", expand=True)
    ttk.Label(
        frame,
        text="Nhập khoá Google Safe Browsing trực tiếp tại đây.\nKhoá chỉ lưu trong .env local, không đưa vào chat, ảnh hoặc Git.\nGiữ nguyên PostgreSQL và provider OpenPhish đang hoạt động.",
    ).pack(anchor="w", pady=8)
    entry = ttk.Entry(frame, show="●")
    entry.pack(fill="x", pady=8)
    status = ttk.Label(
        frame,
        text="Cần bật Safe Browsing API v4 cho dự án chứa khoá.\nChỉ đối chiếu example.org để xác minh khoá; không mở trang đích.",
        wraplength=600,
    )
    status.pack(anchor="w", pady=8)

    def save():
        button.configure(state="disabled")
        window.update_idletasks()
        try:
            key = entry.get().strip()
            if not key:
                raise ValueError("empty")
            result = asyncio.run(GoogleSafeBrowsing(key).check("https://example.org/"))
            if result.status not in {"detected", "not_found"}:
                status.configure(
                    text="Chưa xác minh được khoá/API. Kiểm tra dịch vụ đã bật, quyền của khoá và quota rồi thử lại. Không gửi khoá qua chat."
                )
                STATUS.write_text(
                    json.dumps({"status": "needs_input", "provider_status": result.status}),
                    encoding="utf-8",
                )
                button.configure(state="normal")
                return
            update_google_key(ROOT / ".env", key)
            entry.delete(0, "end")
            STATUS.write_text('{"status":"ready"}', encoding="utf-8")
            status.configure(
                text="Khoá đã được xác minh và lưu local. OpenPhish vẫn hoạt động như trước."
            )
            window.after(3000, window.destroy)
        except Exception:
            STATUS.write_text('{"status":"needs_input"}', encoding="utf-8")
            status.configure(
                text="Chưa lưu được cấu hình. Kiểm tra định dạng khoá và quyền ghi .env; không gửi khoá qua chat."
            )
            button.configure(state="normal")

    button = ttk.Button(frame, text="Xác minh và lưu local", command=save)
    button.pack(anchor="e", pady=8)
    entry.focus_set()
    window.mainloop()


if __name__ == "__main__":
    main()
