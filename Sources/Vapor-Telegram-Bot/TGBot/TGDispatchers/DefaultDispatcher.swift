//
//  Untitled.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 19.01.2026.
//

import Vapor
import Fluent
import SwiftTelegramBot
import PostgresNIO

final class DefaultBotHandlers: TGDefaultDispatcher, @unchecked Sendable {
    
    private var reminderTimers: [String: DispatchSourceTimer] = [:]
    
    override
    func handle() async {
        await commandStartHandler()
        await commandHelpHandler()
        await commandBeginHandler()
        await commandEndHandler()
        await commandStatusHandler()
        await commandStatsHandler()
        await commandAdminStatsHandler()
        await commandDebugHandler()
        await commandDeleteProjectHandler()
        await commandProjectSessionsHandler()
        await commandGroupEndHandler()
        // Новая команда для управления проектами
        await commandProjectsHandler()
        await commandAddProjectHandler()
        await commandProjectStatsHandler()
    }
    
    
    private func commandStartHandler() async {
        await add(TGCommandHandler(commands: ["/start", "/start@time_tracker_swiftbot"]) { [weak self] update in
            guard let message = update.message else {
                return
            }
            let chat = message.chat
            let params: TGSendMessageParams = .init(
                chatId: .chat(chat.id),
                text: """
                👋 Привет! Я бот для учета рабочего времени.
                
                📋 *Доступные команды:*
                /begin - Начать рабочий день
                /end - Завершить рабочий день
                /status - Статус рабочего дня
                /stats - Детальная статистика
                /projects - Управление проектами
                /help - Помощь по командам
                
                🗄️ *Особенности:*
                • Используется база данных PostgreSQL
                • Сохранение истории работы
                • Статистика и отчеты
                • Привязка к проектам
                """,
                parseMode: .html
            )
            
            try await self?.bot.sendMessage(params: params)
        })
    }
    
    private func commandHelpHandler() async {
        await add(TGCommandHandler(commands: ["/help", "/помощь", "/help@time_tracker_swiftbot"]) { [weak self] update in
            guard let message = update.message,
                  let user = message.from else {
                return
            }
            let chat = message.chat
            
            // Проверяем, является ли пользователь администратором
            let adminUserIds: [Int64] = [296089632, 448044251]
            let isAdmin = adminUserIds.contains(user.id)
            
            var helpText = """
            🤖 *Помощь по командам*
            
            🎯 *ОСНОВНЫЕ КОМАНДЫ:*
            • /start - Начало работы с ботом
            • /begin - Начать рабочий день (с выбором проекта)
            • /end - Завершить рабочий день
            • /status - Текущий статус и активные сессии
            • /stats - Детальная статистика за сегодня
            • /projects - Список всех проектов
            • /help - Эта справка
            
            📊 *ФУНКЦИОНАЛ:*
            • Учет рабочего времени с привязкой к проектам
            • Автоматическое напоминание через 8 часов
            • Сохранение всей истории в базу данных
            • Детальная статистика и отчеты
            • Управление проектами
            """
            
            // Команды только для администраторов
            if isAdmin {
                helpText += """
                
                👑 *КОМАНДЫ ДЛЯ АДМИНИСТРАТОРОВ:*
                • /addproject [название] - Добавить новый проект
                • /deleteproject [ID/название] - Удалить проект
                • /deleteproject [ID/название] force - Принудительное удаление
                • /projectsessions [ID/название] - Просмотр сессий проекта
                • /projectstats - Детальная статистика по всем проектам
                • /projectstats [ID/название] - Статистика по конкретному проекту
                • /adminstats - Статистика за текущий месяц
                • /debug - Отладочная информация и проверка данных
                
                ⚙️ *УПРАВЛЕНИЕ ПРОЕКТАМИ:*
                1. Добавьте проект: /addproject Название
                2. Просмотрите список: /projects
                3. Удалите проект: /deleteproject [ID или название]
                """
            }
            
            helpText += """
            
            💡 *КАК ИСПОЛЬЗОВАТЬ:*
            1. Работайте над задачами
            2. Завершите день командой /end
            3. Смотрите статистику через /status или /stats
            
            ⏰ *ОСОБЕННОСТИ:*
            • Автоматическое напоминание через 8 часов работы
            • Привязка времени к конкретным проектам
            • Возможность работать без проекта
            • Подробная аналитика для администраторов
            
            📞 *ПОДДЕРЖКА:*
            По вопросам и предложениям обращайтесь к администратору.
            """
            
            let params: TGSendMessageParams = .init(
                chatId: .chat(chat.id),
                text: helpText,
                parseMode: .html,
                replyParameters: message.messageId != nil ? TGReplyParameters(messageId: message.messageId) : nil
            )
            
            try await self?.bot.sendMessage(params: params)
        })
    }
    
