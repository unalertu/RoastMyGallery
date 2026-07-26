import Foundation

/// Build-time configuration. Exactly one place to point the app at a backend.
enum AppConfig {
    /// Base URL of the insight backend (see `backend/README.md` for deploy).
    ///
    /// - Production (deployed 2026-07-14, Vercel project "ertu-hobby/backend"):
    ///   `https://backend-ertu-hobby.vercel.app`
    /// - Local development: run `vercel dev` in `backend/` and switch to
    ///   `http://localhost:3000` (the simulator reaches the Mac's localhost;
    ///   ATS local-networking exception is set in project.yml).
    static let backendBaseURL = URL(string: "https://backend-ertu-hobby.vercel.app")!

    /// Shared secret sent as the `X-App-Secret` header on every insight
    /// request. Must match the backend's `APP_SHARED_SECRET` env var (Vercel
    /// dashboard); the backend only enforces the check once that var is set.
    ///
    /// THREAT MODEL: this is a tripwire, not authentication. It's embedded in
    /// the shipped binary, so anyone who extracts it can call the API — the
    /// point is to stop casual abuse (someone finding the URL and curling it),
    /// not a determined attacker. Rotate by changing both this value and the
    /// Vercel env var. If the app ever gets real traction, replace with
    /// App Attest.
    static let appSharedSecret = "17ad313147db12c78c1c2191622e96bb6be43919ae3662b143ca65f109e9f8d9"

    /// Public legal pages, served by the Cloudflare Worker that hosts the
    /// app's site. Linked from the permission screen, the paywall and Settings
    /// — kept here so a move to a custom domain is a one-line change instead of
    /// a hunt through three views.
    static let privacyPolicyURL = URL(string: "https://roastmygallery.unlertu.workers.dev/privacy/")!
    static let termsOfUseURL = URL(string: "https://roastmygallery.unlertu.workers.dev/terms/")!

    /// Support page — the same URL given to App Store Connect as the app's
    /// Support URL. Settings → Contact & Feedback opens this rather than a
    /// `mailto:` draft, so a user with no mail account configured still gets
    /// somewhere useful (the page carries the FAQ *and* the contact address).
    static let supportURL = URL(string: "https://roastmygallery.unlertu.workers.dev/support/")!
}
