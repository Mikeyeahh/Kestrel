//
//  KestrelPaywallView.swift
//  Kestrel
//
//  Paywall screen for Kestrel Pro subscriptions.
//

import SwiftUI
import RevenueCat

// MARK: - Plan Type

private enum PlanType: String, CaseIterable, Identifiable {
    case monthly  = "Monthly"
    case yearly   = "Yearly"
    case lifetime = "Lifetime"

    var id: String { rawValue }
}

// MARK: - Kestrel Paywall View

struct KestrelPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var revenueCat = KestrelRevenueCatService.shared
    @State private var selectedPlan: PlanType = .yearly
    @State private var isPurchasing = false
    @State private var showingError = false
    @State private var purchaseSucceeded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Hero
                    heroSection

                    // Feature list
                    featureList

                    // Plan cards
                    planCards

                    // Suite bundle card
                    if !revenueCat.hasSuiteBundle {
                        bundleCard
                    }

                    // CTA
                    purchaseButton

                    // Restore + terms
                    footerLinks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(KestrelColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
            }
            .toolbarBackground(KestrelColors.background, for: .navigationBar)
        }
        .alert("Purchase Successful", isPresented: $purchaseSucceeded) {
            Button("Done") { dismiss() }
        } message: {
            Text("Welcome to Kestrel Pro!")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(revenueCat.errorMessage ?? "Something went wrong")
        }
        .onAppear {
            Analytics.capture("paywall_shown")
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 80, height: 80)

                Text("◈")
                    .font(.system(size: 36))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }
            .padding(.top, 20)

            Text("KESTREL PRO")
                .font(KestrelFonts.mono(14))
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Unlock the full\nserver toolkit")
                .font(KestrelFonts.display(28, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("Everything you need to manage, monitor,\nand secure your infrastructure from anywhere")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let features: [(String, String)] = [
                ("server.rack",       "Unlimited servers & SSH keys"),
                ("chart.bar",         "Live server dashboard with charts"),
                ("folder",            "SFTP file manager"),
                ("sparkles",          "AI terminal assistant"),
                ("rectangle.stack",   "Multi-server command execution"),
                ("gearshape.2",       "Service monitor & process manager"),
                ("record.circle",     "Session recording & audit trail"),
                ("command",           "Full command library editing"),
            ]

            ForEach(features, id: \.0) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .frame(width: 20)

                    Text(text)
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textPrimary)

                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)

                if icon != features.last?.0 {
                    Rectangle()
                        .fill(KestrelColors.cardBorder)
                        .frame(height: 1)
                        .padding(.leading, 46)
                }
            }
        }
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
        )
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        HStack(spacing: 10) {
            planCard(
                type: .monthly,
                label: "Monthly",
                price: revenueCat.monthlyProduct?.localizedPriceString ?? "£3.99",
                period: "/mo"
            )

            planCard(
                type: .yearly,
                label: "Yearly",
                price: revenueCat.yearlyProduct?.localizedPriceString ?? "£24.99",
                period: "/yr",
                badge: "BEST VALUE"
            )

            planCard(
                type: .lifetime,
                label: "Lifetime",
                price: revenueCat.lifetimeProduct?.localizedPriceString ?? "£49.99",
                period: "once"
            )
        }
    }

    private func planCard(
        type: PlanType,
        label: String,
        price: String,
        period: String,
        badge: String? = nil
    ) -> some View {
        let isSelected = selectedPlan == type

        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                selectedPlan = type
            }
        } label: {
            VStack(spacing: 8) {
                if let badge {
                    Text(badge)
                        .font(KestrelFonts.mono(7))
                        .fontWeight(.bold)
                        .tracking(0.5)
                        .foregroundStyle(KestrelColors.background)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(Capsule())
                } else {
                    Spacer()
                        .frame(height: 14)
                }

                Text(label)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(isSelected ? KestrelColors.textPrimary : KestrelColors.textMuted)

                Text(price)
                    .font(KestrelFonts.display(18, weight: .bold))
                    .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textPrimary)

                Text(period)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bundle Card

    private var bundleCard: some View {
        Button {
            selectedPlan = .yearly // switch context — bundle purchase handled separately
            Task { await purchaseBundle() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("OSPREY + KESTREL")
                            .font(KestrelFonts.mono(10))
                            .fontWeight(.bold)
                            .tracking(1)
                            .foregroundStyle(KestrelColors.amber)

                        Text("SUITE")
                            .font(KestrelFonts.mono(8))
                            .fontWeight(.bold)
                            .foregroundStyle(KestrelColors.background)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(KestrelColors.amber)
                            .clipShape(Capsule())
                    }

                    Text("The complete engineer's suite")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(revenueCat.bundleProduct?.localizedPriceString ?? "£39.99")
                        .font(KestrelFonts.display(16, weight: .bold))
                        .foregroundStyle(KestrelColors.amber)
                    Text("/yr")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [KestrelColors.amber.opacity(0.06), KestrelColors.amber.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [KestrelColors.amber.opacity(0.5), KestrelColors.amber.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await performPurchase() }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(KestrelColors.background)
                }
                Text(isPurchasing ? "Processing…" : "Continue with \(selectedPlan.rawValue)")
                    .font(KestrelFonts.monoBold(14))
            }
            .foregroundStyle(KestrelColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(KestrelColors.phosphorGreen)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isPurchasing)
    }

    // MARK: - Footer

    private var footerLinks: some View {
        VStack(spacing: 10) {
            Button {
                Task { await restore() }
            } label: {
                Text("Restore Purchases")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://getosprey.app/terms")!)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)

                Link("Privacy Policy", destination: URL(string: "https://getosprey.app/privacy")!)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Text("Payment charged to your Apple ID. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Actions

    private func performPurchase() async {
        isPurchasing = true

        let success: Bool
        switch selectedPlan {
        case .monthly:  success = await revenueCat.purchaseMonthly()
        case .yearly:   success = await revenueCat.purchaseYearly()
        case .lifetime: success = await revenueCat.purchaseLifetime()
        }

        isPurchasing = false

        if success {
            purchaseSucceeded = true
        } else if revenueCat.errorMessage != nil {
            showingError = true
        }
    }

    private func purchaseBundle() async {
        isPurchasing = true
        let success = await revenueCat.purchaseBundle()
        isPurchasing = false

        if success {
            purchaseSucceeded = true
        } else if revenueCat.errorMessage != nil {
            showingError = true
        }
    }

    private func restore() async {
        isPurchasing = true
        let restored = await revenueCat.restorePurchases()
        isPurchasing = false

        if restored {
            purchaseSucceeded = true
        }
    }
}

// MARK: - Pro Locked View (Blur Overlay)

struct ProLockedView: View {
    let feature: KestrelFeature
    @State private var showingPaywall = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Pro Feature")
                .font(KestrelFonts.display(18, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(feature.rawValue)
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text(feature.description)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 6) {
                    Text("◈")
                        .font(.system(size: 12))
                    Text("Unlock with Pro")
                        .font(KestrelFonts.monoBold(13))
                }
                .foregroundStyle(KestrelColors.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(KestrelColors.phosphorGreen)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.95))
        .sheet(isPresented: $showingPaywall) {
            KestrelPaywallView()
        }
    }
}

// MARK: - Pro Gated ViewModifier

struct ProGatedModifier: ViewModifier {
    let feature: KestrelFeature
    @State private var revenueCat = KestrelRevenueCatService.shared

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: revenueCat.isProOrBundle ? 0 : 6)
                .allowsHitTesting(revenueCat.isProOrBundle)

            if !revenueCat.isProOrBundle {
                ProLockedView(feature: feature)
            }
        }
    }
}

extension View {
    /// Gates this view behind a Kestrel Pro subscription.
    /// Shows a blur overlay with unlock button if the user is not Pro.
    func proGated(feature: KestrelFeature) -> some View {
        modifier(ProGatedModifier(feature: feature))
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(KestrelFonts.mono(8))
            .fontWeight(.bold)
            .tracking(0.8)
            .foregroundStyle(KestrelColors.background)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(KestrelColors.phosphorGreen)
            .clipShape(Capsule())
    }
}
