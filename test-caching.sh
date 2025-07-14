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

print_timing() {
    local timing_output="$1"
    IFS=',' read -ra TIMING_ARRAY <<< "$timing_output"

    local LABELS=("DNS lookup" "TCP connect" "SSL handshake" "Transfer start" "First byte" "Total time" "Size" "Speed")
    local UNITS=("s" "s" "s" "s" "s" "s" " bytes" " bytes/sec")

    for i in "${!TIMING_ARRAY[@]}"; do
        echo "${LABELS[$i]}: ${TIMING_ARRAY[$i]}${UNITS[$i]}"
    done
}

mkdir --parents ./profiler-output

echo "First request..."
docker compose exec --workdir /profiler-output web sh -c 'asprof start -e cpu -f first.jfr 1' > /dev/null

TIMING_OUTPUT=$(curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL")
FIRST_TOTAL_TIME=$(echo "$TIMING_OUTPUT" | cut -d',' -f6)
echo
print_timing "$TIMING_OUTPUT"

docker compose exec web sh -c 'asprof stop 1' > /dev/null

sleep 1

echo
echo "Second request..."
docker compose exec --workdir /profiler-output web sh -c 'asprof start -e cpu -f second.jfr 1' > /dev/null

TIMING_OUTPUT=$(curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL")
SECOND_TOTAL_TIME=$(echo "$TIMING_OUTPUT" | cut -d',' -f6)
echo
print_timing "$TIMING_OUTPUT"

docker compose exec web sh -c 'asprof stop 1' > /dev/null

echo
# Convert to flamegraph and collapsed
docker compose exec --workdir /profiler-output web sh -c "jfrconv first.jfr --title \"First $API took $FIRST_TOTAL_TIME\" first.html"
docker compose exec --workdir /profiler-output web sh -c "jfrconv second.jfr --title \"Second $API took $SECOND_TOTAL_TIME\" second.html"
docker compose exec --workdir /profiler-output web sh -c 'jfrconv first.jfr first.collapsed'
docker compose exec --workdir /profiler-output web sh -c 'jfrconv second.jfr second.collapsed'
docker compose cp web:/profiler-output ./
echo "Flamegraphs saved to ./profiler-output"
