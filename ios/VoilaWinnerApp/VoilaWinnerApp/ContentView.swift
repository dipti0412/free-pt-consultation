import SwiftUI

// MARK: - App Flow

enum StrengthExerciseCatalog: String, CaseIterable, Identifiable {
    case squat = "Squat"
    case benchPress = "Bench Press"
    case deadlift = "Deadlift"
    case shoulderPress = "Shoulder Press"

    var id: String { rawValue }

    var exercise: Exercise {
        switch self {
        case .squat:
            return Exercise(id: UUID(), name: rawValue, primaryMuscles: [.legs, .glutes], secondaryMuscles: [.core, .calves], isUpperBody: false, progressionIncrementLbs: 5)
        case .benchPress:
            return Exercise(id: UUID(), name: rawValue, primaryMuscles: [.chest, .triceps], secondaryMuscles: [.shoulders], isUpperBody: true, progressionIncrementLbs: 5)
        case .deadlift:
            return Exercise(id: UUID(), name: rawValue, primaryMuscles: [.back, .glutes], secondaryMuscles: [.legs, .core], isUpperBody: false, progressionIncrementLbs: 10)
        case .shoulderPress:
            return Exercise(id: UUID(), name: rawValue, primaryMuscles: [.shoulders], secondaryMuscles: [.triceps, .core], isUpperBody: true, progressionIncrementLbs: 2.5)
        }
    }
}

struct LoggedSet: Identifiable {
    let id: UUID
    let exercise: Exercise
    let setEntry: SetEntry
}

struct ActiveWorkoutDraft: Identifiable {
    let id: UUID
    let startTime: Date
    var workoutBlocks: [WorkoutBlock]
    var loggedSets: [LoggedSet]
    var totalDistanceMiles: Double
    var totalCardioMinutes: Int
}

@MainActor
final class WorkoutFlowViewModel: ObservableObject {
    @Published var activeWorkout: ActiveWorkoutDraft?
    @Published var lastCompletedWorkout: Workout?

    func startWorkout() {
        activeWorkout = ActiveWorkoutDraft(
            id: UUID(),
            startTime: .now,
            workoutBlocks: [],
            loggedSets: [],
            totalDistanceMiles: 0,
            totalCardioMinutes: 0
        )
    }

    func addStrengthSet(exercise: Exercise, reps: Int, weightLbs: Double) {
        guard var draft = activeWorkout else { return }
        let setEntry = SetEntry(id: UUID(), reps: reps, weightLbs: weightLbs, isCompleted: true)
        draft.loggedSets.append(LoggedSet(id: UUID(), exercise: exercise, setEntry: setEntry))

        if let blockIndex = draft.workoutBlocks.firstIndex(where: { $0.type == .strength }) {
            if !draft.workoutBlocks[blockIndex].exercises.contains(where: { $0.name == exercise.name }) {
                draft.workoutBlocks[blockIndex].exercises.append(exercise)
            }
        } else {
            draft.workoutBlocks.append(
                WorkoutBlock(
                    id: UUID(),
                    type: .strength,
                    exercises: [exercise],
                    durationMinutes: nil,
                    linkedWorkoutId: nil
                )
            )
        }

        activeWorkout = draft
    }

    func addCardioBlock(durationMinutes: Int, distanceMiles: Double) {
        guard var draft = activeWorkout else { return }
        draft.totalCardioMinutes += durationMinutes
        draft.totalDistanceMiles += distanceMiles

        draft.workoutBlocks.append(
            WorkoutBlock(
                id: UUID(),
                type: .cardio,
                exercises: [],
                durationMinutes: durationMinutes,
                linkedWorkoutId: nil
            )
        )

        activeWorkout = draft
    }

    func stopWorkout() {
        guard let draft = activeWorkout else { return }

        let endTime = Date.now
        let elapsed = max(1, Int(endTime.timeIntervalSince(draft.startTime) / 60))
        let caloriesEstimate = (draft.loggedSets.count * 8) + (draft.totalCardioMinutes * 10)
        let pacePerMile = draft.totalDistanceMiles > 0 ? Double(draft.totalCardioMinutes) / draft.totalDistanceMiles : nil

        lastCompletedWorkout = Workout(
            id: UUID(),
            startTime: draft.startTime,
            endTime: endTime,
            type: .internalWorkout,
            source: .manual,
            durationMinutes: elapsed,
            caloriesBurned: caloriesEstimate,
            distanceMiles: draft.totalDistanceMiles > 0 ? draft.totalDistanceMiles : nil,
            pacePerMile: pacePerMile,
            workoutBlocks: draft.workoutBlocks
        )

        activeWorkout = nil
    }
}

struct ContentView: View {
    @StateObject private var viewModel = WorkoutFlowViewModel()
    @State private var showActiveWorkout = false

