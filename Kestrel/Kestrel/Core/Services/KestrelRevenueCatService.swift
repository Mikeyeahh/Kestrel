//
//  KestrelRevenueCatService.swift
//  Kestrel
//
//  RevenueCat integration for Kestrel Pro subscriptions and suite bundle.
//
//  ── RevenueCat Dashboard Setup ──
//  Entitlement ID: "kestrel_pro"
//    Attach: com.kestrel.pro.monthly, com.kestrel.pro.yearly, com.kestrel.pro.lifetime
//  Entitlement ID: "suite_bundle"
//    Attach: com.suite.bundle.yearly
//  Offering ID: "kestrel_pro"
//    Packages: $rc_monthly, $rc_annual, lifetime, bundle
//
//  ── App Store Connect Products ──
//  com.kestrel.pro.monthly   → Auto-renewable, £3.99/mo
//  com.kestrel.pro.yearly    → Auto-renewable, £24.99/yr
//  com.kestrel.pro.lifetime  → Non-consumable, £49.99
//  com.suite.bundle.yearly   → Auto-renewable, £39.99/yr (OSPREY + Kestrel)
//

import Foundation
import RevenueCat

// MARK: - Product IDs

enum KestrelProductID {
    static let monthly  = "com.kestrel.pro.monthly"
    static let yearly   = "com.kestrel.pro.yearly"
    static let lifetime = "com.kestrel.pro.lifetime"
    static let bundle   = "com.suite.bundle.yearly"
}

// MARK: - Entitlement IDs

enum KestrelEntitlement {
    static let pro    = "kestrel_pro"
    static let bundle = "suite_bundle"
}

// MARK: - Kestrel Feature Gating

enum KestrelFeature: String, CaseIterable {
    case serverDashboard     = "Server Dashboard"
    case sftpFiles           = "SFTP File Manager"
    case aiAssistant         = "AI Terminal Assistant"
    case multiServer         = "Multi-Server Actions"
    case serviceMonitor      = "Service Monitor"
    case sessionRecording    = "Session Recording"
    case commandLibraryEdit  = "Command Library Editing"
    case unlimitedServers    = "Unlimited Servers"
    case unlimitedKeys       = "Unlimited SSH Keys"

    var icon: String {
        switch self {
        case .serverDashboard:    "chart.bar"
        case .sftpFiles:          "folder"
        case .aiAssistant:        "sparkles"
        case .multiServer:        "rectangle.stack"
        case .serviceMonitor:     "gearshape.2"
        case .sessionRecording:   "record.circle"
        case .commandLibraryEdit: "pencil"
        case .unlimitedServers:   "server.rack"
        case .unlimitedKeys:      "key"
        }
    }

    var description: String {
        switch self {
        case .serverDashboard:    "Live CPU, memory, disk, and network stats"
        case .sftpFiles:          "Browse and transfer files over SFTP"
        case .aiAssistant:        "AI-powered terminal output analysis"
        case .multiServer:        "Run commands across multiple servers"
        case .serviceMonitor:     "Monitor systemd services and processes"
        case .sessionRecording:   "Record and audit terminal sessions"
        case .commandLibraryEdit: "Create and edit custom commands"
        case .unlimitedServers:   "Connect to unlimited servers (free: 2)"
        case .unlimitedKeys:      "Store unlimited SSH keys (free: 3)"
        }
    }
}

// MARK: - Free Tier Limits

enum KestrelFreeLimits {
    static let maxServers = 5
    static let maxKeys    = 3
}

// MARK: - Developer Override

/// Emails that automatically receive Pro access (the developer!).
private let kestrelDeveloperEmails: Set<String> = [
    // Add your Supabase login email here (lowercased)
    "totaladdictionxx@me.com"
]

// MARK: - RevenueCat Service

@Observable
@MainActor
final class KestrelRevenueCatService {

    // MARK: - Singleton

    static let shared = KestrelRevenueCatService()

    // MARK: - State

    private(set) var isPro: Bool = false
    private(set) var hasSuiteBundle: Bool = false
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    /// Tracked override — set by simulated purchase, persisted to UserDefaults.
    private(set) var proOverride: Bool = false

    // Offering data
    private(set) var monthlyProduct: StoreProduct?
    private(set) var yearlyProduct: StoreProduct?
    private(set) var lifetimeProduct: StoreProduct?
    private(set) var bundleProduct: StoreProduct?

    private static let proOverrideKey = "kestrel_pro_override"

    // MARK: - Computed

    var isProOrBundle: Bool {
        isPro || hasSuiteBundle || proOverride || isDeveloper || cloudPro
    }

    /// True when the signed-in user matches a developer email.
    private(set) var isDeveloper: Bool = false

    /// Pro entitlement read from the Supabase `subscriptions` table — the
    /// service-role-written source of truth shared with the Mac and Windows
    /// apps. This is how Pro bought on ANY platform shows here, including
    /// RevenueCat Web Billing purchases that the native SDK's `customerInfo`
    /// never reports. Set by `SupabaseService` after auth / on sign-out.
    var cloudPro: Bool = false

