param(
    [switch]$CheckOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArguments
)

$ErrorActionPreference = 'Stop'
try {
    $repository = Split-Path -Parent $PSScriptRoot
    $entries = @(& git -C $repository worktree list --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Git worktrees.' }
    $target = $null
    $candidate = $null
    foreach ($line in $entries) {
        if ($line.StartsWith('worktree ')) { $candidate = $line.Substring(9) }
        if ($line -eq 'branch refs/heads/test') { $target = $candidate }
    }
    if (!$target) { throw 'No worktree has the local test branch checked out.' }
    $expected = & git -C $repository rev-parse refs/heads/test
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve local test.' }
    $actual = & git -C $target rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actual -ne $expected) { throw 'Test worktree HEAD does not match local test.' }
    $changes = @(& git -C $target status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect test worktree changes.' }
    if ($changes.Count -gt 0) { throw 'Test worktree has uncommitted tracked changes. Review them before launching.' }
    $engine = 'D:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe'
    if (!(Test-Path -LiteralPath $engine)) { throw "Godot executable missing: $engine" }
    if (!(Test-Path -LiteralPath (Join-Path $target 'scenes/journey_boot.tscn'))) { throw 'Test boot scene missing.' }
    Write-Host "Local test: $expected"
    Write-Host "Worktree: $target"
    if ($CheckOnly) { exit 0 }
    & $engine --path $target res://scenes/journey_boot.tscn @GameArguments
    exit $LASTEXITCODE
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
