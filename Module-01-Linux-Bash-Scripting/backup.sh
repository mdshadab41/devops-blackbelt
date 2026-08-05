#!/bin/bash
set -e
SOURCE_DIR=~/important-data
BACKUP_DIR=~/backups
DATE=$(date +%Y-%m-%d)

mkdir -p $BACKUP_DIR/backup-$DATE

cp $SOURCE_DIR/* $BACKUP_DIR/backup-$DATE

echo "Backup completed to $BACKUP_DIR"
