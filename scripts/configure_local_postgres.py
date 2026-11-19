"""Manual masked local admin input; never persist/log the administrator password.

Creates a dedicated runtime role and migrates with the administrator connection.
Does not change PostgreSQL authentication, existing roles, or existing application rows.
"""

import json
import secrets
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import ttk

from alembic import command
from alembic.config import Config
from psycopg import sql
from sqlalchemy import URL, create_engine, inspect, text
from sqlalchemy.pool import NullPool

ROOT = Path(__file__).resolve().parents[1]
STATUS = ROOT / ".verification" / "postgres-setup.json"


def configure(username, password):
    env_path = ROOT / ".env"
    if env_path.exists():
        raise ValueError("Đã có .env; dừng để bảo toàn cấu hình. Cần đối chiếu trước khi chạy lại.")
    admin_url = URL.create(
        "postgresql+psycopg",
        username=username,
        password=password,
        host="127.0.0.1",
        port=5432,
        database="lynveris",
    )
    engine = create_engine(admin_url, poolclass=NullPool, connect_args={"connect_timeout": 5})
    role = "lynveris_app"
    app_password = secrets.token_urlsafe(40)
    with engine.begin() as connection:
        tables = inspect(connection).get_table_names()
        if "research_events" in tables and "alembic_version" not in tables:
            raise ValueError(
                "Có bảng research_events chưa có lịch sử migration; dừng để đối chiếu, không ghi đè."
            )
        if connection.execute(
            text("select 1 from pg_roles where rolname=:role"), {"role": role}
        ).scalar():
            role += "_" + secrets.token_hex(4)
        # PostgreSQL receives a SCRAM verifier, never the plaintext runtime password in DDL.
        driver = connection.connection.driver_connection
        verifier = driver.pgconn.encrypt_password(
            app_password.encode(), role.encode(), b"scram-sha-256"
        ).decode()
        driver.execute(
            sql.SQL(
                "CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD {}"
            ).format(sql.Identifier(role), sql.Literal(verifier))
        )
        config = Config(str(ROOT / "backend" / "alembic.ini"))
        config.set_main_option("script_location", str(ROOT / "backend" / "migrations"))
        config.attributes["connection"] = connection
        command.upgrade(config, "head")
        driver.execute(
            sql.SQL("GRANT CONNECT ON DATABASE lynveris TO {}").format(sql.Identifier(role))
        )
        driver.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(sql.Identifier(role)))
        driver.execute(
            sql.SQL("GRANT SELECT, INSERT, DELETE ON TABLE public.research_events TO {}").format(
                sql.Identifier(role)
            )
        )
        revision = connection.execute(text("select version_num from alembic_version")).scalar_one()
    engine.dispose()
    app_url = URL.create(
        "postgresql+psycopg",
        username=role,
        password=app_password,
        host="127.0.0.1",
        port=5432,
        database="lynveris",
    )
    runtime = create_engine(app_url, poolclass=NullPool)
    with runtime.connect() as connection:
        assert connection.execute(text("select current_database()")).scalar_one() == "lynveris"
        assert (
            connection.execute(
                text("select rolsuper from pg_roles where rolname=current_user")
            ).scalar_one()
            is False
        )
        connection.execute(text("select 1 from research_events limit 1"))
    runtime.dispose()
    env_path.write_text(
        "# Local only. Administrator password is never stored.\n"
        f"LYNVERIS_DATABASE_URL='{app_url.render_as_string(hide_password=False)}'\n"
        "LYNVERIS_AUTO_CREATE_DEV_DATABASE=false\n"
        "# Preserve existing rows during this local verification session.\n"
        "LYNVERIS_RETENTION_CLEANUP_ENABLED=false\n",
        encoding="utf-8",
    )
    # Limit this newly created secret file to this Windows account and SYSTEM.
    import os

    if os.name == "nt":
        sid = (
            subprocess.check_output(["whoami", "/user", "/fo", "csv", "/nh"], text=True)
            .strip()
            .split(",")[-1]
            .strip('"')
        )
        subprocess.run(
            ["icacls", str(env_path), "/inheritance:r", "/grant:r", f"*{sid}:(F)", "*S-1-5-18:(F)"],
            check=True,
            capture_output=True,
        )
    STATUS.write_text(
        json.dumps(
            {
                "status": "ready",
                "database": "lynveris",
                "port": 5432,
                "role": role,
                "revision": revision,
            }
        ),
        encoding="utf-8",
    )


def main():
    STATUS.parent.mkdir(exist_ok=True)
    STATUS.write_text('{"status":"waiting_for_local_password"}', encoding="utf-8")
    window = tk.Tk()
    window.title("Lynveris — Kết nối PostgreSQL local")
    window.geometry("600x320")
    window.attributes("-topmost", True)
    frame = ttk.Frame(window, padding=20)
    frame.pack(fill="both", expand=True)
    ttk.Label(
        frame,
        text="Database: lynveris • 127.0.0.1:5432\nNhập mật khẩu quản trị PostgreSQL trực tiếp tại đây.\nMật khẩu quản trị chỉ dùng trong bộ nhớ, không lưu vào tệp.",
    ).pack(anchor="w", pady=8)
    ttk.Label(frame, text="Tài khoản quản trị").pack(anchor="w")
    username = ttk.Entry(frame)
    username.insert(0, "postgres")
    username.pack(fill="x")
    ttk.Label(frame, text="Mật khẩu (không gửi qua chat)").pack(anchor="w", pady=(8, 0))
    password = ttk.Entry(frame, show="●")
    password.pack(fill="x")
    status = ttk.Label(
        frame,
        text="Tạo tài khoản ứng dụng riêng và chạy migrations; giữ dữ liệu hiện có.",
        wraplength=550,
    )
    status.pack(anchor="w", pady=12)

    def submit():
        button.configure(state="disabled")
        status.configure(text="Đang kết nối và chạy migrations…")
        window.update_idletasks()
        try:
            configure(username.get().strip(), password.get())
        except Exception as exc:
            # Driver messages can contain connection parameters. Show only safe categories.
            message = (
                str(exc)
                if isinstance(exc, ValueError)
                else "Chưa kết nối được. Kiểm tra tài khoản/mật khẩu và quyền quản trị PostgreSQL."
            )
            STATUS.write_text(
                json.dumps({"status": "needs_input", "error_type": type(exc).__name__}),
                encoding="utf-8",
            )
            status.configure(text=message)
            button.configure(state="normal")
        else:
            password.delete(0, "end")
            status.configure(
                text="Đã kết nối, chạy migration và lưu tài khoản ứng dụng vào .env local."
            )
            window.after(3000, window.destroy)

    button = ttk.Button(frame, text="Kết nối và cấu hình", command=submit)
    button.pack(anchor="e")
    password.focus_set()
    window.bind("<Return>", lambda event: submit())
    window.mainloop()


if __name__ == "__main__":
    main()
