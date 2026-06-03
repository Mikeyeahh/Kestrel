import Foundation
import PostHog

enum Analytics {
    static func configure() {
        let config = PostHogConfig(
            projectToken: "phc_myxUuqQuwpLnp8GMx6GgDoCAkB67s3tEawSmZ7WsfVHx",
            host: "https://eu.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true

        // Session replay (mobile). Screenshot mode renders SwiftUI correctly;
        // standard text inputs and images are masked.
        //
        // ⚠️ SECURITY: the SSH terminal (SwiftTerm), SFTP file views, and key
        // material are CUSTOM views — they are NOT auto-masked and would be
        // captured in full. Mask those views with `.postHogMask()` (see
        // TerminalView / SFTP / key-management screens) before relying on this
        // in production, or sensitive output and credentials could be recorded.
        config.sessionReplay = true
        config.sessionReplayConfig.screenshotMode = true
        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.maskAllImages = true

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["app": "kestrel"])
    }

    static func capture(_ event: String, _ properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
