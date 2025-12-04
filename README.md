# Paperless-NGX Backup System

Automated backup solution for Paperless-NGX with remote storage and Telegram notifications.

## Architecture

- **Source:** Paperless-NGX (Docker) on Linux server
- **Destination:** Raspberry Pi 4 on local network (or any linux mashin with ssh client)
- **Method:** Direct stream from container via tar+ssh
- **Notifications:** Telegram bot with full backup logs
- **Scheduling:** Daily smart backups + monthly full backups

### Communication Flow Diagram

![Backup Flow](http://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/Hexanders/docker_papperless_ngx_installation/main/backup-flow.puml)

*[View PlantUML source](backup-flow.puml)*


## Features

- **Smart Backups:** Only runs when documents change
- **Full Backups:** Monthly full backup regardless of changes
- **No Local Copy:** Streams directly from container to remote (efficient)
- **Telegram Notifications:** Instant notifications with complete logs
- **Automatic Scheduling:** Cron-based automation
- **Log Management:** 30-day log retention

## Prerequisites

**Linux Server:**
- Docker & Docker Compose
- Paperless-NGX running in container
- Python 3 with `requests` library
- SSH client
- Cron

**Raspberry Pi 4:**
- SSH server enabled
- User account with write permissions

**Telegram:**
- Telegram bot token (from @BotFather)
- Your Telegram chat ID

## Installation

### 1. Clone Repository

```bash
cd /path/to/paperless-ngx-data
git clone https://github.com/Hexanders/docker_papperless_ngx_installation.git .
```

### 2. Configure Paperless

Copy template files and customize:

```bash
# Copy Docker Compose configuration
cp docker-compose.yml.template docker-compose.yml
cp docker-compose.env.template docker-compose.env

# Edit with your values
nano docker-compose.yml  # Update paths, domain, IP addresses
nano docker-compose.env   # Update URL, timezone, secret key
```

**Important:** The actual `docker-compose.yml` and `docker-compose.env` files are git-ignored for security.

### 3. Set Up SSH Access

Generate SSH key and copy to Raspberry Pi:

```bash
ssh-keygen -t ed25519
ssh-copy-id your-user@192.168.1.100
```

Test connection:

```bash
ssh your-user@192.168.1.100
```

### 4. Configure Backup Destination

Edit `backup.sh` configuration section with your values:

```bash
BACKUP_METHOD="rsync"
RSYNC_REMOTE_USER="your-remote-user"
RSYNC_REMOTE_HOST="192.168.1.100"
RSYNC_REMOTE_PATH="/path/to/backup/location"
RSYNC_SSH_PORT="22"
```

### 5. Set Up Telegram Notifications

Create `.telegram-config` from template:

```bash
cp .telegram-config.template .telegram-config
nano .telegram-config
```

Add your credentials:

```
BOT_TOKEN=your_bot_token_from_botfather
CHAT_ID=your_telegram_chat_id
```

**Get Bot Token:**
1. Open Telegram → Search `@BotFather`
2. Send `/newbot` and follow instructions
3. Copy the token

**Get Chat ID:**
1. Message your bot
2. Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Find `"chat":{"id":123456789}`

### 6. Install Python Dependencies

```bash
pip3 install requests
```

### 7. Create Backup Directory on Raspberry Pi

```bash
ssh your-user@192.168.1.100 "mkdir -p /path/to/backup/location"
```

## Usage

### Manual Backups

**Full backup:**
```bash
./backup.sh
```

**Smart backup (only if changed):**
```bash
./backup-if-changed.sh
```

### Test Notification

```bash
python3 telegram-notify.py ./logs/backup-*.log
```

## Automation

Automated backups via cron:

```bash
crontab -e
```

Add:

```cron
# Daily smart backup - only if documents changed (2 AM)
0 2 * * * cd /path/to/paperless-ngx-data && ./backup-if-changed.sh >> ./logs/cron.log 2>&1

# Monthly full backup - 1st of each month (3 AM)
0 3 1 * * cd /path/to/paperless-ngx-data && ./backup.sh >> ./logs/cron.log 2>&1
```

## File Structure

```
.
├── backup.sh                    # Main backup script
├── backup-if-changed.sh         # Smart backup (checks for changes)
├── telegram-notify.py           # Telegram notification script
├── .telegram-config             # Telegram credentials (not in git)
├── .telegram-config.template    # Template for credentials
├── docker-compose.yml           # Paperless-NGX configuration
├── docker-compose.env           # Paperless environment variables
├── logs/                        # Backup logs (30-day retention)
├── export/                      # Local export directory (not used)
├── consume/                     # Paperless consume directory
└── README.md                    # This file
```

## How It Works

### Smart Backup Flow

1. Query PostgreSQL for latest document modification time
2. Compare with last backup timestamp
3. If changed:
   - Run document exporter in container
   - Stream export to Raspberry Pi via tar+ssh
   - Update timestamp
   - Send Telegram notification
4. If unchanged:
   - Skip backup
   - Send "no changes" notification

### Full Backup Flow

1. Run document exporter in container (`/usr/src/paperless/export`)
2. Stream export directly to Raspberry Pi via tar+ssh
3. Verify backup size on remote
4. Send Telegram notification with full log

### Notification Content

- Status (✅ Success / ❌ Failure / ℹ️ Skipped)
- Backup size and duration
- Complete backup log
- Timestamp
- Auto-split for long logs (>4000 chars)

## Configuration

### Backup Script Options

Edit `backup.sh` configuration section:

```bash
# Backup method
BACKUP_METHOD="rsync"  # or "rclone", "local-only"

# Document exporter flags
EXPORTER_FLAGS="-d -f -c"
# -d: delete old files
# -f: use filename format
# -c: compare checksums

# Log retention
LOG_RETENTION_DAYS=30
```

### Exporter Flags

- `-c`: Compare checksums (slower, more accurate)
- `-d`: Delete files no longer in export
- `-f`: Use filename format configuration
- `-na`: Exclude archive files
- `-nt`: Exclude thumbnail files
- `-z`: Create zip file

## Troubleshooting

### SSH Connection Issues

```bash
# Remove old host key
ssh-keygen -R 192.168.1.100

# Add new host key
ssh-keyscan -H 192.168.1.100 >> ~/.ssh/known_hosts

# Test connection
ssh your-user@192.168.1.100
```

### Telegram Notifications Not Working

```bash
# Test configuration
python3 telegram-notify.py ./logs/backup-*.log

# Check config file
cat .telegram-config

# Verify bot token
curl -s "https://api.telegram.org/bot<TOKEN>/getMe"
```

### Backup Fails

```bash
# Check logs
tail -f logs/cron.log
ls -lh logs/

# Verify container is running
docker compose ps

# Check export inside container
docker compose exec webserver ls -lh /usr/src/paperless/export/

# Test manual export
docker compose exec -T webserver document_exporter /usr/src/paperless/export -d -f
```

### Cron Not Running

```bash
# Verify crontab
crontab -l

# Check cron logs
tail -f logs/cron.log

# Test script manually
cd /path/to/paperless-ngx-data && ./backup-if-changed.sh
```

## Security

- SSH key-based authentication (no passwords)
- Telegram bot token excluded from git (`.gitignore`)
- Local network only (no internet exposure)
- Read-only database queries for change detection

## Backup Restoration

To restore from backup on Raspberry Pi:

```bash
# Copy backup from Pi to Linux server
scp -r your-user@192.168.1.100:/path/to/backup/location /tmp/restore

# Import into Paperless
docker compose exec -T webserver document_importer /tmp/restore
```

**Note:** Imports must use the same Paperless version as the export.

## Performance

- Export size: ~820MB (226 documents)
- Backup duration: ~42 seconds
- Transfer method: tar+gzip over SSH
- Network: Local gigabit
- Incremental: Only changed files

## License

MIT

## References

- [Paperless-NGX Documentation](https://docs.paperless-ngx.com/administration/#exporter)
- [Telegram Bot API](https://core.telegram.org/bots/api)
