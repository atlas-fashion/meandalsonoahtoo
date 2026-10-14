<#
.SYNOPSIS
  Retexture a model with Tripo (v3 /models/texture) and save the GLB.

.DESCRIPTION
  Same key handling as tripo.ps1: TRIPO_API_KEY from the User scope first, then
  the process, then Machine; never printed, logged or written to disk.

  -Source is the task id of a Tripo generation (best: Tripo keeps its own UVs
  and knows the source) or a path to a local GLB/FBX/OBJ, which is uploaded
  first. A model that did not come from Tripo needs -Prompt.

  The v3 API lives on openapi.tripo3d.ai (the .com host in Tripo's docs
  answers this key with 401).

.EXAMPLE
  ./tools/tripo_texture.ps1 -Source 7b41eb15-e4ce-4f27-8bf5-28915ac730f6 `
      -Prompt "damp dungeon flagstones" -Out models/source/brick_kit_raw/floor_damp.glb

.EXAMPLE
  # Pick up a texture task that is already running.
  ./tools/tripo_texture.ps1 -TaskId <id> -Out models/x.glb
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Prompt,
    [string]$TaskId,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateSet("standard", "detailed", "extreme")][string]$TextureQuality = "detailed",
    [string]$Model = "",
    [switch]$NoPbr,
    [int]$Seed = -1,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
$base = "https://openapi.tripo3d.ai/v3"

$apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "User")
if (-not $apiKey) { $apiKey = $env:TRIPO_API_KEY }
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "Machine") }
if (-not $apiKey) { Write-Host "TRIPO_API_KEY is not set." -ForegroundColor Red; exit 1 }
$headers = @{ Authorization = "Bearer $apiKey" }


function Get-Balance {
    try {
        $b = Invoke-RestMethod -Uri "$base/account/balance" -Headers $headers -TimeoutSec 30
        return [double]$b.data.balance
    } catch { return $null }
}


function Send-File([string]$path) {
    # Multipart by hand (PowerShell 5.1 has no -Form), so the key never goes on
    # a command line.
    $name = [IO.Path]::GetFileName($path)
    $boundary = [Guid]::NewGuid().ToString()
    $latin1 = [Text.Encoding]::GetEncoding("iso-8859-1")
    $data = $latin1.GetString([IO.File]::ReadAllBytes($path))
    $payload = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"",
        "Content-Type: application/octet-stream",
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

if ($TaskId) {
    $task = $TaskId
    Write-Host "resuming task $task" -ForegroundColor Cyan
} else {
    if (-not $Source) { throw "give -Source <task id | model path> or -TaskId" }
    $src = $Source
    if (Test-Path $Source) {
        Write-Host "uploading $Source ..."
        $src = Send-File $Source
        if (-not $Prompt) { throw "a model that did not come from Tripo needs -Prompt" }
    }
    $body = @{
        input           = $src
        texture_quality = $TextureQuality
        pbr             = (-not $NoPbr)
    }
    if ($Model) { $body.model = $Model }
    if ($Prompt) { $body.texture_prompt = @{ text = $Prompt } }
    if ($Seed -ge 0) { $body.texture_seed = $Seed }
    $json = $body | ConvertTo-Json -Depth 6
    $r = Invoke-RestMethod -Uri "$base/models/texture" -Headers $headers -Method Post `
        -ContentType "application/json" -Body $json -TimeoutSec 60
    if ($r.code -ne 0) { throw "submit failed: $($r | ConvertTo-Json -Depth 6)" }
    $task = $r.data.task_id
    Write-Host "task $task submitted" -ForegroundColor Cyan
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$url = $null
$misses = 0
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    try {
        $t = Invoke-RestMethod -Uri "$base/tasks/$task" -Headers $headers -TimeoutSec 30
        $misses = 0
    } catch {
        $misses++
        Write-Host "  poll hiccup ($misses/8) - still running, retrying" -ForegroundColor DarkYellow
        if ($misses -ge 8) {
            Write-Host "Resume for free: ./tools/tripo_texture.ps1 -TaskId $task -Out $Out"
            exit 2
        }
        continue
    }
    $d = $t.data
    Write-Host ("  {0,-10} {1,3}%" -f $d.status, $d.progress)
    if ($d.status -eq "success") {
        foreach ($c in @($d.output.model_url, $d.output.pbr_model, $d.output.model)) {
            if ($c) { $url = $c; break }
        }
        if (-not $url) { throw "no model URL in: $($t | ConvertTo-Json -Depth 8)" }
        break
    }
    if ($d.status -in @("failed", "cancelled", "banned", "expired")) {
        throw "task $($d.status): $($t | ConvertTo-Json -Depth 8)"
    }
}
if (-not $url) {
    Write-Host "timed out. Resume: ./tools/tripo_texture.ps1 -TaskId $task -Out $Out" -ForegroundColor Yellow
    exit 2
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
Invoke-WebRequest -Uri $url -OutFile $Out -UseBasicParsing -TimeoutSec 300
Write-Host ("wrote {0} ({1:N0} bytes)  task {2}" -f $Out, (Get-Item $Out).Length, $task) -ForegroundColor Green
$after = Get-Balance
if ($null -ne $before -and $null -ne $after) {
    Write-Host ("credits: {0} -> {1}  (spent {2})" -f $before, $after, ($before - $after)) -ForegroundColor DarkGray
}
