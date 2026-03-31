import SwiftUI

// MARK: - Lightweight Workout UI Models

struct WorkoutTemplate: Identifiable, Hashable {
    let id: UUID
    var name: String
    var exercises: [TemplateExercise]
    var lastPerformed: Date?
}

struct TemplateExercise: Identifiable, Hashable {
    let id: UUID
    var name: String
    var sets: Int
    var category: Muscle
    var notes: String
    var lastPerformance: String
}

struct ActiveSetRow: Identifiable, Hashable {
    let id: UUID
    let number: Int
    var weight: String
    var reps: String
    var isCompleted: Bool
}

struct ExerciseProgress: Identifiable, Hashable {
    let id: UUID
    var exercise: TemplateExercise
    var setRows: [ActiveSetRow]
    var notes: String
}

struct CompletedWorkoutSummary {
    let durationSeconds: Int
    let exercisesCompleted: Int
    let totalSets: Int
    let totalVolume: Double
    let personalRecords: [String]
}

@MainActor
final class WorkoutFlowViewModel: ObservableObject {
    @Published var templates: [WorkoutTemplate]
    @Published var workoutHistory: [Workout]
    @Published var activeTemplate: WorkoutTemplate?
    @Published var activeExerciseProgress: [ExerciseProgress] = []
    @Published var activeWorkoutStart: Date?
    @Published var restTimerSecondsRemaining: Int = 0
    @Published var showRestTimer = false
    @Published var completedSummary: CompletedWorkoutSummary?

    @Published var selectedTab: RootTab = .home

    init() {
        let pushExercises = [
            TemplateExercise(id: UUID(), name: "Bench Press", sets: 3, category: .chest, notes: "Pause each first rep", lastPerformance: "3x225 lbs"),
            TemplateExercise(id: UUID(), name: "Incline Dumbbell Press", sets: 3, category: .chest, notes: "Controlled eccentric", lastPerformance: "3x70 lbs"),
            TemplateExercise(id: UUID(), name: "Tricep Pushdown", sets: 3, category: .triceps, notes: "Elbows tucked", lastPerformance: "3x85 lbs")
        ]

        let legExercises = [
            TemplateExercise(id: UUID(), name: "Back Squat", sets: 4, category: .legs, notes: "Brace before descent", lastPerformance: "4x275 lbs"),
            TemplateExercise(id: UUID(), name: "Romanian Deadlift", sets: 3, category: .glutes, notes: "Hip hinge", lastPerformance: "3x205 lbs"),
            TemplateExercise(id: UUID(), name: "Leg Press", sets: 3, category: .legs, notes: "Full range", lastPerformance: "3x450 lbs")
        ]

        templates = [
            WorkoutTemplate(id: UUID(), name: "Push Day", exercises: pushExercises, lastPerformed: .now.addingTimeInterval(-86_400 * 2)),
            WorkoutTemplate(id: UUID(), name: "Leg Day", exercises: legExercises, lastPerformed: .now.addingTimeInterval(-86_400 * 5))
        ]

        workoutHistory = Self.sampleHistory()
    }

