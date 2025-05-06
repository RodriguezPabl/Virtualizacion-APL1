<#
.SYNOPSIS
Consulta frutas por nombre o ID desde la API de Fruityvice.

.DESCRIPTION
Permite buscar frutas por nombre (en inglés) o ID. Guarda los resultados en caché local temporal y los muestra formateados.

.PARAMETER id
Uno o más IDs numéricos de frutas a consultar.

.PARAMETER name
Uno o más nombres de frutas a consultar (en inglés).

.EXAMPLE
.\ejercicio5.ps1 -id 1,2 -name banana,orange

.NOTES
El archivo de caché se elimina al finalizar el script, incluso si ocurre un error.
#>

############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [int[]]$id,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$name
)

# Validar que al menos uno esté presente
if (-not $id -and -not $name) {
    Write-Error "Debes especificar al menos un parámetro: -id o -name."
    exit 1
}

# Ruta de caché temporal en /tmp
if ($IsWindows) {
    $TempDir = $env:TEMP
} else {
    $TempDir = "/tmp"
}

$CachePath = Join-Path $TempDir "fruit_cache_$(Get-Random).json"

function Init-Cache {
    '{}' | Out-File -Encoding utf8 $CachePath
    return Get-Content $CachePath | ConvertFrom-Json
}

function Save-Cache ($cache) {
    $cache | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $CachePath
}

function Get-FruitInfo {
    param (
        [string]$key,
        [string]$query,
        [ref]$cache
    )

    if ($cache.Value.PSObject.Properties.Name -contains $key) {
        return $cache.Value.$key | ConvertTo-Json -Compress
    }

    try {
        $response = Invoke-RestMethod "https://www.fruityvice.com/api/fruit/$query" -ErrorAction Stop
    } catch {
        Write-Warning "Error al consultar '$query'. Verifica que el nombre o ID sea válido o tu conexión a Internet."
        return
    }

    if (-not $response.nutritions) {
        Write-Warning "La fruta '$query' no tiene información nutricional disponible."
        return
    }

    $parsed = [PSCustomObject]@{
        id             = $response.id
        name           = $response.name
        genus          = $response.genus
        calories       = $response.nutritions.calories
        fat            = $response.nutritions.fat
        sugar          = $response.nutritions.sugar
        carbohydrates  = $response.nutritions.carbohydrates
        protein        = $response.nutritions.protein
    }
    $cache.Value | Add-Member -MemberType NoteProperty -Name "$key" -Value $parsed -Force
    return $parsed | ConvertTo-Json -Compress
}

# MAIN
try {
    $cache = Init-Cache

    foreach ($i in $id) {
        $key = "$i"
        $result = Get-FruitInfo -key $key -query $i -cache ([ref]$cache)
        if ($result) {
            $result | ConvertFrom-Json | Format-List
        }
    }

    foreach ($n in $name) {
        $key = $n.Trim().ToLower()
        $result = Get-FruitInfo -key $key -query $n -cache ([ref]$cache)
        if ($result) {
            $result | ConvertFrom-Json | Format-List
        }
    }

    Save-Cache $cache
}
catch {
    Write-Error "Error inesperado: $_.Message"
}
finally {
    # Borrar el archivo de caché al finalizar el script
    if (Test-Path $CachePath) {
        Remove-Item -Path $CachePath -ErrorAction SilentlyContinue
    }
}
