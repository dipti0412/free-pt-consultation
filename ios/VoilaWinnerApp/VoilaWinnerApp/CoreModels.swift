import Foundation

enum WorkoutType: String, CaseIterable, Codable {
    case external = "External"
    case internalWorkout = "Internal"
}

enum WorkoutSource: String, CaseIterable, Codable {
    case garmin = "Garmin"
    case manual = "Manual"
    case appleHealth = "AppleHealth"
}

enum Muscle: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case core = "Core"
    case legs = "Legs"
    case glutes = "Glutes"
    case calves = "Calves"
}

enum GoalType: String, CaseIterable, Codable {
    case strength = "Strength"
    case running = "Running"
    case consistency = "Consistency"
    case skill = "Skill"
}

enum WorkoutBlockType: String, CaseIterable, Codable {
    case strength = "Strength"
    case cardio = "Cardio"
    case mobility = "Mobility"
}

enum SmallWinCategory: String, CaseIterable, Codable {
    case strength = "Strength"
    case cardio = "Cardio"
    case consistency = "Consistency"
    case habit = "Habit"
}

enum Unit: String, CaseIterable, Codable {
    case lbs
    case miles
    case pace
    case reps
}

enum NutritionTrigger: String, CaseIterable, Codable {
    case postWorkout = "PostWorkout"
}

struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]
    let isUpperBody: Bool
    let progressionIncrementLbs: Double
}

struct SetEntry: Identifiable, Codable {
    let id: UUID
    let reps: Int
    let weightLbs: Double
    let isCompleted: Bool
}

struct WorkoutBlock: Identifiable, Codable {
    let id: UUID
    let type: WorkoutBlockType
    var exercises: [Exercise]
    var durationMinutes: Int?
    var linkedWorkoutId: UUID?
}

struct Workout: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let type: WorkoutType
    let source: WorkoutSource
    let durationMinutes: Int
    let caloriesBurned: Int
    let distanceMiles: Double?
    let pacePerMile: Double?
    let workoutBlocks: [WorkoutBlock]

    var pacePerKm: Double? {
        guard let pacePerMile else { return nil }
        return pacePerMile / 1.60934
    }
}

struct Goal: Identifiable, Codable {
    let id: UUID
    let type: GoalType
    let name: String
    let currentValue: Double
    let targetValue: Double
    let unit: Unit
    let lastUpdatedDate: Date
}

struct SmallWin: Identifiable, Codable {
    let id: UUID
    let date: Date
    let lastUpdatedDate: Date
    let relatedWorkoutId: UUID?
    let message: String
    let category: SmallWinCategory
}

struct NutritionSuggestion: Identifiable, Codable {
    let id: UUID
    let trigger: NutritionTrigger
    let relatedWorkoutType: WorkoutBlockType
    let message: String
    let checklistItems: [String]
    let completedItems: Set<String>
}
