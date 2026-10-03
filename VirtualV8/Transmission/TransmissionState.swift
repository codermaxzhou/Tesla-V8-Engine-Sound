import Foundation

enum ShiftType: String {
    case none, upshift, downshift
}

struct TransmissionState {
    var currentGear = 1
    var targetGear = 1
    var isShifting = false
    var shiftProgress: Double = 0
    var shiftType: ShiftType = .none
}
