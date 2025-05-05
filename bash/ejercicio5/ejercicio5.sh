#!/bin/bash

############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

API_URL="https://www.fruityvice.com/api/fruit"
CACHE_FILE="/tmp/fruit_cache.json"

# Verificar si jq está instalado
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: La herramienta 'jq' no está instalada. Por favor instálala e intenta nuevamente." >&2
    echo "En Ubuntu/Debian: sudo apt install jq" >&2
    exit 1
fi

# Función para mostrar la ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Consulta información de frutas desde la API de Fruityvice."
    echo ""
    echo "Opciones:"
    echo "  -h, --help          Muestra este mensaje de ayuda."
    echo "  -i, --id            Uno o más IDs de frutas separados por coma."
    echo "  -n, --name          Uno o más nombres de frutas separados por coma."
    echo ""
    echo "Ejemplo de uso:"
    echo "  $0 --id 1,2 --name banana,orange"
}

# Crear el archivo de caché si no existe
touch "$CACHE_FILE"

# Función para obtener y cachear datos
get_fruit_info() {
    local key="$1"
    local query="$2"

    # Buscar en caché
    cached=$(jq -r --arg key "$key" '.[$key] // empty' "$CACHE_FILE")
    if [[ -n "$cached" ]]; then
        echo "$cached"
        return
    fi

    # Consultar API
    response=$(curl -s -f "$API_URL/$query")
    if [[ $? -ne 0 || -z "$response" ]]; then
        echo "Error: No se encontró la fruta '$query' o hubo un problema con la API." >&2
        return
    fi

    # Extraer campos necesarios y mostrar
    parsed=$(echo "$response" | jq -r '{
        id: .id,
        name: .name,
        genus: .genus,
        calories: .nutritions.calories,
        fat: .nutritions.fat,
        sugar: .nutritions.sugar,
        carbohydrates: .nutritions.carbohydrates,
        protein: .nutritions.protein
    }')

    echo "$parsed"

    # Guardar en caché
    tmp=$(mktemp)
    jq --arg key "$key" --argjson val "$parsed" '. + {($key): $val}' "$CACHE_FILE" > "$tmp" && mv "$tmp" "$CACHE_FILE"
}

# Parsear argumentos
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -i|--id) IFS=',' read -ra IDS <<< "$2"; shift ;;
        -n|--name) IFS=',' read -ra NAMES <<< "$2"; shift ;;
        *) echo "Opción no válida: $1"; show_help; exit 1 ;;
    esac
    shift
done

# Verificar si al menos uno de los parámetros obligatorios está presente
if [[ -z "${IDS+x}" && -z "${NAMES+x}" ]]; then
    echo "Error: Debes proporcionar al menos un parámetro (-i o -n)." >&2
    show_help
    exit 1
fi

# Buscar por ID
for id in "${IDS[@]}"; do
    id_trimmed=$(echo "$id" | xargs)
    result=$(get_fruit_info "$id_trimmed" "$id_trimmed")
    [[ -n "$result" ]] && echo "$result"
done

# Buscar por nombre
for name in "${NAMES[@]}"; do
    name_trimmed=$(echo "$name" | xargs)
    result=$(get_fruit_info "$name_trimmed" "$name_trimmed")
    [[ -n "$result" ]] && echo "$result"
done

# Borrar el archivo de caché al finalizar el script
trap 'rm -f "$CACHE_FILE"' EXIT
