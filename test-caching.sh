#!/bin/bash
# Request the same resource twice using the same user but different HTTP connections
# TODO pass request in
# Note:
# curl --output is used so curl takes the processing of the JSON payload into account in its
# timing. Write the payload to a file to not clutter stdout which should only show the timings.
#
# We assume Tomcat runs as PID 1

URL="http://system:System123@localhost:8080/api/organisationUnits?pageSize=2000&fields=:all,!name,!id,!favorites,!translations,!children,!sharing"
TIMING_FORMAT="DNS lookup:\t%{time_namelookup}s\nTCP connect:\t%{time_connect}s\nSSL handshake:\t%{time_appconnect}s\nTransfer start:\t%{time_pretransfer}s\nFirst byte:\t%{time_starttransfer}s\nTotal time:\t%{time_total}s\nSize:\t\t%{size_download} bytes\nSpeed:\t\t%{speed_download} bytes/sec\n"

mkdir --parents ./profiler-output

echo "First request..."
docker compose exec --workdir /profiler-output web sh -c 'asprof start -e cpu -f first.jfr 1'

curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL"

docker compose exec web sh -c 'asprof stop 1'

sleep 1

echo "Second request..."
docker compose exec --workdir /profiler-output web sh -c 'asprof start -e cpu -f second.jfr 1'

curl --silent --output /tmp/dhis2-response.json --write-out "$TIMING_FORMAT" "$URL"

docker compose exec web sh -c 'asprof stop 1'

# Convert to flamegraph and collapsed
docker compose exec --workdir /profiler-output web sh -c "jfrconv first.jfr --title \"First $URL\" first.html"
docker compose exec --workdir /profiler-output web sh -c "jfrconv second.jfr --title \"Second $URL\" second.html"
docker compose exec --workdir /profiler-output web sh -c 'jfrconv first.jfr first.collapsed'
docker compose exec --workdir /profiler-output web sh -c 'jfrconv second.jfr second.collapsed'
docker compose cp web:/profiler-output ./
echo "Flamegraphs saved to ./profiler-output"
