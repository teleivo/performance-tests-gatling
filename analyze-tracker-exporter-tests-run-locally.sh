#!/bin/bash
# Pre-process and generate reports for local runs in target/gatling

RUN=${RUN:=$(cat target/gatling/lastRun.txt)}

# extract raw Gatling data from binary simulation.log
glog \
  --config ../performance-tests-gatling/src/test/resources/gatling.conf \
  --scan-subdirs target/gatling

RUN_LOG="target/gatling/$RUN/simulation.csv"

# Extract first start_timestamp and last end_timestamp for record_type request
BEGIN_TIMESTAMP=$(awk --field-separator=',' '$1=="request" && $6!="" {print $6}' "$RUN_LOG" | sort --numeric-sort | head --lines=1)
END_TIMESTAMP=$(awk --field-separator=',' '$1=="request" && $7!="" {print $7}' "$RUN_LOG" | sort --numeric-sort | tail --lines=1)

# Convert timestamps from milliseconds to date format for pgbadger (in UTC as thats also configured
# in ./docker/test-performance-dhis2-org-postgresql.conf)
BEGIN_TIME=$(date --utc --date="@$((BEGIN_TIMESTAMP / 1000))" "+%Y-%m-%d %H:%M:%S")
END_TIME=$(date --utc --date="@$((END_TIMESTAMP / 1000))" "+%Y-%m-%d %H:%M:%S")

# TODO are there timing differences between the containers/apps so that pgbadger does not always
# show 200 event queries?
echo "Analyzing run $RUN which had its first request start at $BEGIN_TIME and last request end at $END_TIME"

docker compose cp db:/var/lib/postgresql/data/log/postgresql.log .
pgbadger \
  --title "$RUN" \
  --prefix '%t [%p]: user=%u,db=%d,app=%a ' \
  --exclude-query '^(select version|select pg_database_size)' \
  --begin "$BEGIN_TIME" \
  --end "$END_TIME" \
  --outfile pgbadger.html postgresql.log
open pgbadger.html

gstat --plot scatter "target/gatling/$RUN"
open "target/gatling/$RUN/index.html"
