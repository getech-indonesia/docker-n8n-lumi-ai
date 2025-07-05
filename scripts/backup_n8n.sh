#!/bin/bash

# Konfigurasi S3
S3_BUCKET_NAME="lumi-ai-project"
S3_ENDPOINT_URL="https://is3.cloudhost.id"
S3_REGION="us-east-1"
# S3_ACCESS_KEY dan S3_SECRET_KEY akan diambil dari environment variables

# Nama volume Docker yang akan dibackup
VOLUME_NAME="docker-n8n-lumi-ai_n8n_data"

# Direktori sementara untuk menyimpan backup sebelum diunggah
BACKUP_TEMP_DIR="/tmp/n8n_backup_temp"
# Format nama file backup: n8n_backup_YYYY-MM-DD_HH-MM-SS.tar.gz
BACKUP_FILENAME="n8n_backup_$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
# Path lengkap file backup lokal
LOCAL_BACKUP_PATH="$BACKUP_TEMP_DIR/$BACKUP_FILENAME"

# Path di S3: backup-n8n/DD-MM/
S3_BACKUP_DATE_FOLDER="backup-n8n/$(date +%d-%m)"
S3_DESTINATION_PATH="s3://$S3_BUCKET_NAME/$S3_BACKUP_DATE_FOLDER/$BACKUP_FILENAME"

# Logging
LOG_FILE="/var/log/n8n_backup.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "=============================================="
echo "Memulai proses backup n8n pada $(date)"
echo "=============================================="

# Membuat direktori sementara jika belum ada
mkdir -p $BACKUP_TEMP_DIR
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal membuat direktori sementara $BACKUP_TEMP_DIR. Proses backup dibatalkan."
    exit 1
fi
echo "Direktori sementara $BACKUP_TEMP_DIR telah disiapkan."

# Mendapatkan path absolut dari volume Docker
# Perhatian: Ini berasumsi container 'n8n' sedang berjalan atau setidaknya ada.
# Dan juga berasumsi docker inspect dapat dijalankan oleh user yang menjalankan skrip ini.
# Jika container n8n didefinisikan dengan nama lain di docker-compose.yml, sesuaikan 'n8n_n8n_1' atau 'n8n'
# Coba cari container ID dari nama service 'n8n' di docker compose
CONTAINER_ID=$(docker compose ps -q n8n)
if [ -z "$CONTAINER_ID" ]; then
    echo "ERROR: Container n8n tidak ditemukan melalui 'docker compose ps -q n8n'. Mencoba mencari dengan 'docker ps -q --filter name=n8n'..."
    CONTAINER_ID=$(docker ps -q --filter "name=n8n")
    if [ -z "$CONTAINER_ID" ]; then
        echo "ERROR: Container n8n masih tidak ditemukan. Pastikan container berjalan atau service 'n8n' ada di file konfigurasi compose Anda. Proses backup dibatalkan."
        exit 1
    fi
fi
echo "Container n8n ditemukan dengan ID: $CONTAINER_ID"

VOLUME_PATH=$(docker inspect --format '{{ range .Mounts }}{{ if eq .Name "'"$VOLUME_NAME"'" }}{{ .Source }}{{ end }}{{ end }}' $CONTAINER_ID)

if [ -z "$VOLUME_PATH" ]; then
    echo "ERROR: Tidak dapat menemukan path untuk volume Docker '$VOLUME_NAME'. Pastikan volume terpasang pada container n8n yang sedang berjalan. Proses backup dibatalkan."
    exit 1
fi
echo "Path untuk volume '$VOLUME_NAME' adalah: $VOLUME_PATH"

# Membuat arsip .tar.gz dari volume
echo "Membuat arsip backup dari $VOLUME_PATH ke $LOCAL_BACKUP_PATH..."
tar -czf "$LOCAL_BACKUP_PATH" -C "$VOLUME_PATH" .
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal membuat arsip backup. Periksa izin dan ruang disk. Proses backup dibatalkan."
    # Membersihkan file backup parsial jika ada
    rm -f "$LOCAL_BACKUP_PATH"
    exit 1
fi
echo "Arsip backup berhasil dibuat: $LOCAL_BACKUP_PATH"

# Memeriksa apakah variabel lingkungan untuk kredensial S3 sudah di-set
if [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ]; then
    echo "ERROR: Variabel lingkungan S3_ACCESS_KEY dan/atau S3_SECRET_KEY tidak di-set."
    echo "Harap set variabel tersebut sebelum menjalankan skrip."
    exit 1
fi

# Mengkonfigurasi AWS CLI dengan kredensial dari variabel lingkungan dan endpoint S3
echo "Mengkonfigurasi AWS CLI..."
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY
export AWS_DEFAULT_REGION=$S3_REGION

# Mengunggah file backup ke S3 compatible storage
echo "Mengunggah $BACKUP_FILENAME ke $S3_DESTINATION_PATH..."
aws s3 cp "$LOCAL_BACKUP_PATH" "$S3_DESTINATION_PATH" --endpoint-url "$S3_ENDPOINT_URL"
if [ $? -ne 0 ]; then
    echo "ERROR: Gagal mengunggah backup ke S3 di $S3_ENDPOINT_URL. Periksa konfigurasi AWS CLI, kredensial, dan koneksi jaringan."
    # Jangan hapus file lokal jika upload gagal agar bisa di-retry manual
    exit 1
fi
echo "Backup berhasil diunggah ke S3."

# Menghapus file backup lokal setelah berhasil diunggah
echo "Menghapus file backup lokal: $LOCAL_BACKUP_PATH..."
rm -f "$LOCAL_BACKUP_PATH"
if [ $? -ne 0 ]; then
    echo "WARNING: Gagal menghapus file backup lokal $LOCAL_BACKUP_PATH. Hapus secara manual jika perlu."
fi
echo "File backup lokal telah dihapus."

echo "Proses backup n8n selesai pada $(date)"
echo "=============================================="

exit 0
