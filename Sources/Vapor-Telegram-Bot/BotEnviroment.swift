//
//  BotEnviroment.swift
//  time-tracker-bot
//
//  Created by Евгений Старшов on 14.09.2026.
//

enum BotEnvironment {
    case development
    case production
    
    var token: String {
        switch self {
        case .development:
            return "your telegram token here" // test
        case .production:
            return "your telegram token here" // prod
        }
    }
    
    var port: Int {
        switch self {
        case .development:
            return 8091
        case .production:
            return 8080
        }
    }
    
    var chatIds: ChatIDs {
        switch self {
        case .development:
            return ChatIDs(
                testChatId: -0, // тестовый чат
                // ... другие тестовые ID
            )
        case .production:
            return ChatIDs(
                prodChatId: -0, // продакшн чат
            )
        }
    }
}

struct ChatIDs {
    let testChatId: Int64
    let prodChatId: Int64
    // ... другие ID
}
