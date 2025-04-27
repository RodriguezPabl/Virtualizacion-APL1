#!/bin/bash

# Mostrar ayuda
mostrar_ayuda() {
    echo "Uso: $0 -d DIRECTORIO -b BACKUP -c CANTIDAD [-k]"
    echo
    echo "Parámetros:"
    echo "  -d, --directorio  Ruta del directorio a monitorear"
    echo "  -b, --backup      Ruta del directorio donde se guardarán los backups"
    echo "  -c, --cantidad    Cantidad de archivos a mover antes de generar backup"
    echo "  -k, --kill        Detener el demonio asociado al directorio"
    echo "  -h, --help        Mostrar esta ayuda"
}

# Variables
DIRECTORIO=""
BACKUP=""
CANTIDAD=""
KILL=false

# Parseo de parámetros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directorio)
            DIRECTORIO="$2"
            shift 2
            ;;
        -b|--backup)
            BACKUP="$2"
            shift 2
            ;;
        -c|--cantidad)
            CANTIDAD="$2"
            shift 2
            ;;
        -k|--kill)
            KILL=true
            shift
            ;;
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        *)
            echo "Parámetro desconocido: $1"
            mostrar_ayuda
            exit 1
            ;;
    esac
done

# Validaciones
if [[ "$KILL" != true ]]; then
    if [[ -z "$DIRECTORIO" || -z "$BACKUP" || -z "$CANTIDAD" ]]; then
        echo "Parámetros faltantes: -d, -b, -c son obligatorios" >&2
        exit 1
    fi
    if ! [[ "$CANTIDAD" =~ ^[1-9][0-9]*$ ]]; then
        echo "El parámetro -c (cantidad) debe ser un número entero positivo." >&2
        exit 1
    fi
fi

# Convertir rutas relativas a absolutas
DIRECTORIO=$(realpath "$DIRECTORIO" 2>/dev/null)
BACKUP=$(realpath "$BACKUP" 2>/dev/null)

# Archivo PID y PGID
HASH=$(echo "$DIRECTORIO" | md5sum | cut -d ' ' -f1)
PID_FILE="/tmp/demonio_${HASH}.pid"
PGID_FILE="/tmp/demonio_${HASH}.pgid"
LOG_FILE="/tmp/backup_error_${HASH}.log"

# Si es kill, intentar detener demonio
if [[ "$KILL" == true ]]; then
    if [[ -z "$DIRECTORIO" ]]; then
        echo "Debe especificar el directorio con -d para detener el demonio." >&2
        exit 1
    fi

    if [[ -f "$PID_FILE" && -f "$PGID_FILE" ]]; then
        PGID=$(cat "$PGID_FILE")
        if kill -0 "-$PGID" 2>/dev/null; then
            kill -- -"$PGID"
            echo "Demonio detenido (PGID $PGID)."
        else
            echo "No se pudo detener el demonio. Puede que ya no esté activo." >&2
        fi
        rm -f "$PID_FILE" "$PGID_FILE" "$LOG_FILE"
        exit 0
    else
        echo "No se encontró un proceso demonio para este directorio." >&2
        exit 1
    fi
fi


# Validar directorios
if [[ ! -d "$DIRECTORIO" ]]; then
    echo "El directorio especificado no existe: $DIRECTORIO" >&2
    exit 1
fi

if [[ ! -d "$BACKUP" ]]; then
    echo "El directorio de backup especificado no existe: $BACKUP" >&2
    exit 1
fi

# Comprobar comandos necesarios
for cmd in inotifywait zip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: el comando '$cmd' no está instalado. Instalalo." >&2
        exit 1
    fi
done

# Verificar si ya hay un demonio corriendo
if [[ -f "$PID_FILE" ]]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Ya hay un demonio ejecutándose para este directorio (PID $PID)." >&2
        exit 1
    else
        rm -f "$PID_FILE" "$PGID_FILE" "$LOG_FILE"
    fi
fi

# Función para generar backup
generar_backup() {
    FECHA=$(date +%Y%m%d_%H%M%S)
    DIR_BASE=$(basename "$DIRECTORIO")
    DIR_PARENT=$(dirname "$DIRECTORIO")
    BACKUP_FILE="$BACKUP/${DIR_BASE}_$FECHA.zip"

    if cd "$DIR_PARENT"; then
        zip -r "$BACKUP_FILE" "$DIR_BASE" > /dev/null 2>>"$LOG_FILE"
        if [[ $? -eq 0 ]]; then
            echo "Backup generado: ${DIR_BASE}_$FECHA.zip"
        else
            echo "Error al generar el backup. Revisá $LOG_FILE"
        fi
    else
        echo "No se pudo acceder al directorio padre de $DIRECTORIO para generar el backup."
    fi
}

# Lanzar demonio en segundo plano
(
    contador=0

    # Ordenar archivos existentes
    for archivo in "$DIRECTORIO"/*; do
        [[ -f "$archivo" ]] || continue
        extension="${archivo##*.}"
        carpeta="$DIRECTORIO/$(echo "$extension" | tr '[:lower:]' '[:upper:]')"
        mkdir -p "$carpeta"
        mv "$archivo" "$carpeta/"
        ((contador++))
    done

    if (( contador >= CANTIDAD )); then
        generar_backup
        contador=0
    fi

    # Monitorear nuevos archivos
    inotifywait -mq -e create -e moved_to --format '%f' "$DIRECTORIO" | while read -r archivo; do
        full_path="$DIRECTORIO/$archivo"

        for i in {1..30}; do
            [[ -f "$full_path" ]] && break
            sleep 0.1
        done

        [[ -f "$full_path" ]] || continue

        extension="${archivo##*.}"
        carpeta="$DIRECTORIO/$(echo "$extension" | tr '[:lower:]' '[:upper:]')"
        mkdir -p "$carpeta"
        mv "$full_path" "$carpeta/"
        ((contador++))

        if (( contador >= CANTIDAD )); then
            generar_backup
            contador=0
        fi
    done
) &

# Guardar PID y PGID
echo $! > "$PID_FILE"
PGID=$(ps -o pgid= -p $! | tr -d ' ')
echo "$PGID" > "$PGID_FILE"

echo "Demonio iniciado correctamente. PID: $! PGID: $PGID"
