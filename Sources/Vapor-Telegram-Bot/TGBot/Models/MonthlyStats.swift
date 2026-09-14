//
//  MonthlyStats.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 19.01.2026.
//

import Foundation

// Структура для хранения месячной статистики пользователя
struct MonthlyUserStats {
    let userId: Int64
    let username: String
    let firstName: String
    let lastName: String?
    var workDaysCount: Int
    var totalSessions: Int
    var totalTime: TimeInterval
    var lastActivity: Date?
}
