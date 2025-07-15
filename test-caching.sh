#!/bin/bash
# Request the same resource twice using the same user but different HTTP connections
#
# Note:
# curl --output is used so curl takes the processing of the JSON payload into account in its
# timing. Write the payload to a file to not clutter stdout which should only show the timings.
#
# We assume Tomcat runs as PID 1

BASE_URL="http://system:System123@localhost:8080/api"
API=${API:="/organisationUnits?pageSize=2000&fields=:all,!name,!id,!favorites,!translations,!children,!sharing"}
URL="$BASE_URL$API"
TIMING_FORMAT="%{time_namelookup},%{time_connect},%{time_appconnect},%{time_pretransfer},%{time_starttransfer},%{time_total},%{size_download},%{speed_download}"
PROF_ARGS=${PROF_ARGS:="-e cpu"}

echo "Profiling requests to $API"

rotate_sql_logs() {
  # Remove existing and create a new PostgreSQL log
  docker compose exec db rm /var/lib/postgresql/data/log/postgresql.log
  docker compose exec db psql \
    --username=dhis --dbname=dhis --set=application_name=log_rotator \
    --quiet --output=/dev/null --command="SELECT pg_rotate_logfile();"
}

process_sql_logs() {
  local name="$1"
  pgbadger \
    --title "$name" \
    --prefix '%t [%p]: user=%u,db=%d,app=%a ' \
    --dbname dhis \
    --outfile "./profiler-output/${name}-sql.html" "./profiler-output/${name}.log"
}

print_timing() {
    local timing_output="$1"
    IFS=',' read -ra TIMING_ARRAY <<< "$timing_output"

    local LABELS=("DNS lookup" "TCP connect" "SSL handshake" "Transfer start" "First byte" "Total time" "Size" "Speed")
    local UNITS=("s" "s" "s" "s" "s" "s" " bytes" " bytes/sec")

    echo
    echo "HTTP timings:"
    for i in "${!TIMING_ARRAY[@]}"; do
        echo "${LABELS[$i]}: ${TIMING_ARRAY[$i]}${UNITS[$i]}"
    done
}

print_cache_metrics() {
  # Extract resource name from API path and make it singular
  local resource_name
  resource_name=$(echo "$API" | sed 's/.*\/\([^?]*\).*/\1/' | sed 's/s$//')

  echo
  echo "Cache metrics:"
  curl --silent --user admin:district --header 'accept: text/plain' \
    "$BASE_URL/metrics" | grep --ignore-case "$resource_name\""
}

mkdir --parents ./profiler-output

echo "First request..."
rotate_sql_logs
# Start profiling
docker compose exec --workdir /profiler-output web sh -c "asprof start $PROF_ARGS -f first.jfr 1" > /dev/null

TIMING_OUTPUT=$(curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL")
FIRST_TOTAL_TIME=$(echo "$TIMING_OUTPUT" | cut -d',' -f6)
print_timing "$TIMING_OUTPUT"

docker compose exec web sh -c 'asprof stop 1' > /dev/null

docker compose cp db:/var/lib/postgresql/data/log/postgresql.log ./profiler-output/first.log
print_cache_metrics

sleep 1

echo
echo "Second request..."
rotate_sql_logs
# Start profiling
docker compose exec --workdir /profiler-output web sh -c "asprof start $PROF_ARGS -f second.jfr 1" > /dev/null

TIMING_OUTPUT=$(curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL")
SECOND_TOTAL_TIME=$(echo "$TIMING_OUTPUT" | cut -d',' -f6)
print_timing "$TIMING_OUTPUT"

docker compose exec web sh -c 'asprof stop 1' > /dev/null

docker compose cp db:/var/lib/postgresql/data/log/postgresql.log ./profiler-output/second.log
print_cache_metrics

echo
# Convert to flamegraph and collapsed
docker compose exec --workdir /profiler-output web sh -c "jfrconv first.jfr --title \"First $API took $FIRST_TOTAL_TIME\" first.html"
docker compose exec --workdir /profiler-output web sh -c "jfrconv second.jfr --title \"Second $API took $SECOND_TOTAL_TIME\" second.html"
docker compose exec --workdir /profiler-output web sh -c 'jfrconv first.jfr first.collapsed'
docker compose exec --workdir /profiler-output web sh -c 'jfrconv second.jfr second.collapsed'
docker compose cp web:/profiler-output ./
process_sql_logs "first"
process_sql_logs "second"
echo "Flamegraphs and PostgreSQL logs saved to ./profiler-output"
