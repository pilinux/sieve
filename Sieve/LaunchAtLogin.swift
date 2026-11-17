import ServiceManagement
import SwiftUI

/// The "Launch at login" switch. It shows the real state, so if registering or unregistering fails, the switch does not move.
struct LaunchAtLogin: View {
    let filter: Filter
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Text("Launch at login").font(.aileron(12)).foregroundStyle(.ink2)
            Spacer()
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { on },
                    set: { wanted in Task { if await filter.mayChange() { set(wanted) } } })
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(.allow)
            .held()
        }
    }

    private func set(_ wanted: Bool) {
        let service = SMAppService.mainApp
        do {
            try wanted ? service.register() : service.unregister()
        } catch {
            errorLog.warning("login", "Cannot change Launch at login", error)
        }
        on = service.status == .enabled
    }
}
