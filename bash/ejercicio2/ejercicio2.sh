#!/bin/bash

# Variables para manejo de errores
error_log="/tmp/matrix_script_error.log"
trap 'rm -f /tmp/matrix_script.tmp' EXIT

# Función para mostrar la ayuda
ayuda() {
    echo "Uso: $0 [-m MATRIZ] ( [-p PRODUCTO] o [-t] ) [-s SEPARADOR]"
    echo "  -m, --matriz   Ruta del archivo de la matriz."
    echo "  -p, --producto Valor entero para el producto escalar. No se puede usar con -t o --trasponer."
    echo "  -t, --trasponer Indica que se debe realizar la operación de trasposición. No se puede usar con -p o --producto."
    echo "  -s, --separador Carácter para usar como separador de columnas."
    echo "  -h, --help     Muestra esta ayuda."
}

# Validar comandos y parámetros
validar() {
    if [[ -z "$matrix_file" ]]; then
        echo "Error: El parámetro -m es obligatorio. Utilice $0 -h o --help para obtener ayuda."
        exit 1
    fi

    if [[ "$product" && "$transpose" ]]; then
        echo "Error: Los parámetros -p y -t son mutuamente excluyentes. Utilice $0 -h o --help para obtener ayuda."
        exit 1
    fi
}

# Función para verificar y leer la matriz desde el archivo
leer_matriz() {
    if [[ ! -f "$matrix_file" ]]; then
        echo "Error: El archivo de la matriz no existe."
        exit 1
    fi

    if [[ ! -s "$matrix_file" ]]; then
        echo "Error: El archivo de la matriz está vacío."
        exit 1
    fi

    # Definir el separador, usar por defecto '|'
    local separador=${sep:-|}
    # Verifica que el archivo tiene el formato adecuado
    awk -F"$separador" '
    BEGIN {
        valid = 1
        num_campos_por_linea = 0
    }
    {
        # Verificar que cada campo sea un número negativo, positivo o decimal
        for (i = 1; i <= NF; i++) {
            if ($i < -99999 || $i > 99999) {
                valid = 0
            }
	    #if ($i !~ /^-?[0-9]+(\.[0-9]+)?$/) -> esto no me funciona
        }
        # Actualiza el número máximo de campos encontrados
        if (NF > num_campos_por_linea) {
            num_campos_por_linea = NF
        }
    }     
    END {
        #Verificar si alguna línea no es válida o si no hay líneas
        if (valid == 0 || num_campos_por_linea == 0) {
            exit 1
        }
    }' "$matrix_file" || {
        echo "Error: El archivo de la matriz contiene caracteres no válidos o tiene un formato incorrecto."
        exit 1
    }

    matrix=$(<"$matrix_file")
}
# Función para realizar la trasposición de la matriz
trasponer() {
    local tmpfile="/tmp/matrix_script.tmp"
    local separador=${separador:-|}
    awk -v FS="$separador" '{
        for (i = 1; i <= NF; i++) {
            matrix[NR,i] = $i
        }
        num_campos_por_linea = (NF > num_campos_por_linea ? NF : num_campos_por_linea)
    }
    END {
        for (i = 1; i <= num_campos_por_linea; i++) {
            for (j = 1; j <= NR; j++) {
                printf "%.2f", matrix[j,i]
                if (j < NR) {
                    printf "%s", FS
                }
            }
            print ""
        }
    }' "$matrix_file" > "$tmpfile"

    mv "$tmpfile" "$output_file"
    echo "Trasposición completada. Resultado guardado en $output_file"
}

# Función para realizar el producto escalar de la matriz
producto() {
    local escalar=$1
    local tmpfile="/tmp/matrix_script.tmp"
    local separador=${separador:-|}
    awk -v FS="$separador" -v escalar="$escalar" '{
        for (i = 1; i <= NF; i++) {
            printf "%.2f", $i * escalar
            if (i < NF) {
                printf "%s", FS
            }
        }
        print ""
    }' "$matrix_file" > "$tmpfile"
    mv "$tmpfile" "$output_file"
    echo "Producto escalar completado. Resultado guardado en $output_file"
}

# Procesar los parámetros
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -m|--matriz)
            matrix_file="$2"
            shift 2
            ;;
        -p|--producto)
            if [[ -z "$2" ]]; then
                echo "Error: Se debe ingresar el valor entero para escalar la matriz."
	 	        exit 1
            fi
            product="$2"
            shift 2
            ;;
        -t|--trasponer)
            transpose=1
            shift
            ;;
        -s|--separador)
            sepa="$2"
	    if [[ ($sepa =~ ^-?[0-9]*\.?[0-9]+$) || $sepa == "-" ]]; then
		echo "No se puede utilizar como separador numeros o el simbolo '-'"
	 	exit 1
	    fi
            shift 2
            ;;
        -h|--help)
            ayuda
            exit 0
            ;;
        *)
            echo "Error: Parámetro desconocido $1"
            ayuda
            exit 1
            ;;
    esac
done

output_file="$(dirname "$matrix_file")/salida.$(basename "$matrix_file")"

validar
leer_matriz

if [[ "$transpose" ]]; then
    trasponer
elif [[ "$product" ]]; then
    producto "$product"
else
    echo "Error: Se debe especificar al menos una operación: -p o -t. Utilice $0 -h o --help para obtener ayuda."
    exit 1
fi

if [[ "$sepa" ]]; then
    tr '|' "$sepa" < "$output_file" > temp && mv temp "$output_file"
fi