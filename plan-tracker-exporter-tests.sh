#!/bin/sh
# Get the query plan for analysis

mkdir plans
# relies on https://www.postgresql.org/docs/current/libpq-envars.html to connect to the DB
psql -XqAt -f ./tracker-exporter-tests.sql > plans/"$PLAN_NAME".json
