# Diárias — controle e fechamento

Controle de diárias de prestadoras: marcar quem trabalhou em cada dia, fechar o
mês por prestadora e registrar o pagamento.

Built from the Claude Design project **"App de controle de prestadoras"**
(`Diarias App.dc.html`), using the **Acesso+** design system for tokens.

- **App** — Flutter (iOS, Android, macOS, Web)
- **API** — Go 1.26, standard-library HTTP + `pgx/v5`
- **Database** — PostgreSQL 16

```
.
├── app/                  Flutter client
│   ├── lib/theme/        Acesso+ tokens ported to Dart
│   ├── lib/screens/      Calendário · Fechamento · Prestadoras
│   ├── lib/widgets/      DS components, day sheet, share dialog, toast
│   ├── lib/api/          HTTP client for the Go API
│   └── lib/state/        AppState (ChangeNotifier)
├── backend/
│   ├── cmd/api/          entrypoint
│   ├── internal/         config · db · domain · store · httpapi
│   └── migrations/       embedded SQL, applied on boot
└── docker-compose.yml    Postgres (+ optional API container)
```

## Running it locally

Copy `.env.example` to `.env` first — `POSTGRES_PASSWORD` is required and
compose refuses to start without it.

**1. Postgres** — the dev override republishes it on `127.0.0.1:5433` so the API
can be run from source. The production file publishes no host port at all.

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d db
```

**2. API** — migrations run automatically on boot.

```bash
cd backend && go run ./cmd/api
```

**3. An account** — there is no signup endpoint; accounts are created here.

```bash
cd backend && go run ./cmd/api user add felipe
```

**4. App**

```bash
cd app && flutter run
```

The client defaults to `http://localhost:8080` (`http://10.0.2.2:8080` on the
Android emulator). Point it elsewhere with:

```bash
flutter run --dart-define=DIARIAS_API_URL=http://192.168.0.10:8080
```

### Running on this Mac and on a phone on the same LAN

The API already listens on all interfaces, so one address works for both: the
Mac reaches its own LAN IP fine. [`app/config/lan.json`](app/config/lan.json)
holds it so it isn't retyped:

```bash
cd app && flutter run -d macos --dart-define-from-file=config/lan.json
```

```bash
cd app && flutter run -d <device-id> --dart-define-from-file=config/lan.json
```

`adb devices` lists the ids; `flutter devices` shows the models next to them.

**⚠️ This Mac uses DHCP** — the address in `lan.json` is the current lease
(`192.168.10.26`, 24h), not a static IP. If it changes, update `lan.json` **and**
`android/app/src/main/res/xml/network_security_config.xml`. A DHCP reservation on
the router (192.168.10.1) avoids the problem; `MacBook-Pro-de-Felipe.local` is
already whitelisted if you prefer the Bonjour name.

None of the platform network permissions come enabled by default in Flutter —
all four are configured here:

| Platform | What was needed and why |
| --- | --- |
| macOS | `com.apple.security.network.client` in **both** `DebugProfile.entitlements` and `Release.entitlements`. The app is sandboxed and Flutter's template omits this, so requests fail as "operation not permitted". |
| iOS | `NSAppTransportSecurity → NSAllowsLocalNetworking` (cleartext to private IPs only — ATS stays on for the public internet) plus `NSLocalNetworkUsageDescription` for the iOS 14+ local-network prompt. |
| Android | `INTERNET` in the **main** manifest — Flutter only declares it for debug/profile, so release builds have no network. Plus a `networkSecurityConfig` permitting cleartext for the LAN hosts specifically, rather than `usesCleartextTraffic="true"` app-wide. |

macOS may prompt once to allow incoming connections for the Go binary — accept it,
or the phone won't reach the API.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `DIARIAS_DATABASE_URL` | — (required) | Postgres connection string |
| `DIARIAS_ADDR` | `:8080` | HTTP listen address |
| `DIARIAS_TRUST_PROXY` | `false` | Trust `X-Forwarded-For`. **Only** behind a reverse proxy — otherwise callers forge it and evade login throttling |
| `DIARIAS_CORS_ORIGINS` | `*` | Comma-separated allowed origins (needed for Flutter Web) |
| `DIARIAS_SEED` | `false` | Seed two demo prestadoras into an empty database |
| `POSTGRES_PASSWORD` | — (required by compose) | Database password |

