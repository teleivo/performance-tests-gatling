#!/bin/bash
# Get the query plan for analysis

set -u

mkdir plans -p
# relies on https://www.postgresql.org/docs/current/libpq-envars.html to connect to the DB
psql -XqAt -f ./tracker-exporter-tests.sql > plans/"$PLAN_NAME".json
