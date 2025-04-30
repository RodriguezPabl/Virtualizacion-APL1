#!/bin/bash

############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

function mostrar_ayuda() {
    echo "Uso: $0 -d <directorio> -p <palabra1,palabra2,...> -a <ext1,ext2,...>"
    echo
    echo "Parámetros:"
    echo "  -d, --directorio   Ruta del directorio a analizar"
    echo "  -p, --palabras     Lista de palabras a contabilizar (separadas por coma)"
    echo "  -a, --archivos     Lista de extensiones de archivos a buscar (separadas por coma)"
    echo "  -h, --help         Muestra esta ayuda"
    exit 0
}

# Inicialización
DIRECTORIO=""
PALABRAS=""
EXTENSIONES=""

# Parsear parámetros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directorio)
            DIRECTORIO="$2"
            shift 2
            ;;
        -p|--palabras)
            PALABRAS="$2"
            shift 2
            ;;
        -a|--archivos)
            EXTENSIONES="$2"
            shift 2
            ;;
        -h|--help)
            mostrar_ayuda
            ;;
        *)
            echo "Parámetro desconocido: $1"
            mostrar_ayuda
            ;;
    esac
done

# Validaciones específicas
if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: debe especificar el directorio con -d o --directorio."
    exit 1
fi

if [[ -z "$PALABRAS" ]]; then
    echo "Error: debe especificar al menos una palabra con -p o --palabras."
    exit 1
fi

if [[ -z "$EXTENSIONES" ]]; then
    echo "Error: debe especificar al menos una extensión de archivo con -a o --archivos."
    exit 1
fi

if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: el directorio '$DIRECTORIO' no existe o no es un directorio válido."
    exit 1
fi

# Convertir listas separadas por comas a arrays
IFS=',' read -r -a PALABRAS_ARRAY <<< "$PALABRAS"
IFS=',' read -r -a EXT_ARRAY <<< "$EXTENSIONES"

# Buscar archivos con extensiones dadas
ARCHIVOS=()
for ext in "${EXT_ARRAY[@]}"; do
    while IFS= read -r -d '' archivo; do
        ARCHIVOS+=("$archivo")
    done < <(find "$DIRECTORIO" -type f -name "*.$ext" -print0)
done

if [ ${#ARCHIVOS[@]} -eq 0 ]; then
    echo "No se encontraron archivos con las extensiones dadas."
    exit 0
fi

# Pasar palabras a una cadena para awk
PALABRAS_AWK=$(IFS=" "; echo "${PALABRAS_ARRAY[*]}")

# Ejecutar AWK con limpieza de símbolos
awk -v palabras="$PALABRAS_AWK" '
BEGIN {
    split(palabras, lista)
    for (i in lista) {
        contar[lista[i]] = 0
    }
}
{
    texto = $0
    while (match(texto, /[a-zA-Z0-9_]+/)) {
        palabra = substr(texto, RSTART, RLENGTH)
        texto = substr(texto, RSTART + RLENGTH)

        for (i in lista) {
            if (palabra == lista[i]) {
                contar[lista[i]]++
            }
        }
    }
}
END {
    for (palabra in contar) {
        print palabra ": " contar[palabra]
    }
}
' "${ARCHIVOS[@]}" | sort -t ':' -k2 -nr

