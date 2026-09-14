//
//  UserWorkDay.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 19.01.2026.
//

import Vapor
import Fluent

final class UserWorkDay: Model, Content {
    static let schema = "user_work_days"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "telegram_user_id")
    var telegramUserId: Int64
    
    @Field(key: "telegram_username")
    var telegramUsername: String?
    
    @Field(key: "telegram_first_name")
    var telegramFirstName: String?
    
    @Field(key: "telegram_last_name")
    var telegramLastName: String?
    
    @Field(key: "date")
    var date: String
    
    // Проверьте, что это поле существует
    @OptionalParent(key: "project_id")
    var project: Project?
    
    @Children(for: \.$workDay)
    var workSessions: [WorkSession]
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() {}
    
    init(
        telegramUserId: Int64,
        telegramUsername: String? = nil,
        telegramFirstName: String? = nil,
        telegramLastName: String? = nil,
        date: String,
        projectId: UUID? = nil  // Тип должен быть UUID? (Project.IDValue)
    ) {
        self.telegramUserId = telegramUserId
        self.telegramUsername = telegramUsername
        self.telegramFirstName = telegramFirstName
        self.telegramLastName = telegramLastName
        self.date = date
        self.$project.id = projectId
    }
}

// Добавляем соответствие Sendable
extension UserWorkDay: @unchecked Sendable {}

struct CreateUserWorkDay: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(UserWorkDay.schema)
            .id()
            .field("telegram_user_id", .int64, .required)
            .field("telegram_username", .string)
            .field("telegram_first_name", .string)
            .field("telegram_last_name", .string)
            .field("date", .string, .required)
            .field("project_id", .uuid, .references("projects", "id")) // Новая колонка
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "telegram_user_id", "date")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(UserWorkDay.schema).delete()
    }
}
