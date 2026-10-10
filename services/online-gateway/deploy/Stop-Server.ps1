param([string]$DataDirectory = "$env:LOCALAPPDATA\SIDcloud\EpochRushServer",[switch]$Force)
$ErrorActionPreference = 'Stop'
$serverDataRoot = [IO.Path]::GetFullPath($DataDirectory)
if (!(Test-Path -LiteralPath $serverDataRoot)) { Write-Output 'No server data directory.'; exit 0 }
$serverDrain = Join-Path $serverDataRoot 'draining.flag'
New-Item -ItemType File -Path $serverDrain -Force | Out-Null
$serverPidFile = Join-Path $serverDataRoot 'gateway.pid'
if (Test-Path -LiteralPath $serverPidFile) {
$serverPid = [int](Get-Content -LiteralPath $serverPidFile -Raw)
$serverRuntime = Get-Content -LiteralPath (Join-Path $serverDataRoot 'runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$serverExpected = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'bin\epoch-online.exe'))
$serverProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$serverPid"
if ($serverProcess) {
if ($serverProcess.ExecutablePath -ne $serverExpected -or $serverRuntime.binary -ne $serverExpected) { throw 'PID does not belong to this extracted server; no process was stopped.' }
$serverStatus = $null
try {
for ($serverDrainAttempt=0; $serverDrainAttempt -lt 20; $serverDrainAttempt++) {
    $serverStatus = Invoke-RestMethod -Uri "http://127.0.0.1:$($serverRuntime.port)/healthz" -TimeoutSec 2
    if ($serverStatus.draining) { break }
    Start-Sleep -Milliseconds 100
}
} catch { if (!$Force) { throw } }
if (!$Force -and (!$serverStatus -or !$serverStatus.draining)) { throw 'Admission has not stopped; gateway remains running.' }
if (!$Force -and $serverStatus.active_matches -gt 0) { Write-Output "Draining: $($serverStatus.active_matches) matches still active. Run Stop-Server again when empty, or use -Force for a recoverable immediate stop."; exit 0 }
Stop-Process -Id $serverPid
}}
if (Test-Path -LiteralPath (Join-Path $serverDataRoot 'pgdata\postmaster.pid')) {
    $serverPostgresPid=[int](Get-Content -LiteralPath (Join-Path $serverDataRoot 'pgdata\postmaster.pid') -TotalCount 1)
    $serverPostgres=Get-CimInstance Win32_Process -Filter "ProcessId=$serverPostgresPid"
    $serverPostgresExpected=[IO.Path]::GetFullPath((Join-Path $serverDataRoot 'pgsql\bin\postgres.exe'))
    if ($serverPostgres -and $serverPostgres.ExecutablePath -ne $serverPostgresExpected) { throw 'Database PID does not belong to this data directory; no database was stopped.' }
    & (Join-Path $serverDataRoot 'pgsql\bin\pg_ctl.exe') -D (Join-Path $serverDataRoot 'pgdata') stop -m fast -w *> $null
}
Remove-Item -LiteralPath $serverPidFile -ErrorAction SilentlyContinue
Write-Output 'Native gateway and its isolated database stopped. Persistent data retained.'
