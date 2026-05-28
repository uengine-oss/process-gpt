#!/bin/sh
# Upload the two seed storage objects used by the PIFC suite:
#   pifc/completed.txt — referenced by proc_inst_source, must be deleted
#   pifc/keep.txt      — unreferenced control file, must survive
#
# Runs as a one-shot container after db-seed-pifc and after the storage
# container is healthy. Idempotent: upserts with `upsert: true` header.

set -eu

: "${STORAGE_URL:=http://kong:8000/storage/v1}"
: "${SERVICE_KEY:?SERVICE_KEY env var is required}"
BUCKET="files"

echo "[pifc-storage-seed] uploading pifc/completed.txt to ${STORAGE_URL}"
printf "pifc-completed-content" > /tmp/completed.txt
curl --silent --show-error --fail-with-body -X POST \
  -H "Authorization: Bearer ${SERVICE_KEY}" \
  -H "apikey: ${SERVICE_KEY}" \
  -H "Content-Type: text/plain" \
  -H "x-upsert: true" \
  --data-binary @/tmp/completed.txt \
  "${STORAGE_URL}/object/${BUCKET}/pifc/completed.txt"
echo

echo "[pifc-storage-seed] uploading pifc/keep.txt"
printf "pifc-keep-content" > /tmp/keep.txt
curl --silent --show-error --fail-with-body -X POST \
  -H "Authorization: Bearer ${SERVICE_KEY}" \
  -H "apikey: ${SERVICE_KEY}" \
  -H "Content-Type: text/plain" \
  -H "x-upsert: true" \
  --data-binary @/tmp/keep.txt \
  "${STORAGE_URL}/object/${BUCKET}/pifc/keep.txt"
echo

echo "[pifc-storage-seed] verifying upload via public GET"
curl --silent --show-error --fail-with-body \
  "${STORAGE_URL}/object/public/${BUCKET}/pifc/completed.txt"
echo
curl --silent --show-error --fail-with-body \
  "${STORAGE_URL}/object/public/${BUCKET}/pifc/keep.txt"
echo

echo "[pifc-storage-seed] done"
