# Profiling

[docker-compose.profile.yml](docker-compose.profile.yml) adds an async profiler to the base Docker
setup for us to profile our app. Read
[async-profiler](https://github.com/async-profiler/async-profiler) for all the things you are able
to do with it.

Start DHIS2 with profiling enabled

```bash
docker compose -f docker-compose.yml -f docker-compose.profile.yml up
```

## Basic commands

Tomcat which is what we'll profile runs as PID 1 in [docker-compose.yml](docker-compose.yml). You
can for example profile the CPU for a specific amount of time

```bash
docker compose exec web sh -c 'asprof -d 30 -f /profiler-output/cpu.html 1'
```

Or wrap some actions by starting an stopping the profile as done in `./test-caching.sh`.

Results saved to a named Docker volume `profiler-output` which you can copy onto your machine using

```sh
docker compose cp web:/profiler-output ./
```
