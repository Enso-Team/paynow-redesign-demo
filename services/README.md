# Demo bank services

Six Spring Boot 3 services on Java 17, built as one Gradle multi-project. `../CONTRACTS.md` defines the endpoints, events and error codes.

| Module | Port | Job |
|---|---|---|
| auth | 8081 | Device binding, challenge and signature, JWT and refresh tokens |
| account | 8082 | Accounts summary with ETag, internal holds |
| lookup | 8083 | PayNow name lookup, 60 s cache, 30 a minute per user |
| payment | 8084 | PayNow payments, long-poll status, settles from Kafka |
| mock-directory | 8085 | Fake PayNow directory |
| mock-fast | 8086 | Fake FAST, settles `payments.requested` after a delay |
| common | | JWT check, error body, CORS, `/health`, directory client, measured latency filter |

MariaDB 11 and Kafka (KRaft, `localhost:9092`) run in Docker. MariaDB listens on host port 3307 so it stays clear of a local MySQL on 3306. Set `DB_PORT` to change it. All services share the `dbs` database. Each one creates its own tables and seed rows at startup from `schema.sql` and `data.sql`.

## Run

Docker must be running. You need a Java 17 JDK on `PATH` or in `JAVA_HOME`.

Copy `.env.example` to `.env` and set `JWT_SECRET`, `DB_PASSWORD` and `DB_ROOT_PASSWORD`. `scripts/up.sh` and `scripts/down.sh` load `.env` and stop with a message naming any variable that's missing. The services read the same variables, so run them through `up.sh` or export them yourself.

```sh
cp .env.example .env   # then edit the values
scripts/up.sh      # compose up, build, start all six, wait for /health
scripts/e2e.sh     # curl and openssl checks against the running stack
scripts/down.sh    # stop the services and containers (--wipe also deletes the database)
```

Logs and pid files go to `logs/`. `FAST_PROFILE=today scripts/up.sh` starts mock-fast with a 2 s delay, close to what today's banking apps show. The default is 200 ms.

`LATENCY_PROFILE=measured scripts/up.sh` starts every service with the `measured` profile. Each endpoint then waits the time a real banking app spends on it, from `../latency/measured.json` (`latency.table` overrides the path). Run `LATENCY_PROFILE=measured scripts/e2e.sh` against it, so the timing check expects a lookup of at least 500 ms.

`up.sh` builds and starts only the services that aren't already up. A running service keeps its jar and its profile, so run `scripts/down.sh` first to change either.

## Demo login

User `alextan`, OTP `123456`. Register a key with `POST /auth/devices`, then sign the nonce from `/auth/challenge` and send it to `/auth/session`. Auth takes DER signatures and also raw 64-byte r||s signatures, which is what WebCrypto produces.

## Test numbers

- 91234567 resolves to TAN ** **NG (OCBC) and settles.
- 90000001 takes 3 s in the directory, so the lookup returns 504 `DIRECTORY_TIMEOUT`.
- 90000002 resolves, then FAST rejects it with `BENEFICIARY_BANK_REJECTED` and the hold is released.
- 80000000 isn't registered, so lookup returns 404 and payment returns 422 `PROXY_NOT_FOUND`.
