#!/usr/bin/env python3

"""
Telegram Notification Script for Paperless-NGX Backups
Sends backup log to Telegram bot
"""

import sys
import os
import requests
from pathlib import Path
from datetime import datetime

# Configuration file path
SCRIPT_DIR = Path(__file__).parent.absolute()
CONFIG_FILE = SCRIPT_DIR / ".telegram-config"

# Telegram message length limit
MAX_MESSAGE_LENGTH = 4000  # Leave some room for formatting


def load_config():
    """Load Telegram bot token and chat ID from config file."""
    if not CONFIG_FILE.exists():
        print(f"ERROR: Configuration file not found: {CONFIG_FILE}")
        print("Please create .telegram-config with your bot token and chat ID")
        sys.exit(1)

    config = {}
    with open(CONFIG_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config[key.strip()] = value.strip()

    if 'BOT_TOKEN' not in config or 'CHAT_ID' not in config:
        print("ERROR: BOT_TOKEN and CHAT_ID must be set in .telegram-config")
        sys.exit(1)

    return config['BOT_TOKEN'], config['CHAT_ID']


def send_telegram_message(bot_token, chat_id, message):
    """Send a message to Telegram."""
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # Split message if too long
    messages = []
    if len(message) <= MAX_MESSAGE_LENGTH:
        messages.append(message)
    else:
        # Split into chunks
        lines = message.split('\n')
        current_chunk = ""

        for line in lines:
            if len(current_chunk) + len(line) + 1 <= MAX_MESSAGE_LENGTH:
                current_chunk += line + '\n'
            else:
                if current_chunk:
                    messages.append(current_chunk)
                current_chunk = line + '\n'

        if current_chunk:
            messages.append(current_chunk)

    # Send all message chunks
    for i, msg in enumerate(messages):
        if len(messages) > 1:
            prefix = f"📄 Part {i+1}/{len(messages)}\n\n"
            msg = prefix + msg

        payload = {
            'chat_id': chat_id,
            'text': msg,
            'parse_mode': 'HTML'
        }

        try:
            response = requests.post(url, json=payload, timeout=10)
            response.raise_for_status()
        except requests.exceptions.RequestException as e:
            print(f"ERROR: Failed to send Telegram message: {e}")
            return False

    return True


def format_log_for_telegram(log_content, log_file):
    """Format the backup log for Telegram with HTML formatting."""
    # Add header
    header = f"🔔 <b>Paperless-NGX Backup Report</b>\n"
    header += f"📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
    header += f"📋 Log: {os.path.basename(log_file)}\n"
    header += "=" * 40 + "\n\n"

    # Check if backup was successful
    if "Backup Completed Successfully" in log_content:
        header += "✅ <b>Status: SUCCESS</b>\n\n"
    elif "No changes detected" in log_content:
        header += "ℹ️ <b>Status: SKIPPED (No Changes)</b>\n\n"
    else:
        header += "❌ <b>Status: FAILED</b>\n\n"

    # Format log content (escape HTML special characters)
    log_content = log_content.replace('&', '&amp;')
    log_content = log_content.replace('<', '&lt;')
    log_content = log_content.replace('>', '&gt;')

    # Use monospace font for log
    formatted_log = f"<pre>{log_content}</pre>"

    return header + formatted_log


def main():
    """Main function."""
    if len(sys.argv) < 2:
        print("Usage: telegram-notify.py <log_file>")
        sys.exit(1)

    log_file = sys.argv[1]

    if not os.path.exists(log_file):
        print(f"ERROR: Log file not found: {log_file}")
        sys.exit(1)

    # Load configuration
    try:
        bot_token, chat_id = load_config()
    except Exception as e:
        print(f"ERROR: Failed to load configuration: {e}")
        sys.exit(1)

    # Read log file
    try:
        with open(log_file, 'r') as f:
            log_content = f.read()
    except Exception as e:
        print(f"ERROR: Failed to read log file: {e}")
        sys.exit(1)

    # Format and send message
    message = format_log_for_telegram(log_content, log_file)

    if send_telegram_message(bot_token, chat_id, message):
        print("✓ Telegram notification sent successfully")
        sys.exit(0)
    else:
        print("✗ Failed to send Telegram notification")
        sys.exit(1)


if __name__ == "__main__":
    main()