    var weeklyWorkoutCount: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        return workoutHistory.filter { $0.startTime >= weekAgo }.count
    }

    var currentStreak: Int {
        let calendar = Calendar.current
        let daysWithWorkouts = Set(workoutHistory.map { calendar.startOfDay(for: $0.startTime) })

        var streak = 0
        var cursor = calendar.startOfDay(for: .now)

        while daysWithWorkouts.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    var lastWorkoutDate: Date? {
        workoutHistory.sorted { $0.startTime > $1.startTime }.first?.startTime
    }

    var elapsedSeconds: Int {
        guard let start = activeWorkoutStart else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start)))
    }

    func startWorkout(with template: WorkoutTemplate) {
        activeTemplate = template
        activeWorkoutStart = .now
        completedSummary = nil
        restTimerSecondsRemaining = 0
        showRestTimer = false

        activeExerciseProgress = template.exercises.map { exercise in
            let rows = (1 ... exercise.sets).map {
                ActiveSetRow(id: UUID(), number: $0, weight: "", reps: "", isCompleted: false)
            }
            return ExerciseProgress(id: UUID(), exercise: exercise, setRows: rows, notes: "")
        }

        selectedTab = .active
    }

    func startEmptyWorkout() {
        let empty = WorkoutTemplate(id: UUID(), name: "Empty Workout", exercises: [], lastPerformed: nil)
        startWorkout(with: empty)
    }

    func completeSet(exerciseID: UUID, setID: UUID) {
        guard let exerciseIndex = activeExerciseProgress.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = activeExerciseProgress[exerciseIndex].setRows.firstIndex(where: { $0.id == setID }) else {
            return
        }

        activeExerciseProgress[exerciseIndex].setRows[setIndex].isCompleted.toggle()
        if activeExerciseProgress[exerciseIndex].setRows[setIndex].isCompleted {
            startRestTimer()
        }
    }

    func addSet(exerciseID: UUID) {
        guard let exerciseIndex = activeExerciseProgress.firstIndex(where: { $0.id == exerciseID }) else { return }
        let next = (activeExerciseProgress[exerciseIndex].setRows.last?.number ?? 0) + 1
        activeExerciseProgress[exerciseIndex].setRows.append(
            ActiveSetRow(id: UUID(), number: next, weight: "", reps: "", isCompleted: false)
        )
    }

    func addExercise(_ exercise: TemplateExercise) {
        let rowCount = max(1, exercise.sets)
        let rows = (1 ... rowCount).map {
            ActiveSetRow(id: UUID(), number: $0, weight: "", reps: "", isCompleted: false)
        }
        activeExerciseProgress.append(ExerciseProgress(id: UUID(), exercise: exercise, setRows: rows, notes: ""))
    }

    func cancelWorkout() {
        activeTemplate = nil
        activeWorkoutStart = nil
        activeExerciseProgress = []
        showRestTimer = false
        restTimerSecondsRemaining = 0
        selectedTab = .home
    }

    func finishWorkout() {
        guard let start = activeWorkoutStart else { return }
        let duration = Int(Date().timeIntervalSince(start))

        var totalSets = 0
        var totalVolume = 0.0
        var completedExercises = 0

        for exercise in activeExerciseProgress {
            let completedRows = exercise.setRows.filter(\.isCompleted)
            if !completedRows.isEmpty {
                completedExercises += 1
            }
            totalSets += completedRows.count
            for row in completedRows {
                let weight = Double(row.weight) ?? 0
                let reps = Double(row.reps) ?? 0
                totalVolume += weight * reps
            }
        }

        completedSummary = CompletedWorkoutSummary(
            durationSeconds: duration,
            exercisesCompleted: completedExercises,
            totalSets: totalSets,
            totalVolume: totalVolume,
            personalRecords: ["Bench Press 5RM", "Volume PR: Chest"]
        )

        let finished = Workout(
            id: UUID(),
            startTime: start,
            endTime: .now,
            type: .internalWorkout,
            source: .manual,
            durationMinutes: max(1, duration / 60),
            caloriesBurned: max(100, totalSets * 9),
            distanceMiles: nil,
            pacePerMile: nil,
            workoutBlocks: [WorkoutBlock(id: UUID(), type: .strength, exercises: [], durationMinutes: nil, linkedWorkoutId: nil)]
        )

        workoutHistory.insert(finished, at: 0)

        if let activeTemplateID = activeTemplate?.id,
           let idx = templates.firstIndex(where: { $0.id == activeTemplateID }) {
            templates[idx].lastPerformed = .now
        }

        activeTemplate = nil
        activeWorkoutStart = nil
        activeExerciseProgress = []
        showRestTimer = false
        restTimerSecondsRemaining = 0
        selectedTab = .summary
    }

    func startRestTimer() {
        restTimerSecondsRemaining = 90
        showRestTimer = true
    }

    func restTimerTick() {
        guard showRestTimer else { return }
        if restTimerSecondsRemaining > 0 {
            restTimerSecondsRemaining -= 1
        } else {
            showRestTimer = false
        }
    }

    func addRestSeconds(_ seconds: Int) {
        restTimerSecondsRemaining += seconds
    }

    func dismissRestTimer() {
        showRestTimer = false
    }

    func doneWithSummary() {
        completedSummary = nil
        selectedTab = .home
    }

    static func sampleHistory() -> [Workout] {
        let now = Date()
        return (0 ..< 12).map { index in
            let dayOffset = TimeInterval(86_400 * index)
            return Workout(
                id: UUID(),
                startTime: now.addingTimeInterval(-dayOffset - 3_600),
                endTime: now.addingTimeInterval(-dayOffset),
                type: .internalWorkout,
                source: .manual,
                durationMinutes: 55 - (index % 4) * 5,
                caloriesBurned: 360 + index * 12,
                distanceMiles: nil,
                pacePerMile: nil,
                workoutBlocks: [WorkoutBlock(id: UUID(), type: .strength, exercises: [], durationMinutes: nil, linkedWorkoutId: nil)]
            )
        }
    }
}

