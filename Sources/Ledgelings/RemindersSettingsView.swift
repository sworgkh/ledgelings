import LedgelingsCore
import SwiftUI

/// Settings › Reminders: a new reminder and how they are delivered on the left,
/// every reminder on the right.
struct RemindersSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var reminders: ReminderBook
    /// Deliver one now: the Send Now buttons and the test letter.
    let send: (Reminders.Reminder) -> Void

    @State private var text = ""
    @State private var time = RemindersSettingsView.nextRoundHour()
    @State private var repeats = Reminders.Repeat.once

    var body: some View {
        TwoColumns {
            Section {
                TextField("Remind me to", text: $text, prompt: Text("Stretch, call mom, stand-up…"))
                    .onSubmit(add)
                DatePicker("When", selection: $time, displayedComponents: [.date, .hourAndMinute])
                Picker("Repeat", selection: $repeats) {
                    ForEach(Reminders.Repeat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                HStack {
                    ForEach([("In 5 min", 5.0), ("In 30 min", 30.0), ("In 1 hour", 60.0)], id: \.0) { title, minutes in
                        Button(title) { time = Date().addingTimeInterval(minutes * 60) }
                    }
                    Spacer()
                    Button("Add Reminder", action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("New reminder")
            } footer: {
                Text("When the time comes, one of the creatures folds it into a paper plane and throws it at you. A time already past is delivered straight away. Repeating reminders keep their time of day; weekdays skip Saturday and Sunday.")
            }

            Section {
                Toggle("Reminders arrive by paper plane", isOn: $settings.remindersEnabled)
                SliderRow("Letter stays open", value: $settings.reminderLetterSeconds, in: AppSettings.reminderLetterRange, step: 10, unit: " s")
                Toggle("The thrower reads its note out loud", isOn: $settings.reminderReadAloud)
                HStack {
                    Spacer()
                    Button("Send a Test Letter") { send(Reminders.Reminder(text: "This is what a reminder looks like", time: Date())) }
                }
            } header: {
                Text("Delivery")
            } footer: {
                Text(footer)
            }
        } right: {
            Section {
                let all = reminders.book.sorted
                if all.isEmpty { Text("No reminders yet.").foregroundStyle(.secondary) }
                ForEach(all) { row($0) }
            } header: {
                Text("Your reminders")
            } footer: {
                Text("Sent one-off reminders stay here, greyed, until you clear them.")
            }

            Section {
                HStack {
                    Text(reminders.file.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Clear Sent") { reminders.clearFinished() }
                        .disabled(!reminders.book.reminders.contains(where: \.isFinished))
                }
            } header: {
                Text("The file")
            }
        }
    }

    private var footer: String {
        var words = "The plane flies to the middle of the screen your cursor is on, comes at you and opens into a letter: your reminder, a note from whoever threw it, and their signature. Click the letter to fold it away; otherwise it folds itself after this long, counting only while you are at the computer. Off: nothing is delivered, and what came due meanwhile arrives when you turn it back on."
        if settings.brain != .script { words += " With a model, the note is written for the moment (Costs › Reminders)." }
        return words
    }

    private func row(_ reminder: Reminders.Reminder) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.text).font(.headline)
                Text(reminder.isFinished ? "Sent \(Reminders.when(reminder.sentAt ?? reminder.time, now: Date()))" : reminder.describe(now: Date()))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .opacity(reminder.isFinished ? 0.5 : 1)
            Spacer()
            Button("Send Now") { send(reminder) }.buttonStyle(.link).font(.caption)
            Button("Delete") { reminders.remove(reminder.id) }.buttonStyle(.link).font(.caption)
        }
    }

    private func add() {
        let words = text.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        reminders.add(words, at: time, repeats: repeats)
        text = ""
        time = Self.nextRoundHour()
    }

    /// The top of the next hour: a sensible first guess for "when".
    static func nextRoundHour() -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? Date()
    }
}