## Authentication

Username and password. Data is **shared**: every account sees the same
prestadoras and diárias — this is one household's calendar, and the login exists
to keep the published API closed, not to separate tenants.

- **Passwords** are argon2id (19 MiB, t=2, p=1 — OWASP's recommended profile),
  salted per user, stored in PHC format. The parameters live inside each hash, so
  they can be raised later without invalidating existing ones.
- **Sessions** are opaque 256-bit tokens, valid 30 days. The database stores only
  their SHA-256, so a dump of `sessions` hands over nothing usable.
- **No signup endpoint.** Accounts exist only via `api user add` on the server.
- **Login throttling**: 8 failures per 15 minutes, counted per username *and* per
  client address. A lockout blocks the correct password too — that is the point,
  but it means a legitimate user waits out the window.
- Unknown usernames spend the same CPU as real ones (a dummy hash is verified),
  so response timing does not reveal which accounts exist. Measured: 32 ms vs
  33 ms.
- Changing a password or disabling an account **revokes every open session**
  immediately.

### Managing accounts

The admin commands live in the API binary, so the deployed image needs nothing
extra:

```bash
docker compose exec api /api user add felipe
```

`user list`, `user passwd <nome>`, `user disable <nome>` and `user enable <nome>`
round it out. The password is read from stdin — never from an argument, where it
would land in shell history and `ps`. In a terminal it is prompted without echo;
piped, it is read as one line:

```bash
docker compose exec -T api /api user add marilia <<< 'uma-senha-bem-longa'
```

## Deploying on the VM

The API listens on `:8081` in the container, and compose publishes it on
**`127.0.0.1:7000`** — loopback only, on purpose. The reverse proxy reaches it
over localhost, and nothing on the internet can hit plain HTTP directly and
bypass TLS. Point the proxy at `http://127.0.0.1:7000`.

```bash
docker compose up -d          # db + api
docker compose exec api /api user add felipe
```

Postgres publishes no host port at all; only the api container can reach it.

**TLS is not optional here.** The login sends a password in the request body: over
plain HTTP anyone on the path reads it. Terminate TLS at the proxy and let only
HTTPS reach the outside.

`DIARIAS_TRUST_PROXY=true` is set in compose so login throttling sees the real
client address instead of the proxy's. That is safe *only* because the API port
is bound to loopback — if it were ever published publicly, a caller could forge
`X-Forwarded-For` and evade the per-IP limit.

## Data model

Money is **integer cents** (`bigint`) end to end — in the database, in JSON and
in Dart. Reais are a presentation concern only; this keeps sums exact and keeps
binary floats out of the wire format.

- **`providers`** — a prestadora: name, `default_rate_cents`, `color_index`
  (her palette colour), `position`. Deletion is a **soft delete**
  (`archived_at`): worked days and payments are history and must outlive her
  removal from the active list.
- **`work_entries`** — one row per (prestadora, day) with the value agreed *for
  that day*. `UNIQUE (provider_id, work_date)`. The value is copied from her
  rate at insert time rather than joined, so changing the default rate later
  never rewrites history.
- **`monthly_closings`** — a prestadora's month marked as paid. No row means
  "em aberto". `paid_amount_cents` is snapshotted so editing the month
  afterwards cannot silently change what was recorded as paid.

## API

Base path `/api/v1`. All dates are `YYYY-MM-DD`.

Only `/health` and `/auth/login` are public. **Everything else needs**
`Authorization: Bearer <token>` — new routes are registered on the authenticated
mux, so an endpoint cannot be added unprotected by accident.

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/health` | Public |
| `POST` | `/auth/login` | Public. `{username, password}` → `{token, expires_at, user}` |
| `POST` | `/auth/logout` | Revokes the calling token |
| `GET` | `/auth/me` | Confirms a stored token is still valid |
| `POST` | `/auth/password` | `{current_password, new_password}` — revokes every session |
| `GET` | `/providers` | Active prestadoras, in display order |
| `POST` | `/providers` | `{name?, default_rate_cents?, color_index?}` — colour auto-assigned |
| `PATCH` | `/providers/{id}` | Omitted fields are left unchanged |
| `DELETE` | `/providers/{id}` | Archives; history is kept |
| `GET` | `/entries?year=&month=` | Or `?from=&to=` (half-open range) |
| `PUT` | `/entries` | Upsert `{provider_id, date, value_cents?}` — omit the value to adopt her default rate |
| `DELETE` | `/entries?provider_id=&date=` | Unmarks the day |
| `GET` | `/months/{year}/{month}` | The Fechamento payload |
| `PUT` | `/months/{year}/{month}/providers/{id}/payment` | Mark paid; returns the refreshed month |
| `DELETE` | `/months/{year}/{month}/providers/{id}/payment` | Reopen; returns the refreshed month |

Errors are `{"code": "...", "message": "..."}` with `400` for validation, `401`
for a missing/invalid session or wrong credentials, `404` for missing rows, `429`
for too many login attempts (with `Retry-After`), `500` otherwise.

`total_cents` is everything worked in the month; **`outstanding_cents`** excludes
prestadoras already paid and is what the header shows as "A pagar".

## Design fidelity

Tokens are ported 1:1 from the design project's `_ds/.../tokens/*.css` into
`app/lib/theme/tokens.dart` — colour ramps, the `--grad-hero` header gradient,
radii, the 5-step navy-tinted shadow scale, and motion curves. The CSS remains
the source of truth; change it there, then mirror it in that one Dart file.

- **Fonts** are **bundled** in `app/assets/fonts` (Sora, Atkinson Hyperlegible)
  rather than loaded from the Google Fonts CDN as the design system does, so the
  app renders correctly offline. The design system's own readme flags the CDN as
  something to replace before production.
- **Prestadora palette** — the design reuses the four Acesso+ accessibility
  category colours as per-person identity colours, in the order
  física / auditiva / visual / sensorial. The backend stores only the index.
- **Icons** — the design uses 2px-stroke line icons; Material's outlined set is
  the closest match without shipping custom SVGs.

Two deliberate departures from the prototype:

1. **"Enviar" copies the message instead of claiming to send it.** The prototype
   showed a toast saying the fechamento had been sent, without sending anything.
   The dialog still previews the exact WhatsApp text; confirming copies it to the
   clipboard. Actually sending would need `url_launcher` and a phone number per
   prestadora — neither is in the design.
2. **Prestadoras can be removed.** The design adds prestadoras with no way back,
   which is a dead end. Removal is behind a confirmation and archives rather than
   deletes.

"Marcar como pago" and "Enviar" are disabled for a prestadora with no days in the
month — there is nothing to pay or send, and the API rejects it.

## Tests

```bash
cd backend && go test ./...
cd app && flutter test
```

Go covers the date/period logic (half-open month bounds, December rolling into
January, leap February), argon2id hashing (salting, tampered hashes, a hostile
`m=` parameter), and login throttling. Flutter covers pt-BR money
parsing/formatting round-trips, the wire models, the full auth flow (restore,
wrong password, mid-session 401, offline logout), and widget tests that drive the
real shell against a mocked API — the three tabs, the day sheet, month navigation
refetching, and the offline retry state. Widget tests run at the design's 402x874
frame so what sits below the fold matches the real device.

## Not built

From the design's own "Próximos passos", plus what a deployment would still want:

- Meia diária and faltas
- Reminder on the last day of the month
- History of past months (the data is all there; there is no screen for it)
- **Password change from inside the app.** The endpoint exists
  (`POST /auth/password`); there is no screen for it, so use `api user passwd`.
- **Multi-tenancy.** Accounts share one dataset by design. Separating households
  would need an owner column on `providers` and a filter on every query.
- **Session list / "log out my other devices".** Sessions are revocable
  wholesale (`user passwd`, `user disable`) but not individually from the app.
