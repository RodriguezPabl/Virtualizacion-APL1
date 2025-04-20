<#
.SYNOPSIS
Cuenta la cantidad de ocurrencias de palabras específicas en archivos dentro de un directorio.

.DESCRIPTION
Este script analiza todos los archivos con extensiones específicas dentro de un directorio y sus subdirectorios, 
y cuenta cuántas veces aparecen ciertas palabras. Las búsquedas son case-sensitive.

.PARAMETER directorio
Ruta del directorio a analizar (obligatorio).

.PARAMETER palabras
Lista de palabras a contabilizar (obligatorio).

.PARAMETER archivos
Lista de extensiones de archivo en las que se buscarán las palabras (obligatorio).

.EXAMPLE
.\ejercicio3.ps1 -directorio .\ -palabras if,hola,else -archivos txt

#>

param (
    [Parameter(Mandatory = $false, HelpMessage = "Ruta del directorio a analizar.")]
    [ValidateNotNullOrEmpty()]
    [string]$directorio,

    [Parameter(Mandatory = $false, HelpMessage = "Lista de palabras a contabilizar.")]
    [ValidateNotNullOrEmpty()]
    [string[]]$palabras,

    [Parameter(Mandatory = $false, HelpMessage = "Lista de extensiones de archivo.")]
    [ValidateNotNullOrEmpty()]
    [string[]]$archivos
)


# --- Validaciones de parámetros obligatorios ---
if (-not $directorio) {
    Write-Host "Error: debe especificar el directorio con -directorio."
    exit 1
}

if (-not $palabras -or $palabras.Count -eq 0) {
    Write-Host "Error: debe especificar al menos una palabra con -palabras."
    exit 1
}

if (-not $archivos -or $archivos.Count -eq 0) {
    Write-Host "Error: debe especificar al menos una extensión de archivo con -archivos."
    exit 1
}

if (-not (Test-Path -Path $directorio -PathType Container)) {
    Write-Host "Error: el directorio '$directorio' no existe."
    exit 1
}

# Inicializar el contador
$contador = @{}
foreach ($p in $palabras) {
    $contador[$p] = 0
}

# Buscar archivos por extensión
$archivosEncontrados = @()
foreach ($ext in $archivos) {
    $archivosEncontrados += Get-ChildItem -Path $directorio -Recurse -File -Filter "*.$ext"
}

if ($archivosEncontrados.Count -eq 0) {
    Write-Host "No se encontraron archivos con las extensiones dadas."
    exit 0
}

# Procesar cada archivo
foreach ($archivo in $archivosEncontrados) {
    $contenido = Get-Content $archivo -Raw
    $matches = [regex]::Matches($contenido, '\b[a-zA-Z0-9_]+\b')

    foreach ($m in $matches) {
        $palabraDetectada = $m.Value

        foreach ($buscar in $palabras) {
            if ($palabraDetectada -eq $buscar) {
                $contador[$buscar]++
            }
        }
    }
}


# Mostrar resultados ordenados por cantidad (descendente)
$contador.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    Write-Output "$($_.Key): $($_.Value)"
}

