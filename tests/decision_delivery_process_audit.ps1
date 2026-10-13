$taskProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -like 'Godot*' -or $_.Name -eq 'python.exe') -and
    $_.CommandLine -match 'ConjoinedTwins'
} | Select-Object ProcessId, Name, CommandLine)
@{ matching_process_count = $taskProcesses.Count; processes = $taskProcesses } |
    ConvertTo-Json -Depth 4
