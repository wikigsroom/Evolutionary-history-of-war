param([ValidateSet('protect','unprotect')][string]$Mode)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
try {
    # Secret data travels over redirected stdin/stdout, never process arguments.
    $credentialInput = [Console]::ReadLine()
    $credentialEntropy = [Text.Encoding]::UTF8.GetBytes('SIDcloud/EpochRush/Online/v1')
    if ($Mode -eq 'protect') {
        $credentialBytes = [Text.Encoding]::UTF8.GetBytes($credentialInput)
        $credentialProtected = [Security.Cryptography.ProtectedData]::Protect($credentialBytes, $credentialEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [Console]::WriteLine([Convert]::ToBase64String($credentialProtected))
    } else {
        $credentialBytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($credentialInput), $credentialEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [Console]::WriteLine([Text.Encoding]::UTF8.GetString($credentialBytes))
    }
} catch {
    [Console]::WriteLine('ERROR')
    exit 1
}
