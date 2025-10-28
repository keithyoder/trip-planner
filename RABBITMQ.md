`/etc/systemd/system/telemetry-sync.service`

```ini
[Unit]
Description=Telemetry Sync Worker
After=network.target rabbitmq-server.service postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/trip-planner/current
Environment=RAILS_ENV=production

# Load all environment variables from your .env or use ExecStartPre
EnvironmentFile=/var/www/trip-planner/current/.env.production

ExecStart=/bin/bash -lc 'bundle exec rails telemetry:sync'

Restart=always
RestartSec=10

StandardOutput=append:/var/log/telemetry-sync.log
StandardError=append:/var/log/telemetry-sync.log

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable telemetry-sync
sudo systemctl start telemetry-sync
sudo systemctl status telemetry-sync
```

[Unit]
Description=Telemetry Sync Worker
After=network.target rabbitmq-server.service postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/trip-planner/current

# Environment variables
EnvironmentFile=/var/www/trip-planner/shared/.env.production
Environment=RAILS_ENV=production

# IMPORTANT: Set full PATH including rbenv
Environment="PATH=/home/deploy/.rbenv/shims:/home/deploy/.rbenv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Use absolute path to bundle
ExecStart=/home/deploy/.rbenv/shims/bundle exec rails telemetry:sync

Restart=always
RestartSec=10

StandardOutput=append:/var/log/telemetry-sync.log
StandardError=append:/var/log/telemetry-sync-error.log

[Install]
WantedBy=multi-user.target