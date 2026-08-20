# Research: Apple SwiftUI/UIKit Dynamic Type size system

## Summary

`DynamicTypeSize` is a `@frozen` SwiftUI enum with exactly **12 cases**, ordered smallest→largest as `xSmall, small, medium, large, xLarge, xxLarge, xxxLarge, accessibility1…accessibility5`. There is **no `.default` case** — `default` is a *static property* (`public static let \`default\`: DynamicTypeSize`) that evaluates to `.large`. Apple publishes no official numeric point-size table; the rendered sizes are derived by runtime measurement (`UIFont.preferredFont(forTextStyle:)`), with the `.body` style producing `[14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]` pt and corresponding scale factors `0.82…3.12` relative to `.large`. SwiftUI's `.dynamicTypeSize(_:)` writes a value/range into the `\.dynamicTypeSize` environment, so only dynamic-type-responsive content (text styles, SF Symbols, `@ScaledMetric`) scales; `large` is the 1.0× baseline.

---

## Findings

### 1. Full ordered list of `DynamicTypeSize` cases (smallest → largest)

Ordered ascending (SwiftUI `DynamicTypeSize` == SwiftUICore since Xcode 16 / iOS 18):

1. `.xSmall`
2. `.small`
3. `.medium`
4. `.large`  ← default/baseline (1.0×)
5. `.xLarge`
6. `.xxLarge`
7. `.xxxLarge`
8. `.accessibility1`  (AX1)
9. `.accessibility2`  (AX2)
10. `.accessibility3`  (AX3)
11. `.accessibility4`  (AX4)
12. `.accessibility5`  (AX5)

The declaration in `SwiftUICore.swiftinterface` (re-exported by `SwiftUI`; identical declaration in pre-iOS-18 `SwiftUI.swiftinterface`):

```swift
@frozen public enum DynamicTypeSize : Hashable, @unchecked Sendable, Comparable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    public static let allCases: [DynamicTypeSize]
    public static let `default`: DynamicTypeSize
    public var isAccessibilitySize: Bool { get }
    public init?(_ uiSizeCategory: UIContentSizeCategory)
}
```

