<#
.SYNOPSIS
    Demonio organizador de archivos por extensión.

.DESCRIPTION
    Monitorea un directorio, organiza archivos por extensión, realiza backups cada X archivos,
    y se ejecuta como demonio en segundo plano.

.PARAMETER directorio
    Ruta del directorio a monitorear.

.PARAMETER backup
    Ruta del directorio donde se guardarán los backups.

.PARAMETER cantidad
    Cantidad de archivos ordenados antes de generar un backup.

.PARAMETER kill
    Finaliza el demonio en ejecución para el directorio especificado.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$directorio,

    [Parameter(Mandatory = $false)]
    [string]$backup,

    [Parameter(Mandatory = $false)]
    [int]$cantidad = 5,

    [Parameter(Mandatory = $false)]
    [switch]$kill
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

function Crear-Backup {
    param ($src, $dest)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "$(Split-Path -Leaf $src)_$timestamp.zip"
    $backupPath = Join-Path -Path $dest -ChildPath $filename
    try {
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $backupPath)
        Write-Host "Backup creado: $backupPath"
    } catch {
        Mostrar-Error "No se pudo crear el backup: $_"
    }
}

$directorio = Resolve-Path -Path $directorio | Select-Object -ExpandProperty Path

if ($kill) {
    $pidFile = Get-PIDFile -dir $directorio
    if (Test-Path $pidFile) {
        $jobId = Get-Content $pidFile
        Write-Host "Leyendo jobId desde .pid: $jobId"

        try {
            $job = Get-Job -Id $jobId -ErrorAction SilentlyContinue
            if ($null -eq $job) {
                Mostrar-Error "No se encontró un job con el ID $jobId. Puede que ya haya terminado."
            }

            Write-Host "Intentando detener el demonio con ID $jobId..."
            Stop-Job -Id $jobId
            Remove-Job -Id $jobId
            Remove-Item $pidFile -Force
            Write-Host "Demonio detenido exitosamente." -ForegroundColor Green
            exit 0
        } catch {
            Mostrar-Error "No se pudo detener el demonio. Error: $_"
        }
    } else {
        Mostrar-Error "No hay demonio registrado para este directorio."
    }
}

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

# Lanzar demonio como job
$job = Start-Job -ScriptBlock {
    param($directorio, $backup, $cantidad)

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

} -ArgumentList $directorio, $backup, $cantidad

# Guardar el Job ID
Set-Content -Path $pidFile -Value $job.Id

Write-Host "Demonio iniciado en segundo plano para: $directorio" -ForegroundColor Green
