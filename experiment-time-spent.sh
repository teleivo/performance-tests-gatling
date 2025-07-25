#!/bin/bash
set -e

cleanup() {
  echo ""
  echo "CTRL+C pressed, cleaning up..."
  docker compose -f docker-compose.yml -f docker-compose.profile.yml down --volumes
  trap - INT
  kill -INT "$$"
}

trap cleanup INT

DHIS2_IMAGES=(
  "dhis2/core:42.0"
  # "dhis2/core-dev:42.0-local-no-ehcache-no-system-cache"
  "dhis2/core-dev:42.0-local-fieldfiltering-better"
)

PROF_ARGS=${PROF_ARGS:="-e cpu"}
TEST=${TEST:="OrganisationUnitsTest"}
TEST_ARGS=${TEST_ARGS:="-DpageSize=50"}

parse_prof_args() {
  local prof_args="$1"

  [[ $prof_args =~ -e[[:space:]]+([^[:space:]]+) ]] || return 1
  EVENT_FLAG="${BASH_REMATCH[1]}"

  if [[ $prof_args =~ -t|--threads ]]; then
    THREAD_FLAG="threads"
  else
    THREAD_FLAG=""
  fi
}

parse_prof_args "$PROF_ARGS"

rotate_sql_logs() {
  docker compose exec db rm -f /var/lib/postgresql/data/log/postgresql.log
  docker compose exec db psql \
    --username=dhis --dbname=dhis --set=application_name=log_rotator \
    --quiet --output=/dev/null --command="SELECT pg_rotate_logfile();"
}

wait_for_health() {
  echo "Waiting for DHIS2 to start..."
  local start_time
  start_time=$(date +%s)

  while ! docker compose ps web | grep -q "healthy"; do
    sleep 10
    echo "Still waiting..."
    if [ $(($(date +%s) - start_time)) -gt 600 ]; then
      echo "Timeout waiting for DHIS2 to start"
      exit 1
    fi
  done
  echo "DHIS2 is ready!"
}

save_profiler_data() {
  local image_name="$1"
  local gatling_dir="$2"

  echo "Saving profiler data for $image_name..."

  docker compose cp web:/profiler-output/. "$gatling_dir/"
  docker compose cp db:/var/lib/postgresql/data/log/postgresql.log "$gatling_dir/postgresql.log"

  echo "Profiler data saved to $gatling_dir"
}

post_process_profiler_data() {
  local image_name="$1"
  local gatling_dir="$2"

  echo "Post-processing profiler data for $image_name..."

  local jfrconv_flags="--${EVENT_FLAG}"
  if [[ -n "$THREAD_FLAG" ]]; then
    jfrconv_flags="$jfrconv_flags --${THREAD_FLAG}"
  fi
  if [[ "$EVENT_FLAG" == "alloc" || "$EVENT_FLAG" == "lock" ]]; then
    jfrconv_flags="$jfrconv_flags --total"
  fi

  local title="$TEST on $image_name (async-profiler $PROF_ARGS)"
  # generate flamegraph and collapsed stack traces using jfrconv from async-profiler
  docker compose exec --workdir /profiler-output web \
    sh -c "jfrconv $jfrconv_flags --dot --title \"$title\" profile.jfr profile.html"
  docker compose exec --workdir /profiler-output web \
    sh -c "jfrconv $jfrconv_flags --dot profile.jfr profile.collapsed"

  docker compose cp web:/profiler-output/. "$gatling_dir/"

  pgbadger \
    --title "$TEST on $image_name (async-profiler $PROF_ARGS)" \
    --prefix '%t [%p]: user=%u,db=%d,app=%a ' \
    --dbname dhis \
    --outfile "$gatling_dir/pgbadger.html" "$gatling_dir/postgresql.log"

  echo "Post-processing complete. Files saved to $gatling_dir"
}

mvn clean

echo "Starting experiment across ${#DHIS2_IMAGES[@]} DHIS2 images..."

for image in "${DHIS2_IMAGES[@]}"; do
  echo
  echo "Testing with image: $image"

  docker compose -f docker-compose.yml -f docker-compose.profile.yml down --volumes

  DHIS2_IMAGE="$image" \
    docker compose -f docker-compose.yml -f docker-compose.profile.yml up --detach

  wait_for_health

  docker compose exec db psql -U dhis -c 'VACUUM;'

  rotate_sql_logs

  docker compose exec --workdir /profiler-output web sh -c "asprof start $PROF_ARGS -f profile.jfr 1" > /dev/null

  echo "Running $TEST..."
  mvn gatling:test \
    -Dgatling.simulationClass="org.hisp.dhis.test.$TEST" \
    $TEST_ARGS

  echo "Stopping profiler..."
  docker compose exec web sh -c 'asprof stop 1' > /dev/null

  if [ -f target/gatling/lastRun.txt ]; then
    gatling_run_dir="target/gatling/$(cat target/gatling/lastRun.txt)"
    echo "Gatling results in: $gatling_run_dir"

    save_profiler_data "$image" "$gatling_run_dir"
    post_process_profiler_data "$image" "$gatling_run_dir"
  else
    echo "Warning: target/gatling/lastRun.txt not found, cannot save profiler data"
  fi

  echo "Completed test for $image"
done

docker compose -f docker-compose.yml -f docker-compose.profile.yml down --volumes
# convert Gatlings' binary simulation.log to simulation.csv
glog --config ./src/test/resources/gatling.conf --scan-subdirs target/gatling

