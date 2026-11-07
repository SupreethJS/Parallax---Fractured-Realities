# deploy.ps1 - Automated Godot Web Export & GitHub Pages Deployment
param(
    [string]$CommitMessage = "Update Godot web build for GitHub Pages"
)

$ErrorActionPreference = "Stop"

Write-Host "`n🚀 Starting RESPAWN: PARALLAX GitHub Pages Deployment...`n" -ForegroundColor Cyan

# 1. Resolve Project Root
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

# 2. Locate Godot Executable
$Candidates = @(
    $env:GODOT_PATH,
    "C:\Godot_v4.7.2-stable_win64.exe",
    "C:\Godot_v4.7.2-stable_win64_console.exe",
    "$HOME\Desktop\Godot_v4.7.2-stable_win64.exe",
    "$HOME\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe",
    "godot"
)

$GodotCmd = $null
foreach ($c in $Candidates) {
    if ($c -and (Test-Path $c -ErrorAction SilentlyContinue)) {
        $GodotCmd = $c
        break
    } elseif ($c -eq "godot" -and (Get-Command "godot" -ErrorAction SilentlyContinue)) {
        $GodotCmd = "godot"
        break
    }
}

if (-not $GodotCmd) {
    Write-Error "Godot binary not found. Set `$env:GODOT_PATH to your Godot executable."
    exit 1
}

Write-Host "📦 Exporting Web release using: $GodotCmd" -ForegroundColor Yellow
if (-not (Test-Path "build/web")) {
    New-Item -ItemType Directory -Path "build/web" -Force | Out-Null
}

& $GodotCmd --headless --path . --export-release "Web" "build/web/index.html"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot export failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
Write-Host "✅ Godot Web export complete." -ForegroundColor Green

# 3. Ensure .nojekyll exists
New-Item -Path "build/web/.nojekyll" -ItemType File -Force | Out-Null
Write-Host "✅ Created build/web/.nojekyll" -ForegroundColor Green

# 4. Git Stage and Commit
git add -A
$status = git status --porcelain
if ($status) {
    Write-Host "📝 Committing project and build files..." -ForegroundColor Yellow
    git commit -m $CommitMessage
} else {
    Write-Host "ℹ️ No changes detected to commit." -ForegroundColor Cyan
}

# 5. Push to main
Write-Host "📤 Pushing main branch to origin..." -ForegroundColor Yellow
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Push to origin main failed or returned non-zero code."
} else {
    Write-Host "✅ Pushed to origin/main successfully." -ForegroundColor Green
}

# 6. Push subtree to gh-pages
Write-Host "🌐 Pushing build/web subtree to origin/gh-pages..." -ForegroundColor Yellow
$subtreeSuccess = $false
try {
    git subtree push --prefix build/web origin gh-pages
    if ($LASTEXITCODE -eq 0) { $subtreeSuccess = $true }
} catch {
    $subtreeSuccess = $false
}

if (-not $subtreeSuccess) {
    Write-Host "Standard subtree push encountered an issue; executing fallback forced split push..." -ForegroundColor Yellow
    $splitOutput = (git subtree split --prefix build/web main)
    if ($splitOutput) {
        $splitId = $splitOutput.Trim()
        git push origin "${splitId}:refs/heads/gh-pages" --force
    }
}

# 7. Print Live URL
$RemoteUrl = git remote get-url origin 2>$null
$RepoName = ""
$User = ""
if ($RemoteUrl -match "github\.com[:/]([^/]+)/([^/.]+)(\.git)?") {
    $User = $matches[1]
    $RepoName = $matches[2]
}

Write-Host "`n🎉 Deployment finished!" -ForegroundColor Green
if ($User -and $RepoName) {
    $PagesUrl = "https://$User.github.io/$RepoName/"
    Write-Host "🔗 Live GitHub Pages URL: $PagesUrl" -ForegroundColor Cyan
}

