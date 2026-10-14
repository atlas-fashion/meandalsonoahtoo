<#
.SYNOPSIS
  Edit a picture with Tripo (v3 /generation/image-to-image) and save the result.

.DESCRIPTION
  Same key handling as tripo.ps1 (never printed, logged or written to disk).
  Used to make texture references: the edited picture then goes to
  tripo_texture.ps1 -Image.

.EXAMPLE
  ./tools/tripo_image.ps1 -Image ref.png -Prompt "make the stone wet" -Out wet.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Model = "seedream_v5",
    [string]$Size = "2K",
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
$base = "https://openapi.tripo3d.ai/v3"
$apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "User")
if (-not $apiKey) { $apiKey = $env:TRIPO_API_KEY }
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "Machine") }
if (-not $apiKey) { Write-Host "TRIPO_API_KEY is not set." -ForegroundColor Red; exit 1 }
$headers = @{ Authorization = "Bearer $apiKey" }

function Get-Balance {
    try { return [double](Invoke-RestMethod -Uri "$base/account/balance" -Headers $headers -TimeoutSec 30).data.balance }
    catch { return $null }
}

function Send-File([string]$path) {
    $name = [IO.Path]::GetFileName($path)
    $mime = if ($path.ToLower().EndsWith(".png")) { "image/png" } else { "image/jpeg" }
    $boundary = [Guid]::NewGuid().ToString()
    $latin1 = [Text.Encoding]::GetEncoding("iso-8859-1")
    $data = $latin1.GetString([IO.File]::ReadAllBytes($path))
    $payload = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"",
        "Content-Type: $mime",
        "",
        $data,
        "--$boundary--",
        ""
    ) -join "`r`n"
    $up = Invoke-RestMethod -Uri "$base/files" -Headers $headers -Method Post `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $latin1.GetBytes($payload) -TimeoutSec 300
    if ($up.code -ne 0) { throw "upload failed: $($up | ConvertTo-Json -Depth 6)" }
    return $up.data.file_token
}

$before = Get-Balance
if ($null -ne $before) { Write-Host "credits: $before" -ForegroundColor DarkGray }
Write-Host "uploading $Image ..."
$token = Send-File $Image
$body = @{ input = $token; prompt = $Prompt; model = $Model; size = $Size } | ConvertTo-Json -Depth 4
$r = Invoke-RestMethod -Uri "$base/generation/image-to-image" -Headers $headers -Method Post `
    -ContentType "application/json" -Body $body -TimeoutSec 60
if ($r.code -ne 0) { throw "submit failed: $($r | ConvertTo-Json -Depth 6)" }
$task = $r.data.task_id
Write-Host "task $task submitted" -ForegroundColor Cyan

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$url = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    try { $t = Invoke-RestMethod -Uri "$base/tasks/$task" -Headers $headers -TimeoutSec 30 }
    catch { Write-Host "  poll hiccup, retrying" -ForegroundColor DarkYellow; continue }
    $d = $t.data
    Write-Host ("  {0,-10} {1,3}%" -f $d.status, $d.progress)
    if ($d.status -eq "success") { $url = $d.output.generated_image_url; break }
    if ($d.status -in @("failed", "cancelled", "banned", "expired")) {
        throw "task $($d.status): $($t | ConvertTo-Json -Depth 8)"
    }
}
if (-not $url) { throw "no image (timed out or no URL); task $task" }
Invoke-WebRequest -Uri $url -OutFile $Out -UseBasicParsing -TimeoutSec 300
Write-Host ("wrote {0} ({1:N0} bytes)  task {2}" -f $Out, (Get-Item $Out).Length, $task) -ForegroundColor Green
$after = Get-Balance
if ($null -ne $before -and $null -ne $after) {
    Write-Host ("credits: {0} -> {1}  (spent {2})" -f $before, $after, ($before - $after)) -ForegroundColor DarkGray
}