enum RootTab: String, Hashable {
    case home
    case active
    case summary
}

struct ContentView: View {
    @StateObject private var viewModel = WorkoutFlowViewModel()

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            NavigationStack {
                DashboardScreen(viewModel: viewModel)
            }
            .tag(RootTab.home)
            .tabItem { Label("Home", systemImage: "house.fill") }
        }
        .tint(Color(red: 0.26, green: 0.48, blue: 1.0))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.selectedTab == .active },
            set: { if !$0 && viewModel.selectedTab == .active { viewModel.cancelWorkout() } }
        )) {
            NavigationStack {
                ActiveWorkoutScreen(viewModel: viewModel)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.selectedTab == .summary && viewModel.completedSummary != nil },
            set: { if !$0 && viewModel.selectedTab == .summary { viewModel.doneWithSummary() } }
        )) {
            NavigationStack {
                WorkoutCompleteScreen(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Screen 1: Home / Dashboard

struct DashboardScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @State private var showCreateTemplate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Existing workout templates")
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        showCreateTemplate = true
                    } label: {
                        Text("+Template")
                    }
                    .buttonStyle(.borderedProminent)
                }

                ForEach(viewModel.templates) { template in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(template.name)
                                .font(.headline)
                            Spacer()
                            Text("\(template.exercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Last performed: \(template.lastPerformed?.formatted(date: .abbreviated, time: .omitted) ?? "Never")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            Button("Start Workout") {
                                viewModel.startWorkout(with: template)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Home")
        .sheet(isPresented: $showCreateTemplate) {
            CreateEditTemplateScreen(viewModel: viewModel)
        }
    }
}

// MARK: - Screen 2: Template Library

struct TemplateLibraryScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @State private var selection: Int = 0
    @State private var showCreateTemplate = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selection) {
                Text("Templates").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 12)

            if selection == 0 {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.templates) { template in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(template.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(template.exercises.count) exercises")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                }

                                Text("Last performed: \(template.lastPerformed?.formatted(date: .abbreviated, time: .omitted) ?? "Never")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Spacer()
                                    Button("Start") {
                                        viewModel.startWorkout(with: template)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contextMenu {
                                Button("Edit") {
                                    showCreateTemplate = true
                                }
                                Button("Delete", role: .destructive) {}
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.workoutHistory.prefix(20)) { workout in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline)
                                Text("Duration \(workout.durationMinutes) min • Calories \(workout.caloriesBurned)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateTemplate) {
            CreateEditTemplateScreen(viewModel: viewModel)
        }
    }
}

// MARK: - Screen 3: Create/Edit Template

struct CreateEditTemplateScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var draftExercises: [TemplateExercise] = []
    @State private var showExerciseSearch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Template name", text: $name)
                    .font(.title2.bold())
                    .textFieldStyle(.roundedBorder)

                List {
                    ForEach($draftExercises) { $exercise in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                Text(exercise.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(exercise.sets) sets")
                                    .font(.caption.bold())
                            }

                            HStack {
                                Text("Set Count")
                                Spacer()
                                Stepper("\(exercise.sets)", value: $exercise.sets, in: 1 ... 10)
                                    .labelsHidden()
                            }

                            Button {
                                showExerciseSearch = true
                            } label: {
                                Label("+ Add Exercise", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onMove { indices, newOffset in
                        draftExercises.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.plain)

                HStack {
                    Button {
                        showExerciseSearch = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !draftExercises.isEmpty else { return }
                        viewModel.templates.append(
                            WorkoutTemplate(id: UUID(), name: name, exercises: draftExercises, lastPerformed: nil)
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .navigationTitle("New Template")
            .toolbar { EditButton() }
            .sheet(isPresented: $showExerciseSearch) {
                ExerciseSearchModal { exercise in
                    draftExercises.append(exercise)
                }
            }
        }
    }
}

struct ExerciseSearchModal: View {
    let onSelect: (TemplateExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private let catalog: [TemplateExercise] = [
        TemplateExercise(id: UUID(), name: "Pull-Up", sets: 3, category: .back, notes: "", lastPerformance: "3x10 BW"),
        TemplateExercise(id: UUID(), name: "Barbell Row", sets: 3, category: .back, notes: "", lastPerformance: "3x185 lbs"),
        TemplateExercise(id: UUID(), name: "Dumbbell Curl", sets: 3, category: .biceps, notes: "", lastPerformance: "3x35 lbs"),
        TemplateExercise(id: UUID(), name: "Leg Extension", sets: 3, category: .legs, notes: "", lastPerformance: "3x140 lbs")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Categories") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Muscle.allCases, id: \.self) { muscle in
                                Text(muscle.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Section("Exercises") {
                    ForEach(filteredCatalog) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                    Text(exercise.category.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
        }
    }

    private var filteredCatalog: [TemplateExercise] {
        if search.isEmpty { return catalog }
        return catalog.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

// MARK: - Screen 4: Active Workout

struct ActiveWorkoutScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @State private var addExerciseSheet = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if let template = viewModel.activeTemplate {
                topBar(templateName: template.name)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($viewModel.activeExerciseProgress) { $exercise in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(exercise.exercise.name)
                                    .font(.title3.bold())
                                Text("Last: \(exercise.exercise.lastPerformance)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ForEach($exercise.setRows) { $row in
                                    HStack {
                                        Text("Set \(row.number)")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(width: 52, alignment: .leading)

                                        TextField("lbs", text: $row.weight)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 90)

                                        TextField("reps", text: $row.reps)
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(maxWidth: 90)

                                        Button {
                                            viewModel.completeSet(exerciseID: exercise.id, setID: row.id)
                                        } label: {
                                            Image(systemName: row.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                        }
                                    }
                                }

                                Button("Add Set") {
                                    viewModel.addSet(exerciseID: exercise.id)
                                }
                                .buttonStyle(.bordered)

                                DisclosureGroup("Notes") {
                                    TextField("Add exercise notes...", text: $exercise.notes, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)

                bottomBar
            } else {
                ContentUnavailableView("No Active Workout", systemImage: "bolt.slash", description: Text("Start from Dashboard or Templates."))
            }
        }
        .sheet(isPresented: $addExerciseSheet) {
            ExerciseSearchModal { exercise in
                viewModel.addExercise(exercise)
            }
        }
        .overlay {
            if viewModel.showRestTimer {
                RestTimerOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(timer) { _ in
            viewModel.restTimerTick()
        }
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func topBar(templateName: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formatDuration(viewModel.elapsedSeconds))
                    .font(.title.bold())
                Text(templateName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Finish") {
                viewModel.finishWorkout()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var bottomBar: some View {
        HStack {
            Button {
                addExerciseSheet = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel Workout", role: .destructive) {
                viewModel.cancelWorkout()
            }
            .font(.footnote)
            .padding(.leading, 8)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct RestTimerOverlay: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel

    var body: some View {
        VStack(spacing: 14) {
            Capsule().frame(width: 38, height: 5).foregroundStyle(.secondary)
            Text("Rest Timer")
                .font(.headline)
            Text("\(viewModel.restTimerSecondsRemaining)s")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            HStack {
                Button("+15s") {
                    viewModel.addRestSeconds(15)
                }
                .buttonStyle(.bordered)

                Button("Skip") {
                    viewModel.dismissRestTimer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
        .onTapGesture {
            viewModel.dismissRestTimer()
        }
    }
}

// MARK: - Screen 5: Workout Complete

struct WorkoutCompleteScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @State private var notes = ""

    var body: some View {
        VStack {
            if let summary = viewModel.completedSummary {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Workout Complete")
                        .font(.largeTitle.bold())

                    metric(title: "Total duration", value: formatDuration(summary.durationSeconds))
                    metric(title: "Exercises completed", value: "\(summary.exercisesCompleted)")
                    metric(title: "Total sets", value: "\(summary.totalSets)")
                    metric(title: "Total volume", value: "\(Int(summary.totalVolume)) lbs")

                    if !summary.personalRecords.isEmpty {
                        Text("Personal Records")
                            .font(.headline)
                        ForEach(summary.personalRecords, id: \.self) { pr in
                            Label(pr, systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }

                    TextField("Add notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    Button("Share Summary") {}
                        .buttonStyle(.bordered)

                    Button("Done") {
                        viewModel.doneWithSummary()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
            } else {
                ContentUnavailableView("No Summary Yet", systemImage: "checkmark.seal", description: Text("Finish an active workout to view your summary."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Complete")
    }

    private func metric(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Screen 6: History / Analytics

struct HistoryAnalyticsScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Workout Calendar")
                    .font(.headline)
                calendarHeatMap

                Text("Stats")
                    .font(.headline)
                statsCards

                Text("Workout Log")
                    .font(.headline)
                ForEach(viewModel.workoutHistory.prefix(20)) { workout in
                    DisclosureGroup(workout.startTime.formatted(date: .abbreviated, time: .shortened)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration: \(workout.durationMinutes) min")
                            Text("Calories: \(workout.caloriesBurned)")
                            Text("Type: \(workout.type.rawValue)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("History")
    }

    private var calendarHeatMap: some View {
        let workoutsByDay = Dictionary(grouping: viewModel.workoutHistory) {
            Calendar.current.startOfDay(for: $0.startTime)
        }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(0 ..< 28, id: \.self) { offset in
                let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400 * Double(offset)))
                let count = workoutsByDay[day]?.count ?? 0
                RoundedRectangle(cornerRadius: 6)
                    .fill(count == 0 ? Color.gray.opacity(0.2) : Color.blue.opacity(min(0.2 + Double(count) * 0.2, 1.0)))
                    .frame(height: 24)
            }
        }
    }

    private var statsCards: some View {
        VStack(spacing: 10) {
            HStack {
                statsCard(title: "Frequency", value: "\(viewModel.weeklyWorkoutCount)/week")
                statsCard(title: "PRs", value: "8")
            }

            statsCard(title: "Volume Trend", value: "↗︎ +12% month-over-month")
        }
    }

    private func statsCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        List {
            Text("Date: \(workout.startTime.formatted(date: .complete, time: .shortened))")
            Text("Duration: \(workout.durationMinutes) min")
            Text("Calories: \(workout.caloriesBurned)")
            Text("Source: \(workout.source.rawValue)")
        }
        .navigationTitle("Workout Details")
    }
}

struct TemplateSelectionModal: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Choose a template") {
                    ForEach(viewModel.templates) { template in
                        Button {
                            viewModel.startWorkout(with: template)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                Text("\(template.exercises.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button("Empty Workout") {
                        viewModel.startEmptyWorkout()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Start Workout")
        }
    }
}

#Preview {
    ContentView()
}
