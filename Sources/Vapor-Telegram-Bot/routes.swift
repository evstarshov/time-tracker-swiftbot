//
//  BotEnviroment.swift
//  time-tracker-bot
//
//  Created by Евгений Старшов on 14.09.2026.
//

import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: TelegramController())
}
