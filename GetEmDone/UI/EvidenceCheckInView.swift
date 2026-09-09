import PhotosUI
import SwiftUI

struct EvidenceCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    let chore: Chore
    @ObservedObject var store: HouseholdStore
    @State private var photoItem: PhotosPickerItem?

    private var currentChore: Chore {
        store.chores.first(where: { $0.id == chore.id }) ?? chore
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                GEDCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(chore.title, systemImage: chore.evidence.symbol).font(.title2.bold())
                        Text(chore.detail).foregroundStyle(.secondary)
                    }
                }

                if chore.evidence == .photo { photoCapture }
                if chore.evidence == .timer { practiceTimer }

                Spacer()
                Button("Send to parent") {
                    store.submit(currentChore)
                    Task { await store.reconcilePolicy() }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!currentChore.canSubmit)
            }
            .padding()
            .background(GEDTheme.canvas)
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var photoCapture: some View {
        GEDCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add a quick photo").font(.headline)
                Text("Your parent sees it only to review this responsibility.").font(.subheadline).foregroundStyle(.secondary)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity).padding(12)
                }
                .buttonStyle(.bordered)
                .onChange(of: photoItem) { _, item in
                    if item != nil { store.attachPhoto(to: chore) }
                }
                if currentChore.canSubmit {
                    Label("Photo ready", systemImage: "checkmark.circle.fill").foregroundStyle(GEDTheme.mint)
                }
            }
        }
    }

    private var practiceTimer: some View {
        GEDCard {
            VStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timerText(at: context.date))
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity)
                }
                Text("Goal: \(max(1, chore.minimumTimerSeconds / 60)) minute")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(currentChore.timerStartedAt == nil ? "Start practice" : "Finish practice") {
                    if currentChore.timerStartedAt == nil { store.startPractice(for: currentChore) }
                    else { store.stopPractice(for: currentChore) }
                }
                .buttonStyle(.borderedProminent)
                .tint(GEDTheme.childAccent)
            }
        }
    }

    private func timerText(at date: Date) -> String {
        let live = store.elapsedPractice(for: currentChore, at: date)
        return String(format: "%02d:%02d", live / 60, live % 60)
    }
}
