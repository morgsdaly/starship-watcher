import SwiftUI
import UIKit

struct SettingsView: View {
    @Binding var usesUTC: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var liveActivityEnabled: Bool
    @Binding var mockFlightEnabled: Bool
    @Binding var mockFlightMode: MockFlightMode

    @AppStorage("reminderDayBefore") private var reminderDayBefore = true
    @AppStorage("reminderCountdown") private var reminderCountdown = true
    @AppStorage("reminderWebcast") private var reminderWebcast = true
    @AppStorage("reminderChanges") private var reminderChanges = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use UTC", isOn: $usesUTC)
                    Toggle("Launch reminders", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        Group {
                            Toggle("The day before", isOn: $reminderDayBefore)
                            Toggle("Countdown ready to pin", isOn: $reminderCountdown)
                            Toggle("30 minutes before", isOn: $reminderWebcast)
                            Toggle("New dates, holds and results", isOn: $reminderChanges)
                        }
                        .padding(.leading, 16)
                        .foregroundStyle(Theme.secondary)
                    }
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        Link("Permissions in iOS Settings", destination: settingsURL)
                            .foregroundStyle(.white)
                    }
                } footer: {
                    Text("The Live Activity pins the countdown to your Lock Screen from three hours before liftoff. iOS starts it by itself once a launch time is set.")
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.hairline)

                Section {
                    Toggle("Preview a launch", isOn: $mockFlightEnabled)
                    if mockFlightEnabled {
                        Picker("Start from", selection: $mockFlightMode) {
                            ForEach(MockFlightMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                } footer: {
                    Text("Runs a practice flight in real time, so you can see the countdown, stages and Live Activity before launch day. Turn off and on to restart.")
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.hairline)

                Section {
                    if let url = URL(string: "https://thespacedevs.com") {
                        Link("Launch data: The Space Devs", destination: url)
                            .foregroundStyle(.white)
                    }
                    if let url = URL(string: "https://spaceflightnewsapi.net") {
                        Link("News: Spaceflight News API", destination: url)
                            .foregroundStyle(.white)
                    }
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Times after liftoff follow the planned timeline, not live telemetry.")
                }
                .listRowBackground(Color.black)
                .listRowSeparatorTint(Theme.hairline)
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
