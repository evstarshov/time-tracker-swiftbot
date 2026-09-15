# Time Tracker Bot — Telegram Bot on Swift (Vapor)

![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Vapor](https://img.shields.io/badge/Vapor-4-blue)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-✓-336791)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-E95420)
![systemd](https://img.shields.io/badge/systemd-✓-black)

**🇬🇧 English** | **[🇷🇺 Русская версия](README.ru.md)**

Pet project: Telegram bot for employee work time tracking, deployed on a dedicated Ubuntu Server. Demonstrates enterprise practices (Sber) adapted for solo development.

---

## Demo

### Monthly statistics
![Monthly statistics](docs/screenshot1.png)

*The bot shows monthly statistics: distribution by users, participation percentage, progress bars, total.*

### Help and work day start
![Help and work day start](docs/screenshot2.png)

*The bot provides command help and confirms the start of a work day.*

---

## What the bot does

- **Work time tracking:** start/stop sessions, pauses, auto-end after 12 hours.
- **Project binding:** project selection at day start, statistics per project.
- **Statistics:** detailed reports per day, month, user, and project.
- **Project management:** create, delete, view sessions (admin only).
- **Reminders:** automatic reminder after 8 hours of work.
- **`/ping` command:** health check.

---

## Infrastructure and DevOps practices

| Practice | Implementation |
|---|---|
| Service management | **systemd** (autostart, restart on failure) |
| Database | **PostgreSQL** (Fluent ORM) |
| Logging | **journald** |
| Alerting | critical errors → **Telegram chat** |
| Environment separation | **production / development** via config switch |
| Deploy | `git pull` → `swift build -c release` → `systemctl restart` |
| Remote access | **SSH** (keys + fail2ban) |

---

## Engineering decisions

- **Environment separation scaled to the project.** At Sber, 5 environments were used for different roles (dev, QA, security, acceptance, prod). For a solo project, I reduced them to two (production / development) — enough to test on a bot clone without stopping the main service.
- **Alerting instead of full monitoring.** Instead of deploying Prometheus + Grafana, I set up critical error notifications directly to Telegram — minimal overhead while keeping 24/7 control.
- **Code and configuration separation.** Tokens and DB credentials are externalized to environment variables (`DATABASE_PASSWORD`, `BOT_TOKEN`). Environment switching without code changes.
- **Security by default.** SSH with keys, fail2ban, externalized tokens, `.gitignore` for personal data — standard practices transferred from enterprise.

---

## Stack

- **Language:** Swift, Vapor
- **Database:** PostgreSQL (Fluent ORM)
- **Infrastructure:** Ubuntu Server, systemd, journald
- **Version control:** Git, GitHub
- **Monitoring:** Telegram alerting

---

## Deploy scheme

1. Development in a separate branch from `main`.
2. Push to GitHub.
3. On the server: `git pull` → `swift build -c release` → `systemctl restart`.
4. Critical errors automatically go to Telegram.

---

## systemd unit example

The bot is managed via systemd (autostart, restart on failure).

Full example: [docs/systemd.service](docs/systemd.service)

```ini
[Unit]
Description=time-tracker-bot service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=waifubot
Restart=always
RestartSec=10
WorkingDirectory=/opt/time-tracker-bot
EnvironmentFile=-/etc/time-tracker-bot/env
ExecStart=/opt/time-tracker-bot/.build/release/App

[Install]
WantedBy=multi-user.target
