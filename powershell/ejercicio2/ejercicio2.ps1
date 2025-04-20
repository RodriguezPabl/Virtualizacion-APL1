<#
.SYNOPSIS
Este script realiza operaciones de producto escalar y trasposicion de matrices a partir de un archivo de texto plano.

.DESCRIPTION
Este script realiza la operacion de producto escalar o trasposicion (no ambas) a una matriz guardada en un archivo de texto plano que tiene '|' como caracter de separacion entre elementos, pudiendo cambiar este en la ejecucion del script.
Este se guarda en la misma carpeta de la matriz original bajo el nombre de "salida.NombreDeLaMatrizOriginal.txt".
.PARAMETER matriz
Ruta del archivo que contiene la matriz.

.PARAMETER producto
Valor entero para utilizarse en el producto escalar.

.PARAMETER trasponer
Indica que se debe realizar la operación de trasposición sobre la matriz.

.PARAMETER separador
Carácter para utilizarse como separador de columnas.

.EXAMPLE
Get-Help ./ejercicio2.ps1
.EXAMPLE
./ejercicio2.ps1 -matriz lote1/matriz.txt -trasponer -separador '/'
.EXAMPLE
./ejercicio2.ps1 -matriz lote4/matriz.txt -producto 3
.EXAMPLE
./ejercicio2.ps1 -matriz lote3/matriz.txt -separador 'F' -producto -1
.EXAMPLE
./ejercicio2.ps1 -trasponer -matriz lote1/matriz.txt
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$matriz,

    [Parameter()]
    [ValidatePattern('^-?\d+(\.\d+)?$')]
    [double]$producto,

    [Parameter()]
    [switch]$trasponer,

    [Parameter()]
    [ValidatePattern('^(?!-|\d).*$')]
    [char]$separador
)

# Función para manejar errores
function Handle-Error (){
    param (
        [string]$message
    )
    Write-Host "Error: $message" -ForegroundColor Red
    exit 1
}

# Validar la existencia del archivo
if (-Not (Test-Path $matriz)) {
    Handle-Error "El archivo especificado no existe: $matriz"
}

# Leer la matriz desde el archivo
$matrizContenido = Get-Content $matriz -ErrorAction Stop
if ($null -eq $matrizContenido -or $matrizContenido.Count -eq 0) {
    Handle-Error "El archivo de la matriz esta vacio o no se pudo leer."
}

# Procesar la matriz
$sep = '|'
$matrizValores = @()
foreach ($linea in $matrizContenido) {
    $fila = $linea -split [regex]::Escape($sep)
    # Validar que todos los valores son numéricos
    if ($fila -notmatch '^-?\d+(\.\d+)?$' -and $fila -notmatch '^-?\d+$') {
        Handle-Error "La fila '$linea' contiene valores no numericos."
    }
    $matrizValores += $fila
}
$columnas = $fila.Length

# Función para realizar el producto escalar
function Producto-Escalar() {
    param (
        [array]$matriz,
        [double]$factor
    )
    $resultado = @()
    $matriz = $matriz | ForEach-Object {[double]$_ * $factor}
    for ($i = 0; $i -lt $matriz.Length; $i += $columnas) {
        $nuevaFila = $matriz[$i..([math]::min($i + $columnas - 1, $matriz.Length - 1))]
    	$resultado += $nuevaFila -join "$separador"
    }
    $output = $resultado -join "`n"
    return $output
}

# Función para trasponer la matriz
function Trasponer-Matriz() {
    param (
        [array]$matriz
    )
    $matriz = $matriz -split ' ' | ForEach-Object { [double]$_ }
    $filas = [math]::Ceiling($matriz.Length / $columnas)
    $matrizTraspuesta = @()
    for($i = 0; $i -lt $columnas; $i++) {
	$nuevaFila = @()
	for ($j = 0; $j -lt $filas; $j++) {
 	    $indice = $i + $j * $columnas
	    if ($indice -lt $matriz.Length) {
 		$nuevaFila += $matriz[$indice]
	    }
	}
   	$matrizTraspuesta += ($nuevaFila -join "$separador")
    }
    $output = $matrizTraspuesta -join "`n"
    return $output
}

# Manejo de la lógica de operación
try {  
    if ($producto -and $trasponer) {
        Handle-Error "No se puede usar -producto junto con -trasponer."
    }
    if (-not $separador) {
	$separador = $sep
    }
    if ($trasponer) {
        $resultado = Trasponer-Matriz -matriz $matrizValores
    } elseif ($producto) {
        $resultado = Producto-Escalar -matriz $matrizValores -factor $producto
    } else {
        Handle-Error "Se debe especificar al menos -producto o -trasponer."
    }

    # Generar el nombre del archivo de salida
    $nombreSalida = "salida.$([System.IO.Path]::GetFileName($matriz))"
    $rutaSalida = Join-Path -Path (Split-Path -Path $matriz -Parent) -ChildPath $nombreSalida

    # Escribir el resultado en el archivo de salida
    Set-Content -Path $rutaSalida -Value $resultado -ErrorAction Stop
    Write-Host "El resultado se ha guardado en: $rutaSalida" -ForegroundColor Green
}
catch {
    Handle-Error "Ocurrió un error inesperado: $_"
}