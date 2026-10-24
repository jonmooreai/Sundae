import SwiftUI

/// One icon set, referenced by name in one place.
///
/// The PRD picks Phosphor Icons. Until the PhosphorSwift package is added to the project,
/// these map to the closest SF Symbols so the app builds without a network fetch.
/// Swapping the set is a change to this file only: keep the case names, change the bodies.
enum Icon {
    static let feed = "house"
    static let search = "magnifyingglass"
    static let post = "plus.circle"
    static let approvals = "checkmark.circle"
    static let profile = "person.circle"
    static let settings = "gearshape"
    static let shuffle = "shuffle"
    static let done = "checkmark"
    static let heart = "heart"
    static let heartFilled = "heart.fill"
    static let comment = "bubble"
    static let tag = "tag"
    static let more = "ellipsis"
    static let close = "xmark"
    static let trash = "trash"
    static let lock = "lock"
    static let photos = "photo.on.rectangle"
    static let reorder = "arrow.up.arrow.down"
    static let person = "person"
    static let personAdd = "person.badge.plus"
    static let bell = "bell"
    static let share = "square.and.arrow.up"
    static let calendar = "calendar"
    static let sun = "sun.max"
    static let flag = "flag"
    static let block = "hand.raised"
    static let chevronRight = "chevron.right"
    static let altText = "text.below.photo"
    static let eyeOff = "eye.slash"
}
