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
El archivo de caché se mantiene entre ejecuciones y se elimina manualmente si se desea.
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

# Ruta de caché temporal en /tmp o en TEMP según el sistema
if ($IsWindows) {
    $TempDir = $env:TEMP
} else {
    $TempDir = "/tmp"
}

# Usamos un nombre fijo para el archivo de caché
$CachePath = Join-Path $TempDir "fruit_cache.json"

function Init-Cache {
    # Si el archivo de caché no existe, lo inicializamos como un objeto vacío
    if (-not (Test-Path $CachePath)) {
        '{}' | Out-File -Encoding utf8 $CachePath
    }
    return Get-Content $CachePath | ConvertFrom-Json
}

function Save-Cache ($cache) {
    # Guardar el caché en el archivo
    $cache | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $CachePath
}

function Get-FruitInfo {
    param (
        [string]$key,
        [string]$query,
        [ref]$cache
    )

    # Verificar si ya existe en el caché
    if ($cache.Value.PSObject.Properties.Name -contains $key) {
        return $cache.Value.$key | ConvertTo-Json -Compress
    }

    try {
        # Si no está en el caché, hacer la solicitud a la API
        $response = Invoke-RestMethod "https://www.fruityvice.com/api/fruit/$query" -ErrorAction Stop
    } catch {
        Write-Warning "Error al consultar '$query'. Verifica que el nombre o ID sea válido o tu conexión a Internet."
        return
    }

    if (-not $response.nutritions) {
        Write-Warning "La fruta '$query' no tiene información nutricional disponible."
        return
    }

    # Formatear la respuesta y guardarla en el caché
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
    # Inicializar el caché
    $cache = Init-Cache

    # Buscar por ID
    foreach ($i in $id) {
        $key = "$i"
        $result = Get-FruitInfo -key $key -query $i -cache ([ref]$cache)
        if ($result) {
            $result | ConvertFrom-Json | Format-List
        }
    }

    # Buscar por nombre
    foreach ($n in $name) {
        $key = $n.Trim().ToLower()
        $result = Get-FruitInfo -key $key -query $n -cache ([ref]$cache)
        if ($result) {
            $result | ConvertFrom-Json | Format-List
        }
    }

    # Guardar el caché actualizado
    Save-Cache $cache
}
catch {
    Write-Error "Error inesperado: $_.Message"
}