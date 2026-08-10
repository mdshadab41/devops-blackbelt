#!/bin/bash
set -e

BACKUP_SRC=/home/ubuntu/important-data
BACKUP_DST=/home/ubuntu/backups/interview
mkdir -p $BACKUP_DST

echo "Starting backup..."

file_count=$(ls $BACKUP_SRC | wc -l)

if [ $file_count = 0 ]
then
    echo "No files to back up"
    exit 1
fi

for file in $BACKUP_SRC/*
do
    cp $file $BACKUP_DST
done

echo "Backup complete. $file_count files backed up."
