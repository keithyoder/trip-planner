# CLAUDE.md — trip-planner

Rails app behind **trip.tessi.com.br**: planning, live telemetry, expenses and fuel tracking for a road trip by car through Brazil, Bolivia, Peru, Argentina and Chile. The vehicle is a 2014 Mitsubishi Pajero TR4 2.0L flex-fuel. The trip has **not started yet** (as of 2026-11-23), so there is room for upgrades and risky changes now. Once it is underway, production is in daily use and a broken deploy means a broken dashboard on the road.

I'm the only developer and the only user. Prefer simple, direct solutions over generality.

## Stack

- Ruby 3.4.13, Rails 7.2 (`load_defaults 7.0`), app module `RoadTrip`
- PostgreSQL + PostGIS (`activerecord-postgis-adapter`, RGeo, `rgeo-geojson`), Scenic views, Redis (cache + calibration state)
- Slim templates, Bootstrap 5 + Bootstrap Icons, Stimulus + Turbo, Leaflet, `jsbundling-rails` / `cssbundling-rails`
- ActionCable for the live dashboard; ActiveJob/Sidekiq for background jobs
- Prawn for PDFs, Nokogiri for receipt XML, `money` + `money-open-exchange-rates`, Chartkick
- Devise (`:omniauthable` + `:trackable` only, no passwords) + Google OAuth. Invite-only, see Authentication
- i18n: `en` (default), `pt`, `es` — use `i18n-tasks` to find missing keys
- Tests: Minitest (`test/`), fixtures. Lint: RuboCop. Schema annotations: `annotate`

Companion repo: **trip-telemetry** (Python on a Raspberry Pi 5). It reads OBD (ELM327), GPS (u-blox) and I2C sensors (BMP581, LTR390, SHTC3) and publishes to RabbitMQ. This app consumes that feed.

## Commands

```bash
bin/dev                      # local dev server (NOT bin/rails server: JS/CSS bundlers need it)
bin/rails test               # Minitest
bundle exec rubocop          # lint
bundle exec i18n-tasks missing
bin/rails generate scenic:view name --version N
bin/rails stimulus:manifest:update   # after adding a Stimulus controller
```

## External services

- **OpenRouteService** at `api.heigit.org/openrouteservice/v2`. It moved off `api.openrouteservice.org` in Aug 2026, so don't reintroduce the old host. Elevation: `/openelevationservice/v0/line`
- **Google Maps Directions** for transit legs (`ENV['GOOGLE_MAPS_API_KEY']`)
- **Stadia Maps** (`osm_bright`) for web tiles. **Print/PDF maps use OSM standard tiles** because they show highway shields
- Overpass API (POIs), osm-boundaries.com, Open Topo Data, Open Exchange Rates
- Secrets live in `.env` / `.env.production` (dotenv). Never commit them

## Architecture

Use service objects and concerns rather than fat models. Code is grouped into namespaces; put new code in the right one:

| Namespace | What it does |
|---|---|
| `Routing::` | ORS/Google route calculation, waypoints, segments |
| `Renderer::Map::Pdf`, `Renderer::Text::Pdf` | PDF atlas (parallel namespaces); shared `Renderer::WaypointIconography`, `Renderer::SurfaceStyling`. Needs DejaVu Sans + Bootstrap Icons TTF |
| `Receipt::` | NFC-e import: `Receipt::Detector` → `Receipt::Detectors::Brazil` → `Receipt::Adapters::Brazil::Nfce`. Peru/Argentina/Chile/Bolivia adapters are stubs that raise `NotImplementedError` |
| `Fuel::` | `Fuel::FillUp` (table `fuel_fill_ups`) → `Expense` → `Stop` → `Trip`. It is both the transaction record and the live fuel-state cache; `TelemetrySyncService` updates its running totals |
| `Stops::` | `Stops::Detector` finds stops from gaps between `TripLog` segments |
| `NetworkCoverage::` | `Union` is scoped **per route**, not per trip; `RouteCoverageBuilder` dispatches by country |
| `Units::` | Locale-aware units through `default_unit_for_locale` (from locale YAML); `LocalizedUnits` presenter concern |
| `BarometricAltitude::` | `Calibrator`, with P0 persisted in Redis |
| `SpeedBumps::`, `SpeedLimitAudit::` | Tooling for OSM contributions (detection, matching, GPX export) |

Front end: Stimulus controllers, with Leaflet logic kept in a `MapManager` class. Number formatting uses `Intl.NumberFormat` with the locale from `<meta name="app-locale">`.

### Telemetry pipeline

`TelemetrySyncService` (its own systemd unit, `telemetry-sync.service`) consumes RabbitMQ and writes `TelemetryLog` rows (JSONB `data`). It then broadcasts on per-locale ActionCable streams, `dashboard_updates_#{locale}`.

