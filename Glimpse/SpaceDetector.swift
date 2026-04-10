import Foundation

/// Private CGS APIs for detecting fullscreen Spaces.
/// Type 0 = normal desktop, Type 4 = fullscreen Space.

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> UInt64

@_silgen_name("CGSSpaceGetType")
func CGSSpaceGetType(_ cid: CGSConnectionID, _ space: UInt64) -> Int32

struct SpaceDetector {
    /// Returns true if the currently active Space is a fullscreen Space.
    static func isFullscreenSpace() -> Bool {
        let cid = CGSMainConnectionID()
        let activeSpace = CGSGetActiveSpace(cid)
        let spaceType = CGSSpaceGetType(cid, activeSpace)
        NSLog("[Space] activeSpace=\(activeSpace), type=\(spaceType)")
        return spaceType == 4
    }
}
