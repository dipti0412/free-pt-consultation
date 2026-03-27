import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Text("Voila! You have won unlimited free personal trainer sessions, enjoy!")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(24)
        }
    }
}

#Preview {
    ContentView()
}
