<#
.SYNOPSIS
  Generate a 3D model with Tripo and drop the GLB into the project.

.DESCRIPTION
  Talks to the Tripo REST API directly rather than through an MCP server, which
  keeps the dependency list at "things Windows already has" and avoids running a
  third-party package with the API key in its environment.

  The key is read from TRIPO_API_KEY and is never printed, logged or written to
  disk. The User/Machine scopes are checked too, so `setx` takes effect without
  restarting anything.

    setx TRIPO_API_KEY "your-key-here"      # once; no restart needed

.EXAMPLE
  ./tools/tripo.ps1 -Mode text -Prompt "a rusted iron portcullis" -Out models/portcullis.glb

.EXAMPLE
  ./tools/tripo.ps1 -Mode image -Image reference.jpg -Out models/shield.glb -FaceLimit 4000

.EXAMPLE
  # Pick up a task that is already running (a dropped connection costs no credits).
  ./tools/tripo.ps1 -TaskId b914b539-741b-4df4-a88c-6c4365ca5d0c -Out models/chest.glb

.NOTES
  Whatever comes back still needs processing before it belongs in the game --
  see tools/README.md. Tripo defaults to tens of thousands of triangles; the
  shipped skeleton is 3,498 and the sword is 1,264.
#>
[CmdletBinding()]
param(
    [ValidateSet("text", "image")][string]$Mode,
    [string]$Prompt,
    [string]$Image,
    # Resume polling an existing task instead of submitting a new one.
    [string]$TaskId,
    [Parameter(Mandatory = $true)][string]$Out,
    # Capped low on purpose: the target GPU is a Quadro P620.
    [int]$FaceLimit = 8000,
    [string]$ModelVersion = "v3.1-20260211",
    [switch]$NoPbr,
    # "detailed" asks for the high-resolution texture pass (costs more credits).
    [ValidateSet("", "standard", "detailed")][string]$TextureQuality = "",
    [ValidateSet("", "standard", "detailed")][string]$GeometryQuality = "",
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"
$base = "https://api.tripo3d.ai/v2/openapi"

if (-not $TaskId -and -not $Mode) { throw "give either -Mode text|image or -TaskId <id>" }

# The User/Machine scopes read the registry live. A process started before
# `setx` ran inherits a stale environment block, so without this the whole app
# would have to be restarted before a new key became visible.
# The User scope is read FIRST: after `setx` swaps the key, every process that
# was already running (this app, its shells) still carries the old one in its
# environment, and reading that first kept billing the old account.
$apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "User")
if (-not $apiKey) { $apiKey = $env:TRIPO_API_KEY }
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable("TRIPO_API_KEY", "Machine") }
if (-not $apiKey) {
    Write-Host "TRIPO_API_KEY is not set." -ForegroundColor Red
    Write-Host "  1. Create a key at https://platform.tripo3d.ai/api-keys"
    Write-Host '  2. setx TRIPO_API_KEY "your-key-here"'
    Write-Host "  No restart needed -- this script reads the value live."
    exit 1
}
$headers = @{ Authorization = "Bearer $apiKey" }


function Get-Balance {
    try {
        $b = Invoke-RestMethod -Uri "$base/user/balance" -Headers $headers -Method Get -TimeoutSec 30
        if ($null -ne $b.data) { return [double]$b.data.balance }
    } catch { }
    return $null
}


function Submit-Task([hashtable]$body) {
    $json = $body | ConvertTo-Json -Depth 6
    $r = Invoke-RestMethod -Uri "$base/task" -Headers $headers -Method Post `
        -ContentType "application/json" -Body $json -TimeoutSec 60
    if ($r.code -ne 0) { throw "submit failed: $($r | ConvertTo-Json -Depth 6)" }
    return $r.data.task_id
}


function Send-Image([string]$path) {
    # Multipart built by hand rather than shelled out to curl.exe: curl takes
    # the bearer token as a command-line argument, and command lines are
    # readable by other processes. This way the key never leaves this process.
    # (Invoke-RestMethod -Form would be tidier but needs PowerShell 6+.)
    $name = [IO.Path]::GetFileName($path)
    $boundary = [Guid]::NewGuid().ToString()
    $latin1 = [Text.Encoding]::GetEncoding("iso-8859-1")
    $fileData = $latin1.GetString([IO.File]::ReadAllBytes($path))
    $payload = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"",
        "Content-Type: application/octet-stream",
        "",
        $fileData,
        "--$boundary--",
        ""
    ) -join "`r`n"
    $up = Invoke-RestMethod -Uri "$base/upload" -Headers $headers -Method Post `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $latin1.GetBytes($payload) -TimeoutSec 120
    if ($up.code -ne 0) { throw "upload failed: $($up | ConvertTo-Json -Depth 6)" }
    return $up.data.image_token
}


