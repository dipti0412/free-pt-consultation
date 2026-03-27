import Foundation
import HealthKit
import SwiftUI

protocol WearableDataProvider {
    var sourceName: String { get }
    func refreshStats() async throws -> WearableStats
}

struct WearableStats {
    let activeCaloriesLastWeek: Int
    let averageWeeklyStepCount: Int
    let upperBodySessions: Int
    let lowerBodySessions: Int
    let absSessions: Int
    let cardioSessions: Int
    let refreshedAt: Date
}

enum WearableProviderKind: String, CaseIterable, Identifiable {
    case appleHealth = "Apple Health"
    case whoop = "Whoop"

    var id: String { rawValue }

    var provider: WearableDataProvider {
        switch self {
        case .appleHealth:
            return AppleHealthProvider()
        case .whoop:
            return PlaceholderWearableProvider(sourceName: rawValue)
        }
    }
}

struct AppleHealthProvider: WearableDataProvider {
    let sourceName = WearableProviderKind.appleHealth.rawValue

    func refreshStats() async throws -> WearableStats {
        let client = HealthKitClient()
        return try await client.fetchWeeklyStats()
    }
}

private struct HealthKitClient {
    private let store = HKHealthStore()

    func fetchWeeklyStats(now: Date = .now) async throws -> WearableStats {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(
                domain: "BestPT.HealthKit",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Health data is not available on this device."]
            )
        }

        try await requestAuthorization()

        let endDate = Calendar.current.startOfDay(for: now)
        guard let startDate = Calendar.current.date(byAdding: .day, value: -6, to: endDate) else {
            throw NSError(
                domain: "BestPT.HealthKit",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not compute last-week date range."]
            )
        }

        async let totalActiveCalories = sumQuantity(
            type: .activeEnergyBurned,
            unit: .kilocalorie(),
            startDate: startDate,
            endDate: endDate
        )
        async let totalSteps = sumQuantity(
            type: .stepCount,
            unit: .count(),
            startDate: startDate,
            endDate: endDate
        )
        async let workouts = fetchWorkouts(startDate: startDate, endDate: endDate)

        let (calories, steps, weeklyWorkouts) = try await (totalActiveCalories, totalSteps, workouts)

        let upperBodyTypes: Set<HKWorkoutActivityType> = [
            .traditionalStrengthTraining,
            .functionalStrengthTraining,
            .crossTraining,
            .boxing,
            .wrestling
        ]
        let lowerBodyTypes: Set<HKWorkoutActivityType> = [
            .running,
            .walking,
            .hiking,
            .stairClimbing,
            .kickboxing,
            .barre,
            .elliptical,
            .cycling
        ]
        let absTypes: Set<HKWorkoutActivityType> = [
            .coreTraining,
            .pilates,
            .yoga
        ]
        let cardioTypes: Set<HKWorkoutActivityType> = [
            .running,
            .walking,
            .cycling,
            .swimming,
            .highIntensityIntervalTraining,
            .elliptical,
            .rowing,
            .stairClimbing
        ]

        let upperBodyCount = weeklyWorkouts.count { upperBodyTypes.contains($0.workoutActivityType) }
        let lowerBodyCount = weeklyWorkouts.count { lowerBodyTypes.contains($0.workoutActivityType) }
        let absCount = weeklyWorkouts.count { absTypes.contains($0.workoutActivityType) }
        let cardioCount = weeklyWorkouts.count { cardioTypes.contains($0.workoutActivityType) }

        return WearableStats(
            activeCaloriesLastWeek: Int(calories.rounded()),
            averageWeeklyStepCount: Int((steps / 7.0).rounded()),
            upperBodySessions: upperBodyCount,
            lowerBodySessions: lowerBodyCount,
            absSessions: absCount,
            cardioSessions: cardioCount,
            refreshedAt: .now
        )
    }

    private func requestAuthorization() async throws {
        guard
            let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount),
            let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let workoutType = HKObjectType.workoutType() as HKSampleType?
        else {
            throw NSError(
                domain: "BestPT.HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Required HealthKit data types are unavailable."]
            )
        }

        let readTypes: Set<HKObjectType> = [stepCountType, activeEnergyType, workoutType]
        try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "BestPT.HealthKit",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey: "HealthKit permission was not granted."]
                        )
                    )
                }
            }
        }
    }

    private func sumQuantity(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: type) else {
            throw NSError(
                domain: "BestPT.HealthKit",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Could not load HealthKit type: \(type.rawValue)."]
            )
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate.addingTimeInterval(86_399),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let total = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: total)
            }

            store.execute(query)
        }
    }

    private func fetchWorkouts(startDate: Date, endDate: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate.addingTimeInterval(86_399),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }

            store.execute(query)
        }
    }
}

struct PlaceholderWearableProvider: WearableDataProvider {
    let sourceName: String

    func refreshStats() async throws -> WearableStats {
        throw NSError(
            domain: "BestPT.WearableProvider",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "\(sourceName) support is coming soon."]
        )
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedProvider: WearableProviderKind = .appleHealth
    @Published var stats: WearableStats?
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    @Published var weightGoal = ""
    @Published var stressGoal = ""
    @Published var sleepGoal = ""
    @Published var consistencyGoal = ""

    func refreshWearableData() async {
        isRefreshing = true
        errorMessage = nil

        do {
            stats = try await selectedProvider.provider.refreshStats()
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }
}

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        TabView {
            youTab
                .tabItem {
                    Label("You", systemImage: "person.crop.circle")
                }

            goalsTab
                .tabItem {
                    Label("Your goals", systemImage: "target")
                }

            motivationTab
                .tabItem {
                    Label("Just do it", systemImage: "figure.run")
                }
        }
        .task {
            await viewModel.refreshWearableData()
        }
    }

    private var youTab: some View {
        NavigationStack {
            List {
                Section("Connected source") {
                    Text(viewModel.selectedProvider.rawValue)
                    if viewModel.isRefreshing {
                        ProgressView("Refreshing Apple Health data…")
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Your latest stats") {
                    if let stats = viewModel.stats {
                        statRow(title: "Active calories (last 7 days)", value: "\(stats.activeCaloriesLastWeek)")
                        statRow(title: "Average daily steps (last 7 days)", value: "\(stats.averageWeeklyStepCount)")
                        statRow(title: "Upper body sessions", value: "\(stats.upperBodySessions)")
                        statRow(title: "Lower body sessions", value: "\(stats.lowerBodySessions)")
                        statRow(title: "Abs sessions", value: "\(stats.absSessions)")
                        statRow(title: "Cardio sessions", value: "\(stats.cardioSessions)")
                        statRow(
                            title: "Last sync",
                            value: stats.refreshedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    } else {
                        Text("No Apple Health stats yet. Pull to refresh.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable {
                await viewModel.refreshWearableData()
            }
            .navigationTitle("You")
        }
    }

    private var goalsTab: some View {
        NavigationStack {
            Form {
                Section("Set goals") {
                    TextField("Weight goal (e.g. lose 5 lbs)", text: $viewModel.weightGoal)
                    TextField("Stress goal", text: $viewModel.stressGoal)
                    TextField("Sleep goal", text: $viewModel.sleepGoal)
                    TextField("Consistency goal", text: $viewModel.consistencyGoal)
                }
            }
            .navigationTitle("Your goals")
        }
    }

    private var motivationTab: some View {
        ZStack {
            LinearGradient(
                colors: [.orange.opacity(0.9), .pink.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white)
                Text("Just do it")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Show up today. Your future self will thank you.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 24)
            }
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    ContentView()
}
