"""Local QA service with a genuinely missing Google key; no fake source responses."""

import uvicorn
from lynveris.api import create_app
from lynveris.config import Settings

if __name__ == "__main__":
    uvicorn.run(
        create_app(
            Settings(google_api_key="", threat_provider="combined", retention_cleanup_enabled=False)
        ),
        host="127.0.0.1",
        port=8003,
        access_log=False,
        proxy_headers=False,
    )
