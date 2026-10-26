import CoreGraphics
import Foundation

// ponytail: precondition checks instead of swift-testing; its macro plugin ships only with Xcode.
func selfTest() {
    let combo: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
    precondition(comboMatches(combo, combo: combo))
    precondition(comboMatches(combo.union(.maskShift), combo: combo), "Hyper key must fire the combo")
    precondition(comboMatches(combo.union(.maskAlphaShift), combo: combo), "caps lock must be ignored")
    precondition(!comboMatches([.maskControl, .maskCommand], combo: combo))
    precondition(!comboMatches(combo, combo: combo.union(.maskShift)))
    precondition(!comboMatches([], combo: []), "empty combo must never match")

    precondition(pickLabel("&", "1") == "1", "AZERTY digit row shows digits")
    precondition(pickLabel("1", "!") == "1")
    precondition(pickLabel("a", "A") == "A")
    precondition(pickLabel(",", "?") == ",")

    let json = #"{"keys":{"1":{"kind":"app","value":"com.apple.Safari"}}}"#
    let config = try! JSONDecoder().decode(Config.self, from: Data(json.utf8))
    precondition(config.keys[1] == Target(kind: .app, value: "com.apple.Safari"), "keys survive missing fields")
    precondition(config.tilt == 25 && config.combo == combo)
    print("self-test ok")
}
