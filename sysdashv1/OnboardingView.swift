import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var monitor: SystemMonitor
    @Binding var isPresented: Bool

    @AppStorage("sysdash.onboardingDone") private var onboardingDone = false

    @State private var loginEnabled = LoginItemManager.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 6) {
                Text("Welcome to UP SysDash")
                    .font(.system(size: 17, weight: .bold))
                Text("Set up a couple of things before you start.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                onboardingCard(
                    icon: "bolt.fill",
                    tint: .mint,
                    title: "Launch at Login",
                    description: "SysDash starts at boot and keeps your stats visible in the menu bar from the moment you log in."
                ) {
                    loginAction
                }
            }
            .padding(.horizontal, 24)

            Button(action: finish) {
                Text("Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 400)
        .onDisappear { onboardingDone = true }
    }

    @ViewBuilder
    private var loginAction: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Toggle("", isOn: $loginEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: loginEnabled) { enabled in
                    do {
                        if enabled { try LoginItemManager.enable() }
                        else       { try LoginItemManager.disable() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        loginEnabled = !enabled
                    }
                }
            if let err = loginError {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func finish() {
        onboardingDone = true
        isPresented = false
    }

    private func onboardingCard<Action: View>(
        icon: String,
        tint: Color,
        title: String,
        description: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            action()
                .frame(minWidth: 80, alignment: .trailing)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}