# ---------------------------------------------------------------------------
# submit, or pick up where a dropped run left off
# ---------------------------------------------------------------------------
$before = Get-Balance
if ($null -ne $before) { Write-Host "credits: $before" -ForegroundColor DarkGray }

if ($TaskId) {
    $taskId = $TaskId
    Write-Host "resuming task $taskId" -ForegroundColor Cyan
} else {
    if ($Mode -eq "text") {
        if (-not $Prompt) { throw "-Prompt is required for -Mode text" }
        $body = @{
            type          = "text_to_model"
            prompt        = $Prompt
            model_version = $ModelVersion
            face_limit    = $FaceLimit
            texture       = $true
            pbr           = (-not $NoPbr)
        }
    } else {
        if (-not $Image) { throw "-Image is required for -Mode image" }
        if (-not (Test-Path $Image)) { throw "image not found: $Image" }
        Write-Host "uploading $Image ..."
        $token = Send-Image $Image
        Write-Host "uploaded, token acquired"
        $ext = ([IO.Path]::GetExtension($Image)).TrimStart(".").ToLower()
        if ($ext -eq "jpeg") { $ext = "jpg" }
        $body = @{
            type          = "image_to_model"
            file          = @{ type = $ext; file_token = $token }
            model_version = $ModelVersion
            face_limit    = $FaceLimit
            texture       = $true
            pbr           = (-not $NoPbr)
        }
    }
    if ($TextureQuality) { $body.texture_quality = $TextureQuality }
    if ($GeometryQuality) { $body.geometry_quality = $GeometryQuality }
    $taskId = Submit-Task $body
    Write-Host "task $taskId submitted" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# poll
#
# Transient 5xx from the API used to abort the whole run even though the job
# carried on server-side, which wasted the credits. Now a blip is retried, and
# if it really does give up it prints the -TaskId needed to resume for free.
# ---------------------------------------------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$modelUrl = $null
$misses = 0
$maxMisses = 8

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $t = $null
    try {
        $t = Invoke-RestMethod -Uri "$base/task/$taskId" -Headers $headers -Method Get -TimeoutSec 30
        $misses = 0
    } catch {
        $misses++
        $code = ""
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        Write-Host ("  poll hiccup {0} ({1}/{2}) - the task is still running, retrying" `
            -f $code, $misses, $maxMisses) -ForegroundColor DarkYellow
        if ($misses -ge $maxMisses) {
            Write-Host ""
            Write-Host "Gave up polling, but the task itself is probably fine." -ForegroundColor Yellow
            Write-Host "Resume without spending credits again:" -ForegroundColor Yellow
            Write-Host "  ./tools/tripo.ps1 -TaskId $taskId -Out $Out"
            exit 2
        }
        Start-Sleep -Seconds 5
        continue
    }

    $d = $t.data
    Write-Host ("  {0,-10} {1,3}%" -f $d.status, $d.progress)
    if ($d.status -eq "success") {
        # The field has moved around between API versions, so try each.
        foreach ($candidate in @(
                $d.output.pbr_model, $d.output.model, $d.output.base_model,
                $d.result.pbr_model.url, $d.result.model.url)) {
            if ($candidate) { $modelUrl = $candidate; break }
        }
        if (-not $modelUrl) {
            throw "task succeeded but no model URL found in: $($t | ConvertTo-Json -Depth 8)"
        }
        break
    }
    if ($d.status -in @("failed", "cancelled", "banned", "expired")) {
        throw "task $($d.status) : $($t | ConvertTo-Json -Depth 8)"
    }
}
if (-not $modelUrl) {
    Write-Host "timed out after $TimeoutSeconds s. Resume with:" -ForegroundColor Yellow
    Write-Host "  ./tools/tripo.ps1 -TaskId $taskId -Out $Out"
    exit 2
}

# ---------------------------------------------------------------------------
# download
# ---------------------------------------------------------------------------
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
Invoke-WebRequest -Uri $modelUrl -OutFile $Out -UseBasicParsing -TimeoutSec 300
Write-Host ("wrote {0} ({1:N0} bytes)" -f $Out, (Get-Item $Out).Length) -ForegroundColor Green

$after = Get-Balance
if ($null -ne $before -and $null -ne $after) {
    Write-Host ("credits: {0} -> {1}  (spent {2})" -f $before, $after, ($before - $after)) -ForegroundColor DarkGray
}
Write-Host "Next: decimate / re-orient / fix colour space before using it in game." -ForegroundColor Yellow
Write-Host "      See tools/README.md -- Tripo output is not drop-in for a P620."