    var body: some View {
        NavigationStack {
            HomeScreen(
                startWorkout: {
                    viewModel.startWorkout()
                    showActiveWorkout = true
                },
                lastCompletedWorkout: viewModel.lastCompletedWorkout
            )
            .navigationDestination(isPresented: $showActiveWorkout) {
                ActiveWorkoutScreen(
                    viewModel: viewModel,
                    onStopWorkout: {
                        showActiveWorkout = false
                    }
                )
            }
        }
    }
}

struct HomeScreen: View {
    let startWorkout: () -> Void
    let lastCompletedWorkout: Workout?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Manual Workout Logger")
                .font(.title2.bold())

            Button("Start Workout", action: startWorkout)
                .buttonStyle(.borderedProminent)

            if let workout = lastCompletedWorkout {
                VStack(spacing: 8) {
                    Text("Last Workout")
                        .font(.headline)
                    Text("Started: \(workout.startTime.formatted(date: .abbreviated, time: .shortened))")
                    Text("Ended: \(workout.endTime.formatted(date: .abbreviated, time: .shortened))")
                    Text("Type: \(workout.type.rawValue) • Source: \(workout.source.rawValue)")
                    Text("Duration: \(workout.durationMinutes) min • Calories: \(workout.caloriesBurned)")
                    Text("Blocks: \(workout.workoutBlocks.count)")
                    if let miles = workout.distanceMiles {
                        Text("Distance: \(miles.formatted(.number.precision(.fractionLength(0...2)))) mi")
                    }
                    if let pacePerMile = workout.pacePerMile,
                       let pacePerKm = workout.pacePerKm {
                        Text("Pace: \(pacePerMile.formatted(.number.precision(.fractionLength(1...2)))) min/mi • \(pacePerKm.formatted(.number.precision(.fractionLength(1...2)))) min/km")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Home")
    }
}

struct ActiveWorkoutScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    let onStopWorkout: () -> Void

    var body: some View {
        if let draft = viewModel.activeWorkout {
            List {
                Section("Workout") {
                    Text("Started: \(draft.startTime.formatted(date: .abbreviated, time: .shortened))")
                    Text("Blocks: \(draft.workoutBlocks.count)")
                }

                Section("Logged blocks") {
                    if draft.workoutBlocks.isEmpty {
                        Text("No blocks logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.workoutBlocks) { block in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(block.type.rawValue)
                                    .font(.headline)
                                if !block.exercises.isEmpty {
                                    Text("Exercises: \(block.exercises.map(\.name).joined(separator: ", "))")
                                        .font(.subheadline)
                                }
                                if let minutes = block.durationMinutes {
                                    Text("Duration: \(minutes) min")
                                        .font(.subheadline)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Logged sets") {
                    if draft.loggedSets.isEmpty {
                        Text("No sets logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.loggedSets) { item in
                            Text("• \(item.exercise.name): \(item.setEntry.reps) reps @ \(item.setEntry.weightLbs.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                .font(.subheadline)
                        }
                    }
                }

                Section("Actions") {
                    NavigationLink("Add Strength Set") {
                        AddStrengthSetScreen(viewModel: viewModel)
                    }

                    NavigationLink("Add Cardio Block") {
                        AddCardioBlockScreen(viewModel: viewModel)
                    }

                    Button(role: .destructive) {
                        viewModel.stopWorkout()
                        onStopWorkout()
                    } label: {
                        Text("Stop Workout")
                    }
                }
            }
            .navigationTitle("Active Workout")
            .navigationBarBackButtonHidden(true)
        } else {
            Text("No active workout.")
                .foregroundStyle(.secondary)
                .navigationTitle("Active Workout")
        }
    }
}

struct AddStrengthSetScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExercise: StrengthExerciseCatalog = .squat
    @State private var reps = 8
    @State private var weightLbs = 135.0

    var body: some View {
        Form {
            Picker("Exercise", selection: $selectedExercise) {
                ForEach(StrengthExerciseCatalog.allCases) { exercise in
                    Text(exercise.rawValue).tag(exercise)
                }
            }

            Stepper("Reps: \(reps)", value: $reps, in: 1 ... 100)

            HStack {
                Text("Weight (lbs)")
                Spacer()
                TextField("Weight", value: $weightLbs, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            Button("Add Set") {
                viewModel.addStrengthSet(exercise: selectedExercise.exercise, reps: reps, weightLbs: weightLbs)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Add Strength Set")
    }
}

struct AddCardioBlockScreen: View {
    @ObservedObject var viewModel: WorkoutFlowViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var durationMinutes = 20
    @State private var distanceMiles = 2.0

    var body: some View {
        Form {
            Stepper("Duration (minutes): \(durationMinutes)", value: $durationMinutes, in: 1 ... 300)

            HStack {
                Text("Distance (miles)")
                Spacer()
                TextField("Distance", value: $distanceMiles, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            Button("Add Cardio") {
                viewModel.addCardioBlock(durationMinutes: durationMinutes, distanceMiles: distanceMiles)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Add Cardio Block")
    }
}

#Preview {
    ContentView()
}
