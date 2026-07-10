// FMSeedGate — runtime probe for the FoundationModels API surface this binary was built
// against. FoundationModels ships in the OS and its Swift ABI has churned between OS 27
// beta seeds (e.g. the Attachment<ImageAttachmentContent> initializer manglings changed
// between iOS 27 beta 1 and the beta 3 SDK), while App Store Connect only accepts archives
// built with the newest beta SDK — so a TestFlight build can land on a device whose seed
// predates the SDK. The framework is weak-linked (see project.yml OTHER_LDFLAGS), which
// keeps dyld from killing the app at launch; this gate detects the mismatch so the
// FM-backed features degrade to an "update iOS" notice instead of trapping at call time.
//
// The sentinels are the exact mangled names this build references. If the FM call sites
// change (or a new SDK re-mangles them), regenerate with:
//   nm -u CoreAIZoo.app/CoreAIZoo | grep 16FoundationModels

import Darwin

enum FMSeedGate {
    /// True when the OS exports the FoundationModels symbols this binary references,
    /// i.e. the device's OS seed matches the SDK the app was archived with.
    static let available: Bool = {
        let sentinels = [
            // Attachment<ImageAttachmentContent>.init(_:orientation:) — VisionModel prompt
            "$s16FoundationModels10AttachmentVA2A05ImageC7ContentVRszlE_11orientationACyAEGSo10CGImageRefa_So0G19PropertyOrientationVSgtcfC",
            // LanguageModelExecutorGenerationChannel.send — the kit's FM executor bridge
            "$s16FoundationModels38LanguageModelExecutorGenerationChannelV4sendyyAC5EventVYaF",
        ]
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        return sentinels.allSatisfy { dlsym(rtldDefault, $0) != nil }
    }()
}
