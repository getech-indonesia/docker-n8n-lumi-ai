#!/bin/bash
# filepath: scripts/restore_n8n.sh

# Konfigurasi S3
S3_BUCKET_NAME="lumi-ai-project"
S3_ENDPOINT_URL="https://is3.cloudhost.id"
S3_REGION="us-east-1"
# S3_ACCESS_KEY dan S3_SECRET_KEY diambil dari environment variables

# Nama volume Docker yang akan direstore
VOLUME_NAME="docker-n8n-lumi-ai_n8n_data"

# Path file backup yang akan direstore (bisa dari argumen atau otomatis ambil backup terbaru)
RESTORE_FILENAME="$1"
BACKUP_TEMP_DIR="/tmp/n8n_backup_temp"
LOCAL_RESTORE_PATH="$BACKUP_TEMP_DIR/$RESTORE_FILENAME"

# Path di S3: backup-n8n/DD-MM/
# Jika ingin otomatis ambil backup terbaru, bisa tambahkan logika list-object S3

# Logging
LOG_FILE="/var/log/n8n_restore.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=============================================="
echo "Memulai proses restore n8n pada $(date)"
echo "=============================================="

# Cek argumen
if [ -z "$RESTORE_FILENAME" ]; then
    echo "ERROR: Nama file backup harus diberikan sebagai argumen!"
    echo "Contoh: ./restore_n8n.sh n8n_backup_2025-07-05_15-19-26.tar.gz"
    exit 1
fi

# Membuat direktori sementara jika belum ada
mkdir -p $BACKUP_TEMP_DIR
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal membuat direktori sementara $BACKUP_TEMP_DIR. Proses restore dibatalkan."
    exit 1
fi

# Cek kredensial S3
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    echo "ERROR: Variabel lingkungan S3_ACCESS_KEY dan/atau S3_SECRET_KEY tidak di-set."
    exit 1
fi

# Konfigurasi AWS CLI
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY
export AWS_DEFAULT_REGION=$S3_REGION

# Download file backup dari S3
echo "Mengunduh file backup dari S3..."
aws s3 cp "s3://$S3_BUCKET_NAME/backup-n8n/$(date +%d-%m)/$RESTORE_FILENAME" "$LOCAL_RESTORE_PATH" --endpoint-url "$S3_ENDPOINT_URL"
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal mengunduh file backup dari S3."
    exit 1
fi
echo "File backup berhasil diunduh: $LOCAL_RESTORE_PATH"

# Mendapatkan path volume Docker
CONTAINER_ID=$(docker compose ps -q n8n)
if [ -z "$CONTAINER_ID" ]; then
    CONTAINER_ID=$(docker ps -q --filter "name=n8n")
    if [ -z "$CONTAINER_ID" ]; then
        echo "ERROR: Container n8n tidak ditemukan."
        exit 1
    fi
fi
VOLUME_PATH=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Name "'"$VOLUME_NAME"'" }}{{ .Source }}{{ end }}{{ end }}' $CONTAINER_ID)
if [ -z "$VOLUME_PATH" ]; then
    echo "ERROR: Tidak dapat menemukan path untuk volume Docker '$VOLUME_NAME'."
    exit 1
fi
echo "Path untuk volume '$VOLUME_NAME' adalah: $VOLUME_PATH"

# Hapus isi volume lama (hati-hati!)
echo "Menghapus seluruh isi volume $VOLUME_PATH..."
sudo rm -rf "$VOLUME_PATH"/*
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal menghapus isi volume."
    exit 1
fi

# Restore backup ke volume
echo "Mengekstrak backup ke volume..."
sudo tar -xzf "$LOCAL_RESTORE_PATH" -C "$VOLUME_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal mengekstrak backup ke volume."
    exit 1
fi

docker compose restart n8n
echo "Restore selesai. Silakan restart container n8n jika diperlukan."
echo "=============================================="
exit 0