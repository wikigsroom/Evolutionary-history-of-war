param(
    [int]$Port = 28187,
    [int]$DatabasePort = 54329,
    [int]$MaxMatches = 10,
    [switch]$LocalOnly,
    [switch]$TrustLocalProxy,
    [string]$DataDirectory = "$env:LOCALAPPDATA\SIDcloud\EpochRushServer"
)
$ErrorActionPreference = 'Stop'
$serverBundleRoot = $PSScriptRoot
foreach ($serverRuntimeLibrary in @('MSVCP140.dll','VCRUNTIME140.dll','VCRUNTIME140_1.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path "$env:WINDIR\System32" $serverRuntimeLibrary))) { throw 'Install the official Microsoft Visual C++ 2015-2022 x64 runtime before starting native PostgreSQL: https://aka.ms/vs/17/release/vc_redist.x64.exe' }
}
$serverDataRoot = [IO.Path]::GetFullPath($DataDirectory)
if ($Port -lt 1024 -or $Port -gt 65535 -or $DatabasePort -lt 1024 -or $DatabasePort -gt 65535) { throw 'Invalid native service port.' }
if ($serverDataRoot -match '[^\x00-\x7F]') { throw 'PostgreSQL on Windows requires an ASCII data directory. Use -DataDirectory with an ASCII path.' }
New-Item -ItemType Directory -Path $serverDataRoot -Force | Out-Null
$serverBinary = Join-Path $serverBundleRoot 'bin\epoch-online.exe'
$serverReferee = Join-Path $serverBundleRoot 'referee'
$serverEngine = Join-Path $serverBundleRoot 'engine\Godot.exe'
foreach ($required in @($serverBinary,$serverEngine,(Join-Path $serverReferee 'project.godot'))) { if (!(Test-Path -LiteralPath $required)) { throw 'Extract the complete server ZIP before starting.' } }
$serverPidFile = Join-Path $serverDataRoot 'gateway.pid'
if (Test-Path -LiteralPath $serverPidFile) {
    $serverExistingPid = [int](Get-Content -LiteralPath $serverPidFile -Raw)
    $serverExisting = Get-CimInstance Win32_Process -Filter "ProcessId=$serverExistingPid"
    if ($serverExisting -and $serverExisting.ExecutablePath -eq $serverBinary) { Write-Output "Server already running (PID $serverExistingPid)."; exit 0 }
}
$serverPgRoot = Join-Path $serverDataRoot 'pgsql'
if (!(Test-Path -LiteralPath (Join-Path $serverPgRoot 'bin\postgres.exe'))) { Copy-Item -LiteralPath (Join-Path $serverBundleRoot 'pgsql') -Destination $serverPgRoot -Recurse }
$serverPgBin = Join-Path $serverPgRoot 'bin'
$serverPgData = Join-Path $serverDataRoot 'pgdata'
$serverCredentialFile = Join-Path $serverDataRoot 'database-credential.xml'
if (Test-Path -LiteralPath $serverCredentialFile) {
    $serverDatabaseCredential = Import-Clixml -LiteralPath $serverCredentialFile
} else {
    $serverRandomBytes = New-Object byte[] 32
    $serverRandom = [Security.Cryptography.RandomNumberGenerator]::Create()
    $serverRandom.GetBytes($serverRandomBytes); $serverRandom.Dispose()
    $serverPassword = ([BitConverter]::ToString($serverRandomBytes)).Replace('-','').ToLowerInvariant()
    $serverDatabaseCredential = New-Object System.Management.Automation.PSCredential('epoch',(ConvertTo-SecureString $serverPassword -AsPlainText -Force))
    $serverDatabaseCredential | Export-Clixml -LiteralPath $serverCredentialFile
}
$serverPassword = $serverDatabaseCredential.GetNetworkCredential().Password
if (!(Test-Path -LiteralPath (Join-Path $serverPgData 'PG_VERSION'))) {
    $serverPasswordFile = Join-Path $serverDataRoot 'init-password.tmp'
    [IO.File]::WriteAllText($serverPasswordFile,$serverPassword,(New-Object Text.UTF8Encoding($false)))
    try {
        & (Join-Path $serverPgBin 'initdb.exe') -D $serverPgData -U epoch -A scram-sha-256 --pwfile $serverPasswordFile --encoding UTF8 --locale C *> (Join-Path $serverDataRoot 'initdb.log')
        if ($LASTEXITCODE -ne 0) { throw 'Native PostgreSQL initialization failed; inspect initdb.log.' }
    } finally { Remove-Item -LiteralPath $serverPasswordFile -ErrorAction SilentlyContinue }
}
& (Join-Path $serverPgBin 'pg_ctl.exe') -D $serverPgData status *> $null
if ($LASTEXITCODE -ne 0) {
    # A background postgres child must not inherit a PowerShell capture pipe;
    # otherwise the shell waits for that pipe even after pg_ctl exits.
    $serverPostgresArguments=@('-D',"`"$serverPgData`"",'-l',"`"$(Join-Path $serverDataRoot 'postgres.log')`"",'-o',"`"-p $DatabasePort -h 127.0.0.1`"",'start','-w')
    $serverPostgresStarter=Start-Process -FilePath (Join-Path $serverPgBin 'pg_ctl.exe') -ArgumentList $serverPostgresArguments -WindowStyle Hidden -PassThru
    if (!$serverPostgresStarter.WaitForExit(30000) -or $serverPostgresStarter.ExitCode -ne 0) { throw 'Native PostgreSQL startup failed; inspect postgres.log.' }
}
# Keep the actual process handle: Windows PowerShell 5 Start-Process can report
# a null exit code for Godot's GUI-subsystem executable after a successful import.
$serverImportInfo = New-Object Diagnostics.ProcessStartInfo
$serverImportInfo.FileName = $serverEngine
$serverImportInfo.Arguments = "--headless --path `"$serverReferee`" --editor --import --quit"
$serverImportInfo.UseShellExecute = $false
$serverImportInfo.CreateNoWindow = $true
$serverImportInfo.RedirectStandardOutput = $true
$serverImportInfo.RedirectStandardError = $true
$serverImporter = New-Object Diagnostics.Process
$serverImporter.StartInfo = $serverImportInfo
try {
    if (!$serverImporter.Start()) { throw 'Could not start the native referee importer.' }
    $serverImportOutput = $serverImporter.StandardOutput.ReadToEndAsync()
    $serverImportErrors = $serverImporter.StandardError.ReadToEndAsync()
    if (!$serverImporter.WaitForExit(60000)) {
        $serverImporter.Kill()
        $serverImporter.WaitForExit()
        throw 'Referee import timed out.'
    }
    $serverImportExitCode = $serverImporter.ExitCode
    [IO.File]::WriteAllText((Join-Path $serverDataRoot 'referee-import.log'),$serverImportOutput.Result,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $serverDataRoot 'referee-import.stderr.log'),$serverImportErrors.Result,(New-Object Text.UTF8Encoding($false)))
    if ($serverImportExitCode -ne 0 -or $serverImportErrors.Result -match 'SCRIPT ERROR:|Parse Error:') { throw 'Referee import failed; inspect referee-import.log and referee-import.stderr.log.' }
} finally { $serverImporter.Dispose() }
$env:EPOCH_DATABASE_URL = "postgres://epoch:$serverPassword@127.0.0.1:$DatabasePort/postgres?sslmode=disable"
$serverAddress = if ($LocalOnly) { '127.0.0.1' } else { '0.0.0.0' }
$serverArguments = @('--listen',"${serverAddress}:$Port",'--max-matches',"$MaxMatches",'--project',"`"$serverReferee`"",'--godot',"`"$serverEngine`"",'--drain-file',"`"$(Join-Path $serverDataRoot 'draining.flag')`"")
if ($TrustLocalProxy) { $serverArguments += '--trust-local-proxy' }
try {
    $serverProcess = Start-Process -FilePath $serverBinary -ArgumentList $serverArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $serverDataRoot 'gateway.stdout.log') -RedirectStandardError (Join-Path $serverDataRoot 'gateway.stderr.log')
} finally { Remove-Item Env:EPOCH_DATABASE_URL -ErrorAction SilentlyContinue; $serverPassword = $null }
[IO.File]::WriteAllText($serverPidFile,[string]$serverProcess.Id)
[IO.File]::WriteAllText((Join-Path $serverDataRoot 'runtime.json'),(@{port=$Port;database_port=$DatabasePort;binary=$serverBinary} | ConvertTo-Json))
for ($serverAttempt = 0; $serverAttempt -lt 40; $serverAttempt++) {
    if ($serverProcess.HasExited) { throw 'Gateway exited; inspect gateway.stderr.log.' }
    try {
        $serverHealth = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/healthz" -TimeoutSec 1
        if ($serverHealth.ok) {
            Write-Output "Server ready: http://127.0.0.1:$Port (PID $($serverProcess.Id))"
            if (!$LocalOnly) { Write-Output "Clients on the same LAN use http://<this computer's LAN IPv4>:$Port" }
            Write-Output "Persistent data: $serverDataRoot"
            exit 0
        }
    } catch {}
    Start-Sleep -Milliseconds 250
}
throw 'Gateway did not pass its health check.'
