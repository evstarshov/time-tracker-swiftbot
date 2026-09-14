//
//  BotEnviroment.swift
//  time-tracker-bot
//
//  Created by Евгений Старшов on 14.09.2026.
//

@preconcurrency import Foundation
import Vapor
@preconcurrency import SwiftTelegramBot
import Fluent
import FluentPostgresDriver

public func configure(_ app: Application) async throws {
    let tgApi: String = BotEnvironment.token.production
    
    // Настройка логов и порта
    app.logger.logLevel = .info
    app.http.server.configuration.port = 8899
    
    // 1. Настраиваем базу данных (прямо здесь)
    let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
    let port = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? 5432
    let username = Environment.get("DATABASE_USERNAME") ?? "vapor_username"
    let password = Environment.get("DATABASE_PASSWORD") ?? "your_password_here"
    let database = Environment.get("DATABASE_NAME") ?? "waifubot_db"
    
    app.logger.info("🔌 Подключение к базе данных...")
    app.logger.info("   Host: \(hostname)")
    app.logger.info("   Port: \(port)")
    app.logger.info("   Database: \(database)")
    app.logger.info("   Username: \(username)")
    
    // Используем новый API для PostgreSQL (депрекейшн fixed)
    let configuration = SQLPostgresConfiguration(
        hostname: hostname,
        port: port,
        username: username,
        password: password,
        database: database,
        tls: .disable
    )
    app.databases.use(.postgres(configuration: configuration), as: .psql)
    
    app.logger.info("✅ База данных настроена")
    
    // 2. Добавляем миграции
    app.migrations.add(CreateProject())      // 1. Сначала projects
    app.migrations.add(CreateUserWorkDay())  // 2. Потом user_work_days
    app.migrations.add(CreateWorkSession())  // 3. Потом work_sessions
    
    // 3. ВЫПОЛНЯЕМ МИГРАЦИИ СРАЗУ
    app.logger.info("🚀 Выполнение миграций...")
    try await app.autoMigrate().get()
    app.logger.info("✅ Миграции выполнены")
    
    // 4. Только после миграций инициализируем бота
    app.bot = try await .init(connectionType: .longpolling(),
                                     tgClient: TGClientDefault(),
                                     tgURI: TGBot.standardTGURL,
                                     botId: tgApi,
                                     log: app.logger)
    
    // 5. Добавляем обработчики
    try await app.bot.add(dispatcher: DefaultBotHandlers(bot: app.bot, logger: app.logger))
    
    // 6. Запускаем бота
    try await app.bot.start()
    
    // 7. Запускаем планировщик напоминаний
    startReminderScheduler(app: app)
    
    // 8. Настраиваем роуты
    try routes(app)
}

private func startReminderScheduler(app: Application) {
    let timer = DispatchSource.makeTimerSource()
    
    // Вычисляем время до следующего срабатывания (10:30)
    let calendar = Calendar.current
    let now = Date()
    
    // Создаем компоненты для 10:30
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    components.hour = 07
    components.minute = 15
    
    // Получаем следующее время 10:30
    var nextReminder = calendar.date(from: components)!
    if nextReminder <= now {
        // Если 10:30 уже прошло сегодня, планируем на завтра
        nextReminder = calendar.date(byAdding: .day, value: 1, to: nextReminder)!
    }
    
    let interval = nextReminder.timeIntervalSince(now)
    
    app.logger.info("⏰ Напоминание запланировано на \(nextReminder) (через \(Int(interval/3600))ч \(Int(interval.truncatingRemainder(dividingBy: 3600)/60))м)")
    
    timer.schedule(deadline: .now() + interval, repeating: .seconds(24 * 3600))
    timer.setEventHandler {
        app.logger.info("🔔 Сработало ежедневное напоминание!")
        
        Task {
            await sendReminderToChannel(app: app)
        }
    }
    
    timer.setCancelHandler {
        app.logger.info("⏰ Таймер напоминания остановлен")
    }
    
    timer.resume()
    
    // Сохраняем таймер с помощью обертки Sendable
    app.storage.set(ReminderTimerStorageKey.self, to: SendableTimerBox(timer))
}

// Исправленный ключ для хранения таймера с Sendable оберткой
private struct ReminderTimerStorageKey: StorageKey {
    typealias Value = SendableTimerBox
}

// Обертка, делающая DispatchSourceTimer Sendable
struct SendableTimerBox: @unchecked Sendable {
    let timer: DispatchSourceTimer
    
    init(_ timer: DispatchSourceTimer) {
        self.timer = timer
    }
}

private func sendReminderToChannel(app: Application) async {
    do {
        // ID чата или пользователя
        let chatId: Int64 = -0
        
        let params: TGSendMessageParams = .init(
            chatId: .chat(chatId),
            text: """
            ⏰ *Доброе утро, команда! Время 10:30*
            
            Напоминаем начать рабочий день.
            
            Используйте команду /begin чтобы начать работу.
            
            Удачного дня! ☀️
            """,
            parseMode: .html
        )
        
        try await app.bot.sendMessage(params: params)
        app.logger.info("✅ Ежедневное напоминание отправлено")
        
    } catch {
        app.logger.error("❌ Ошибка при отправке ежедневного напоминания: \(error)")
    }
}
