#!/bin/bash

############### INTEGRANTES ###############
###     Justiniano, Máximo              ###
###     Mallia, Leandro                 ###
###     Maudet, Alejandro               ###
###     Naspleda, Julián                ###
###     Rodriguez, Pablo                ###
###########################################

# --- Variables globales ---
DIRECTORIO=""
SALIDA=""
MOSTRAR_POR_PANTALLA=false
TEMP_FILE="/tmp/temp_$$.json"

# --- Limpieza de archivos temporales ---
function limpiar() {
    [[ -f "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"
    [[ -f "$TEMP_FILE.data" ]] && rm -f "$TEMP_FILE.data"
}
trap limpiar EXIT

# --- Función de ayuda ---
function mostrar_ayuda() {
    echo "Uso: $0 -d <directorio> [-a <archivo_salida> | -p]"
    echo ""
    echo "  -d, --directorio   Ruta del directorio con archivos CSV a leer."
    echo "  -a, --archivo      Ruta del archivo JSON de salida (ruta completa incluyendo el nombre del archivo)."
    echo "  -p, --pantalla     Muestra el resultado por pantalla (en formato JSON)."
    echo "  -h, --help         Muestra esta ayuda."
}

# --- Validación de parámetros ---
function validar_parametros() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--directorio)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: el parámetro -d requiere una ruta como argumento."
                    exit 1
                fi
                DIRECTORIO="$2"
                shift 2
                ;;
            -a|--archivo)
                if [[ -z "$2" || "$2" == -* ]]; then
                    echo "Error: el parámetro -a requiere una ruta de archivo como argumento."
                    exit 1
                fi
                SALIDA="$2"
                shift 2
                ;;
            -p|--pantalla)
                MOSTRAR_POR_PANTALLA=true
                shift
                ;;
            -h|--help)
                mostrar_ayuda
                exit 0
                ;;
            *)
                echo "Error: parámetro desconocido: $1"
                mostrar_ayuda
                exit 1
                ;;
        esac
    done

    if [[ -z "$DIRECTORIO" ]]; then
        echo "Error: debe especificar el directorio con -d o --directorio."
        exit 1
    fi

    if [[ "$MOSTRAR_POR_PANTALLA" = false && -z "$SALIDA" ]]; then
        echo "Error: debe elegir mostrar por pantalla (-p) o generar un archivo (-a)."
        exit 1
    fi

    if [[ "$MOSTRAR_POR_PANTALLA" = true && -n "$SALIDA" ]]; then
        echo "Error: no puede usar -a y -p al mismo tiempo."
        exit 1
    fi

    if [[ ! -d "$DIRECTORIO" ]]; then
        echo "Error: el directorio '$DIRECTORIO' no existe o no es un directorio."
        exit 1
    fi

    if [[ -n "$SALIDA" ]]; then
        DIR_SALIDA=$(dirname "$SALIDA")
        if [[ ! -d "$DIR_SALIDA" ]]; then
            echo "Error: el directorio de salida '$DIR_SALIDA' no existe."
            exit 1
        fi

        if [[ -e "$SALIDA" ]]; then
            echo "Error: el archivo de salida '$SALIDA' ya existe. Elija otro nombre o elimine el archivo."
            exit 1
        fi
    fi
}


# --- Procesar archivos CSV ---
function procesar_csv() {
    TMP_RAW="${TEMP_FILE}.raw"

    for archivo in "$DIRECTORIO"/*.csv; do
        [[ ! -f "$archivo" ]] && continue

        while IFS=',' read -r id fecha hora ubicacion temp; do
            [[ -z "$temp" ]] && continue
            if ! [[ "$temp" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                echo "Advertencia: temperatura inválida en archivo $archivo: '$temp'" >&2
                continue
            fi
            dia_formateado=$(echo "$fecha" | tr '/' '-')
            clave="$dia_formateado|$ubicacion"
            echo "$clave $temp" >> "$TMP_RAW"
        done < "$archivo"
    done

    mv "$TMP_RAW" "$TEMP_FILE.data"
}

# --- Calcular estadísticas y generar JSON ---
function generar_json() {
    echo '{ "fechas": [' > "$TEMP_FILE"

    fechas=$(awk -F'[| ]' '{print $1}' "$TEMP_FILE.data" | sort -u)

    for fecha in $fechas; do
        echo "    {" >> "$TEMP_FILE"
        echo "      \"$fecha\": {" >> "$TEMP_FILE"

        ubicaciones=$(awk -F'[| ]' -v fecha="$fecha" '$1 == fecha {print $2}' "$TEMP_FILE.data" | sort -u)

        for ubic in $ubicaciones; do
            valores=$(awk -F'[| ]' -v fecha="$fecha" -v ubic="$ubic" '$1 == fecha && $2 == ubic {print $3}' "$TEMP_FILE.data")

            min=$(echo "$valores" | sort -n | head -n1)
            max=$(echo "$valores" | sort -n | tail -n1)

            suma=0
            count=0
            while read -r t; do
                suma=$(echo "$suma + $t" | bc)
                count=$((count + 1))
            done <<< "$valores"

            if [[ "$count" -eq 0 ]]; then
                promedio=0
            else
                promedio=$(echo "scale=2; $suma / $count" | bc)
            fi

            echo "        \"$ubic\": {" >> "$TEMP_FILE"
            echo "          \"Promedio\": $promedio," >> "$TEMP_FILE"
            echo "          \"Max\": $max," >> "$TEMP_FILE"
            echo "          \"Min\": $min" >> "$TEMP_FILE"
            echo "        }," >> "$TEMP_FILE"
        done

        sed -i '$ s/,$//' "$TEMP_FILE"
        echo "      }" >> "$TEMP_FILE"
        echo "    }," >> "$TEMP_FILE"
    done

    sed -i '$ s/,$//' "$TEMP_FILE"
    echo "  ]" >> "$TEMP_FILE"
    echo "}" >> "$TEMP_FILE"

    rm -f "$TEMP_FILE.data"
}

# --- Mostrar o guardar resultado ---
function salida() {
    if $MOSTRAR_POR_PANTALLA; then
        cat "$TEMP_FILE"
    else
        mv "$TEMP_FILE" "$SALIDA"
        echo "Archivo JSON guardado en: $SALIDA"
    fi
}

# --- Ejecución ---
validar_parametros "$@"
procesar_csv
generar_json
salida
