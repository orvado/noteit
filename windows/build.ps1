#Requires -Version 7
param(
  [ValidateSet("Debug", "Release")][string]$Configuration = "Release",
  [switch]$Run
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
$noteitProcesses = Get-Process -Name NoteIt -ErrorAction SilentlyContinue
if ($noteitProcesses) {
  Stop-Process -Name NoteIt -Force -ErrorAction SilentlyContinue
}

dotnet build "$root\NoteIt.sln" -c $Configuration
if ($Run) {
  $exe = Get-ChildItem "$root\NoteIt\bin\$Configuration\net9.0-windows\NoteIt.exe" | Select-Object -First 1
  # The exe's apphost honors DOTNET_ROOT, which may point at a private runtime install
  # lacking net9.0 (the app then exits with code 150 before showing a window). Point it
  # at the dotnet that built the app so a matching runtime is always found.
  $env:DOTNET_ROOT = Split-Path -Parent (Get-Command dotnet).Source
  & $exe.FullName
}
