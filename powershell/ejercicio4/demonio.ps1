############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

<#
.SYNOPSIS
    Demonio organizador de archivos por extensión.

.DESCRIPTION
    Monitorea un directorio, organiza archivos por extensión, realiza backups cada X archivos,
    y se ejecuta como demonio en segundo plano real (proceso autónomo).

.PARAMETER directorio
    Ruta del directorio a monitorear.

.PARAMETER backup
    Ruta del directorio donde se guardarán los backups.

.PARAMETER cantidad
    Cantidad de archivos ordenados antes de generar un backup.

.PARAMETER kill
    Finaliza el demonio en ejecución para el directorio especificado.

.EXAMPLE
    ./demonio.ps1 -directorio ./descargas -backup ./backup -cantidad 3
    
.EXAMPLE
    ./demonio.ps1 -directorio ./descargas -kill

.PARAMETER daemonInterno
    Flag interno utilizado por el demonio lanzado en segundo plano. No usar manualmente.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$directorio,

    [Parameter(Mandatory = $false)]
    [string]$backup,

    [Parameter(Mandatory = $false)]
    [int]$cantidad,

    [Parameter(Mandatory = $false)]
    [switch]$kill,

    [Parameter(Mandatory = $false)]
    [switch]$daemonInterno
)

function Mostrar-Error {
    param ($Mensaje)
    Write-Host "ERROR: $Mensaje" -ForegroundColor Red
    Exit 1
}

function Get-Hash {
    param ($path)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($path)
    $sha256 = New-Object -TypeName System.Security.Cryptography.SHA256Managed
    $hash = $sha256.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace("-", "")
}

function Get-PIDFile {
    param ($dir)
    $hash = Get-Hash $dir
    $tmpDir = if ($env:TEMP) { $env:TEMP } else { "/tmp" }
    return Join-Path -Path $tmpDir -ChildPath "demonio_$hash.pid"
}

# Validaciones previas
if ($kill) {
    if ($backup -or $cantidad -or $daemonInterno) {
        Mostrar-Error "Cuando se usa -kill, no se deben usar otros parámetros además de -directorio."
    }
    if (-not (Test-Path $directorio)) {
        Mostrar-Error "Debe especificar un directorio válido al usar -kill."
    }
} else {
    if (-not (Test-Path $directorio)) {
        Mostrar-Error "Debe especificar un directorio válido."
    }
    if (-not $backup) {
        Mostrar-Error "El parámetro -backup es obligatorio si no se usa -kill."
    }
    if ($cantidad -le 0) {
        Mostrar-Error "El parámetro -cantidad debe ser mayor a cero."
    }
}

# Resolución de rutas absolutas
$directorio = Resolve-Path -Path $directorio | Select-Object -ExpandProperty Path

if ($kill) {
    $pidFile = Get-PIDFile -dir $directorio
    if (Test-Path $pidFile) {
        $daemonPid = Get-Content $pidFile
        try {
            $proc = Get-Process -Id $daemonPid -ErrorAction Stop
            Stop-Process -Id $daemonPid -Force
            Write-Host "Demonio detenido (PID $daemonPid)." -ForegroundColor Green
        } catch {
            Write-Host "Advertencia: No se encontró el proceso con PID $daemonPid. Eliminando archivo PID de todas formas." -ForegroundColor Yellow
        } finally {
            if (Test-Path $pidFile) {
                Remove-Item $pidFile -Force
            }
        }
        exit 0
    } else {
        Mostrar-Error "No hay demonio registrado para este directorio."
    }
}

if (-not $daemonInterno) {
    if (-not $backup) {
        Mostrar-Error "El parámetro -backup es obligatorio si no se usa -kill."
    }
    if (-not (Test-Path $directorio)) {
        Mostrar-Error "El directorio especificado no existe."
    }
    $backup = Resolve-Path -Path $backup | Select-Object -ExpandProperty Path
    if (-not (Test-Path $backup)) {
        try {
            New-Item -ItemType Directory -Path $backup | Out-Null
        } catch {
            Mostrar-Error "No se pudo crear el directorio de backup."
        }
    }

    $pidFile = Get-PIDFile -dir $directorio
    if (Test-Path $pidFile) {
        Mostrar-Error "Ya hay un demonio en ejecución para este directorio."
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    $argsList = @(
        "-directorio", "`"$directorio`"",
        "-backup", "`"$backup`"",
        "-cantidad", $cantidad,
        "-daemonInterno"
    )

    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if (-not $pwshPath) {
        $pwshPath = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $pwshPath) {
        Mostrar-Error "No se pudo encontrar PowerShell para lanzar el demonio."
    }

    $argumentos = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`""
    ) + $argsList

    if ($IsWindows) {
        $proc = Start-Process -FilePath $pwshPath `
            -ArgumentList $argumentos `
            -WindowStyle Hidden -NoNewWindow:$false -PassThru
    } else {
        $proc = Start-Process -FilePath $pwshPath `
            -ArgumentList $argumentos `
            -PassThru
    }


    if ($proc -and $proc.Id) {
        Set-Content -Path $pidFile -Value $proc.Id
        Write-Host "Demonio iniciado con PID $($proc.Id) para: $directorio" -ForegroundColor Green
    } else {
        Mostrar-Error "No se pudo iniciar el demonio."
    }
    exit 0
}

# === Desde aca empieza el demonio real (proceso independiente) ===

$pidFile = Get-PIDFile -dir $directorio
Register-EngineEvent PowerShell.Exiting -Action {
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force
    }
}

Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

$script:fileCount = 0

function Crear-Backup {
    param ($src, $dest)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "$(Split-Path -Leaf $src)_$timestamp.zip"
    $backupPath = Join-Path -Path $dest -ChildPath $filename
    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $backupPath)
        Write-Host "Backup creado: $backupPath"
    } catch {
        Write-Host "Error creando backup: $_"
    }
}

function Organizar-Archivo {
    param ($file)
    if (-not (Test-Path $file)) { return }

    Start-Sleep -Milliseconds 500
    $ext = [System.IO.Path]::GetExtension($file).TrimStart('.').ToUpper()
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = "SIN_EXTENSION" }

    $targetDir = Join-Path $directorio $ext
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
    }

    try {
        $destFile = Join-Path $targetDir (Split-Path -Leaf $file)
        Move-Item -Path $file -Destination $destFile -Force
        $script:fileCount++
        Write-Host "Archivo movido: $file -> $destFile"

        if ($script:fileCount -ge $cantidad) {
            Crear-Backup $directorio $backup
            $script:fileCount = 0
        }
    } catch {
        Write-Host ("Error moviendo archivo " + $file + ": " + $_)
    }
}

# Procesar archivos existentes
Get-ChildItem -Path $directorio -File | ForEach-Object {
    Organizar-Archivo $_.FullName
}

# Configurar el watcher
$fsw = New-Object System.IO.FileSystemWatcher $directorio, '*'
$fsw.EnableRaisingEvents = $true
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter = [System.IO.NotifyFilters]'FileName, CreationTime'

Register-ObjectEvent -InputObject $fsw -EventName Created -Action {
    param($sender, $eventArgs)
    Organizar-Archivo $eventArgs.FullPath
} | Out-Null

while ($true) {
    Start-Sleep -Seconds 5
}
