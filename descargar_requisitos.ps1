# Descarga e instala lo necesario para la Practica 2 de SGE en Windows.
# Uso (PowerShell, en la carpeta del repo):
#   powershell -ExecutionPolicy Bypass -File .\descargar_requisitos.ps1
# (Sin tildes a proposito: PowerShell 5.1 lee mal UTF-8 sin BOM.)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # acelera Invoke-WebRequest

# Todo se guarda en la carpeta 'descargas' dentro del repo (ignorada por git)
$dest = Join-Path $PSScriptRoot 'descargas'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Write-Host "Carpeta de descargas: $dest" -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. ISO Ubuntu Server 24.04 (ultima revision)
$base  = 'https://releases.ubuntu.com/24.04'
$raw   = (Invoke-WebRequest "$base/SHA256SUMS" -UseBasicParsing).Content
if ($raw -is [byte[]]) { $raw = [Text.Encoding]::ASCII.GetString($raw) }   # PS 5.1 lo devuelve como bytes
$sums  = $raw -split "`r?`n"
$best  = $sums |
    Where-Object { $_ -match '^([0-9a-f]{64}) \*(ubuntu-([\d\.]+)-live-server-amd64\.iso)$' } |
    ForEach-Object {
        $null = $_ -match '^([0-9a-f]{64}) \*(ubuntu-([\d\.]+)-live-server-amd64\.iso)$'
        [pscustomobject]@{ Hash = $Matches[1]; File = $Matches[2]; Ver = [version]$Matches[3] }
    } |
    Sort-Object Ver | Select-Object -Last 1

if (-not $best) { throw 'No se encontro la ISO de Ubuntu Server en SHA256SUMS.' }

$iso = Join-Path $dest $best.File
Write-Host "ISO elegida: $($best.File)" -ForegroundColor Cyan

$needDownload = $true
if (Test-Path $iso) {
    Write-Host 'La ISO ya existe, comprobando su huella SHA256...'
    if ((Get-FileHash $iso -Algorithm SHA256).Hash -eq $best.Hash.ToUpper()) { $needDownload = $false }
}

if ($needDownload) {
    Write-Host 'Descargando ISO (~3 GB, puede tardar)...'
    try {
        Start-BitsTransfer -Source "$base/$($best.File)" -Destination $iso   # muestra progreso y reanuda
    } catch {
        Invoke-WebRequest "$base/$($best.File)" -OutFile $iso -UseBasicParsing
    }
    Write-Host 'Comprobando huella SHA256...'
    if ((Get-FileHash $iso -Algorithm SHA256).Hash -ne $best.Hash.ToUpper()) {
        throw 'La huella SHA256 NO coincide: la ISO esta corrupta. Borrala y vuelve a ejecutar el script.'
    }
}
Write-Host "OK  ISO verificada: $iso" -ForegroundColor Green

# ---------------------------------------------------------------- 2. VirtualBox (con winget)
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
    if (Test-Path $vbox) {
        Write-Host "OK  VirtualBox ya instalado: $(& $vbox --version)" -ForegroundColor Green
    } else {
        Write-Host 'Instalando Visual C++ Redistributable y VirtualBox (pedira permisos de administrador)...'
        winget install --id Microsoft.VCRedist.2015+.x64 -e --accept-source-agreements --accept-package-agreements
        # El instalador de VirtualBox se guarda en el repo y luego se instala
        winget download --id Oracle.VirtualBox -e -d $dest --accept-source-agreements --accept-package-agreements
        winget install --id Oracle.VirtualBox -e --accept-source-agreements --accept-package-agreements
    }
} else {
    Write-Host 'winget no disponible: descarga VirtualBox a mano desde https://www.virtualbox.org/wiki/Downloads' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 3. Cliente SSH de Windows
if (Get-Command ssh -ErrorAction SilentlyContinue) {
    Write-Host "OK  Cliente SSH disponible" -ForegroundColor Green
} else {
    Write-Host 'Falta el cliente SSH. Abre PowerShell como administrador y ejecuta:' -ForegroundColor Yellow
    Write-Host '    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0'
}

# ---------------------------------------------------------------- 4. Virtualizacion por hardware
$virt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
if ($virt -eq $false) {
    Write-Host 'AVISO: la virtualizacion (AMD-V / SVM Mode) esta desactivada en la BIOS. Activala.' -ForegroundColor Yellow
} else {
    Write-Host 'OK  Virtualizacion por hardware activa (o gestionada por Hyper-V)' -ForegroundColor Green
}

Write-Host "`nListo. Crea la VM en VirtualBox usando: $iso" -ForegroundColor Cyan