    private func commandBeginHandler() async {
        await add(
            TGCommandHandler(commands: ["/begin", "/начать", "/startwork", "/begin@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                guard let self else { return }
                let chat = message.chat
                
                do {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    // Проверяем, есть ли активный рабочий день
                    let existingDay = try await UserWorkDay.query(on: app.db)
                        .filter(\.$telegramUserId == user.id)
                        .filter(\.$date == today)
                        .first()
                    
                    if let existingDay = existingDay {
                        // Проверяем активные сессии
                        let activeSession = try await WorkSession.query(on: app.db)
                            .filter(\.$workDay.$id == existingDay.requireID())
                            .filter(\.$endTime == nil)
                            .first()
                        
                        if activeSession != nil {
                            let params: TGSendMessageParams = .init(
                                chatId: .chat(chat.id),
                                text: "⚠️ У вас уже есть активная рабочая сессия.",
                                replyParameters: TGReplyParameters(messageId: messageID)
                            )
                            try await bot.sendMessage(params: params)
                            return
                        }
                    }
                    
                    // Получаем все доступные проекты
                    let allProjects = try await Project.query(on: app.db).all()
                    
                    // Если проектов нет, начинаем день без проекта
                    if allProjects.isEmpty {
                        await self.startWorkDayWithReminder(
                            for: user,
                            chat: chat,
                            date: today,
                            existingDay: existingDay,
                            messageID: messageID,
                            projectId: nil
                        )
                        return
                    }
                    
                    // Создаем кнопки для выбора проекта
                    var buttons: [[TGInlineKeyboardButton]] = []
                    
                    // Добавляем кнопки проектов (по 2 в ряд)
                    for project in allProjects {
                        let buttonRow = [TGInlineKeyboardButton(
                            text: project.name,
                            callbackData: "begin_project:\(project.id?.uuidString ?? "")"
                        )]
                        buttons.append(buttonRow)
                    }
                    
                    // Добавляем кнопку "Без проекта"
                    buttons.append([TGInlineKeyboardButton(
                        text: "🚫 Без проекта",
                        callbackData: "begin_project:no_project"
                    )])
                    
                    let keyboard = TGInlineKeyboardMarkup(inlineKeyboard: buttons)
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        📂 *Выберите проект для работы:*
                        
                        Нажмите на кнопку с названием проекта, чтобы начать работу над ним.
                        
                        _Или выберите "Без проекта" для общей работы._
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID), replyMarkup: .inlineKeyboardMarkup(keyboard)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("❌ Ошибка при начале рабочего дня: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при начале рабочего дня.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
        
        // Добавляем обработчик callback для кнопок выбора проекта
        await add(TGCallbackQueryHandler(pattern: "begin_project:(.+)") { [weak self] update in
            guard let self = self,
                  let callbackQuery = update.callbackQuery,
                  let message = callbackQuery.message
            else {
                return
            }
            
            let chat = message.chat
            let callbackData = callbackQuery.data ?? ""
            let user = callbackQuery.from
            
            do {
                // Извлекаем ID проекта из callback данных
                let projectIdString = callbackData.replacingOccurrences(of: "begin_project:", with: "")
                
                var projectId: UUID? = nil
                var projectName = "Без проекта"
                
                if projectIdString != "no_project", let uuid = UUID(uuidString: projectIdString) {
                    projectId = uuid
                    if let project = try await Project.find(uuid, on: app.db) {
                        projectName = project.name
                    }
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let today = dateFormatter.string(from: Date())
                
                // Проверяем, есть ли активный рабочий день
                let existingDay = try await UserWorkDay.query(on: app.db)
                    .filter(\.$telegramUserId == user.id)
                    .filter(\.$date == today)
                    .first()
                
                // Запускаем рабочий день с выбранным проектом
                await self.startWorkDayWithReminder(
                    for: user,
                    chat: chat,
                    date: today,
                    existingDay: existingDay,
                    messageID: message.messageId,
                    projectId: projectId,
                    projectName: projectName,
                    callbackQueryId: callbackQuery.id
                )
                
            } catch {
                app.logger.error("❌ Ошибка при обработке выбора проекта: \(error)")
                // Отвечаем на callback с ошибкой
                do {
                    try await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                        callbackQueryId: callbackQuery.id,
                        text: "❌ Ошибка при начале работы",
                        showAlert: false
                    ))
                } catch {
                    app.logger.error("❌ Ошибка при отправке callback ответа: \(error)")
                }
            }
        })
    }
    
    
    // Обновленный handler команды /end
    private func commandEndHandler() async {
        await add(
            TGCommandHandler(commands: ["/end", "/закончить", "/stopwork", "/end@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let user = message.from,
                      let messageID = update.message?.messageId else {
                    return
                }
                
                guard let self else { return }
                let chat = message.chat
                do {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    // Ищем рабочий день
                    guard let workDay = try await UserWorkDay.query(on: app.db)
                        .filter(\.$telegramUserId == user.id)
                        .filter(\.$date == today)
                        .first() else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "ℹ️ У вас нет активного рабочего дня.",
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Ищем активную сессию
                    guard let session = try await WorkSession.query(on: app.db)
                        .filter(\.$workDay.$id == workDay.requireID())
                        .filter(\.$endTime == nil)
                        .first() else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "ℹ️ Нет активной сессии.",
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Отменяем автоматическое завершение для этой сессии
                    if let sessionId = session.id {
                        self.cancelAutoEndSession(for: user.id, sessionId: sessionId)
                    }
                    
                    // Завершаем сессию
                    session.endTime = Date()
                    try await session.update(on: app.db)
                    
                    // Вычисляем длительность
                    let duration = Int(session.endTime!.timeIntervalSince(session.startTime))
                    let hours = duration / 3600
                    let minutes = (duration % 3600) / 60
                    
                    dateFormatter.dateFormat = "HH:mm"
                    let endTimeString = dateFormatter.string(from: session.endTime!)
                    let startTimeString = dateFormatter.string(from: session.startTime)
                    
                    // Добавляем информацию о проекте, если есть
                    var projectInfo = ""
                    if let projectId = session.$project.id {
                        if let project = try await Project.find(projectId, on: app.db) {
                            projectInfo = "\n📂 Проект: \(project.name)"
                        }
                    }
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ✅ *Рабочий день завершен! Пользователь: @\(user.username ?? user.firstName)*
                        🕐 Начало: \(startTimeString)
                        🕐 Окончание: \(endTimeString)
                        ⏱️ Длительность: \(hours)ч \(minutes)м
                        \(projectInfo) 
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                    app.logger.info("✅ Рабочий день пользователя \(user.id) завершен вручную")
                    
                } catch {
                    app.logger.error("Ошибка при завершении рабочего дня: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при завершении рабочего дня.",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    
    private func commandStatusHandler() async {
        await add(
            TGCommandHandler(commands: ["/status", "/статус", "/status@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self else { return }
                let chat = message.chat
                
                do {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    // Получаем рабочий день
                    guard let workDay = try await UserWorkDay.query(on: app.db)
                        .filter(\.$telegramUserId == user.id)
                        .filter(\.$date == today)
                        .with(\.$workSessions)
                        .first() else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: """
                            📊 *Статус*
                            
                            Пользователь: @\(user.username ?? user.firstName)
                            Нет данных за сегодня.
                            Используйте /begin чтобы начать работу.
                            """,
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    let activeSession = workDay.workSessions.first { $0.endTime == nil }
                    let completedSessions = workDay.workSessions.filter { $0.endTime != nil }
                    
                    // Считаем общее время
                    let totalTime = completedSessions.reduce(0) { total, session in
                        total + Int(session.endTime!.timeIntervalSince(session.startTime))
                    }
                    
                    let hours = totalTime / 3600
                    let minutes = (totalTime % 3600) / 60
                    
                    dateFormatter.dateFormat = "dd.MM.yyyy"
                    let dateString = dateFormatter.string(from: Date())
                    
                    // Добавляем информацию о проекте, если есть
                    var projectInfo = ""
                    if let projectId = workDay.$project.id {
                        if let project = try await Project.find(projectId, on: app.db) {
                            projectInfo = "\n📂 Текущий проект: \(project.name)"
                        }
                    }
                    
                    var statusText = """
                    📊 *Статус за \(dateString)*
                    
                    🕐 Отработано: \(hours)ч \(minutes)м
                    📈 Сессий: \(completedSessions.count)
                    \(projectInfo)
                    """
                    
                    if let activeSession = activeSession {
                        dateFormatter.dateFormat = "HH:mm"
                        let startTime = dateFormatter.string(from: activeSession.startTime)
                        
                        // Добавляем информацию о проекте для активной сессии
                        var sessionProjectInfo = ""
                        if let projectId = activeSession.$project.id {
                            if let project = try await Project.find(projectId, on: app.db) {
                                sessionProjectInfo = "Проект: \(project.name)\n"
                            }
                        }
                        
                        statusText += """
                        
                        🟢 *Активная сессия:*
                        Начата в \(startTime)
                        \(sessionProjectInfo)Используйте /end для завершения
                        """
                    } else {
                        statusText += "\n\n⚪ Нет активных сессий"
                    }
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: statusText,
                        parseMode: .html,
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("Ошибка при получении статуса: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении статуса.",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandStatsHandler() async {
        await add(
            TGCommandHandler(commands: ["/stats", "/статистика", "/stats@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self = self else { return }
                
                let chat = message.chat
                
                do {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let today = dateFormatter.string(from: Date())
                    
                    // Получаем рабочий день с загрузкой сессий и проектов
                    let workDayQuery = UserWorkDay.query(on: app.db)
                        .filter(\.$telegramUserId == user.id)
                        .filter(\.$date == today)
                        .with(\.$workSessions)
                    
                    guard let workDay = try await workDayQuery.first() else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "📊 Нет данных за сегодня по пользователю @\(user.username ?? user.firstName).",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    let sessions = workDay.workSessions.sorted { $0.startTime < $1.startTime }
                    
                    if sessions.isEmpty {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "📊 Нет сессий по пользователю @\(user.username ?? user.firstName) за сегодня.",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    var statsText = "📈 *Статистика @\(user.username ?? user.firstName) за сегодня*\n\n"
                    
                    dateFormatter.dateFormat = "HH:mm"
                    
                    // Группируем сессии по проектам
                    var projectStats: [UUID?: (name: String, time: Int, count: Int)] = [:]
                    
                    for (index, session) in sessions.enumerated() {
                        let projectName = session.project?.name ?? "Без проекта"
                        let projectId = session.$project.id
                        
                        if let endTime = session.endTime {
                            let duration = Int(endTime.timeIntervalSince(session.startTime))
                            
                            // Обновляем статистику по проекту
                            var stats = projectStats[projectId] ?? (name: projectName, time: 0, count: 0)
                            stats.time += duration
                            stats.count += 1
                            projectStats[projectId] = stats
                            
                            let hours = duration / 3600
                            let minutes = (duration % 3600) / 60
                            
                            statsText += "\(index + 1). \(dateFormatter.string(from: session.startTime)) - \(dateFormatter.string(from: endTime)) (\(hours)ч \(minutes)м)\n"
                        } else {
                            statsText += "\(index + 1). \(dateFormatter.string(from: session.startTime)) - ... (активна)\n"
                        }
                        
                    }
                    
                    // Добавляем статистику по проектам
                    if !projectStats.isEmpty {
                        statsText += "\n📂 *РАСПРЕДЕЛЕНИЕ ПО ПРОЕКТАМ:*\n"
                        
                        for (_, stats) in projectStats.sorted(by: { $0.value > $1.value }) {
                            let hours = stats.time / 3600
                            let minutes = (stats.time % 3600) / 60
                            statsText += "• \(stats.name): \(hours)ч \(minutes)м (\(stats.count) сессий)\n"
                        }
                    }
                    
                    // Итоги
                    let completedSessions = sessions.filter { $0.endTime != nil }
                    let totalTime = completedSessions.reduce(0) { total, session in
                        total + Int(session.endTime!.timeIntervalSince(session.startTime))
                    }
                    
                    let totalHours = totalTime / 3600
                    let totalMinutes = (totalTime % 3600) / 60
                    
                    statsText += "\n📊 *Итого:* \(totalHours)ч \(totalMinutes)м"
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: statsText,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("Ошибка при получении статистики: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении статистики.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    // Новая команда для управления проектами
    private func commandProjectsHandler() async {
        await add(
            TGCommandHandler(commands: ["/projects", "/проекты", "/projects@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self else { return }
                let chat = message.chat
                
                do {
                    // Получаем все проекты
                    let allProjects = try await Project.query(on: app.db)
                        .all()
                    
                    if allProjects.isEmpty {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: """
                            📂 *Проекты*
                            
                            Список проектов пуст.
                            
                            ℹ️ Чтобы добавить проект, обратитесь к администратору.
                            """,
                            parseMode: .html,
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    var projectsText = "📂 *СПИСОК ПРОЕКТОВ*\n\n"
                    
                    for (index, project) in allProjects.enumerated() {
                        projectsText += "\(index + 1). *\(project.name)*\n"
                        projectsText += "   🔑 Код: \(project.id?.uuidString.prefix(8) ?? "N/A")\n\n"
                    }
                    
                    projectsText += """
                    
                    📊 Для просмотра статистики по проектам используйте /stats
                    """
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: projectsText,
                        parseMode: .html,
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("Ошибка при получении списка проектов: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении списка проектов.",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    // Новая команда: статистика по всем пользователям за текущий месяц
    private func commandAdminStatsHandler() async {
        await add(
            TGCommandHandler(commands: ["/adminstats", "/админстат", "/adminstats@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId else {
                    return
                }
                
                guard let self else { return }
                let chat = message.chat
                
                /* команда временно доступна всем
                 // Список ID администраторов
                 let adminUserIds: [Int64] = [296089632, 448044251]
                 
                 // Проверяем, является ли пользователь администратором
                 guard let user = message.from,
                 adminUserIds.contains(user.id) else {
                 let params: TGSendMessageParams = .init(
                 chatId: .chat(chat.id),
                 text: "⛔ У вас нет доступа к этой команде.",
                 replyParameters: TGReplyParameters.init(messageId: messageID)
                 )
                 try await bot.sendMessage(params: params)
                 return
                 }
                 */
                
                do {
                    
                    // Получаем первый и последний день текущего месяца
                    let calendar = Calendar.current
                    let now = Date()
                    
                    guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                          let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
                        throw Abort(.internalServerError, reason: "Не удалось определить даты месяца")
                    }
                    
                    // Форматируем даты для фильтрации
                    let dbDateFormatter = DateFormatter()
                    dbDateFormatter.dateFormat = "yyyy-MM-dd"
                    
                    let monthStartStr = dbDateFormatter.string(from: monthStart)
                    let monthEndStr = dbDateFormatter.string(from: monthEnd)
                    
                    app.logger.info("🔍 Поиск данных за период: \(monthStartStr) - \(monthEndStr)")
                    
                    // Получаем все рабочие дни за текущий месяц
                    let allWorkDays = try await UserWorkDay.query(on: app.db)
                        .filter(\.$date >= monthStartStr)
                        .filter(\.$date <= monthEndStr)
                        .with(\.$workSessions) {
                            $0.with(\.$project) // Загружаем проекты для сессий
                        }
                        .all()
                    
                    app.logger.info("📁 Найдено рабочих дней: \(allWorkDays.count)")
                    
                    // Форматируем даты для отображения
                    let displayDateFormatter = DateFormatter()
                    displayDateFormatter.dateFormat = "dd.MM.yyyy"
                    let monthStartDisplay = displayDateFormatter.string(from: monthStart)
                    let monthEndDisplay = displayDateFormatter.string(from: monthEnd)
                    
                    displayDateFormatter.dateFormat = "MMMM yyyy"
                    let monthName = displayDateFormatter.string(from: now)
                    
                    if allWorkDays.isEmpty {
                        let allDates = try await UserWorkDay.query(on: app.db)
                            .field(\.$date)
                            .all()
                            .map { $0.date }
                            .sorted()
                        
                        app.logger.info("📅 Все доступные даты в базе: \(allDates)")
                        
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: """
                            📊 *Статистика за \(monthName)*
                            
                            Период: \(monthStartDisplay) - \(monthEndDisplay)
                            
                            ❌ Нет данных о работе за текущий месяц.
                            
                            🔍 Поиск по датам: \(monthStartStr) - \(monthEndStr)
                            📅 Всего дат в базе: \(allDates.count)
                            """,
                            parseMode: .html,
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Статистика по проектам
                    var projectStats: [UUID?: (name: String, time: Double, sessions: Int)] = [:]
                    
                    // Группируем данные по пользователям
                    var userStats: [Int64: MonthlyUserStats] = [:]
                    
                    for workDay in allWorkDays {
                        let userId = workDay.telegramUserId
                        app.logger.debug("📅 Обработка дня: \(workDay.date) для пользователя \(userId)")
                        
                        if userStats[userId] == nil {
                            userStats[userId] = MonthlyUserStats(
                                userId: userId,
                                username: workDay.telegramUsername ?? "Без имени",
                                firstName: workDay.telegramFirstName ?? "Неизвестно",
                                lastName: workDay.telegramLastName,
                                workDaysCount: 0,
                                totalSessions: 0,
                                totalTime: 0,
                                lastActivity: nil
                            )
                        }
                        
                        var stats = userStats[userId]!
                        stats.workDaysCount += 1
                        
                        let sessions = workDay.workSessions
                        stats.totalSessions += sessions.count
                        
                        for session in sessions {
                            if let endTime = session.endTime {
                                let duration = endTime.timeIntervalSince(session.startTime)
                                stats.totalTime += duration
                                
                                /*
                                 // Обновляем статистику по проекту
                                 if let project = session.project {
                                 var projectStat = projectStats[project.id] ?? (name: project.name, time: 0, sessions: 0)
                                 projectStat.time += duration
                                 projectStat.sessions += 1
                                 projectStats[project.id] = projectStat
                                 }
                                 */
                                app.logger.debug("⏱️ Сессия: \(duration) секунд")
                            }
                            
                            if stats.lastActivity == nil || session.startTime > stats.lastActivity! {
                                stats.lastActivity = session.startTime
                            }
                        }
                        
                        userStats[userId] = stats
                    }
                    
                    app.logger.info("👥 Найдено пользователей: \(userStats.count)")
                    
                    let totalMonthTime = userStats.values.reduce(0) { $0 + $1.totalTime }
                    
                    if totalMonthTime == 0 {
                        var hasActiveSessions = false
                        for workDay in allWorkDays {
                            for session in workDay.workSessions {
                                if session.endTime == nil {
                                    hasActiveSessions = true
                                    break
                                }
                            }
                        }
                        
                        if hasActiveSessions {
                            let params: TGSendMessageParams = .init(
                                chatId: .chat(chat.id),
                                text: """
                                📊 *Статистика за \(monthName)*
                                
                                Период: \(monthStartDisplay) - \(monthEndDisplay)
                                
                                ℹ️ Есть активные сессии, но нет завершенных сессий с временем работы.
                                Используйте /end чтобы завершить текущие сессии.
                                
                                👥 Пользователей: \(userStats.count)
                                📅 Рабочих дней: \(allWorkDays.count)
                                """,
                                parseMode: .html,
                                replyParameters: TGReplyParameters.init(messageId: messageID)
                            )
                            try await bot.sendMessage(params: params)
                            return
                        }
                    }
                    
                    let sortedUsers = userStats.values.sorted { $0.totalTime > $1.totalTime }
                    
                    let timeDateFormatter = DateFormatter()
                    timeDateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                    
                    var statsText = """
                    👑 *СТАТИСТИКА ЗА \(monthName.uppercased())*
                    
                    📅 Период: \(monthStartDisplay) - \(monthEndDisplay)
                    👥 Всего активных пользователей: \(userStats.count)
                    📊 Всего рабочих дней: \(allWorkDays.count)
                    """
                    
                    // Добавляем статистику по проектам
                    if !projectStats.isEmpty {
                        statsText += "\n\n📂 *СТАТИСТИКА ПО ПРОЕКТАМ:*\n"
                        
                        for (_, stat) in projectStats.sorted(by: { $0.value > $1.value }) {
                            let hours = Int(stat.time) / 3600
                            let minutes = (Int(stat.time) % 3600) / 60
                            let percentage = (stat.time / totalMonthTime * 100).rounded(toPlaces: 1)
                            
                            statsText += "• \(stat.name): \(hours)ч \(minutes)м (\(stat.sessions) сессий) - \(percentage)%\n"
                        }
                    }
                    
                    if totalMonthTime > 0 {
                        statsText += """
                        
                        📈 *РАСПРЕДЕЛЕНИЕ ПО УЧАСТИЮ:*
                        
                        """
                        
                        for (index, userStat) in sortedUsers.enumerated() {
                            let percentage = (userStat.totalTime / totalMonthTime * 100).rounded(toPlaces: 1)
                            let totalHours = Int(userStat.totalTime) / 3600
                            let totalMinutes = (Int(userStat.totalTime) % 3600) / 60
                            
                            let lastActivity = userStat.lastActivity.map { timeDateFormatter.string(from: $0) } ?? "Нет данных"
                            
                            let progressBar = createProgressBar(percentage: percentage)
                            
                            statsText += """
                            
                            \(index + 1). *\(userStat.firstName)*\(userStat.lastName != nil ? " \(userStat.lastName!)" : "")
                               👤 @\(userStat.username)
                               📅 Дней работы: \(userStat.workDaysCount)
                               📈 Сессий: \(userStat.totalSessions)
                               🕐 Всего времени: \(totalHours)ч \(totalMinutes)м
                               📊 Участие: \(percentage)%
                               \(progressBar)
                               ⏰ Последняя активность: \(lastActivity)
                            """
                        }
                        
                        let totalMonthHours = Int(totalMonthTime) / 3600
                        let totalMonthMinutes = (Int(totalMonthTime) % 3600) / 60
                        
                        let avgTimePerUser = totalMonthTime / Double(userStats.count)
                        let avgHours = Int(avgTimePerUser) / 3600
                        let avgMinutes = (Int(avgTimePerUser) % 3600) / 60
                        
                        statsText += """
                        
                        📊 *ОБЩАЯ СТАТИСТИКА МЕСЯЦА:*
                        
                        🕐 Всего времени работы: \(totalMonthHours)ч \(totalMonthMinutes)м
                        👥 Среднее на пользователя: \(avgHours)ч \(avgMinutes)м
                        📈 Всего сессий: \(sortedUsers.reduce(0) { $0 + $1.totalSessions })
                        📅 Всего рабочих дней: \(allWorkDays.count)
                        
                        ⭐ *ЛУЧШИЙ РЕЗУЛЬТАТ МЕСЯЦА:*
                        🥇 \(sortedUsers.first?.firstName ?? "Нет данных") - \(Int(sortedUsers.first?.totalTime ?? 0) / 3600)ч
                        """
                        
                        if let topUser = sortedUsers.first, topUser.totalTime > 0 {
                            let topPercentage = (topUser.totalTime / totalMonthTime * 100).rounded(toPlaces: 1)
                            
                            if topPercentage > 50 {
                                statsText += "\n\n⚠️ *ВНИМАНИЕ:* Один пользователь выполняет \(topPercentage)% всей работы"
                            }
                        }
                        
                    } else {
                        statsText += """
                        
                        ℹ️ *ОСНОВНАЯ СТАТИСТИКА:*
                        
                        """
                        
                        for (index, userStat) in sortedUsers.enumerated() {
                            let lastActivity = userStat.lastActivity.map { timeDateFormatter.string(from: $0) } ?? "Нет данных"
                            
                            statsText += """
                            
                            \(index + 1). *\(userStat.firstName)*\(userStat.lastName != nil ? " \(userStat.lastName!)" : "")
                               👤 @\(userStat.username)
                               📅 Дней работы: \(userStat.workDaysCount)
                               📈 Сессий: \(userStat.totalSessions)
                               ⏰ Последняя активность: \(lastActivity)
                            """
                        }
                    }
                    
                    if statsText.count > 4000 {
                        let parts = statsText.splitByLength(4000)
                        for (index, part) in parts.enumerated() {
                            let params: TGSendMessageParams = .init(
                                chatId: .chat(chat.id),
                                text: "Часть \(index + 1) из \(parts.count)\n\n\(part)",
                                parseMode: .html,
                                replyParameters: index == 0 ? TGReplyParameters.init(messageId: messageID) : nil
                            )
                            try await bot.sendMessage(params: params)
                        }
                    } else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: statsText,
                            parseMode: .html,
                            replyParameters: TGReplyParameters.init(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                    }
                    
                } catch {
                    app.logger.error("Ошибка при получении административной статистики: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении статистики: \(error.localizedDescription)",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    
    private func commandDebugHandler() async {
        await add(
            TGCommandHandler(commands: ["/debug", "/отладка"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                let adminUserIds: [Int64] = [296089632, 448044251]
                guard adminUserIds.contains(user.id) else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(message.chat.id),
                        text: "⛔ Только администратор может использовать эту команду.",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await self?.bot.sendMessage(params: params)
                    return
                }
                
                guard let self else { return }
                
                do {
                    // Получаем ВСЕ рабочие дни с сессиями и проектами
                    let allWorkDays = try await UserWorkDay.query(on: app.db)
                        .with(\.$workSessions) {
                            $0.with(\.$project)
                        }
                        .with(\.$project)
                        .sort(\.$date, .descending)
                        .all()
                    
                    // Получаем все проекты
                    let allProjects = try await Project.query(on: app.db).all()
                    
                    var debugInfo = "🔧 *ДЕТАЛЬНАЯ ОТЛАДКА ДАННЫХ*\n\n"
                    
                    debugInfo += "📊 *ОБЩАЯ СТАТИСТИКА:*\n"
                    debugInfo += "• Всего записей рабочих дней: \(allWorkDays.count)\n"
                    debugInfo += "• Всего проектов: \(allProjects.count)\n\n"
                    
                    // Информация о проектах
                    debugInfo += "📂 *СПИСОК ПРОЕКТОВ:*\n"
                    if allProjects.isEmpty {
                        debugInfo += "❌ Нет проектов\n\n"
                    } else {
                        for project in allProjects {
                            debugInfo += "• \(project.name) (ID: \(project.id?.uuidString.prefix(8) ?? "N/A"))\n"
                        }
                        debugInfo += "\n"
                    }
                    
                    // Детальная информация по каждому дню
                    debugInfo += "📅 *ДЕТАЛИ ПО КАЖДОМУ ДНЮ:*\n\n"
                    
                    if allWorkDays.isEmpty {
                        debugInfo += "❌ Нет данных о рабочих днях\n"
                    } else {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                        
                        for (index, workDay) in allWorkDays.enumerated() {
                            debugInfo += "\(index + 1). *\(workDay.date)*\n"
                            debugInfo += "   👤 Пользователь: \(workDay.telegramFirstName ?? "Неизвестно") (ID: \(workDay.telegramUserId))\n"
                            debugInfo += "   📝 Username: @\(workDay.telegramUsername ?? "нет")\n"
                            
                            // Информация о проекте дня
                            if let project = workDay.project {
                                debugInfo += "   📂 Проект дня: \(project.name)\n"
                            }
                            
                            debugInfo += "   📊 Всего сессий: \(workDay.workSessions.count)\n"
                            debugInfo += "   📅 Создан: \(workDay.createdAt != nil ? dateFormatter.string(from: workDay.createdAt!) : "неизвестно")\n\n"
                            
                            if workDay.workSessions.isEmpty {
                                debugInfo += "   ❌ Нет сессий\n\n"
                            } else {
                                for (sessionIndex, session) in workDay.workSessions.enumerated() {
                                    let startTime = dateFormatter.string(from: session.startTime)
                                    let endTime = session.endTime.map { dateFormatter.string(from: $0) } ?? "ЕЩЁ НЕ ЗАВЕРШЕНА"
                                    let duration = session.endTime != nil ?
                                    "\(Int(session.endTime!.timeIntervalSince(session.startTime)) / 60) мин" :
                                    "АКТИВНА"
                                    
                                    debugInfo += "   \(sessionIndex + 1). Сессия\n"
                                    debugInfo += "      🕐 Начало: \(startTime)\n"
                                    debugInfo += "      🕐 Конец: \(endTime)\n"
                                    debugInfo += "      ⏱️ Длительность: \(duration)\n"
                                    
                                    /*
                                     // Информация о проекте сессии
                                     if let project = session.project {
                                     debugInfo += "      📂 Проект: \(project.name)\n"
                                     }
                                     */
                                    debugInfo += "      📝 Тип: \(session.sessionType)\n"
                                    debugInfo += "      📅 Создана: \(session.createdAt != nil ? dateFormatter.string(from: session.createdAt!) : "неизвестно")\n\n"
                                }
                            }
                            
                            debugInfo += "---\n\n"
                        }
                    }
                    
                    // Статистика по месяцам
                    debugInfo += "📈 *СТАТИСТИКА ПО МЕСЯЦАМ:*\n\n"
                    
                    var months: [String: Int] = [:]
                    for workDay in allWorkDays {
                        let components = workDay.date.split(separator: "-")
                        if components.count >= 2 {
                            let year = components[0]
                            let month = components[1]
                            let key = "\(year)-\(month)"
                            months[key, default: 0] += 1
                        }
                    }
                    
                    for (month, count) in months.sorted(by: { $0.key > $1.key }) {
                        debugInfo += "• \(month): \(count) дней\n"
                    }
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(message.chat.id),
                        text: debugInfo,
                        parseMode: .html,
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("Ошибка в отладочной команде: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(message.chat.id),
                        text: "❌ Ошибка: \(error.localizedDescription)",
                        replyParameters: TGReplyParameters.init(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandAddProjectHandler() async {
        await add(
            TGCommandHandler(commands: ["/addproject", "/newproject", "/addproject@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self = self else { return }
                let chat = message.chat
                
                // Только для администратора
                let adminUserIds: [Int64] = [296089632, 448044251] // Ваш ID
                guard adminUserIds.contains(user.id) else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "⛔ Только администратор может добавлять проекты.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                // Получаем текст команды
                let commandText = message.text ?? ""
                let parts = commandText.split(separator: " ", maxSplits: 1)
                
                // Проверяем формат: /addproject Название проекта
                guard parts.count == 2 else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ℹ️ *Использование команды:*
                        /addproject Название проекта
                        
                        *Пример:*
                        /addproject Разработка iOS
                        /addproject Дизайн интерфейса
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                let projectName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Проверяем, не пустое ли название
                guard !projectName.isEmpty else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Название проекта не может быть пустым.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                do {
                    // Проверяем, существует ли уже проект с таким именем
                    let existingProject = try await Project.query(on: app.db)
                        .filter(\.$name == projectName)
                        .first()
                    
                    if existingProject != nil {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "⚠️ Проект с названием '\(projectName)' уже существует.",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Создаем новый проект
                    let project = Project(name: projectName)
                    try await project.save(on: app.db)
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ✅ *Проект создан успешно!*
                        
                        📂 *Название:* \(projectName)
                        🔑 *ID:* \(project.id?.uuidString.prefix(8) ?? "N/A")
                        
                        🗄️ Используйте /projects для просмотра всех проектов.
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("❌ Ошибка при создании проекта: \(String(reflecting: error))")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при создании проекта: \(error.localizedDescription)",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandDeleteProjectHandler() async {
        await add(
            TGCommandHandler(commands: ["/deleteproject", "/delproject", "/removeproject", "/deleteproject@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self = self else { return }
                let chat = message.chat
                
                // Только для администратора
                let adminUserIds: [Int64] = [296089632, 448044251]
                guard adminUserIds.contains(user.id) else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "⛔ Только администратор может удалять проекты.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                // Получаем текст команды
                let commandText = message.text ?? ""
                let parts = commandText.split(separator: " ", maxSplits: 2)
                
                // Проверяем формат
                guard parts.count >= 2 else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ℹ️ *Использование команды:*
                        /deleteproject [ID или название] [force]
                        
                        *Примеры:*
                        /deleteproject Разработка iOS
                        /deleteproject DC0A02F5
                        /deleteproject Ново-Огарево force (принудительное удаление)
                        
                        🗄️ Используйте /projects для просмотра списка проектов.
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                let identifier = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let forceDelete = parts.count == 3 && String(parts[2]).lowercased() == "force"
                
                do {
                    var projectToDelete: Project?
                    
                    // 1. Пытаемся найти проект по полному UUID
                    if let projectId = UUID(uuidString: identifier) {
                        projectToDelete = try await Project.find(projectId, on: app.db)
                    }
                    
                    // 2. Если не нашли по полному UUID, ищем по первым 8 символам
                    if projectToDelete == nil && identifier.count >= 8 {
                        let allProjects = try await Project.query(on: app.db).all()
                        projectToDelete = allProjects.first { project in
                            project.id?.uuidString.hasPrefix(identifier.uppercased()) ?? false
                        }
                    }
                    
                    // 3. Если не нашли по ID, ищем по названию
                    if projectToDelete == nil {
                        projectToDelete = try await Project.query(on: app.db)
                            .filter(\.$name == identifier)
                            .first()
                    }
                    
                    // Проверяем, найден ли проект
                    guard let project = projectToDelete else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "❌ Проект не найден.\nИспользуйте полный ID, первые 8 символов ID или точное название проекта.",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Проверяем, используется ли проект в сессиях
                    let sessionsUsingProject = try await WorkSession.query(on: app.db)
                        .filter(\.$project.$id == project.requireID())
                        .count()
                    
                    if sessionsUsingProject > 0 && !forceDelete {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: """
                            ⚠️ *Нельзя удалить проект!*
                            
                            Проект "\(project.name)" используется в \(sessionsUsingProject) сессиях.
                            
                            *Варианты:*
                            1. Используйте `/deleteproject \(identifier) force` для принудительного удаления
                            2. Сначала удалите связанные сессии вручную
                            
                            ⚠️ Принудительное удаление очистит проект из всех сессий!
                            """,
                            parseMode: .html,
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Если принудительное удаление, очищаем связи
                    if forceDelete && sessionsUsingProject > 0 {
                        app.logger.info("🧹 Очищаем связи проекта \(project.name) из сессий...")
                        
                        // Обновляем все сессии, удаляя ссылку на проект
                        try await WorkSession.query(on: app.db)
                            .filter(\.$project.$id == project.requireID())
                            .set(\.$project.$id, to: nil as UUID?)
                            .update()
                        
                        app.logger.info("✅ Связи очищены")
                    }
                    
                    // Удаляем проект
                    try await project.delete(on: app.db)
                    
                    let deletionType = forceDelete ? "принудительно" : "успешно"
                    let sessionsCleaned = forceDelete ? "\n🧹 Удалено связей: \(sessionsUsingProject) сессий" : ""
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ✅ *Проект удален \(deletionType)!*
                        
                        📂 *Название:* \(project.name)
                        🔑 *Полный ID:* \(project.id?.uuidString ?? "N/A")
                        \(sessionsCleaned)
                        
                        🗄️ Проект удален из базы данных.
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    // Просто выводим всю информацию об ошибке
                    app.logger.error("❌ ДЕТАЛЬНАЯ ОШИБКА при удалении проекта:")
                    app.logger.error("\(String(reflecting: error))")
                    
                    // Разбираем ошибку как строку
                    let errorString = String(reflecting: error)
                    
                    // Ищем PSQL информацию в строке
                    if errorString.contains("PSQLError") {
                        app.logger.error("🔍 Это PSQL ошибка")
                        
                        // Извлекаем информацию из строки
                        if let range = errorString.range(of: "message: ") {
                            let messageStart = errorString[range.upperBound...]
                            if let endRange = messageStart.range(of: ",") {
                                let message = String(messageStart[..<endRange.lowerBound])
                                app.logger.error("   Сообщение: \(message)")
                            }
                        }
                        
                        if let range = errorString.range(of: "sqlState: ") {
                            let sqlStateStart = errorString[range.upperBound...]
                            if let endRange = sqlStateStart.range(of: ",") {
                                let sqlState = String(sqlStateStart[..<endRange.lowerBound])
                                app.logger.error("   SQL State: \(sqlState)")
                            }
                        }
                    }
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при удалении проекта.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandProjectSessionsHandler() async {
        await add(
            TGCommandHandler(commands: ["/projectsessions", "/projectsessions@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self = self else { return }
                let chat = message.chat
                
                // Только для администратора
                let adminUserIds: [Int64] = [296089632, 448044251]
                guard adminUserIds.contains(user.id) else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "⛔ Только администратор может просматривать сессии проектов.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                // Получаем текст команды
                let commandText = message.text ?? ""
                let parts = commandText.split(separator: " ", maxSplits: 1)
                
                guard parts.count == 2 else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        ℹ️ *Использование команды:*
                        /projectsessions [ID или название проекта]
                        
                        *Пример:*
                        /projectsessions Ново-Огарево
                        /projectsessions DC0A02F5
                        
                        🗄️ Показывает все сессии, связанные с проектом.
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                let identifier = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                do {
                    var project: Project?
                    
                    // Поиск проекта
                    if let projectId = UUID(uuidString: identifier) {
                        project = try await Project.find(projectId, on: app.db)
                    }
                    
                    if project == nil && identifier.count >= 8 {
                        let allProjects = try await Project.query(on: app.db).all()
                        project = allProjects.first { $0.id?.uuidString.hasPrefix(identifier.uppercased()) ?? false }
                    }
                    
                    if project == nil {
                        project = try await Project.query(on: app.db)
                            .filter(\.$name == identifier)
                            .first()
                    }
                    
                    guard let project = project else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "❌ Проект не найден.",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Получаем сессии проекта
                    let sessions = try await WorkSession.query(on: app.db)
                        .filter(\.$project.$id == project.requireID())
                        .with(\.$workDay)
                        .sort(\.$startTime, .descending)
                        .all()
                    
                    if sessions.isEmpty {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: """
                            📊 *Сессии проекта "\(project.name)"*
                            
                            🗄️ Проект не используется в сессиях.
                            ✅ Можно безопасно удалить командой:
                            /deleteproject \(project.id?.uuidString.prefix(8) ?? "")
                            """,
                            parseMode: .html,
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                    
                    var sessionsText = "📊 *Сессии проекта \"\(project.name)\"*\n\n"
                    sessionsText += "🔢 Всего сессий: \(sessions.count)\n\n"
                    
                    for (index, session) in sessions.prefix(10).enumerated() {
                        let startTime = dateFormatter.string(from: session.startTime)
                        let endTime = session.endTime.map { dateFormatter.string(from: $0) } ?? "В процессе"
                        
                        sessionsText += "\(index + 1). \(startTime) - \(endTime)\n"
                        
                        let workDay = session.workDay
                        sessionsText += "   👤 Пользователь: \(workDay.telegramFirstName ?? "Неизвестно")\n"
                        sessionsText += "   📅 Дата: \(workDay.date)\n"
                        
                        
                        sessionsText += "\n"
                    }
                    
                    if sessions.count > 10 {
                        sessionsText += "📋 ... и еще \(sessions.count - 10) сессий\n"
                    }
                    
                    sessionsText += """
                    
                    ⚠️ *Для удаления проекта нужно:*
                    1. Удалить эти сессии или изменить их проект
                    2. Или использовать `/deleteproject \(identifier) force`
                    """
                    
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: sessionsText,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    
                    try await bot.sendMessage(params: params)
                    
                } catch {
                    app.logger.error("❌ Ошибка при получении сессий проекта: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении сессий проекта.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandProjectStatsHandler() async {
        await add(
            TGCommandHandler(commands: ["/projectstats", "/projectstat", "/статистикапроекта", "/projectstats@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let user = message.from else {
                    return
                }
                
                guard let self = self else { return }
                let chat = message.chat
                
                // Только для администратора
                let adminUserIds: [Int64] = [296089632, 448044251]
                guard adminUserIds.contains(user.id) else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "⛔ Только администратор может просматривать статистику проектов.",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                // Получаем текст команды (если есть фильтр по проекту)
                let commandText = message.text ?? ""
                let parts = commandText.split(separator: " ", maxSplits: 1)
                
                var filterProjectId: UUID? = nil
                var filterProjectName: String? = nil
                
                // Если указан фильтр проекта
                if parts.count == 2 {
                    let identifier = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    do {
                        var project: Project?
                        
                        // Поиск проекта по ID
                        if let projectId = UUID(uuidString: identifier) {
                            project = try await Project.find(projectId, on: app.db)
                        }
                        
                        // Поиск по первым 8 символам
                        if project == nil && identifier.count >= 8 {
                            let allProjects = try await Project.query(on: app.db).all()
                            project = allProjects.first { $0.id?.uuidString.hasPrefix(identifier.uppercased()) ?? false }
                        }
                        
                        // Поиск по названию
                        if project == nil {
                            project = try await Project.query(on: app.db)
                                .filter(\.$name == identifier)
                                .first()
                        }
                        
                        if let project = project {
                            filterProjectId = project.id
                            filterProjectName = project.name
                        } else {
                            let params: TGSendMessageParams = .init(
                                chatId: .chat(chat.id),
                                text: "⚠️ Проект не найден. Показана статистика по всем проектам.",
                                replyParameters: TGReplyParameters(messageId: messageID)
                            )
                            try await bot.sendMessage(params: params)
                            // Продолжаем без фильтра
                        }
                    } catch {
                        app.logger.error("❌ Ошибка при поиске проекта: \(error)")
                    }
                }
                
                do {
                    app.logger.info("📊 Запрос статистики по проектам от пользователя \(user.id)")
                    
                    // Получаем все проекты если не указан фильтр
                    let projects: [Project]
                    if let filterProjectId = filterProjectId {
                        if let project = try await Project.find(filterProjectId, on: app.db) {
                            projects = [project]
                        } else {
                            projects = []
                        }
                    } else {
                        projects = try await Project.query(on: app.db).all()
                    }
                    
                    if projects.isEmpty {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: "📊 Нет проектов в базе данных.\nИспользуйте /addproject чтобы добавить проект.",
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                        return
                    }
                    
                    // Получаем все сессии за все время с проектами
                    let allSessions = try await WorkSession.query(on: app.db)
                        .filter(\.$project.$id != nil) // Только сессии с проектами
                        .with(\.$project)
                        .with(\.$workDay)
                        .all()
                    
                    app.logger.info("📁 Найдено сессий с проектами: \(allSessions.count)")
                    
                    // Группируем данные по проектам
                    var projectStats: [UUID: (project: Project, totalTime: Double, sessions: Int, users: [Int64: Double])] = [:]
                    
                    for session in allSessions {
                        guard let project = session.project,
                              let projectId = project.id,
                              let endTime = session.endTime else {
                            continue
                        }
                        
                        let duration = endTime.timeIntervalSince(session.startTime)
                        
                        if projectStats[projectId] == nil {
                            projectStats[projectId] = (project: project, totalTime: 0, sessions: 0, users: [:])
                        }
                        
                        var stats = projectStats[projectId]!
                        stats.totalTime += duration
                        stats.sessions += 1
                        
                        // Добавляем время пользователя
                        let userId = session.workDay.telegramUserId
                        stats.users[userId, default: 0] += duration
                        
                        projectStats[projectId] = stats
                    }
                    
                    // Если указан фильтр по проекту, оставляем только его
                    if let filterProjectId = filterProjectId {
                        projectStats = projectStats.filter { $0.key == filterProjectId }
                    }
                    
                    // Форматируем статистику
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd.MM.yyyy HH:mm"
                    let currentDate = dateFormatter.string(from: Date())
                    
                    var statsText = ""
                    
                    if let filterProjectName = filterProjectName {
                        statsText = "📊 *СТАТИСТИКА ПРОЕКТА \"\(filterProjectName.uppercased())\"*\n\n"
                    } else {
                        statsText = "📊 *СТАТИСТИКА ПО ВСЕМ ПРОЕКТАМ*\n\n"
                    }
                    
                    statsText += "📅 Дата отчета: \(currentDate)\n"
                    statsText += "📂 Всего проектов: \(projectStats.count)\n"
                    statsText += "📈 Всего сессий с проектами: \(allSessions.count)\n\n"
                    
                    // Сортируем проекты по общему времени (по убыванию)
                    let sortedProjects = projectStats.values.sorted { $0.totalTime > $1.totalTime }
                    
                    // Общее время всех проектов
                    let totalAllProjectsTime = sortedProjects.reduce(0) { $0 + $1.totalTime }
                    
                    for (index, stats) in sortedProjects.enumerated() {
                        let projectHours = Int(stats.totalTime) / 3600
                        let projectMinutes = (Int(stats.totalTime) % 3600) / 60
                        
                        // Процент от общего времени
                        let percentage = totalAllProjectsTime > 0 ?
                        (stats.totalTime / totalAllProjectsTime * 100).rounded(toPlaces: 1) : 0
                        
                        statsText += "\(index + 1). *\(stats.project.name)*\n"
                        statsText += "   🔑 ID: \(stats.project.id?.uuidString.prefix(8) ?? "N/A")\n"
                        statsText += "   🕐 Всего времени: \(projectHours)ч \(projectMinutes)м\n"
                        statsText += "   📈 Сессий: \(stats.sessions)\n"
                        statsText += "   👥 Участников: \(stats.users.count)\n"
                        statsText += "   📊 Участие: \(percentage)%\n"
                        
                        // Прогресс-бар
                        let progressBar = createProgressBar(percentage: percentage, length: 10)
                        statsText += "   \(progressBar)\n"
                        
                        // Топ участников проекта
                        if !stats.users.isEmpty {
                            let sortedUsers = stats.users.sorted { $0.value > $1.value }
                            
                            statsText += "   \n   🥇 *ТОП УЧАСТНИКОВ:*\n"
                            
                            for (userIndex, (userId, userTime)) in sortedUsers.prefix(3).enumerated() {
                                let userHours = Int(userTime) / 3600
                                let userMinutes = (Int(userTime) % 3600) / 60
                                let userPercentage = (userTime / stats.totalTime * 100).rounded(toPlaces: 1)
                                
                                let medal = userIndex == 0 ? "🥇" : userIndex == 1 ? "🥈" : "🥉"
                                
                                // Получаем информацию о пользователе
                                let userWorkDay = try await UserWorkDay.query(on: app.db)
                                    .filter(\.$telegramUserId == userId)
                                    .first()
                                
                                let userName = userWorkDay?.telegramFirstName ?? "Пользователь \(userId)"
                                
                                statsText += "   \(medal) \(userName): \(userHours)ч \(userMinutes)м (\(userPercentage)%)\n"
                            }
                            
                            // Если участников больше 3
                            if stats.users.count > 3 {
                                statsText += "   ... и еще \(stats.users.count - 3) участников\n"
                            }
                        } else {
                            statsText += "   👥 Нет данных об участниках\n"
                        }
                        
                        // Распределение по дням (последние 7 дней)
                        let calendar = Calendar.current
                        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                        dateFormatter.dateFormat = "yyyy-MM-dd"
                        
                        let recentSessions = allSessions.filter { session in
                            guard let project = session.project,
                                  project.id == stats.project.id,
                                  let endTime = session.endTime else {
                                return false
                            }
                            return endTime > weekAgo
                        }
                        
                        if !recentSessions.isEmpty {
                            var dayStats: [String: Double] = [:]
                            for session in recentSessions {
                                guard let endTime = session.endTime else { continue }
                                dateFormatter.dateFormat = "yyyy-MM-dd"
                                let dayKey = dateFormatter.string(from: endTime)
                                let duration = endTime.timeIntervalSince(session.startTime)
                                dayStats[dayKey, default: 0] += duration
                            }
                            
                            if !dayStats.isEmpty {
                                statsText += "   \n   📅 *АКТИВНОСТЬ ЗА 7 ДНЕЙ:*\n"
                                let sortedDays = dayStats.sorted(by: { $0.key > $1.key })
                                
                                for (day, dayTime) in sortedDays.prefix(3) {
                                    dateFormatter.dateFormat = "dd.MM"
                                    let displayDay = dateFormatter.string(from: dateFormatter.date(from: day) ?? Date())
                                    let dayHours = Int(dayTime) / 3600
                                    let dayMinutes = (Int(dayTime) % 3600) / 60
                                    
                                    statsText += "   📍 \(displayDay): \(dayHours)ч \(dayMinutes)м\n"
                                }
                            }
                        }
                        
                        statsText += "\n"
                    }
                    
                    // Общая статистика
                    if filterProjectId == nil && projectStats.count > 1 {
                        let totalHours = Int(totalAllProjectsTime) / 3600
                        let totalMinutes = (Int(totalAllProjectsTime) % 3600) / 60
                        
                        let avgTimePerProject = totalAllProjectsTime / Double(projectStats.count)
                        let avgHours = Int(avgTimePerProject) / 3600
                        let avgMinutes = (Int(avgTimePerProject) % 3600) / 60
                        
                        statsText += """
                        \n📊 *ОБЩАЯ СТАТИСТИКА:*
                        
                        🕐 Общее время по проектам: \(totalHours)ч \(totalMinutes)м
                        📂 Среднее на проект: \(avgHours)ч \(avgMinutes)м
                        👥 Всего уникальных участников: \(Set(allSessions.map { $0.workDay.telegramUserId }).count)
                        
                        ⭐ *САМЫЙ АКТИВНЫЙ ПРОЕКТ:*
                        🥇 \(sortedProjects.first?.project.name ?? "Нет данных") - \(Int(sortedProjects.first?.totalTime ?? 0) / 3600)ч
                        
                        ℹ️ Для детальной статистики по конкретному проекту:
                        /projectstats [ID или название проекта]
                        """
                    }
                    
                    // Если статистика слишком длинная, разбиваем
                    if statsText.count > 4000 {
                        let parts = statsText.splitByLength(4000)
                        for (index, part) in parts.enumerated() {
                            let params: TGSendMessageParams = .init(
                                chatId: .chat(chat.id),
                                text: "Часть \(index + 1) из \(parts.count)\n\n\(part)",
                                parseMode: .html,
                                replyParameters: index == 0 ? TGReplyParameters(messageId: messageID) : nil
                            )
                            try await bot.sendMessage(params: params)
                        }
                    } else {
                        let params: TGSendMessageParams = .init(
                            chatId: .chat(chat.id),
                            text: statsText,
                            parseMode: .html,
                            replyParameters: TGReplyParameters(messageId: messageID)
                        )
                        try await bot.sendMessage(params: params)
                    }
                    
                } catch {
                    app.logger.error("❌ Ошибка при получении статистики проектов: \(error)")
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: "❌ Ошибка при получении статистики проектов: \(error.localizedDescription)",
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                }
            }
        )
    }
    
    private func commandGroupEndHandler() async {
        await add(
            TGCommandHandler(commands: ["/groupend", "/grend", "/groupend@time_tracker_swiftbot"]) { [weak self] update in
                guard let message = update.message,
                      let messageID = update.message?.messageId,
                      let fromUser = message.from else {
                    return
                }
                
                guard let self else { return }
                let chat = message.chat
                
                // Получаем текст команды
                let commandText = message.text ?? ""
                let parts = commandText.split(separator: " ", maxSplits: 1)
                
                // Если не указаны пользователи, показываем справку
                guard parts.count == 2 else {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: """
                        📋 *Использование команды /groupend*

                        *Примеры:*
                        /groupend @user1 @user2 @user3
                        /groupend user1 user2
                        /groupend all
                        """,
                        parseMode: .html,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                    return
                }
                
                let usernamesText = String(parts[1])
                
                // Создаем кнопку подтверждения
                var buttons: [[TGInlineKeyboardButton]] = []
                
                buttons.append([
                    TGInlineKeyboardButton(
                        text: "✅ Завершить сессии",
                        callbackData: "groupend_confirm:\(fromUser.id):\(usernamesText)"
                    )
                ])
                
                let keyboard = TGInlineKeyboardMarkup(inlineKeyboard: buttons)
                
                // Отправляем сообщение с кнопкой
                let params: TGSendMessageParams = .init(
                    chatId: .chat(chat.id),
                    text: """
                    🚀 *Групповое завершение сессий*
                    
                    Инициатор: @\(fromUser.username ?? fromUser.firstName)
                    Цель: \(usernamesText)
                    
                    Нажмите кнопку чтобы завершить сессии.
                    """,
                    parseMode: .html,
                    replyParameters: TGReplyParameters(messageId: messageID),
                    replyMarkup: .inlineKeyboardMarkup(keyboard)
                )
                
                try await bot.sendMessage(params: params)
            }
        )
        
        // Обработчик кнопки подтверждения
        await add(TGCallbackQueryHandler(pattern: "groupend_confirm:(\\d+):(.+)") { [weak self] update in
            guard let self = self,
                  let callbackQuery = update.callbackQuery,
                  let message = callbackQuery.message
            else {
                return
            }
            
            let chat = message.chat
            let callbackData = callbackQuery.data ?? ""
            let fromUser = callbackQuery.from
            
            // Извлекаем данные из callback
            let pattern = "groupend_confirm:(\\d+):(.+)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: callbackData, range: NSRange(callbackData.startIndex..., in: callbackData)),
                  let initiatorIdRange = Range(match.range(at: 1), in: callbackData),
                  let usernamesRange = Range(match.range(at: 2), in: callbackData) else {
                return
            }
            
            let initiatorId = Int64(callbackData[initiatorIdRange]) ?? 0
            let usernamesText = String(callbackData[usernamesRange])
            
            // Проверяем, что нажал тот же пользователь
            if fromUser.id != initiatorId {
                try await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                    callbackQueryId: callbackQuery.id,
                    text: "❌ Только инициатор может подтвердить",
                    showAlert: true
                ))
                return
            }
            
            // Отвечаем на callback
            try await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                callbackQueryId: callbackQuery.id,
                text: "✅ Завершаю сессии...",
                showAlert: false
            ))
            
            // Обновляем сообщение
            try await bot.editMessageText(params: TGEditMessageTextParams(
                chatId: .chat(chat.id),
                messageId: message.messageId,
                text: "\n\n⏳ Выполняется...",
                parseMode: .html
            ))
            
            // Выполняем групповое завершение
            await self.executeGroupEnd(
                chatId: chat.id,
                initiatorUsername: fromUser.username ?? fromUser.firstName,
                usernamesText: usernamesText
            )
        })
    }
    
    // Функция выполнения группового завершения
    private func executeGroupEnd(chatId: Int64, initiatorUsername: String, usernamesText: String) async {
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let today = dateFormatter.string(from: Date())
            
            // Получаем всех активных пользователей за сегодня
            let allActiveUsers = try await UserWorkDay.query(on: app.db)
                .filter(\.$date == today)
                .with(\.$workSessions)
                .all()
                .filter { workDay in
                    workDay.workSessions.contains { $0.endTime == nil }
                }
            
            // Определяем, кого завершать
            let isAll = usernamesText.lowercased() == "all"
            var targetUsers: [UserWorkDay] = []
            
            if isAll {
                targetUsers = allActiveUsers
            } else {
                // Разбираем список пользователей
                let searchUsernames = usernamesText.split(separator: " ")
                    .map { String($0).replacingOccurrences(of: "@", with: "").lowercased() }
                
                for username in searchUsernames {
                    let matchingUsers = allActiveUsers.filter { workDay in
                        let workDayUsername = workDay.telegramUsername?.lowercased() ?? ""
                        let workDayFirstName = workDay.telegramFirstName?.lowercased() ?? ""
                        
                        return workDayUsername == username ||
                               workDayFirstName == username ||
                               workDayUsername.contains(username) ||
                               workDayFirstName.contains(username)
                    }
                    
                    targetUsers.append(contentsOf: matchingUsers)
                }
                
                // Убираем дубликаты
                targetUsers = Array(Set(targetUsers.map { $0.id })).compactMap { id in
                    targetUsers.first { $0.id == id }
                }
            }
            
            if targetUsers.isEmpty {
                let params: TGSendMessageParams = .init(
                    chatId: .chat(chatId),
                    text: "ℹ️ Нет активных пользователей для завершения.",
                    parseMode: .html
                )
                try await bot.sendMessage(params: params)
                return
            }
            
            // Завершаем сессии для каждого пользователя
            var results: [(username: String, success: Bool, duration: TimeInterval?)] = []
            
            for workDay in targetUsers {
                let username = workDay.telegramUsername ?? workDay.telegramFirstName ?? "Неизвестно"
                
                do {
                    // Ищем активную сессию
                    guard let session = workDay.workSessions.first(where: { $0.endTime == nil }) else {
                        results.append((username, false, nil))
                        continue
                    }
                    
                    // Имитируем команду /end для этого пользователя
                    // 1. Отменяем автоматическое завершение
                    if let sessionId = session.id {
                        self.cancelAutoEndSession(for: workDay.telegramUserId, sessionId: sessionId)
                    }
                    
                    // 2. Завершаем сессию (как в команде /end)
                    session.endTime = Date()
                    try await session.update(on: app.db)
                    
                    // 3. Вычисляем длительность
                    let duration = Int(session.endTime!.timeIntervalSince(session.startTime))
                    
                    results.append((username, true, TimeInterval(duration)))
                    
                    app.logger.info("✅ Завершена сессия для @\(username) (имитация /end)")
                    
                } catch {
                    app.logger.error("❌ Ошибка для @\(username): \(error)")
                    results.append((username, false, nil))
                }
            }
            
            // Формируем отчет
            let successfulResults = results.filter { $0.success }
            let failedResults = results.filter { !$0.success }
            
            dateFormatter.dateFormat = "HH:mm"
            let timeText = dateFormatter.string(from: Date())
            
            var reportText = """
            📊 *Результат группового завершения*
            
            ✅ Успешно завершено: \(successfulResults.count) пользователей
            ❌ Не удалось: \(failedResults.count) пользователей
            👤 Инициатор: @\(initiatorUsername)
            🕐 Время: \(timeText)
            """
            
            // Показываем успешные завершения
            if !successfulResults.isEmpty {
                reportText += "\n\n👥 *Завершенные сессии:*"
                
                for (index, result) in successfulResults.prefix(10).enumerated() {
                    if let duration = result.duration {
                        let hours = Int(duration) / 3600
                        let minutes = (Int(duration) % 3600) / 60
                        reportText += "\n\(index + 1). @\(result.username) - \(hours)ч \(minutes)м"
                    }
                }
                
                if successfulResults.count > 10 {
                    reportText += "\n... и еще \(successfulResults.count - 10) пользователей"
                }
                
                // Общая статистика
                let totalDuration = successfulResults.reduce(0) { $0 + ($1.duration ?? 0) }
                let totalHours = Int(totalDuration) / 3600
                let totalMinutes = (Int(totalDuration) % 3600) / 60
                
                if !successfulResults.isEmpty {
                    let avgDuration = totalDuration / Double(successfulResults.count)
                    let avgHours = Int(avgDuration) / 3600
                    let avgMinutes = (Int(avgDuration) % 3600) / 60
                    
                    reportText += """
                    
                    📈 *Статистика:*
                    🕐 Общее время: \(totalHours)ч \(totalMinutes)м
                    ⏱️ Среднее время: \(avgHours)ч \(avgMinutes)м
                    """
                }
            }
            
            // Показываем ошибки
            if !failedResults.isEmpty {
                reportText += "\n\n⚠️ *Не удалось завершить:*"
                
                for (index, result) in failedResults.prefix(5).enumerated() {
                    reportText += "\n\(index + 1). @\(result.username)"
                }
                
                if failedResults.count > 5 {
                    reportText += "\n... и еще \(failedResults.count - 5) пользователей"
                }
            }
            
            // Отправляем отчет
            let params: TGSendMessageParams = .init(
                chatId: .chat(chatId),
                text: reportText,
                parseMode: .html
            )
            
            try await bot.sendMessage(params: params)
            
        } catch {
            app.logger.error("❌ Ошибка при групповом завершении: \(error)")
            
            let params: TGSendMessageParams = .init(
                chatId: .chat(chatId),
                text: "❌ Ошибка: \(error.localizedDescription)",
                parseMode: .html
            )
            
            do {
                try await bot.sendMessage(params: params)
            } catch let error {
                app.logger.error("❌ Ошибка при групповом завершении: \(error)")
            }
        }
    }
    
    
    // Создание прогресс-бара
    private func createProgressBar(percentage: Double, length: Int = 10) -> String {
        let filledCount = Int((percentage / 100) * Double(length))
        let emptyCount = length - filledCount
        
        let filled = String(repeating: "▓", count: filledCount)
        let empty = String(repeating: "░", count: emptyCount)
        
        return "   [" + filled + empty + "]"
    }
    
    // Обновленная функция для начала рабочего дня с автоматическим завершением
    private func startWorkDayWithReminder(
        for user: TGUser,
        chat: TGChat,
        date: String,
        existingDay: UserWorkDay?,
        messageID: Int,
        projectId: UUID? = nil,
        projectName: String? = nil,
        callbackQueryId: String? = nil
    ) async {
        do {
            let workDay: UserWorkDay
            
            if let existing = existingDay {
                workDay = existing
                // Обновляем проект дня, если выбран
                if let projectId = projectId {
                    workDay.$project.id = projectId
                    try await workDay.update(on: app.db)
                }
            } else {
                // Создаем новый день
                workDay = UserWorkDay(
                    telegramUserId: user.id,
                    telegramUsername: user.username,
                    telegramFirstName: user.firstName,
                    telegramLastName: user.lastName,
                    date: date,
                    projectId: projectId
                )
                try await workDay.save(on: app.db)
            }
            
            // Создаем сессию с проектом
            let session = WorkSession(
                workDayId: try workDay.requireID(),
                projectId: projectId,
                startTime: Date(),
                sessionType: "work"
            )
            try await session.save(on: app.db)
            
            guard let sessionId = session.id else {
                throw Abort(.internalServerError, reason: "Не удалось получить ID сессии")
            }
            
            // Запускаем таймер напоминания через 8 часов
            scheduleReminder(for: user.id, chatId: chat.id, afterHours: 8, afterMinutes: 45)
            
            // Запускаем таймер автоматического завершения через 12 часов
            scheduleAutoEndSession(for: user.id, chatId: chat.id, sessionId: sessionId, afterHours: 12, afterMinutes: 0)
            
            // Добавляем информацию о проекте, если есть
            var projectInfo = ""
            if let projectName = projectName {
                projectInfo = "\n📂 Проект: \(projectName)"
            }
            
            let successText = """
              ✅ *Рабочий день начат! Пользователь: @\(user.username ?? user.firstName)*
              \(projectInfo)
              """
            
            // Если это callback, отвечаем и обновляем сообщение
            if let callbackQueryId = callbackQueryId {
                do {
                    // Отвечаем на callback
                    try await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                        callbackQueryId: callbackQueryId,
                        text: "✅ Работа начата на проекте: \(projectName ?? "Общая работа")",
                        showAlert: false
                    ))
                    
                    // Обновляем сообщение с кнопками
                    let params: TGEditMessageTextParams = .init(
                        chatId: .chat(chat.id),
                        messageId: messageID,
                        text: successText,
                        parseMode: .html
                    )
                    try await bot.editMessageText(params: params)
                } catch {
                    app.logger.error("❌ Ошибка при обработке callback: \(error)")
                    // Отправляем новое сообщение в случае ошибки
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: successText,
                        parseMode: .html
                    )
                    try await bot.sendMessage(params: params)
                }
            } else {
                // Отправляем новое сообщение
                let params: TGSendMessageParams = .init(
                    chatId: .chat(chat.id),
                    text: successText,
                    parseMode: .html,
                    replyParameters: TGReplyParameters(messageId: messageID)
                )
                try await bot.sendMessage(params: params)
            }
            
        } catch {
            app.logger.error("❌ Ошибка при старте рабочего дня: \(error)")
            
            let errorText = "❌ Ошибка при начале рабочего дня."
            
            if let callbackQueryId = callbackQueryId {
                do {
                    try await bot.answerCallbackQuery(params: TGAnswerCallbackQueryParams(
                        callbackQueryId: callbackQueryId,
                        text: errorText,
                        showAlert: true
                    ))
                } catch {
                    app.logger.error("❌ Ошибка при отправке callback ответа: \(error)")
                }
            } else {
                do {
                    let params: TGSendMessageParams = .init(
                        chatId: .chat(chat.id),
                        text: errorText,
                        replyParameters: TGReplyParameters(messageId: messageID)
                    )
                    try await bot.sendMessage(params: params)
                } catch {
                    app.logger.error("❌ Ошибка при отправке сообщения об ошибке: \(error)")
                }
            }
        }
    }
    
    // Функция для планирования напоминания
    private func scheduleReminder(for userId: Int64, chatId: Int64, afterHours: Int, afterMinutes: Int = 0) {
        
        let timer = DispatchSource.makeTimerSource()
        let delaySeconds = TimeInterval(afterHours * 3600 + afterMinutes * 60)
        
        timer.schedule(deadline: .now() + delaySeconds)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            Task {
                await self.sendReminder(userId: userId, chatId: chatId, afterHours: afterHours)
                // Удаляем таймер после выполнения
                let timerKey = "reminder_\(userId)_\(Date().timeIntervalSince1970)"
                self.reminderTimers.removeValue(forKey: timerKey)
            }
        }
        timer.resume()
        
        app.logger.info("⏰ Напоминание запланировано для пользователя \(userId) через \(afterHours) часов")
        
        // Сохраняем таймер в словаре
        let timerKey = "reminder_\(userId)_\(Date().timeIntervalSince1970)"
        reminderTimers[timerKey] = timer
    }
    
    // Функция отправки напоминания
    private func sendReminder(userId: Int64, chatId: Int64, afterHours: Int) async {
        do {
            // Проверяем, завершил ли пользователь уже день
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let today = dateFormatter.string(from: Date())
            
            // Получаем информацию о пользователе
            let userWorkDay = try await UserWorkDay.query(on: app.db)
                .filter(\.$telegramUserId == userId)
                .filter(\.$date == today)
                .with(\.$workSessions)
                .first()
            
            guard let workDay = userWorkDay else {
                app.logger.info("ℹ️ Пользователь \(userId) не имеет рабочего дня сегодня")
                return
            }
            
            let hasActiveSession = workDay.workSessions.contains { $0.endTime == nil }
            
            // Если сессия все еще активна, отправляем напоминание
            if hasActiveSession {
                // Получаем имя пользователя
                let userName = "@\(workDay.telegramUsername ?? workDay.telegramFirstName ?? "Пользователь")"
                
                let params: TGSendMessageParams = .init(
                    chatId: .chat(chatId),
                    text: """
                    ⏰ *Напоминание для \(userName)!*
                    
                    Прошло уже \(afterHours) часов с начала рабочего дня.
                    
                    Не забудьте завершить рабочий день командой /end
                    
                    Хорошего отдыха! 🌙
                    """,
                    parseMode: .html
                )
                
                try await bot.sendMessage(params: params)
                app.logger.info("✅ Напоминание отправлено пользователю \(userId) (\(userName))")
            } else {
                app.logger.info("ℹ️ Пользователь \(userId) уже завершил рабочий день, напоминание не нужно")
            }
            
        } catch {
            app.logger.error("❌ Ошибка при отправке напоминания пользователю \(userId): \(error)")
        }
    }
    
    // Функция для планирования автоматического завершения сессии
    private func scheduleAutoEndSession(for userId: Int64, chatId: Int64, sessionId: UUID, afterHours: Int = 12, afterMinutes: Int = 0) {
        let timerKey = "autoend_\(userId)_\(sessionId.uuidString)"
        
        // Отменяем предыдущий таймер, если он есть
        if let existingTimer = reminderTimers[timerKey] {
            existingTimer.cancel()
            reminderTimers.removeValue(forKey: timerKey)
        }
        
        let timer = DispatchSource.makeTimerSource()
        
        // 12 часов = 12 * 3600 секунд
        let delaySeconds = TimeInterval(afterHours * 3600 + afterMinutes * 60)
        
        timer.schedule(deadline: .now() + delaySeconds)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            Task {
                await self.autoEndWorkSession(userId: userId, chatId: chatId, sessionId: sessionId)
                // Удаляем таймер после выполнения
                self.reminderTimers.removeValue(forKey: timerKey)
            }
        }
        timer.resume()
        
        // Сохраняем таймер в словаре
        reminderTimers[timerKey] = timer
        
        app.logger.info("⏰ Автоматическое завершение запланировано для сессии \(sessionId) пользователя \(userId) через \(afterHours) часов")
    }
    
    // Функция автоматического завершения рабочей сессии
    private func autoEndWorkSession(userId: Int64, chatId: Int64, sessionId: UUID) async {
        do {
            // Получаем текущую дату
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            // Ищем сессию по ID
            guard let session = try await WorkSession.find(sessionId, on: app.db) else {
                app.logger.warning("⚠️ Сессия \(sessionId) не найдена для автоматического завершения")
                return
            }
            
            // Проверяем, не завершена ли уже сессия
            if session.endTime != nil {
                app.logger.info("ℹ️ Сессия \(sessionId) уже завершена")
                return
            }
            
            // Получаем рабочий день для проверки пользователя
            guard let workDay = try await UserWorkDay.find(session.$workDay.id, on: app.db) else {
                app.logger.error("❌ Рабочий день для сессии \(sessionId) не найден")
                return
            }
            
            // Завершаем сессию
            session.endTime = Date()
            session.sessionType = "auto_ended"
            try await session.update(on: app.db)
            
            // Вычисляем длительность
            let duration = Int(session.endTime!.timeIntervalSince(session.startTime))
            let hours = duration / 3600
            let minutes = (duration % 3600) / 60
            
            dateFormatter.dateFormat = "HH:mm"
            let endTimeString = dateFormatter.string(from: session.endTime!)
            let startTimeString = dateFormatter.string(from: session.startTime)
            
            // Получаем информацию о проекте, если есть
            var projectInfo = ""
            if let projectId = session.$project.id {
                if let project = try await Project.find(projectId, on: app.db) {
                    projectInfo = "\n📂 Проект: \(project.name)"
                }
            }
            
            // Получаем имя пользователя
            let userName = "@\(workDay.telegramUsername ?? workDay.telegramFirstName ?? "Пользователь")"
            
            // Отправляем уведомление
            let params: TGSendMessageParams = .init(
                chatId: .chat(chatId),
                text: """
                ⏰ *АВТОМАТИЧЕСКОЕ ЗАВЕРШЕНИЕ РАБОЧЕГО ДНЯ*
                
                Рабочий день пользователя \(userName) был автоматически завершен.
                
                🕐 Начало: \(startTimeString)
                🕐 Автозавершение: \(endTimeString)
                ⏱️ Длительность: \(hours)ч \(minutes)м
                \(projectInfo)
                
                ℹ️ Сессия была завершена автоматически по истечении 12 часов.
                """,
                parseMode: .html
            )
            
            try await bot.sendMessage(params: params)
            
            app.logger.info("✅ Сессия \(sessionId) пользователя \(userId) автоматически завершена")
            
        } catch {
            app.logger.error("❌ Ошибка при автоматическом завершении сессии \(sessionId): \(error)")
            
            // Пытаемся отправить сообщение об ошибке
            do {
                let errorParams: TGSendMessageParams = .init(
                    chatId: .chat(chatId),
                    text: "❌ Произошла ошибка при автоматическом завершении рабочего дня.",
                    parseMode: .html
                )
                try await bot.sendMessage(params: errorParams)
            } catch {
                app.logger.error("❌ Ошибка при отправке сообщения об ошибке: \(error)")
            }
        }
    }
    
    // Отмена запланированного автоматического завершения
    private func cancelAutoEndSession(for userId: Int64, sessionId: UUID) {
        let timerKey = "autoend_\(userId)_\(sessionId.uuidString)"
        
        if let timer = reminderTimers[timerKey] {
            timer.cancel()
            reminderTimers.removeValue(forKey: timerKey)
            app.logger.info("⏰ Автоматическое завершение для сессии \(sessionId) отменено")
        }
    }
    
    
}
