//
//  Untitled.swift
//  Vapor-Telegram-Bot
//
//  Created by Евгений Старшов on 19.01.2026.
//

import Vapor
import Fluent

final class WorkSession: Model, Content {
    static let schema = "work_sessions"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "user_work_day_id")
    var workDay: UserWorkDay
    
    // Новая связь с проектом
    @OptionalParent(key: "project_id")
    var project: Project?
    
    @Field(key: "start_time")
    var startTime: Date
    
    @Field(key: "end_time")
    var endTime: Date?
    
    @Field(key: "session_type")
    var sessionType: String
    
    @Field(key: "notes")
    var notes: String?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() {}
    
    init(
        workDayId: UserWorkDay.IDValue,
        projectId: Project.IDValue? = nil, // Новый параметр
        startTime: Date,
        sessionType: String = "work",
        notes: String? = nil
    ) {
        self.$workDay.id = workDayId
        self.$project.id = projectId
        self.startTime = startTime
        self.sessionType = sessionType
        self.notes = notes
    }
}

// Добавляем соответствие Sendable с аннотацией @unchecked
extension WorkSession: @unchecked Sendable {}

struct CreateWorkSession: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WorkSession.schema)
            .id()
            .field("user_work_day_id", .uuid, .required, .references("user_work_days", "id", onDelete: .cascade))
            .field("project_id", .uuid, .references("projects", "id", onDelete: .setNull)) // УБЕРИТЕ .required
            .field("start_time", .datetime, .required)
            .field("end_time", .datetime)
            .field("session_type", .string, .required)
            .field("notes", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema(WorkSession.schema).delete()
    }
}
