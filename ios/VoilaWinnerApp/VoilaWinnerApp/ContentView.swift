import SwiftUI

struct Workout: Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let workoutBlocks: [WorkoutBlock]
    let calories: Int
}

enum WorkoutBlock: Identifiable {
    case strength(StrengthWorkoutBlock)
    case cardio(CardioWorkoutBlock)

    var id: UUID {
        switch self {
        case let .strength(block):
            return block.id
        case let .cardio(block):
            return block.id
        }
    }
}

struct StrengthWorkoutBlock {
    let id: UUID
    var sets: [SetEntry]
}

struct CardioWorkoutBlock {
    let id: UUID
    let cardioType: CardioType
    let durationMinutes: Int
    let distanceMiles: Double
}

struct SetEntry: Identifiable {
    let id: UUID
    let exercise: StrengthExercise
    let reps: Int
    let weightLbs: Double
}

enum StrengthExercise: String, CaseIterable, Identifiable {
    case squat = "Squat"
    case benchPress = "Bench Press"
    case deadlift = "Deadlift"
    case shoulderPress = "Shoulder Press"

    var id: String { rawValue }
}

enum CardioType: String, CaseIterable, Identifiable {
    case run = "Run"
    case walk = "Walk"
    case bike = "Bike"

    var id: String { rawValue }
}

struct ActiveWorkoutDraft: Identifiable {
    let id: UUID
    let startTime: Date
    var workoutBlocks: [WorkoutBlock]
}

@MainActor
final class WorkoutFlowViewModel: ObservableObject {
    @Published var activeWorkout: ActiveWorkoutDraft?
    @Published var lastCompletedWorkout: Workout?

    func startWorkout() {
        activeWorkout = ActiveWorkoutDraft(id: UUID(), startTime: .now, workoutBlocks: [])
    }

    func addStrengthSet(exercise: StrengthExercise, reps: Int, weightLbs: Double) {
        guard var draft = activeWorkout else { return }
        let setEntry = SetEntry(id: UUID(), exercise: exercise, reps: reps, weightLbs: weightLbs)

        if let existingStrengthIndex = draft.workoutBlocks.firstIndex(where: {
            if case .strength = $0 { return true }
            return false
        }) {
            guard case var .strength(strengthBlock) = draft.workoutBlocks[existingStrengthIndex] else {
                return
            }
            strengthBlock.sets.append(setEntry)
            draft.workoutBlocks[existingStrengthIndex] = .strength(strengthBlock)
        } else {
            let newStrengthBlock = StrengthWorkoutBlock(id: UUID(), sets: [setEntry])
            draft.workoutBlocks.append(.strength(newStrengthBlock))
        }

        activeWorkout = draft
    }

    func addCardioBlock(cardioType: CardioType, durationMinutes: Int, distanceMiles: Double) {
        guard var draft = activeWorkout else { return }
        let cardioBlock = CardioWorkoutBlock(
            id: UUID(),
            cardioType: cardioType,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles
        )
        draft.workoutBlocks.append(.cardio(cardioBlock))
        activeWorkout = draft
    }

    func stopWorkout() {
        guard let draft = activeWorkout else { return }
        lastCompletedWorkout = Workout(
            id: UUID(),
            startTime: draft.startTime,
            endTime: .now,
            workoutBlocks: draft.workoutBlocks,
            calories: 0
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
                    Text("Blocks: \(workout.workoutBlocks.count) • Calories: \(workout.calories)")
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
                }

                Section("Logged blocks") {
                    if draft.workoutBlocks.isEmpty {
                        Text("No blocks logged yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.workoutBlocks) { block in
                            switch block {
                            case let .strength(strengthBlock):
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Strength")
                                        .font(.headline)
                                    ForEach(strengthBlock.sets) { set in
                                        Text("• \(set.exercise.rawValue): \(set.reps) reps @ \(set.weightLbs.formatted(.number.precision(.fractionLength(0...2)))) lbs")
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 4)
                            case let .cardio(cardioBlock):
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Cardio")
                                        .font(.headline)
                                    Text("\(cardioBlock.cardioType.rawValue) • \(cardioBlock.durationMinutes) min • \(cardioBlock.distanceMiles.formatted(.number.precision(.fractionLength(0...2)))) mi")
                                        .font(.subheadline)
                                }
                                .padding(.vertical, 4)
                            }
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

    @State private var selectedExercise: StrengthExercise = .squat
    @State private var reps = 8
    @State private var weightLbs = 135.0

    var body: some View {
        Form {
            Picker("Exercise", selection: $selectedExercise) {
                ForEach(StrengthExercise.allCases) { exercise in
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
                viewModel.addStrengthSet(exercise: selectedExercise, reps: reps, weightLbs: weightLbs)
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

    @State private var selectedCardioType: CardioType = .run
    @State private var durationMinutes = 20
    @State private var distanceMiles = 2.0

    var body: some View {
        Form {
            Picker("Cardio Type", selection: $selectedCardioType) {
                ForEach(CardioType.allCases) { cardioType in
                    Text(cardioType.rawValue).tag(cardioType)
                }
            }

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
                viewModel.addCardioBlock(
                    cardioType: selectedCardioType,
                    durationMinutes: durationMinutes,
                    distanceMiles: distanceMiles
                )
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
