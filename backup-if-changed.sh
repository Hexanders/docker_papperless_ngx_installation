#!/bin/bash

################################################################################
# Paperless-NGX Smart Backup Script
# Only runs backup if documents have changed since last backup
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_BACKUP_FILE="${SCRIPT_DIR}/.last_backup_timestamp"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/smart-backup-$(date +%Y%m%d-%H%M%S).log"

# Create log directory
mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Get the latest document modification time from paperless
get_latest_doc_time() {
    # Query the database for the latest modified/created document
    docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T db psql -U paperless -d paperless -t -c \
        "SELECT COALESCE(MAX(GREATEST(added, modified)), '1970-01-01') FROM documents_document;" 2>/dev/null | tr -d ' '
}

# Get the last backup timestamp
get_last_backup_time() {
    if [ -f "$LAST_BACKUP_FILE" ]; then
        cat "$LAST_BACKUP_FILE"
    else
        echo "1970-01-01"
    fi
}

# Main logic
main() {
    log "=========================================="
    log "Smart Backup Check Started"
    log "=========================================="

    # Get timestamps
    local latest_doc_time=$(get_latest_doc_time)
    local last_backup_time=$(get_last_backup_time)

    log "Latest document change: ${latest_doc_time}"
    log "Last backup: ${last_backup_time}"

    # Compare timestamps
    if [[ "$latest_doc_time" > "$last_backup_time" ]]; then
        log "Changes detected! Running backup..."

        # Run the backup
        if "${SCRIPT_DIR}/backup.sh"; then
            # Update last backup timestamp
            echo "$latest_doc_time" > "$LAST_BACKUP_FILE"
            log "Backup completed successfully"
        else
            log "ERROR: Backup failed!"
            exit 1
        fi
    else
        log "No changes detected. Skipping backup."
    fi

    log "=========================================="
    log "Smart Backup Check Completed"
    log "=========================================="

    # Send Telegram notification
    if [ -f "${SCRIPT_DIR}/telegram-notify.py" ] && [ -f "${SCRIPT_DIR}/.telegram-config" ]; then
        log "Sending Telegram notification..."
        python3 "${SCRIPT_DIR}/telegram-notify.py" "${LOG_FILE}" || log "WARNING: Failed to send Telegram notification"
    fi
}

main "$@"
