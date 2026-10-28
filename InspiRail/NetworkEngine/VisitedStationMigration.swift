//
//  VisitedStationMigration.swift
//  rnsapp
//
//  SwiftData migration plan for VisitedStation schema changes
//

import SwiftData
import Foundation

/// Migration plan for VisitedStation model changes
enum VisitedStationMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [VisitedStationSchemaV1.self, VisitedStationSchemaV2.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    /// Migration from V1 (without isFavorite) to V2 (with isFavorite)
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: VisitedStationSchemaV1.self,
        toVersion: VisitedStationSchemaV2.self,
        willMigrate: { context in
            // This runs before migration
            print("🔄 Starting migration from V1 to V2...")
        },
        didMigrate: { context in
            // This runs after migration
            print("✅ Migration from V1 to V2 complete")
        }
    )
}

// MARK: - Schema V1 (Original without isFavorite)

enum VisitedStationSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [VisitedStationV1.self]
    }
    
    @Model
    final class VisitedStationV1 {
        @Attribute(.unique) var stationCode: String
        var stationName: String
        var dateVisited: Date
        var notes: String?
        var rating: Int?
        
        init(
            stationCode: String,
            stationName: String,
            dateVisited: Date = .now,
            notes: String? = nil,
            rating: Int? = nil
        ) {
            self.stationCode = stationCode
            self.stationName = stationName
            self.dateVisited = dateVisited
            self.notes = notes
            self.rating = rating
        }
    }
}

// MARK: - Schema V2 (Current with isFavorite)

enum VisitedStationSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [VisitedStationV2.self]
    }
    
    @Model
    final class VisitedStationV2 {
        @Attribute(.unique) var stationCode: String
        var stationName: String
        var dateVisited: Date
        var notes: String?
        var rating: Int?
        var isFavorite: Bool // NEW in V2
        
        init(
            stationCode: String,
            stationName: String,
            dateVisited: Date = .now,
            notes: String? = nil,
            rating: Int? = nil,
            isFavorite: Bool = false
        ) {
            self.stationCode = stationCode
            self.stationName = stationName
            self.dateVisited = dateVisited
            self.notes = notes
            self.rating = rating
            self.isFavorite = isFavorite
        }
    }
}

// MARK: - Helper for Using Migration Plan

extension ModelContainer {
    /// Create a ModelContainer with migration support for VisitedStation
    static func createWithMigration() throws -> ModelContainer {
        let schema = Schema([VisitedStation.self])
        let modelConfiguration = ModelConfiguration(schema: schema)
        
        // Note: SwiftData doesn't directly support migration plans in the same way as Core Data
        // The automatic migration should handle adding new non-optional properties
        // if they have default values in the initializer
        
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    }
}
