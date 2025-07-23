// AppColorState.swift
class AppColorState {
    static let shared = AppColorState()
    private init() {}

    var rgb: [Double] = [0, 0, 0] // Stores user-entered RGB
}