- RabbitMQ messages can arrive **hours late**. `MAX_PROCESSING_DELAY = 2.minutes` discards stale messages so altitude isn't computed against an old P0. Keep that guard.
- Barometric calibration: the primary calibration only happens while the car is stationary. A moving-window fallback kicks in after 1+ hour of staleness and uses the last 150 rows **ordered by `timestamp`**. Moving-window GPS calibration can look precise and still be systematically wrong because terrain biases the average. Treat it only as a fallback.

### Authentication

Google sign-in, **invite-only**: a `User` row must already exist for the Google account's email. There is no sign-up path and the callback never creates users.

- Add a user from the console: `User.create!(email: "...", name: "...")`. The email must match the Google account. Prod has no users until you add one, so create yours **before** the first deploy of auth or you lock yourself out.
- `ApplicationController` has `before_action :authenticate_user!`. Public controllers opt out with `skip_before_action :authenticate_user!` (currently `WelcomeController`, `LocalesController`, `SessionsController`). New controllers are protected by default.
- Devise only generates session routes for `database_authenticatable`, which we don't use. `/login` (`new_user_session`) and `/logout` are plain routes to `SessionsController`; Devise's failure app needs the `new_user_session` name to exist.
- OmniAuth 2 only accepts **POST** to `/users/auth/google_oauth2`, so the login control is a `button_to`, never a link.
- `Users::OmniauthCallbacksController` rejects unverified Google emails. `User.from_omniauth` matches on `provider`/`uid`, falling back to email for a first sign-in.
- ActionCable: `ApplicationCable::Connection` rejects sockets without a Warden user (the dashboard stream carries live position).
- Config: `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` in `.env.development` and `.env.production`. The OAuth client already had older redirect URIs without the `/users` prefix (`/auth/google_oauth2/callback` for localhost, `trip.tessi.com.br` and `aquinomeumoco.com.br`), so it may be used by something else: leave those alone and only add ours. Ours must be registered under Authorized redirect URIs with the `/users` prefix, because Devise mounts OmniAuth there: `https://trip.tessi.com.br/users/auth/google_oauth2/callback` and `http://localhost:3000/users/auth/google_oauth2/callback`. The app builds the callback from the browser's host, so `127.0.0.1:3000` would need its own entry. Consent screen, test users and the secret are shared with that other app too. A missing key only logs a warning at boot (so prod workers still start); the login button then fails.
- The `users` table exists in prod without ever having had a migration. `CreateUsers` uses `if_not_exists`, so it is a no-op on prod and builds the table elsewhere.

## Conventions and preferences

- **Validate in the Rails console first.** Before building UI or a full feature, prove the query or service in `bin/rails c`. Data entry such as budgets often stays console-only.
- **Fail loudly.** Never swallow exceptions; raise with a descriptive message. No silent retries: prefer Sidekiq dead-lettering on first failure over `retry_on`.
- **No redundant columns.** Derive values from associations. For example, `Expense` gets `occurred_at` and lat/lng from its `Stop`.
- **Don't assume schema.** Check `db/schema.rb` / model annotations to tell whether something is a column or a computed method before using it. Ask for a method body rather than guessing it.
- Work in small, reviewable steps, one file at a time once the design is settled.
- Comments and docs should explain **why**, not just what.
- Enums use explicit integer-keyed hashes (`{ fuel: 0, food: 1, ... }`), never positional arrays.
- User-facing strings go through i18n in all three locales.

## Gotchas (learned the hard way)

**Time and ordering**
- `TripLog` / `TelemetryLog` must be ordered by `timestamp`, never by id or arrival order.
- The server's local zone is UTC-3. In the console use `Time.find_zone("UTC").parse(...)` so query windows don't shift silently.

**PostGIS / ActiveRecord**
- Boundaries carry heavy multipolygons. Before any loop that calls `wp.boundaries.find`, preload with `ActiveRecord::Associations::Preloader` + `Boundary.without_geom`. **Never `includes`.**
- Scenic view SQL goes in `db/views/name_vNN.sql` with explicit column lists, never `*`.
- `Expense#amount_currency` has no DB default. Set it explicitly from `stop.currency` when creating the expense.

