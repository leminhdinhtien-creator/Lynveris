param([int]$Port = 8000)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$pythonExe = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
    python -m venv .venv
    & $pythonExe -m pip install -r backend/requirements.lock
    & $pythonExe -m pip install --no-deps -e backend
}
& $pythonExe -m alembic -c backend/alembic.ini upgrade head
if ($LASTEXITCODE -ne 0) { throw 'Database migration failed.' }
& $pythonExe -m uvicorn lynveris.api:app --host 127.0.0.1 --port $Port --no-access-log --no-proxy-headers
