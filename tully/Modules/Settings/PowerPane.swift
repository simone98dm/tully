import SwiftUI

struct PowerPane: View {
    @Environment(PreventSleepService.self) private var preventSleep
    @Environment(KeyboardCleaningService.self) private var keyboardCleaning

    var body: some View {
        @Bindable var preventSleep = preventSleep
        @Bindable var keyboardCleaning = keyboardCleaning
        Form {
            Section {
                Toggle(isOn: Binding(get: { preventSleep.isEnabled }, set: { preventSleep.setEnabled($0) })) {
                    Text("Prevent sleep")
                    if let endsAt = preventSleep.endsAt {
                        Text("Until \(endsAt.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("Keeps your Mac awake while it's on. Turns off when tully quits.")
                    }
                }
                .accessibilityLabel("Prevent sleep")
                Picker("Keep awake", selection: $preventSleep.keepsDisplayAwake) {
                    Text("Mac and display").tag(true)
                    Text("Mac only (display may sleep)").tag(false)
                }
                .accessibilityLabel("Keep awake")
                Picker("Duration", selection: $preventSleep.duration) {
                    ForEach(PreventSleepService.Duration.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityLabel("Duration")
            } header: {
                Text("Prevent Sleep")
            }

            Section {
                Toggle(isOn: Binding(get: { keyboardCleaning.isEnabled }, set: { keyboardCleaning.setEnabled($0) })) {
                    Text("Disable keyboard for cleaning")
                    Text("Every key, including media keys, is ignored until you click Done.")
                }
                .accessibilityLabel("Disable keyboard for cleaning")
                Picker("Turn the keyboard back on after", selection: $keyboardCleaning.autoExitSeconds) {
                    ForEach(KeyboardCleaningService.autoExitChoices, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) minute\(seconds == 60 ? "" : "s")").tag(seconds)
                    }
                }
                .accessibilityLabel("Turn the keyboard back on after")
            } header: {
                Text("Keyboard Cleaning")
            } footer: {
                Text("Needs Accessibility permission.")
            }
        }
        .formStyle(.grouped)
    }
}
