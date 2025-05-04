# --------------------------------- Informacion para Get-Help ---------------------------------

<#
.SYNOPSIS
Procesa archivos CSV con registros de temperatura y genera estadisticas por dia y ubicacion.

.DESCRIPTION
Lee archivos CSV desde un directorio, calcula minimos, maximos y promedios de temperatura agrupados
por fecha y ubicacion, y muestra el resultado por pantalla o lo guarda en un archivo JSON.

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

# --------------------------------- Parametros ---------------------------------

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$directorio,

    [Parameter(Mandatory = $false)]
    [string]$archivo,

    [Parameter(Mandatory = $false)]
    [switch]$pantalla
)

# --------------------------------- Validar ruta ---------------------------------
function ValidarRuta {
    param (
        [string]$ruta
    )
    if (-not (Test-Path $ruta)) {
        Write-Error "La ruta '$ruta' no existe."
        exit 1
    }
}

# --------------------------------- Limpiar ruta ---------------------------------
function Limpiar {
    Remove-Item -ErrorAction SilentlyContinue $tempFilePath, $tempRawData
}

# --------------------------------- Inicializacion ---------------------------------
$tempFilePath = "/tmp/ps_temp_$PID.json"
$tempRawData = "/tmp/ps_temp_$PID.raw"

try {
    ValidarRuta $directorio

    if ($archivo -and $pantalla) {
        Write-Error "No se puede usar -archivo y -pantalla al mismo tiempo."
        exit 1
    }

    if (-not $archivo -and -not $pantalla) {
        Write-Error "Debe especificar -archivo o -pantalla para indicar como mostrar la salida."
        exit 1
    }

    # --------------------------------- Procesar archivos ---------------------------------
    Get-ChildItem -Path $directorio -Filter *.csv | ForEach-Object {
        $csvFile = $_.FullName
        Write-Host "Procesando archivo: $csvFile"

        Get-Content $csvFile | ForEach-Object {
            $linea = $_.Trim()
            if ($linea -eq '') { return }

            $partes = $linea -split ','
            if ($partes.Length -ne 5) { return }

            $id, $fecha, $hora, $ubic, $temp = $partes
            if (-not ($temp -as [double])) {
                Write-Warning "Temperatura invalida '$temp' en archivo $csvFile"
                return
            }

            $fechaFormateada = $fecha -replace '/', '-'
            $clave = "$fechaFormateada|$ubic"
            Add-Content -Path $tempRawData -Value "$clave $temp"
        }
    }

    # --------------------------------- Agrupar datos ---------------------------------
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

    # --------------------------------- Convertir a JSON ---------------------------------
    $jsonFinal = @{
        fechas = @()
    }

    foreach ($item in $agrupados) {
        $sub = @{ }
        foreach ($u in $item.Ubicaciones) {
            $sub[$u.Ubicacion] = @{
                Min = $u.Min
                Max = $u.Max
                Promedio = $u.Promedio
            }
        }
        $jsonFinal.fechas += @{
            $item.Fecha = $sub
        }
    }

    $jsonOutput = $jsonFinal | ConvertTo-Json -Depth 5

    # --------------------------------- Mostrar o guardar ---------------------------------
    if ($pantalla) {
        $jsonOutput
    } else {
        Set-Content -Path $archivo -Value $jsonOutput -Encoding UTF8
        Write-Output "Archivo JSON guardado en: $archivo"
    }

} catch {
    Write-Error "Ocurrio un error inesperado: $_"
    exit 1
} finally {
    Limpiar
}
