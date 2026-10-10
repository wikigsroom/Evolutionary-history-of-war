param([string]$DataDirectory = "$env:LOCALAPPDATA\SIDcloud\EpochRushServer")
$serverDrain = Join-Path ([IO.Path]::GetFullPath($DataDirectory)) 'draining.flag'
Remove-Item -LiteralPath $serverDrain -ErrorAction SilentlyContinue
Write-Output 'New room admission resumes within one second.'
