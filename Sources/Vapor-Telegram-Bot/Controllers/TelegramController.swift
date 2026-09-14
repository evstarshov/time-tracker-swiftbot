//
//  BotEnviroment.swift
//  time-tracker-bot
//
//  Created by Евгений Старшов on 14.09.2026.
//

import Foundation
import Vapor
import SwiftTelegramBot

final class TelegramController: RouteCollection {
    
    func boot(routes: Vapor.RoutesBuilder) throws {
        routes.post("telegramWebHook", use: telegramWebHook)
    }
}

extension TelegramController {
    
    func telegramWebHook(_ req: Request) async throws -> Bool {
        let update: TGUpdate = try req.content.decode(TGUpdate.self)
        await app.bot.processing(updates: [update])
        return true
    }
}
