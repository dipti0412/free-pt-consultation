import SwiftUI
import Foundation

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
        let config = try GarminAPIConfig.fromBundle()
        let client = GarminHealthAPIClient(config: config)
        return try await client.fetchWeeklyStats()
    }
}

struct GarminAPIConfig {
    let accessToken: String
    let baseURL: URL

    static func fromBundle(bundle: Bundle = .main) throws -> GarminAPIConfig {
        let baseURLString = bundle.object(forInfoDictionaryKey: "GARMIN_API_BASE_URL") as? String
            ?? "https://apis.garmin.com/wellness-api/rest"
        let token = bundle.object(forInfoDictionaryKey: "GARMIN_ACCESS_TOKEN") as? String
            ?? ProcessInfo.processInfo.environment["GARMIN_ACCESS_TOKEN"]
            ?? ""

        guard !token.isEmpty else {
            throw NSError(
                domain: "BestPT.Garmin",
                code: -2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Garmin token missing. Add GARMIN_ACCESS_TOKEN to Info.plist (or env var for previews)."
                ]
            )
        }

        guard let baseURL = URL(string: baseURLString) else {
            throw NSError(
                domain: "BestPT.Garmin",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid GARMIN_API_BASE_URL in Info.plist."]
            )
        }

        return GarminAPIConfig(accessToken: token, baseURL: baseURL)
    }
}

private struct GarminDailySummary: Decodable {
    let calendarDate: String?
    let activeKilocalories: Int?
    let steps: Int?
}

private struct GarminActivity: Decodable {
    let activityType: String?
}

private struct GarminDailySummaryEnvelope: Decodable {
    let dailies: [GarminDailySummary]?
}

private struct GarminActivitiesEnvelope: Decodable {
    let activities: [GarminActivity]?
}

struct GarminHealthAPIClient {
    let config: GarminAPIConfig
    var session: URLSession = .shared

    func fetchWeeklyStats(now: Date = .now) async throws -> WearableStats {
        let endDate = Calendar.current.startOfDay(for: now)
        guard let startDate = Calendar.current.date(byAdding: .day, value: -6, to: endDate) else {
            throw NSError(
                domain: "BestPT.Garmin",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Could not compute last-week date range."]
            )
        }

        async let dailySummaries = fetchDailySummaries(startDate: startDate, endDate: endDate)
        async let activities = fetchActivities(startDate: startDate, endDate: endDate)

        let (summaries, weeklyActivities) = try await (dailySummaries, activities)

        let totalCalories = summaries.reduce(0) { $0 + ($1.activeKilocalories ?? 0) }
        let averageSteps = summaries.isEmpty ? 0 : summaries.reduce(0) { $0 + ($1.steps ?? 0) } / summaries.count

        let upperBodyKeywords = ["upper", "chest", "back", "shoulder", "arm", "bicep", "tricep"]
        let lowerBodyKeywords = ["lower", "leg", "glute", "hamstring", "quad", "calf"]
        let absKeywords = ["core", "abs", "abdominal"]
        let cardioKeywords = ["run", "walk", "ride", "bike", "cardio", "swim", "row", "elliptical", "hiit"]

        let upperBodyCount = weeklyActivities.countMatches(matchingAny: upperBodyKeywords)
        let lowerBodyCount = weeklyActivities.countMatches(matchingAny: lowerBodyKeywords)
        let absCount = weeklyActivities.countMatches(matchingAny: absKeywords)
        let cardioCount = weeklyActivities.countMatches(matchingAny: cardioKeywords)

        return WearableStats(
            activeCaloriesLastWeek: totalCalories,
            averageWeeklyStepCount: averageSteps,
            upperBodySessions: upperBodyCount,
            lowerBodySessions: lowerBodyCount,
            absSessions: absCount,
            cardioSessions: cardioCount,
            refreshedAt: .now
        )
    }

    private func fetchDailySummaries(startDate: Date, endDate: Date) async throws -> [GarminDailySummary] {
        let data = try await request(path: "dailies", startDate: startDate, endDate: endDate)
        if let envelope = try? JSONDecoder().decode(GarminDailySummaryEnvelope.self, from: data) {
            return envelope.dailies ?? []
        }
        return try JSONDecoder().decode([GarminDailySummary].self, from: data)
    }

    private func fetchActivities(startDate: Date, endDate: Date) async throws -> [GarminActivity] {
        let data = try await request(path: "activities", startDate: startDate, endDate: endDate)
        if let envelope = try? JSONDecoder().decode(GarminActivitiesEnvelope.self, from: data) {
            return envelope.activities ?? []
        }
        return try JSONDecoder().decode([GarminActivity].self, from: data)
    }

    private func request(path: String, startDate: Date, endDate: Date) async throws -> Data {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        let startSeconds = Int(startDate.timeIntervalSince1970)
        let endSeconds = Int(endDate.timeIntervalSince1970 + 86_399)
        components?.queryItems = [
            URLQueryItem(name: "uploadStartTimeInSeconds", value: "\(startSeconds)"),
            URLQueryItem(name: "uploadEndTimeInSeconds", value: "\(endSeconds)")
        ]

        guard let url = components?.url else {
            throw NSError(
                domain: "BestPT.Garmin",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Unable to build Garmin request URL."]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "BestPT.Garmin",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: "Garmin API request failed with status code \(code)."]
            )
        }
        return data
    }
}

private extension Array where Element == GarminActivity {
    func countMatches(matchingAny keywords: [String]) -> Int {
        self.reduce(into: 0) { count, activity in
            guard let type = activity.activityType?.lowercased() else { return }
            if keywords.contains(where: { type.contains($0) }) {
                count += 1
            }
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