Key facts:
- **There is no `.default` enum case.** `default` is a *static property* (backtick-escaped because `default` is a keyword) whose value is **`.large`**. You can read `DynamicTypeSize.default` but you cannot write `case .default` in a switch or use `.default` as one of the 12 cases. [Apple DynamicTypeSize docs](https://developer.apple.com/documentation/SwiftUI/DynamicTypeSize), [OpenSwiftUI mirror](https://openswiftuiproject.github.io/OpenSwiftUI/documentation/openswiftui/dynamictypesize/)
- `isAccessibilitySize` returns `true` only for `accessibility1…accessibility5`. [Apple docs](https://developer.apple.com/documentation/swiftui/dynamictypesize/accessibility1)
- The enum is `Comparable` and `CaseIterable`, so `allCases` yields the 12 cases in the ascending order above, and ranges like `...DynamicTypeSize.large` or `DynamicTypeSize.large...DynamicTypeSize.xxxLarge` are valid. [Apple docs](https://developer.apple.com/documentation/swiftui/view/dynamictypesize%28_%3A%29-26aj0)
- **Module note:** since Xcode 16 / iOS 18 Apple split SwiftUI internally; `DynamicTypeSize` physically lives in the `SwiftUICore` module but is re-exported through `SwiftUI`. App code keeps `import SwiftUI`. Direct `import SwiftUICore` is discouraged and on newer toolchains errors ("implementation detail of SwiftUI"). [Apple forums](https://developer.apple.com/forums/thread/765256), [Swift Forums](https://forums.swift.org/t/swiftuicore-vs-swiftui/73722)

### 2. Rendered point sizes and scale factors (UIKit Dynamic Type / font metrics)

Apple does **not** publish an official point-size or scale-factor table in its API documentation; the values below are empirically derived from `UIFont.preferredFont(forTextStyle:)`. The most authoritative publicly available source is Chromium's `ios/components/ui_util/dynamic_type_util.mm`, whose code comment states the values are "calculated by `[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize`", and whose unit test asserts each value. [Chromium dynamic_type_util.mm](https://chromium.googlesource.com/chromium/src/ios/+/f2b44ae3cc5ec601262093ce53cc7f372bca86e6/components/ui_util/dynamic_type_util.mm), [Chromium unit test](https://chromium.googlesource.com/chromium/src/+/9137066a882af5487003834302664a9ab20a281f/ios/components/ui_util/dynamic_type_util_unittest.mm)

**`.body` text style — point size and scale factor per content-size category:**

| SwiftUI `DynamicTypeSize` | UIKit `UIContentSizeCategory` | Body pt | Scale vs `.large` (pt/17) | Chromium multiplier |
|---|---|---|---|---|
| `.xSmall` | `.extraSmall` | 14 | 0.8235 | 0.82 |
| `.small` | `.small` | 15 | 0.8824 | 0.88 |
| `.medium` | `.medium` | 16 | 0.9412 | 0.94 |
| `.large` (default) | `.large` | 17 | 1.0000 | 1.00 |
| `.xLarge` | `.extraLarge` | 19 | 1.1176 | 1.12 |
| `.xxLarge` | `.extraExtraLarge` | 21 | 1.2353 | 1.24 |
| `.xxxLarge` | `.extraExtraExtraLarge` | 23 | 1.3529 | 1.35 |
| `.accessibility1` | `.accessibilityMedium` | 28 | 1.6471 | 1.65 |
| `.accessibility2` | `.accessibilityLarge` | 33 | 1.9412 | 1.94 |
| `.accessibility3` | `.accessibilityExtraLarge` | 40 | 2.3529 | 2.35 |
| `.accessibility4` | `.accessibilityExtraExtraLarge` | 47 | 2.7647 | 2.76 |
| `.accessibility5` | `.accessibilityExtraExtraExtraLarge` | 53 | 3.1176 | 3.12 |

`UIFontMetrics.default.scaledValue(for:)` and SwiftUI's `@ScaledMetric` (default `relativeTo: .body`) use exactly these body-relative multipliers — e.g. a `20` pt base value becomes ~`47` pt at `.accessibility3`. [Apple UIFontMetrics docs](https://developer.apple.com/documentation/uikit/uifontmetrics), [Lickability](https://lickability.com/blog/dynamic-type-and-in-app-font-scaling/)

**Base point sizes of each text style at `.large` (Apple HIG typography):**

| Text style | pt at Large |
|---|---|
| Large Title | 34 |
| Title 1 | 28 |
| Title 2 | 22 |
| Title 3 | 20 |
| Headline (Semibold) | 17 |
| Body | 17 |
| Callout | 16 |
| Subheadline | 15 |
| Footnote | 13 |
| Caption 1 | 12 |
| Caption 2 | 11 |

[Apple HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

Important caveats:
- **The scale curve is per text style, not a single linear multiplier.** Each `UIFont.TextStyle` has its own point-size curve; e.g. Large Title runs 31→…→34→…→~52 at AX5 (it grows less aggressively than `.body`). The body table above is only exact for `.body`/`UIFontMetrics.default`. [Apple HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- **The numbers drift slightly across OS versions.** Search results note e.g. AX5 measured at ~2.99× on some iOS 15/16 builds instead of 3.12×. For pixel-exact values, measure `UIFont.preferredFont(forTextStyle: .body).pointSize` at runtime.
- **The 11/13/17/20 values match Caption 2 / Footnote / Body / Title 3.** The "24" in the question has no direct standard-system equivalent (nearest neighbors are Title 2 = 22, Title 1 = 28, and `.body` at `.xxxLarge` = 23).
- **Accessibility categories are only reachable** when "Larger Accessibility Sizes" is enabled (Settings → Accessibility → Display & Text Size → Larger Text). Without it, the scale tops out at `.extraExtraExtraLarge` (1.35×).
- **`UIContentSizeCategory` has a 13th value, `.unspecified`**, which is not part of the 12-step ordered scale; `DynamicTypeSize.init?(_:)` returns `nil` for it (and unknown values). [Apple UIContentSizeCategory docs](https://developer.apple.com/documentation/uikit/uicontentsizecategory)

### 3. How SwiftUI's `.dynamicTypeSize(_ size:)` scales a hierarchy

- It sets/constrains the `\.dynamicTypeSize` environment value for the view **and its entire descendant subtree**; `large` is the baseline (1.0×). Two overloads exist: a fixed value `dynamicTypeSize(_ size: DynamicTypeSize)` and a range `dynamicTypeSize(_ range: some RangeExpression<DynamicTypeSize>)`. [Apple dynamicTypeSize docs](https://developer.apple.com/documentation/swiftui/view/dynamictypesize%28_%3A%29-26aj0)
- `.dynamicTypeSize(.large)` pins the subtree to Large regardless of the user's system setting (used in previews to validate layout). A partial range like `...DynamicTypeSize.large` lets the system scale normally up to the Large baseline; `DynamicTypeSize.large...` floors it at Large.
- **It is not a single multiplicative zoom.** Only dynamic-type-responsive content changes: system text styles (`.font(.body)`, etc.), SF Symbols, and `@ScaledMetric` values. Fixed-size fonts (`.font(.system(size: 14))`, `.font(.custom(..., fixedSize:))`), fixed frames, paddings, and plain images do **not** scale. Non-text metrics scale only if opted in via `@ScaledMetric(relativeTo:)` (defaults to `.body` at `.large`). [Hacking with Swift — specify supported sizes](https://www.hackingwithswift.com/quick-start/swiftui/how-to-specify-the-dynamic-type-sizes-a-view-supports), [Apple ScaledMetric](https://developer.apple.com/documentation/swiftui/scaledmetric)
- The environment value can be read via `@Environment(\.dynamicTypeSize)` for layout decisions (e.g. `isAccessibilitySize` → stack vertically); this read reflects any ancestor's `.dynamicTypeSize(...)` override, not the user's raw system value. [Apple EnvironmentValues.dynamicTypeSize](https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize)

**SwiftUI ↔ UIKit 1:1 mapping** (via `DynamicTypeSize.init?(_ uiSizeCategory:)` and `UIContentSizeCategory.init(_ dynamicTypeSize:)`):

`xSmall↔extraSmall`, `small↔small`, `medium↔medium`, `large↔large`, `xLarge↔extraLarge`, `xxLarge↔extraExtraLarge`, `xxxLarge↔extraExtraExtraLarge`, `accessibility1↔accessibilityMedium`, `accessibility2↔accessibilityLarge`, `accessibility3↔accessibilityExtraLarge`, `accessibility4↔accessibilityExtraExtraLarge`, `accessibility5↔accessibilityExtraExtraExtraLarge`. [Apple DynamicTypeSize.init docs](https://developer.apple.com/documentation/swiftui/dynamictypesize/init%28_%3A%29)

---

## Sources

**Kept:**
- Apple — `DynamicTypeSize` (https://developer.apple.com/documentation/SwiftUI/DynamicTypeSize) — authoritative case list, `default`/`allCases` static properties, `isAccessibilitySize`.
- Apple — `dynamicTypeSize(_:)` (https://developer.apple.com/documentation/swiftui/view/dynamictypesize%28_%3A%29-26aj0) — modifier semantics and range overloads.
- Apple — `UIContentSizeCategory` (https://developer.apple.com/documentation/uikit/uicontentsizecategory) — 13 UIKit categories incl. `.unspecified`.
- Apple — `UIFontMetrics` (https://developer.apple.com/documentation/uikit/uifontmetrics) — `scaledValue` scaling mechanism.
- Apple — HIG Typography (https://developer.apple.com/design/human-interface-guidelines/typography) — official base point sizes per text style at Large.
- Chromium `dynamic_type_util.mm` (https://chromium.googlesource.com/chromium/src/ios/+/f2b44ae3cc5ec601262093ce53cc7f372bca86e6/components/ui_util/dynamic_type_util.mm) — hardcoded, unit-tested body point sizes `[14,15,16,17,19,21,23,28,33,40,47,53]` and multipliers; best available authoritative numeric table.
- Chromium `dynamic_type_util_unittest.mm` (https://chromium.googlesource.com/chromium/src/+/9137066a882af5487003834302664a9ab20a281f/ios/components/ui_util/dynamic_type_util_unittest.mm) — asserts each point size.
- OpenSwiftUI `DynamicTypeSize` docs (https://openswiftuiproject.github.io/OpenSwiftUI/documentation/openswiftui/dynamictypesize/) — open-source mirror of the `.swiftinterface` declaration.
- Apple Forums / Swift Forums (https://developer.apple.com/forums/thread/765256; https://forums.swift.org/t/swiftuicore-vs-swiftui/73722) — SwiftUICore module-split context.
- Lickability (https://lickability.com/blog/dynamic-type-and-in-app-font-scaling/) — practical scale-factor explanation.

**Dropped:**
- Various Stack Overflow / third-party blog tables — redundant with Chromium primary source or lacking unit-test backing.
- cvs-health accessibility markdown — accurate but secondary; superseded by Apple docs.
- Orange/OpenSwiftUI DocC auto-generated pages — duplicate of the interface, no added fact.

---

## Gaps

- **Exact numeric point sizes are not in Apple's public docs.** Apple publishes the text-style base sizes (HIG) but not the 12-step per-category numeric table; the numbers here are empirically derived (Chromium's unit-tested constants, corroborated across sources). Confirm against the installed SDK at runtime if exact values matter for a specific iOS version.
- **`.default`'s exact value is not spelled out in Apple's docs** as "== .large"; it is stated as "the default dynamic type size." The `.large` value is confirmed by the interface declaration plus community/mirror sources. (Distinct from `\.dynamicTypeSize`'s *environment* default, which Apple documents as device-dependent.)
- **Per-text-style scale curves** (e.g. exact Large Title point sizes at each of the 12 steps) are only partially published (HIG gives the Large baseline; full per-step curves are not in Apple docs).
- The "24 pt" in the original question has no exact standard system equivalent; nearest are Title 2 (22), Title 1 (28), or Body@xxxLarge (23).
