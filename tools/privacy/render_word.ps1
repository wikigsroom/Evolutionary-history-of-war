param(
    [Parameter(Mandatory=$true)][string]$InputDocument,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$privacyDocumentPath = (Resolve-Path -LiteralPath $InputDocument).Path
$privacyRenderDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $privacyRenderDirectory -Force | Out-Null
$privacyPdfPath = [IO.Path]::Combine($privacyRenderDirectory, 'privacy-policy.pdf')
$privacyWordApplication = New-Object -ComObject Word.Application
$privacyWordApplication.Visible = $false
$privacyWordApplication.DisplayAlerts = 0
$privacyWordApplication.AutomationSecurity = 3
$privacyWordDocument = $null
try {
    $privacyWordDocument = $privacyWordApplication.Documents.Open($privacyDocumentPath, $false, $true, $false)
    $privacyWordDocument.ExportAsFixedFormat($privacyPdfPath, 17)
    [PSCustomObject]@{ Pages = $privacyWordDocument.ComputeStatistics(2); PDF = $privacyPdfPath } | ConvertTo-Json -Compress
} finally {
    $privacySaveChanges = 0
    if ($null -ne $privacyWordDocument) { $privacyWordDocument.Close([ref]$privacySaveChanges) }
    $privacyWordApplication.Quit([ref]$privacySaveChanges)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($privacyWordApplication)
}
