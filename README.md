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

## Running it

**1. Postgres**

```bash
docker compose up -d db
```

Published on host port **5433** so it doesn't collide with a local Postgres on
5432.

**2. API** — migrations run automatically on boot.

```bash
cd backend && DIARIAS_DATABASE_URL='postgres://diarias:diarias@localhost:5433/diarias?sslmode=disable' go run ./cmd/api
```

Copy `.env.example` to `.env` to avoid passing variables each time.

`DIARIAS_SEED=true` inserts the design's two demo prestadoras (Marina, Cleide),
but **only when the providers table is empty**. It ships off, so a fresh volume
never resurrects the demo names over real data. Turn it on only to repopulate a
throwaway database.

**3. App**

```bash
cd app && flutter run
```

The client defaults to `http://localhost:8080` (`http://10.0.2.2:8080` on the
Android emulator). Point it elsewhere with:

```bash
flutter run --dart-define=DIARIAS_API_URL=http://192.168.0.10:8080
```

To run the API in a container too: `docker compose --profile full up -d`.

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
| `DIARIAS_API_TOKEN` | empty | When set, every `/api` request needs `Authorization: Bearer <token>` |
| `DIARIAS_CORS_ORIGINS` | `*` | Comma-separated allowed origins (needed for Flutter Web) |
| `DIARIAS_SEED` | `false` | Seed two prestadoras into an empty database |

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

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/health` | |
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

Errors are `{"code": "...", "message": "..."}` with `400` for validation, `404`
for missing rows, `401` when a token is configured and absent, `500` otherwise.

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
January, leap February). Flutter covers pt-BR money parsing/formatting
round-trips, the wire models, and widget tests that drive the real shell against
a mocked API — the three tabs, the day sheet, month navigation refetching, and
the offline retry state. Widget tests run at the design's 402x874 frame so what
sits below the fold matches the real device.

## Not built

From the design's own "Próximos passos", plus what a real deployment needs:

- Meia diária and faltas
- Reminder on the last day of the month
- History of past months (the data is all there; there is no screen for it)
- **Authentication.** The design has no login, so the API has none: it assumes a
  single household. `DIARIAS_API_TOKEN` is a shared-secret stopgap, not
  multi-user auth — anyone with the token sees all data. Multi-user would need an
  owner column on `providers` and a real identity layer.
