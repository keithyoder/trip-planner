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