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
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["app": "kestrel"])
    }

    static func capture(_ event: String, _ properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
