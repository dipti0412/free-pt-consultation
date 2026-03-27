import SwiftUI

protocol WearableDataProvider {
    var sourceName: String { get }
    func refreshStats() async throws -> WearableStats
}

struct WearableStats {
    let recoveryHours: Int
    let sleepNeededHours: Double
    let mostTrainedMuscleGroup: String
    let refreshedAt: Date
}

enum WearableProviderKind: String, CaseIterable, Identifiable {
    case garminConnect = "Garmin Connect"
    case whoop = "Whoop"
    case appleWatch = "Apple Watch"

    var id: String { rawValue }

    var provider: WearableDataProvider {
        switch self {
        case .garminConnect:
            return GarminConnectProvider()
        case .whoop:
            return PlaceholderWearableProvider(sourceName: rawValue)
        case .appleWatch:
            return PlaceholderWearableProvider(sourceName: rawValue)
        }
    }
}

struct GarminConnectProvider: WearableDataProvider {
    let sourceName = WearableProviderKind.garminConnect.rawValue

    func refreshStats() async throws -> WearableStats {
        // Simulate network request to Garmin Connect.
        try await Task.sleep(for: .seconds(1.0))

        return WearableStats(
            recoveryHours: 31,
            sleepNeededHours: 7.8,
            mostTrainedMuscleGroup: "Legs",
            refreshedAt: .now
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
    @Published var selectedProvider: WearableProviderKind = .garminConnect
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
                        ProgressView("Refreshing Garmin data…")
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Your latest stats") {
                    if let stats = viewModel.stats {
                        statRow(title: "Recovery hours", value: "\(stats.recoveryHours)h")
                        statRow(title: "Sleep needed", value: String(format: "%.1f h", stats.sleepNeededHours))
                        statRow(title: "Muscle trained most", value: stats.mostTrainedMuscleGroup)
                        statRow(
                            title: "Last sync",
                            value: stats.refreshedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    } else {
                        Text("No Garmin stats yet. Pull to refresh.")
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
