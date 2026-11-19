param([int]$Port = 8000, [switch]$Migrate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$pythonExe = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonExe)) {
    python -m venv .venv
    & $pythonExe -m pip install -r backend/requirements.lock
    & $pythonExe -m pip install --no-deps -e backend
}
if ($Migrate) {
    # Use a migration account explicitly. The local runtime role cannot alter schema.
    & $pythonExe -m alembic -c backend/alembic.ini upgrade head
    if ($LASTEXITCODE -ne 0) { throw 'Database migration failed. Use the migration account, not the runtime role.' }
}
& $pythonExe -m uvicorn lynveris.api:app --host 127.0.0.1 --port $Port --no-access-log --no-proxy-headers
