#!/bin/sh

psql -h localhost -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -XqAt -f ./tracker-exporter-tests.sql
