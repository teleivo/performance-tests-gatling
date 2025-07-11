#!/bin/bash
# Run tests locally once (assuming against Docker) and pre-process local runs in target/gatling

mvn gatling:test -Dgatling.simulationClass=org.hisp.dhis.test.TrackerExporterTests

glog --config ../performance-tests-gatling/src/test/resources/gatling.conf --scan-subdirs target/gatling
# TODO: automate pgbadger log report: should this script also run tests that would make it easier
# how to get time of test run :joy: the time settings in the db container are off
# pgbadger --prefix '%t [%p]: user=%u,db=%d,app=%a ' \
#   --exclude-query '^(select version|select pg_database_size)' --begin "2025-07-11 04:39:15" --outfile pgbadger.html postgresql.log

gstat --plot scatter "target/gatling/$(cat target/gatling/lastRun.txt)"
open "target/gatling/$(cat target/gatling/lastRun.txt)/index.html"
