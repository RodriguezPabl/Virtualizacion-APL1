<#
.SYNOPSIS
Procesa archivos CSV con registros de temperatura y genera estadísticas por día y ubicación.

.DESCRIPTION
Lee archivos CSV desde un directorio, calcula mínimos, máximos y promedios de temperatura agrupados
por fecha y ubicación, y muestra el resultado por pantalla o lo guarda en un archivo JSON.

.PARAMETER directorio
Ruta del directorio que contiene los archivos CSV a procesar.

.PARAMETER archivo
Ruta completa del archivo de salida JSON. No se puede usar junto con -pantalla.

.PARAMETER pantalla
Muestra la salida por pantalla en lugar de generar un archivo JSON.

.EXAMPLE
.\ejercicio1.ps1 -directorio ./lote1 -pantalla

.EXAMPLE
.\ejercicio1.ps1 -directorio ./lote1 -archivo ./salida.json
#>

############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

[CmdletBinding(DefaultParameterSetName = 'archivo')]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$directorio,

    [Parameter(Mandatory = $false, ParameterSetName = 'archivo')]
    [string]$archivo,

    [Parameter(Mandatory = $false, ParameterSetName = 'pantalla')]
    [switch]$pantalla
)

# --- Validaciones ---
if (-not (Test-Path $directorio -PathType Container)) {
    Write-Error "El directorio '$directorio' no existe."
    exit 1
}

if ($archivo -and $pantalla) {
    Write-Error "No se puede usar -archivo y -pantalla al mismo tiempo."
    exit 1
}

if (-not $archivo -and -not $pantalla) {
    Write-Error "Debe especificar -archivo o -pantalla para indicar cómo mostrar la salida."
    exit 1
}

if ($archivo) {
    # Convertir a ruta absoluta
    $archivoAbs = Resolve-Path -Path $archivo -ErrorAction SilentlyContinue
    if ($archivoAbs -and (Test-Path $archivoAbs -PathType Leaf)) {
        if ($archivoAbs.ToString().StartsWith((Resolve-Path $directorio).ToString())) {
            Write-Error "El archivo de salida no puede estar dentro del mismo directorio de entrada."
            exit 1
        }
        Write-Error "El archivo '$archivo' ya existe. Elija otro nombre o elimínelo antes de ejecutar el script."
        exit 1
    }
}

# --- Inicialización ---
$datosAgrupados = @{}
$tempFilePath = "/tmp/ps_temp_$PID.json"
$tempRawData = "/tmp/ps_temp_$PID.raw"

function Limpiar {
    Remove-Item -ErrorAction SilentlyContinue $tempFilePath, $tempRawData
}

try {
    # --- Procesar archivos ---
    Get-ChildItem -Path $directorio -Filter *.csv | ForEach-Object {
        $csvFile = $_.FullName
        Get-Content $csvFile | ForEach-Object {
            $linea = $_.Trim()
            if ($linea -eq '') { return }

            $partes = $linea -split ','
            if ($partes.Length -ne 5) { return }

            $id, $fecha, $hora, $ubic, $temp = $partes
            if (-not ($temp -as [double])) {
                Write-Warning "Temperatura inválida '$temp' en archivo $csvFile"
                return
            }

            $fechaFormateada = $fecha -replace '/', '-'
            $clave = "$fechaFormateada|$ubic"
            Add-Content -Path $tempRawData -Value "$clave $temp"
        }
    }

    # --- Agrupar datos ---
    $agrupados = Get-Content $tempRawData | ForEach-Object {
        $partes = $_ -split '[| ]'
        [PSCustomObject]@{
            Fecha = $partes[0]
            Ubicacion = $partes[1]
            Temp = [double]$partes[2]
        }
    } | Group-Object Fecha | ForEach-Object {
        $fecha = $_.Name
        $ubicaciones = $_.Group | Group-Object Ubicacion | ForEach-Object {
            $ubic = $_.Name
            $temps = $_.Group | Select-Object -ExpandProperty Temp
            [PSCustomObject]@{
                Ubicacion = $ubic
                Min = ($temps | Measure-Object -Minimum).Minimum
                Max = ($temps | Measure-Object -Maximum).Maximum
                Promedio = [Math]::Round(($temps | Measure-Object -Average).Average, 2)
            }
        }

        [PSCustomObject]@{
            Fecha = $fecha
            Ubicaciones = $ubicaciones
        }
    }

    # --- Convertir a JSON ---
    $jsonFinal = @{
        fechas = @()
    }

    foreach ($item in $agrupados) {
        $sub = @{}
        foreach ($u in $item.Ubicaciones) {
            $sub[$u.Ubicacion] = @{
                Min = $u.Min
                Max = $u.Max
                Promedio = $u.Promedio
            }
        }

        # Añadir cada fecha con sus ubicaciones a un array
        $jsonFinal.fechas += @{
            $item.Fecha = $sub
        }
    }

    $jsonOutput = $jsonFinal | ConvertTo-Json -Depth 5

    # --- Mostrar o guardar ---
    if ($pantalla) {
        $jsonOutput
    } else {
        Set-Content -Path $archivo -Value $jsonOutput -Encoding UTF8
        Write-Output "Archivo JSON guardado en: $archivo"
    }

} catch {
    Write-Error "Ocurrió un error inesperado: $_"
    exit 1
} finally {
    Limpiar
}