    // MARK: - Init

    private init() {
        self.proOverride = UserDefaults.standard.bool(forKey: Self.proOverrideKey)
    }

    // MARK: - Developer Access

    /// Call after Supabase auth restores to check if this is the developer.
    func checkDeveloperAccess(email: String?) {
        guard let email = email?.lowercased() else {
            isDeveloper = false
            return
        }
        isDeveloper = kestrelDeveloperEmails.contains(email)
    }

    // MARK: - Configure

    /// Call from KestrelApp.init with your RevenueCat API key.
    /// - Parameter apiKey: RevenueCat public SDK key for iOS.
    func configure(apiKey: String) {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)

        // Listen for customer info changes
        Purchases.shared.delegate = PurchaseDelegateAdapter.shared

        // Initial fetch
        Task {
            await refreshEntitlements()
            await loadOfferings()
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateEntitlements(from: customerInfo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Links the RevenueCat SDK to the Supabase user id (`app_user_id`) so its
    /// `customerInfo` reflects this account's purchases across every device, and
    /// so native purchases attribute to the right customer / `subscriptions`
    /// row. Guarded on `isConfigured` so an early call during launch (before
    /// `configure`) can't crash.
    func identify(appUserID: String) async {
        guard Purchases.isConfigured else { return }
        do {
            let result = try await Purchases.shared.logIn(appUserID)
            updateEntitlements(from: result.customerInfo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resets the RevenueCat SDK to a fresh anonymous user on sign-out so the
    /// next account can't inherit this one's entitlements.
    func signOutOfRevenueCat() async {
        isPro = false
        hasSuiteBundle = false
        guard Purchases.isConfigured else { return }
        _ = try? await Purchases.shared.logOut()
    }

    func updateEntitlements(from customerInfo: CustomerInfo) {
        isPro = customerInfo.entitlements[KestrelEntitlement.pro]?.isActive == true
        hasSuiteBundle = customerInfo.entitlements[KestrelEntitlement.bundle]?.isActive == true

        // Suite bundle also grants pro
        if hasSuiteBundle {
            isPro = true
        }
    }

    // MARK: - Offerings

    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current ?? offerings["kestrel_pro"] else { return }

            monthlyProduct = offering.monthly?.storeProduct
            yearlyProduct = offering.annual?.storeProduct
            lifetimeProduct = offering.lifetime?.storeProduct

            // Bundle is a custom package
            if let bundlePkg = offering.package(identifier: "bundle") {
                bundleProduct = bundlePkg.storeProduct
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Purchase

    func purchase(_ product: StoreProduct) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await Purchases.shared.purchase(product: product)
            updateEntitlements(from: result.customerInfo)

            // If purchase succeeded but entitlements aren't active
            // (e.g. entitlements not configured in RevenueCat dashboard),
            // grant Pro via override so the purchase still unlocks features.
            if !result.userCancelled && !isProOrBundle {
                proOverride = true
                UserDefaults.standard.set(true, forKey: Self.proOverrideKey)
            }

            isLoading = false
            return !result.userCancelled
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    func purchaseMonthly() async -> Bool {
        guard let product = monthlyProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseYearly() async -> Bool {
        guard let product = yearlyProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseLifetime() async -> Bool {
        guard let product = lifetimeProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    func purchaseBundle() async -> Bool {
        guard let product = bundleProduct else { return simulatePurchase() }
        return await purchase(product)
    }

    /// When RevenueCat products aren't available (e.g. test API key),
    /// simulate a successful purchase so the app can be tested end-to-end.
    private func simulatePurchase() -> Bool {
        proOverride = true
        UserDefaults.standard.set(true, forKey: Self.proOverrideKey)
        return true
    }

    // MARK: - Restore

    func restorePurchases() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateEntitlements(from: customerInfo)
            isLoading = false
            return isPro
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Feature Check

    func canAccess(_ feature: KestrelFeature) -> Bool {
        isProOrBundle
    }

    func isAtServerLimit(currentCount: Int) -> Bool {
        !isProOrBundle && currentCount >= KestrelFreeLimits.maxServers
    }

    func isAtKeyLimit(currentCount: Int) -> Bool {
        !isProOrBundle && currentCount >= KestrelFreeLimits.maxKeys
    }

    /// Returns true when a server at `index` (0-based, sorted by orderIndex)
    /// exceeds the free-tier server limit and the user is not Pro.
    /// Servers within the limit remain fully accessible even after a trial expires.
    func isServerLocked(at index: Int) -> Bool {
        !isProOrBundle && index >= KestrelFreeLimits.maxServers
    }

}

// MARK: - Purchase Delegate Adapter

/// Bridges RevenueCat's delegate pattern to our @Observable service.
private class PurchaseDelegateAdapter: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegateAdapter()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            KestrelRevenueCatService.shared.updateEntitlements(from: customerInfo)
        }
    }
}
