import Testing
import UIKit
@testable import Sundae

/// The icons are the app's own copies, not a package's, so a case without its images would show
/// nothing. Every icon ships in all three weights the app draws.
struct IconTests {
    @Test(arguments: Ph.allCases)
    func everyIconHasItsThreeWeights(_ icon: Ph) {
        for name in [icon.rawValue, "\(icon.rawValue)-bold", "\(icon.rawValue)-fill"] {
            #expect(UIImage(named: name, in: .main, compatibleWith: nil) != nil, "\(name) is missing from Assets.xcassets/Icons")
        }
    }
}
