#Requires -Version 7
param(
  [ValidateSet("Debug", "Release")][string]$Configuration = "Release",
  [switch]$Run
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
dotnet build "$root\NoteIt.sln" -c $Configuration
if ($Run) {
  $exe = Get-ChildItem "$root\NoteIt\bin\$Configuration\net9.0-windows\NoteIt.exe" | Select-Object -First 1
  & $exe.FullName
}
