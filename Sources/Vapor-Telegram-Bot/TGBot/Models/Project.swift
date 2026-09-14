//
//  Project.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 29.01.2026.
//

import Vapor
import Fluent

final class Project: Model, Content {
    static let schema = "projects"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    
    init() {}
    
    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

extension Project: @unchecked Sendable {}

// Миграция для создания таблицы проектов
struct CreateProject: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Project.schema)
            .id()
            .field("name", .string, .required)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(Project.schema).delete()
    }
}
