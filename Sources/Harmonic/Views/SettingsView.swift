import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: SpotifyAuthService

    private enum Tab: Hashable, CaseIterable {
        case spotify, menuBar

        var title: String {
            switch self {
            case .spotify: "Spotify"
            case .menuBar: "Menu Bar"
            }
        }

        var icon: String {
            switch self {
            case .spotify: "music.note.list"
            case .menuBar: "menubar.rectangle"
            }
        }
    }

    @State private var selectedTab: Tab = .spotify

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 160)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 580, height: 420)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .spotify: spotifyContent
        case .menuBar: menuBarContent
        }
    }

    // MARK: - Spotify tab

    private var spotifyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $auth.oauthEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Like / Unlike")
                        .font(.headline)
                    Text("Connect a Spotify Developer App to like or unlike tracks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if auth.oauthEnabled {
                Divider()
                credentialsForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.oauthEnabled)
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Client ID",    $auth.clientId)
            field("Redirect URI", $auth.redirectURI)
            connectRow

            if let err = auth.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectRow: some View {
        HStack(spacing: 10) {
            if auth.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Disconnect", role: .destructive) { auth.disconnect() }
                    .controlSize(.small)
            } else {
                Button(auth.isAuthenticating ? "Connecting…" : "Connect with Spotify") {
                    Task { await auth.authorize() }
                }
                .disabled(auth.clientId.isEmpty || auth.isAuthenticating)
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 86, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
        }
    }

    // MARK: - Menu Bar tab (placeholder)

    private var menuBarContent: some View {
        Text("Menu Bar customization — coming soon.")
            .foregroundStyle(.secondary)
    }
}
