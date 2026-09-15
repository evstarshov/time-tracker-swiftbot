# Time Tracker Bot — Telegram Bot on Swift (Vapor)

![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Vapor](https://img.shields.io/badge/Vapor-4-blue)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-✓-336791)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-E95420)
![systemd](https://img.shields.io/badge/systemd-✓-black)

**🇷🇺 Русская версия — ниже.**

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

# Time Tracker Bot — Telegram Bot на Swift (Vapor)

![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Vapor](https://img.shields.io/badge/Vapor-4-blue)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-✓-336791)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04-E95420)
![systemd](https://img.shields.io/badge/systemd-✓-black)

Пет-проект: Telegram-бот для учёта рабочего времени сотрудников. Развёрнут на выделенном Ubuntu Server. Демонстрирует enterprise-практики (Сбер), адаптированные под solo-разработку.

---

## Демо

### Статистика за месяц
![Статистика за месяц](docs/screenshot1.png)

*Бот показывает статистику за месяц: распределение по пользователям, участие в процентах, прогресс-бары, общий итог.*

### Справка и начало рабочего дня
![Справка и начало дня](docs/screenshot2.png)

*Бот выдаёт справку по командам и подтверждает начало рабочего дня.*

---

## Что делает бот

- **Учёт рабочего времени:** старт/стоп сессии, паузы, автоматическое завершение через 12 часов.
- **Привязка к проектам:** выбор проекта при старте дня, статистика по каждому проекту.
- **Статистика:** детальные отчёты за день, месяц, по пользователям и проектам.
- **Управление проектами:** создание, удаление, просмотр сессий (только для администраторов).
- **Напоминания:** автоматическое напоминание через 8 часов после начала работы.
- **Команда `/ping`:** проверка работоспособности бота.

---

## Инфраструктура и DevOps-практики

| Практика | Реализация |
|---|---|
| Управление сервисом | **systemd** (автозапуск, рестарт при падении) |
| База данных | **PostgreSQL** (Fluent ORM) |
| Логирование | **journald** |
| Алертинг | критические ошибки → **Telegram-чат** |
| Разделение окружений | **production / development** через переключение конфига |
| Деплой | `git pull` → `swift build -c release` → `systemctl restart` |
| Удалённый доступ | **SSH** (ключи + fail2ban) |

---

## Инженерные решения

- **Разделение окружений под масштаб проекта.** В Сбере использовалось 5 окружений под разные роли (dev, QA, security, приёмка, prod). Для solo-проекта я сократил их до двух (production / development) — этого достаточно, чтобы тестировать на клоне бота, не останавливая основной сервис.
- **Алертинг вместо полноценного мониторинга.** Вместо развёртывания Prometheus + Grafana я настроил отправку критических ошибок напрямую в Telegram — минимальные накладные расходы при сохранении контроля 24/7.
- **Разделение кода и конфигурации.** Токены и параметры БД вынесены в переменные окружения (`DATABASE_PASSWORD`, `BOT_TOKEN`). Переключение окружения — без изменения кода.
- **Безопасность по умолчанию.** SSH с ключами, fail2ban, вынесенные токены, `.gitignore` для личных данных — стандартные практики, перенесённые из enterprise.

---

## Стек

- **Язык:** Swift, Vapor
- **База данных:** PostgreSQL (Fluent ORM)
- **Инфраструктура:** Ubuntu Server, systemd, journald
- **Контроль версий:** Git, GitHub
- **Мониторинг:** алертинг в Telegram

---

## Схема деплоя

1. Разработка в отдельной ветке от `main`.
2. Push в GitHub.
3. На сервере: `git pull` → `swift build -c release` → `systemctl restart`.
4. Критические ошибки автоматически приходят в Telegram.

---

## Пример systemd-юнита

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

