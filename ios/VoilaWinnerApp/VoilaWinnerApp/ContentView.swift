import Foundation
import HealthKit
import SwiftUI

protocol WearableDataProvider {
    var sourceName: String { get }
    func refreshStats() async throws -> WearableStats
}

struct WearableStats {
    let activeCaloriesLastWeek: Int
    let workoutsLast7Days: [WorkoutSummary]
    let refreshedAt: Date
}

struct WorkoutSummary: Identifiable {
    let id: UUID
    let date: Date
    let burnedCalories: Int
    let averageHeartRate: Int?
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
        async let workouts = fetchWorkouts(startDate: startDate, endDate: endDate)

        let (calories, weeklyWorkouts) = try await (totalActiveCalories, workouts)
        var workoutSummaries: [WorkoutSummary] = []
        for workout in weeklyWorkouts.sorted(by: { $0.startDate > $1.startDate }) {
            let workoutCalories = Int((workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0).rounded())
            let averageHeartRate = try await fetchAverageHeartRate(for: workout).map { Int($0.rounded()) }
            workoutSummaries.append(
                WorkoutSummary(
                    id: workout.uuid,
                    date: workout.startDate,
                    burnedCalories: workoutCalories,
                    averageHeartRate: averageHeartRate
                )
            )
        }

        return WearableStats(
            activeCaloriesLastWeek: Int(calories.rounded()),
            workoutsLast7Days: workoutSummaries,
            refreshedAt: .now
        )
    }

    private func requestAuthorization() async throws {
        guard
            let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
            let workoutType = HKObjectType.workoutType() as HKSampleType?
        else {
            throw NSError(
                domain: "BestPT.HealthKit",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Required HealthKit data types are unavailable."]
            )
        }

        let readTypes: Set<HKObjectType> = [activeEnergyType, heartRateType, workoutType]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

    private func fetchAverageHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let avgValue = statistics?.averageQuantity()?.doubleValue(for: bpmUnit)
                continuation.resume(returning: avgValue)
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
                        statRow(title: "Active Energy (last 7 days)", value: "\(stats.activeCaloriesLastWeek) kcal")
                    } else {
                        Text("No Apple Health stats yet. Pull to refresh.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Workouts in last 7 days") {
                    if let stats = viewModel.stats, !stats.workoutsLast7Days.isEmpty {
                        ForEach(stats.workoutsLast7Days) { workout in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text("Burned Calories: \(workout.burnedCalories) kcal")
                                Text("Average Heart Rate: \(workout.averageHeartRate.map { "\($0) bpm" } ?? "N/A")")
                            }
                            .padding(.vertical, 4)
                        }
                    } else if viewModel.stats != nil {
                        Text("No workouts recorded in the last 7 days.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No Apple Health stats yet. Pull to refresh.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if let stats = viewModel.stats {
                        statRow(
                            title: "Last sync",
                            value: stats.refreshedAt.formatted(date: .abbreviated, time: .shortened)
                        )
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
