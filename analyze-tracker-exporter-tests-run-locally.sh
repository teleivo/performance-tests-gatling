#!/bin/bash
# Pre-process and generate reports for local runs in target/gatling

# Parse command line arguments
SQL_FLAG=false
GATLING_FLAG=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --sql)
      SQL_FLAG=true
      shift
      ;;
    --gatling)
      GATLING_FLAG=true
      shift
      ;;
    --all)
      SQL_FLAG=true
      GATLING_FLAG=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--sql] [--gatling] [--all]"
      exit 1
      ;;
  esac
done

RUN=${RUN:=$(cat target/gatling/lastRun.txt)}

# extract raw Gatling data from binary simulation.log
glog \
  --config ../performance-tests-gatling/src/test/resources/gatling.conf \
  --scan-subdirs target/gatling

RUN_LOG="target/gatling/$RUN/simulation.csv"

# Extract first start_timestamp and last end_timestamp for record_type request
# Note: CSV contains quoted request names with commas which breaks normal field parsing
# Use sed to extract timestamps after the ,OK, pattern
BEGIN_TIMESTAMP=$(grep '^request,.*,OK,' "$RUN_LOG" | sed 's/.*,OK,\([0-9]\+\),.*/\1/' | sort -n | head -1)
END_TIMESTAMP=$(grep '^request,.*,OK,' "$RUN_LOG" | sed 's/.*,OK,[0-9]\+,\([0-9]\+\),.*/\1/' | sort -n | tail -1)

# Convert timestamps from milliseconds to date format for pgbadger (in UTC as thats also configured
# in ./docker/test-performance-dhis2-org-postgresql.conf)
BEGIN_TIME=$(date --utc --date="@$((BEGIN_TIMESTAMP / 1000))" "+%Y-%m-%d %H:%M:%S")
END_TIME=$(date --utc --date="@$((END_TIMESTAMP / 1000))" "+%Y-%m-%d %H:%M:%S")

# TODO are there timing differences between the containers/apps so that pgbadger does not always
# show 200 event queries?
echo "Analyzing run $RUN which had its first request start at $BEGIN_TIME and last request end at $END_TIME"

if [[ $SQL_FLAG = true ]]; then
  docker compose cp db:/var/lib/postgresql/data/log/postgresql.log .
  pgbadger \
    --title "$RUN" \
    --prefix '%t [%p]: user=%u,db=%d,app=%a ' \
    --exclude-query '^(select version|select pg_database_size)' \
    --begin "$BEGIN_TIME" \
    --end "$END_TIME" \
    --outfile pgbadger.html postgresql.log
  open pgbadger.html
fi

gstat --plot scatter "target/gatling/$RUN"

if [[ $GATLING_FLAG = true ]]; then
  open "target/gatling/$RUN/index.html"
fi
