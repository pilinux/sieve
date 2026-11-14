import ServiceManagement
import SwiftUI

/// The "Launch at login" switch. Shows the real state: if (un)registering fails, the switch stays put.
struct LaunchAtLogin: View {
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Text("Launch at login").font(.aileron(12)).foregroundStyle(.ink2)
            Spacer()
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { on },
                    set: { wanted in
                        let service = SMAppService.mainApp
                        do {
                            try wanted ? service.register() : service.unregister()
                        } catch {
                            errorLog.warning("login", "Cannot change Launch at login", error)
                        }
                        on = service.status == .enabled
                    })
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(.allow)
        }
    }
}
