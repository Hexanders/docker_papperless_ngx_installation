#!/bin/bash

################################################################################
# Paperless-NGX Backup Script
# Description: Exports paperless documents and syncs to remote location
# Usage: ./backup.sh
################################################################################

set -euo pipefail

# ==============================================================================
# CONFIGURATION - Modify these variables according to your setup
# ==============================================================================

# Backup method: "rsync", "rclone", or "local-only"
BACKUP_METHOD="rsync"

# rsync configuration (if using rsync)
# Replace with your values:
RSYNC_REMOTE_USER="your-remote-user"
RSYNC_REMOTE_HOST="192.168.1.100"
RSYNC_REMOTE_PATH="/path/to/backup/location"
RSYNC_SSH_PORT="22"

# rclone configuration (if using rclone)
RCLONE_REMOTE="remote:paperless-backup"

# Local paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="${SCRIPT_DIR}/export"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d-%H%M%S).log"

# Document exporter options
EXPORTER_FLAGS="-d -f -c"  # -d: delete old files, -f: use filename format
# Add other flags as needed:
# -na: exclude archive files
# -nt: exclude thumbnail files
# -z: create zip file
# -c: compare checksums (slower but more accurate)

# Keep logs for N days
LOG_RETENTION_DAYS=30

# ==============================================================================
# FUNCTIONS
# ==============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

cleanup_old_logs() {
    log "Cleaning up logs older than ${LOG_RETENTION_DAYS} days..."
    find "$LOG_DIR" -name "backup-*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
}

check_dependencies() {
    if [ "$BACKUP_METHOD" = "rsync" ]; then
        if ! command -v rsync &> /dev/null; then
            error "rsync is not installed. Install it with: sudo apt-get install rsync"
            exit 1
        fi
    elif [ "$BACKUP_METHOD" = "rclone" ]; then
        if ! command -v rclone &> /dev/null; then
            error "rclone is not installed. Install it from: https://rclone.org/install/"
            exit 1
        fi
    fi
}

run_export() {
    log "Starting document export..."
    log "Export directory (in container): /usr/src/paperless/export"
    log "Exporter flags: ${EXPORTER_FLAGS}"

    if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T webserver document_exporter /usr/src/paperless/export ${EXPORTER_FLAGS}; then
        error "Document export failed!"
        return 1
    fi

    log "Document export completed successfully"

    # Get export size from inside container
    local export_size=$(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T webserver du -sh /usr/src/paperless/export 2>/dev/null | awk '{print $1}')
    log "Export size: ${export_size}"
}

sync_rsync() {
    log "Syncing to remote server via tar+ssh..."
    log "Remote: ${RSYNC_REMOTE_USER}@${RSYNC_REMOTE_HOST}:${RSYNC_REMOTE_PATH}"

    # Get container ID
    local container_id=$(docker compose -f "${SCRIPT_DIR}/docker-compose.yml" ps -q webserver)

    if [ -z "$container_id" ]; then
        error "Could not find webserver container"
        return 1
    fi

    # Clear remote directory first
    log "Clearing remote backup directory..."
    if ! ssh -p "${RSYNC_SSH_PORT}" "${RSYNC_REMOTE_USER}@${RSYNC_REMOTE_HOST}" "rm -rf ${RSYNC_REMOTE_PATH}/* 2>/dev/null || true"; then
        error "Failed to clear remote directory"
        return 1
    fi

    # Stream export from container to remote Pi using tar+ssh
    log "Streaming export to remote server..."
    if ! docker compose -f "${SCRIPT_DIR}/docker-compose.yml" exec -T webserver tar -czf - -C /usr/src/paperless/export . | \
         ssh -p "${RSYNC_SSH_PORT}" "${RSYNC_REMOTE_USER}@${RSYNC_REMOTE_HOST}" "cd ${RSYNC_REMOTE_PATH} && tar -xzf -"; then
        error "Sync failed!"
        return 1
    fi

    log "Sync completed successfully"

    # Verify remote backup size
    local remote_size=$(ssh -p "${RSYNC_SSH_PORT}" "${RSYNC_REMOTE_USER}@${RSYNC_REMOTE_HOST}" "du -sh ${RSYNC_REMOTE_PATH} 2>/dev/null | awk '{print \$1}'")
    log "Remote backup size: ${remote_size}"
}

sync_rclone() {
    log "Syncing to remote via rclone..."
    log "Remote: ${RCLONE_REMOTE}"

    if ! rclone sync "${EXPORT_DIR}/" "${RCLONE_REMOTE}/" --progress; then
        error "rclone failed!"
        return 1
    fi

    log "rclone completed successfully"
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"

    log "=========================================="
    log "Paperless-NGX Backup Started"
    log "=========================================="
    log "Backup method: ${BACKUP_METHOD}"

    # Check dependencies
    check_dependencies

    # Run document export
    if ! run_export; then
        error "Backup failed during export phase"
        exit 1
    fi

    # Sync to remote based on method
    case "$BACKUP_METHOD" in
        rsync)
            if ! sync_rsync; then
                error "Backup failed during rsync phase"
                exit 1
            fi
            ;;
        rclone)
            if ! sync_rclone; then
                error "Backup failed during rclone phase"
                exit 1
            fi
            ;;
        local-only)
            log "Local-only backup, skipping remote sync"
            ;;
        *)
            error "Invalid BACKUP_METHOD: ${BACKUP_METHOD}"
            exit 1
            ;;
    esac

    # Cleanup old logs
    cleanup_old_logs

    log "=========================================="
    log "Backup Completed Successfully"
    log "=========================================="

    # Send Telegram notification
    if [ -f "${SCRIPT_DIR}/telegram-notify.py" ] && [ -f "${SCRIPT_DIR}/.telegram-config" ]; then
        log "Sending Telegram notification..."
        python3 "${SCRIPT_DIR}/telegram-notify.py" "${LOG_FILE}" || log "WARNING: Failed to send Telegram notification"
    fi
}

# Run main function
main "$@"
