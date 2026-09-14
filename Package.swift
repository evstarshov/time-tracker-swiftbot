// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Vapor-Telegram-Bot",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "Vapor-Telegram-Bot", targets: ["Vapor-Telegram-Bot"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.57.0")),
        .package(url: "https://github.com/nerzh/swift-telegram-bot.git", .upToNextMajor(from: "4.2.0")),
        // 🗄 Fluent (опционально)
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
        
        // 🐘 Fluent PostgreSQL driver (опционально)
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.7.2"),
        
    ],
    targets: [
        .executableTarget(
            name: "Vapor-Telegram-Bot",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SwiftTelegramBot", package: "swift-telegram-bot"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ]
        )
    ]
)