**Databases and tests (local vs prod)**
- `DATABASE_URL` overrides `database.yml` in **every** environment, including `test`. It once pointed at prod from `.env`, so `rails test` (fixtures delete and reinsert rows) and `rails runner` were hitting the prod database. Keep it **out of `.env`**.
- `.env.development` defaults to the local DB; the prod URL sits there commented out. To work against real data, swap the two lines, and remember console writes and jobs then hit prod. `.env.test` points at local `trip_test`.
- `test/test_helper.rb` aborts if the DB host isn't local. Don't remove that guard.
- Before any destructive local command, confirm the target: `bin/rails runner 'puts ActiveRecord::Base.connection_db_config.configuration_hash.slice(:host, :database)'`.
- Local Postgres is the shared Homebrew `postgresql@17` (pinned), which also hosts other projects' databases. Don't upgrade or restart it casually. Core `postgis` 3.7 has **no PostgreSQL 17 build**; the working local PostGIS is `postgis@3.5.3`, built from the personal tap `keithyoder/local-postgis` with `--without-raster` (raster doesn't compile on the current toolchain). Don't `brew upgrade` it away. After any brew upgrade of `postgresql@17`, restart the service, or running sessions fail loading `plpgsql.dylib`.
- Prod is PostgreSQL 16 with PostGIS 3.4.2.
- `db/schema.rb` loads into an empty database, and Rails' `maintain_test_schema` rebuilds `trip_test` from it automatically when the stored schema SHA doesn't match, so `bin/rails test` just works after a migration. To rebuild by hand: `RAILS_ENV=test bin/rails db:drop db:create db:schema:load`. (It used to fail on `osm_pois`; migration `RenameOsmPoisIdSequence` fixed that. Prod's sequence is renamed once that migration runs there.)
- Fixtures (`fixtures :all`) load again: keep them in step with the schema when columns change (e.g. `osm_pois.osm_id` is NOT NULL and unique, `waypoints` need a `trip` and a distinct `sequence` per trip, and the schema allows only one `in_progress` trip, so fixture trips stay on the default status). Controller tests call `sign_in users(:keith)` (Devise's integration helpers are included in `test_helper.rb`).
- `db:migrate` rewrites `db/schema.rb` from the local DB, so a local DB that is missing something silently drops it from the file. Diff `schema.rb` after migrating.

**Eager loading (production)**
- Production eager-loads all of `app/`. A `NameError`/`LoadError` in **any** class crashes every worker at boot, even when the request never touches that class. Use lazy string `.constantize` in orchestrators that reference stub adapters.
- Before deploying, check that the app boots with eager loading: `RAILS_ENV=production bin/rails runner "puts 'boot ok'"` (or `bin/rails zeitwerk:check`).

**Routing**
- Iterate route waypoints positionally with `all_waypoints[1..].each_with_index`. Don't filter with `reject(&:routing?)`, which misaligns segment indices against the ORS output.
- A waypoint's `profile` describes how you **arrived** at it, not how you leave.
- The ORS elevation API silently drops trailing points. After import, run `clamp_surface_indices` and `clamp_segment_way_points`.

## Deploy and production

- Capistrano + Passenger embedded in Nginx (there's no separate Passenger systemd unit; only `nginx.service`).
- Push env changes: `scp .env.production yoder@trip.tessi.com.br:/var/www/trip-planner/shared`
- **After every deploy, restart `telemetry-sync.service` by hand.** Capistrano only restarts the web app.
- Logs, in order of usefulness:
  1. `/var/www/trip-planner/current/log/production.log` (under `current/`, not `shared/`; `log` isn't in `linked_dirs`, so it resets each deploy)
  2. `/var/log/nginx/trip-error.log`
  3. `/var/log/nginx/error.log`, which is mostly scanner noise
- Boot-crash signature: `production.log` shows only repeated `[dotenv] Loaded .env.production` lines from different PIDs. Workers are dying at eager-load (see above).

## Open work / context

- **Fuel model at altitude.** The current ENGINE_LOAD speed-density estimate doesn't correct for the 40–60% drop in air density on the altiplano (3,000–4,500 m). The plan is to switch to MAP/IAT ideal-gas: a flat VE constant first, then a least-squares fit across several legs, then an RPM-bucket VE table only if the residuals require it.
- The `FuelUsed` calibration factor (1.685×) comes from a single data point. Re-derive it from a clean fill-to-fill leg.
- Undecided: a `Vehicle` model vs. hardcoded tank capacity; distance-to-empty smoothing; a fast path for manual fuel entry. Dashboard fuel gauge widget is in progress.
- **Planned (not started): move the website to `aquinomeumoco.com.br`.** Both names already resolve to the same server. The code is host-agnostic (no `force_ssl`, host allow-list or hard-coded callback), so it needs: nginx `server_name`, a TLS cert for the new name, and `https://aquinomeumoco.com.br/users/auth/google_oauth2/callback` added to the Google OAuth client. **Keep `trip.tessi.com.br` resolving**: it is also the hostname for RabbitMQ (`RABBITMQ_HOST`, which the Pi in trip-telemetry publishes to), the prod `DATABASE_URL`, and Capistrano's SSH target in `config/deploy/production.rb`. Dropping it stops live telemetry.
- NFC-e adapters for PE/AR/CL/BO are still stubs.
- Auth is verified by automated tests only (`test/integration/google_sign_in_test.rb`, `test/channels/application_cable/connection_test.rb`). The real Google round trip still needs a manual check.
- Planned: split `DayTextPdfRenderer` into sub-modules parallel to `Renderer::Map`; daily food budget as a `TripExpense` line item.