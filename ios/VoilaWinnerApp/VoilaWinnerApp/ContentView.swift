import Foundation
import SwiftUI

protocol WearableDataProvider {
    var sourceName: String { get }
    func refreshStats() async throws -> WearableStats
}

struct WearableStats {
    let activeCaloriesLastWeek: Int
    let workoutsLast7Days: [WorkoutSummary]
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
        throw NSError(
            domain: "BestPT.WearableProvider",
            code: -2,
            userInfo: [
                NSLocalizedDescriptionKey: "Apple Health is disabled for local signing builds. Remove HealthKit capability or use a paid Apple Developer team to enable it."
            ]
        )
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
                Section("Your latest stats") {
                    Text("Source: \(viewModel.selectedProvider.rawValue)")
                        .foregroundStyle(.secondary)

                    if viewModel.isRefreshing {
                        ProgressView("Refreshing Apple Health data…")
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    if let stats = viewModel.stats {
                        statRow(title: "Active Energy (last 7 days)", value: "\(stats.activeCaloriesLastWeek) kcal")
                    } else if viewModel.isRefreshing {
                        Text("Fetching Active Energy from Apple Health…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No Apple Health stats yet. Tap refresh to request Apple Health access.")
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
                    } else if viewModel.isRefreshing {
                        Text("Fetching workouts from Apple Health…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No workout stats yet. Tap refresh to request Apple Health access.")
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
