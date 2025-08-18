// AppColourState.swift
class AppColourState {
    static let shared = AppColourState()
    private init() {}

    var rgb: [Double] = [0, 0, 0] // Stores user-entered RGB
}
