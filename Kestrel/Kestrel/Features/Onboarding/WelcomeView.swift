//
//  WelcomeView.swift
//  Kestrel
//
//  First-launch welcome flow: intro → account → Pro offer.
//

import SwiftUI

// MARK: - Onboarding Step

private enum OnboardingStep: Int, CaseIterable {
    case intro
    case account
    case offer
}

// MARK: - Account Mode

private enum AccountMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case createAccount = "Create Account"

    var id: String { rawValue }
}

// MARK: - Welcome View

/// Shown once, on first launch, before the main app appears.
struct WelcomeView: View {
    /// Called when the user finishes (or skips) onboarding.
    let onComplete: () -> Void

    @ObservedObject private var supabase = SupabaseService.shared
    @State private var revenueCat = KestrelRevenueCatService.shared

    @State private var step: OnboardingStep = .intro

    // Account form state
    @State private var accountMode: AccountMode = .createAccount
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var authError: String?
    @State private var showConfirmEmail = false

    // Paywall
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            KestrelColors.background.ignoresSafeArea()

            ScanlineOverlay()
                .opacity(0.02)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                stepIndicator
                    .padding(.top, 16)

                Group {
                    switch step {
                    case .intro:   introStep
                    case .account: accountStep
                    case .offer:   offerStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
        .onChange(of: revenueCat.isProOrBundle) { _, isPro in
            // Purchase completed inside the paywall sheet — finish onboarding.
            if isPro { finish() }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue
                          ? KestrelColors.phosphorGreen
                          : KestrelColors.cardBorder)
                    .frame(width: s == step ? 20 : 6, height: 6)
                    .animation(.snappy(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Step 1: Intro

    private var introStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Text("◈ KESTREL")
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("SSH · MONITOR · MANAGE")
                    .font(KestrelFonts.mono(10))
                    .tracking(2)
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.4))
            }

            Text("Your servers,\nin your pocket")
                .font(KestrelFonts.display(28, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 28)

            VStack(alignment: .leading, spacing: 0) {
                let highlights: [(String, String)] = [
                    ("terminal",    "Full SSH terminal on the go"),
                    ("chart.bar",   "Live CPU, memory & disk stats"),
                    ("folder",      "Browse & transfer files over SFTP"),
                    ("sparkles",    "AI assistant for terminal output"),
                ]
                ForEach(highlights, id: \.0) { icon, text in
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .frame(width: 22)
                        Text(text)
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)

                    if icon != highlights.last?.0 {
                        Rectangle()
                            .fill(KestrelColors.cardBorder)
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
            .padding(.top, 28)

            Spacer()

            primaryButton(title: "Get Started") {
                advance(to: .account)
            }

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 2: Account

    private var accountStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text(accountMode == .signIn ? "Welcome back" : "Create your account")
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .padding(.top, 16)

            Text("An account syncs your servers, keys, and\ncommands securely across all your devices.")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 6)

            // Mode picker
            Picker("Mode", selection: $accountMode) {
                ForEach(AccountMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 24)
            .onChange(of: accountMode) { _, _ in
                authError = nil
                showConfirmEmail = false
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .tint(KestrelColors.phosphorGreen)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(accountMode == .signIn ? .password : .newPassword)
                    .tint(KestrelColors.phosphorGreen)

                if let authError {
                    Text(authError)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.red)
                        .multilineTextAlignment(.center)
                }

                if showConfirmEmail {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text("Check your email to confirm your account, then sign in.")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
            }
            .padding(.top, 16)

            Spacer()

            primaryButton(
                title: accountMode == .signIn ? "Sign In" : "Create Account",
                isLoading: isWorking,
                isDisabled: email.isEmpty || password.isEmpty
            ) {
                performAuth()
            }

            // Registration is required — no skip button. Replaced with a
            // brief note explaining why an account is mandatory.
            Text("An account is required to use Kestrel — it’s how your servers, keys, and settings sync between devices.")
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 14)

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 3: Pro Offer

    private var offerStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 64, height: 64)
                Text("◈")
                    .font(.system(size: 30))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }

            Text("Unlock Kestrel Pro")
                .font(KestrelFonts.display(24, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .padding(.top, 16)

            Text("Unlimited servers & keys, AI assistant,\nsession recording, and more.")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach([
                    "Unlimited servers & SSH keys",
                    "AI terminal assistant",
                    "Multi-server command execution",
                    "Session recording & audit trail",
                ], id: \.self) { text in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text(text)
                            .font(KestrelFonts.mono(12))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
            .padding(.top, 24)

            Spacer()

            primaryButton(title: "See Plans & Pricing") {
                showingPaywall = true
            }

            Button("Continue with Free Plan") {
                finish()
            }
            .font(KestrelFonts.mono(12))
            .foregroundStyle(KestrelColors.textMuted)
            .padding(.top, 14)

            Text("Free plan: up to \(KestrelFreeLimits.maxServers) servers and \(KestrelFreeLimits.maxKeys) SSH keys.")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.top, 4)

            Spacer().frame(height: 12)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Shared Button

    private func primaryButton(
        title: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(KestrelColors.background)
                }
                Text(isLoading ? "Please wait…" : title)
                    .font(KestrelFonts.monoBold(14))
            }
            .foregroundStyle(KestrelColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(KestrelColors.phosphorGreen)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isDisabled || isLoading ? 0.5 : 1)
        }
        .disabled(isDisabled || isLoading)
    }

    // MARK: - Actions

    private func advance(to next: OnboardingStep) {
        withAnimation(.snappy(duration: 0.3)) {
            step = next
        }
    }

    private func performAuth() {
        isWorking = true
        authError = nil
        showConfirmEmail = false
        Task {
            do {
                switch accountMode {
                case .signIn:
                    try await supabase.signIn(email: email, password: password)
                    advance(to: .offer)
                case .createAccount:
                    let needsConfirmation = try await supabase.signUp(
                        email: email, password: password
                    )
                    if needsConfirmation {
                        showConfirmEmail = true
                    } else {
                        advance(to: .offer)
                    }
                }
            } catch {
                authError = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// Marks onboarding complete; skips the Pro step if the user is already Pro.
    private func finish() {
        onComplete()
    }
}
