import SwiftUI

struct SettingsView: View {
    @Binding var usesUTC: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var liveActivityEnabled: Bool
    @Binding var mockFlightEnabled: Bool
    @Binding var mockFlightMode: MockFlightMode

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use UTC", isOn: $usesUTC)
                    Toggle("Launch reminders", isOn: $notificationsEnabled)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.hairline)

                Section {
                    Toggle("Mock flight", isOn: $mockFlightEnabled)
                    if mockFlightEnabled {
                        Picker("Start from", selection: $mockFlightMode) {
                            ForEach(MockFlightMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                } footer: {
                    Text("Replaces the next flight with a test flight in real time. Turn off and on to restart.")
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.hairline)

                Section {
                    LabeledContent("Version", value: appVersion)
                }
                .listRowBackground(Color.black)
            }
            .font(.subheadline.weight(.light))
            // Clears the tab bar's white tint, which would otherwise colour the controls.
            .tint(nil)
            .scrollContentBackground(.hidden)
            .blackScreen()
            .navigationTitle("SETTINGS")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
