param(
  [ValidateSet("Debug", "Release")][string]$Configuration = "Release",
  [string]$Runtime = "win-x64",
  [switch]$Sign,
  [string]$CertThumbprint,
  [string]$CertSubject = "CN=NoteIt Developer Code Signing",
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)
$ErrorActionPreference = "Stop"

function Resolve-SigningCertificate {
  if ($CertThumbprint) {
    $cert = Get-ChildItem "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue |
      Where-Object { $_.Thumbprint -eq $CertThumbprint } |
      Select-Object -First 1

    if (-not $cert) {
      throw "Certificate with thumbprint $CertThumbprint was not found in CurrentUser\My."
    }

    return $cert
  }

  $existing = Get-ChildItem "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Subject -eq $CertSubject -and
      $_.HasPrivateKey -and
      $_.Extensions -match 'Code Signing'
    } |
    Sort-Object NotBefore -Descending |
    Select-Object -First 1

  if ($existing) {
    return $existing
  }

  $newCert = New-SelfSignedCertificate -CertStoreLocation "Cert:\CurrentUser\My" -Type CodeSigningCert -Subject $CertSubject -HashAlgorithm SHA256 -KeyUsage DigitalSignature -FriendlyName "NoteIt Developer Code Signing"
  if (-not $newCert) {
    throw "Could not create a temporary self-signed certificate for signing."
  }

  Write-Host "Created temporary code-signing certificate for dev signing: $($newCert.Thumbprint)"
  return $newCert
}

function Invoke-InstallerSigning {
  param(
    [string]$MsiPath,
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
  )

  if (Get-Command Set-AuthenticodeSignature -ErrorAction SilentlyContinue) {
    Write-Host "Signing with PowerShell Authenticode..."
    Set-AuthenticodeSignature -FilePath $MsiPath -Certificate $Certificate -TimestampServer $TimestampUrl -HashAlgorithm SHA256 | Out-Null
    return
  }

  $signtool = Get-Command signtool -ErrorAction SilentlyContinue
  if ($signtool) {
    Write-Host "Signing with signtool..."
    & $signtool.Source sign /fd SHA256 /tr $TimestampUrl /td sha256 /sha1 $Certificate.Thumbprint $MsiPath
    if ($LASTEXITCODE -ne 0) {
      throw "Code signing failed for $MsiPath."
    }
    return
  }

  $windowsKitsRoot = @(
    "$env:ProgramFiles(x86)\Windows Kits\10\bin",
    "$env:ProgramFiles\Windows Kits\10\bin"
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

  if ($windowsKitsRoot) {
    $tool = Get-ChildItem -Path $windowsKitsRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1

    if ($tool) {
      Write-Host "Signing with discovered signtool..."
      & $tool.FullName sign /fd SHA256 /tr $TimestampUrl /td sha256 /sha1 $Certificate.Thumbprint $MsiPath
      if ($LASTEXITCODE -ne 0) {
        throw "Code signing failed for $MsiPath."
      }
      return
    }
  }

  throw "No supported signing tool is available. Install the Windows SDK or use a machine with Authenticode signing configured."
}

$root = Split-Path -Parent $PSCommandPath
$appProject = Join-Path $root "NoteIt\NoteIt.csproj"
$installerProject = Join-Path $root "Installer\NoteIt.Installer.wixproj"
$iconScript = Join-Path $root "NoteIt\CreateAppIcon.ps1"
$publishDir = Join-Path $root "NoteIt\bin\$Configuration\net9.0-windows\$Runtime\publish"
$msiRoot = Join-Path $root "Installer\bin\$Configuration"

if (Test-Path $iconScript) {
  Write-Host "Generating installer icon..."
  & $iconScript
}

Write-Host "Publishing NoteIt for $Runtime..."
dotnet publish $appProject -c $Configuration -r $Runtime --self-contained true -p:PublishSingleFile=false -p:UseAppHost=true --output $publishDir

Write-Host "Building MSI package..."
$publishDirMsbuild = $publishDir.Replace('\\', '/')
dotnet build $installerProject -c $Configuration -p:DefineConstants="PublishDir=$publishDirMsbuild"

$msi = Get-ChildItem $msiRoot -Filter "NoteIt*.msi" -Recurse | Select-Object -First 1
if (-not $msi) {
  throw "No MSI installer was produced in $msiRoot"
}

if ($Sign) {
  $cert = Resolve-SigningCertificate
  Write-Host "Signing MSI with certificate $($cert.Thumbprint)..."
  Invoke-InstallerSigning -MsiPath $msi.FullName -Certificate $cert
}

Write-Host "MSI ready: $($msi.FullName)"
