#!/bin/bash
set -e
# Request the same resource multiple times using the same user but different HTTP connections
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
# This is to gather more samples in case the second request is considerably faster
ADDITIONAL_REQUESTS=${ADDITIONAL_REQUESTS:=0}

# Parse PROF_ARGS to extract event and thread flags for jfrconv
parse_prof_args() {
  local prof_args="$1"

  # Extract single event after -e flag - fail if not found
  [[ $prof_args =~ -e[[:space:]]+([^[:space:]]+) ]] || return 1
  EVENT_FLAG="${BASH_REMATCH[1]}"

  # Check for threads flag
  if [[ $prof_args =~ -t|--threads ]]; then
    THREAD_FLAG="threads"
  else
    THREAD_FLAG=""
  fi
}

parse_prof_args "$PROF_ARGS"

echo "Profiling requests to $API"

rotate_sql_logs() {
  # Remove existing and create a new PostgreSQL log without having to restart Postgres
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

print_curl_timings() {
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

make_http_request() {
  local request_id
  request_id=$(uuidgen | tr -d '\n')
  curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" \
    --header "X-Request-ID: $request_id" \
    "$URL"
}

print_http_timings() {
  local timing_output="$1"
  print_curl_timings "$timing_output"
}

get_http_total_time() {
  local timing_output="$1"
  echo "$timing_output" | cut -d',' -f6
}

mkdir --parents ./profiler-output

echo "First request..."
rotate_sql_logs
# Start profiling
docker compose exec --workdir /profiler-output web sh -c "asprof start $PROF_ARGS -f first-${EVENT_FLAG}.jfr 1" > /dev/null

FIRST_TIMING=$(make_http_request)
print_http_timings "$FIRST_TIMING"
FIRST_TOTAL_TIME=$(get_http_total_time "$FIRST_TIMING")

docker compose exec web sh -c 'asprof stop 1' > /dev/null

docker compose cp db:/var/lib/postgresql/data/log/postgresql.log "./profiler-output/first-${EVENT_FLAG}.log"
print_cache_metrics

sleep 1

echo
echo "Second request..."
rotate_sql_logs
# Start profiling
docker compose exec --workdir /profiler-output web sh -c "asprof start $PROF_ARGS -f second-${EVENT_FLAG}.jfr 1" > /dev/null

SECOND_TIMING=$(make_http_request)
print_http_timings "$SECOND_TIMING"
SECOND_TOTAL_TIME=$(get_http_total_time "$SECOND_TIMING")

if (( ADDITIONAL_REQUESTS > 0 )); then
  echo
  echo "Making $ADDITIONAL_REQUESTS additional requests to balance profiling samples..."
  for i in $(seq 1 "$ADDITIONAL_REQUESTS"); do
      echo "Additional request $i/$ADDITIONAL_REQUESTS..."
      TIMING=$(make_http_request)
      print_http_timings "$TIMING"
  done
fi

docker compose exec web sh -c 'asprof stop 1' > /dev/null

docker compose cp db:/var/lib/postgresql/data/log/postgresql.log "./profiler-output/second-${EVENT_FLAG}.log"
print_cache_metrics

echo
echo "Post processing:"

# Build jfrconv flags
JFRCONV_FLAGS="--${EVENT_FLAG}"
if [[ -n "$THREAD_FLAG" ]]; then
  JFRCONV_FLAGS="$JFRCONV_FLAGS --${THREAD_FLAG}"
fi
# Add --total for allocation and lock events
if [[ "$EVENT_FLAG" == "alloc" || "$EVENT_FLAG" == "lock" ]]; then
  JFRCONV_FLAGS="$JFRCONV_FLAGS --total"
fi

# Convert to flamegraph and collapsed
docker compose exec --workdir /profiler-output web \
  sh -c "jfrconv $JFRCONV_FLAGS first-${EVENT_FLAG}.jfr --title \"First $API took $FIRST_TOTAL_TIME (async-prof $PROF_ARGS)\" first-${EVENT_FLAG}.html"
docker compose exec --workdir /profiler-output web \
  sh -c "jfrconv $JFRCONV_FLAGS second-${EVENT_FLAG}.jfr --title \"Second $API took $SECOND_TOTAL_TIME (async-prof $PROF_ARGS)\" second-${EVENT_FLAG}.html"
docker compose exec --workdir /profiler-output web \
  sh -c "jfrconv $JFRCONV_FLAGS first-${EVENT_FLAG}.jfr first-${EVENT_FLAG}.collapsed"
docker compose exec --workdir /profiler-output web \
  sh -c "jfrconv $JFRCONV_FLAGS second-${EVENT_FLAG}.jfr second-${EVENT_FLAG}.collapsed"
docker compose cp web:/profiler-output ./
process_sql_logs "first-${EVENT_FLAG}"
process_sql_logs "second-${EVENT_FLAG}"
echo "Flamegraphs and PostgreSQL logs saved to ./profiler-output"
