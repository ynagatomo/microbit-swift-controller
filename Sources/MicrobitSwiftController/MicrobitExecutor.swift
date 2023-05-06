//
//  MicrobitExecutor.swift
//  MicrobitSwiftController
//
//  Created by Yasuhito Nagatomo on 2023/05/06.
//

import Foundation

@MainActor
final class MicrobitExecutor {
    enum Command {
        case connect
        case disconnect
//        case setNotification(uuid: String, enable: Bool)
        case setMagnetometer(period: UInt16)
        case setAccelerometer(period: UInt16)
        case display(matrix: [UInt8])
        case setScroll(delay: UInt16)
        case displayText(text: String)
        case configure(inputPins: [Int])
        case configureAnalog(analogPins: [Int])
        case output(pins: [(pin: Int, value: UInt8)])
        case outputAnalog(analogPins: [(pin: UInt8, (value: UInt16, period: UInt32))])
        case wait(milliseconds: UInt)
    }

    private let microbitBLEHandler = MicrobitBLEHandler.shared
    private var commandQueue = [Command]()
    private var runTask: Task<Void, Error>?
    private var running = false

    func run() {
        guard !running else { return }

        running = true
        runTask = Task {
            print("[Executor] Running.")
            while true {
                if Task.isCancelled { break }
                if !commandQueue.isEmpty {
                    let command = commandQueue.removeFirst()  // pop the first one
                    try await execute(command)
                }
                // await Task.yield()
                try await Task.sleep(for: .microseconds(100)) // 10 [Hz]
            }
            print("[Executor] Stopped running.")
        }
    }

    func stop() {
        guard running else { return }

        if let runTask {
            running = false
            runTask.cancel()
            print("[Executor] Canceled running.")
        } else {
            // no task
        }
    }
}

// MARK: - API: Commands

extension MicrobitExecutor {
    func connect() {
        let command = Command.connect
        commandQueue.append(command)
    }

    func disconnect() {
        let command = Command.disconnect
        commandQueue.append(command)
    }

//    func setNotification(uuid: String, enable: Bool) {
//        let command = Command.setNotification(uuid: uuid, enable: enable)
//        commandQueue.append(command)
//    }

    func setMagnetometer(period: UInt16) {
        let command = Command.setMagnetometer(period: period)
        commandQueue.append(command)
    }

    func setAccelerometer(period: UInt16) {
        let command = Command.setAccelerometer(period: period)
        commandQueue.append(command)
    }

    func display(matrix: [UInt8]) {
        let command = Command.display(matrix: matrix)
        commandQueue.append(command)
    }

    func setScroll(delay: UInt16) { // [msec]
        let command = Command.setScroll(delay: delay)
        commandQueue.append(command)
    }

    func display(text: String) {
        let command = Command.displayText(text: text)
        commandQueue.append(command)
    }

    func configure(inputPins: [Int]) {
        let command = Command.configure(inputPins: inputPins)
        commandQueue.append(command)
    }

    func configure(analogPins: [Int]) {
        let command = Command.configureAnalog(analogPins: analogPins)
        commandQueue.append(command)
    }

    func output(pins: [(pin: Int, value: UInt8)]) {
        let command = Command.output(pins: pins)
        commandQueue.append(command)
    }

    func output(analogPins: [(pin: UInt8, (value: UInt16, period: UInt32))]) {
        let command = Command.outputAnalog(analogPins: analogPins)
        commandQueue.append(command)
    }

    func wait(milliseconds: UInt) {
        let command = Command.wait(milliseconds: milliseconds)
        commandQueue.append(command)
    }
}

// MARK: - Execute Commands

extension MicrobitExecutor {
    // swiftlint:disable cyclomatic_complexity
    private func execute(_ command: Command) async throws {
        switch command {
        case .connect:
            try await cmdConnect()
        case .disconnect:
            try await cmdDisconnect()
//        case .setNotification(let uuid, let enable):
//            try await cmdSetNotification(uuid: uuid, enable: enable)
        case .setMagnetometer(let period):
            try await cmdSetMagnetometer(period: period)
        case .setAccelerometer(let period):
            try await cmdSetAccelerometer(period: period)
        case .display(let matrix):
            try await cmdDisplay(matrix: matrix)
        case .setScroll(let delay):
            try await cmdSetScroll(delay: delay)
        case .displayText(let text):
            try await cmdDisplayText(text: text)
        case .configure(let inputPins):
            try await cmdConfigure(inputPins: inputPins)
        case .configureAnalog(let analogPins):
            try await cmdConfigureAnalog(analogPins: analogPins)
        case .output(let pins):
            try await cmdOutput(pins: pins)
        case .outputAnalog(let analogPins):
            try await cmdOutputAnalog(analogPins: analogPins)
        case .wait(let milliseconds):
            try await cmdWait(milliseconds: milliseconds)
        }
    }

    private func cmdConnect() async throws {
        if microbitBLEHandler.bleState == .poweredOn &&
           (microbitBLEHandler.peripheralState == .idle || microbitBLEHandler.peripheralState == .disconnected) {
            try await microbitBLEHandler.connect()
            if microbitBLEHandler.availableServices.contains(.button) {
                try await microbitBLEHandler.buttonASetNotify(enable: true)
                try await microbitBLEHandler.buttonBSetNotify(enable: true)
            }
            if microbitBLEHandler.availableServices.contains(.accelerometer) {
                try await microbitBLEHandler.accelerometerDataSetNotify(enable: true)
            }
            if microbitBLEHandler.availableServices.contains(.magnetometer) {
                try await microbitBLEHandler.magnetometerDataSetNotify(enable: true)
            }
            if microbitBLEHandler.availableServices.contains(.iopin) {
                try await microbitBLEHandler.iopinDataSetNotify(enable: true)
            }
        } else {
            // just ignore the command
        }
    }

    private func cmdDisconnect() async throws {
        if microbitBLEHandler.bleState == .poweredOn && microbitBLEHandler.peripheralState == .connected {
            try await microbitBLEHandler.disconnect()
        } else {
            // just ignore the command
        }
    }

//    private func cmdSetNotification(uuid: String, enable: Bool) async throws {
//
//    }

    private func cmdSetMagnetometer(period: UInt16) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            try await microbitBLEHandler.setMagnetometerPeriod(msec: period)
        }
    }

    private func cmdSetAccelerometer(period: UInt16) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            try await microbitBLEHandler.setAccelerometerPeriod(msec: period)
        }
    }

    private func cmdDisplay(matrix: [UInt8]) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            try await microbitBLEHandler.setLedMatrix(bytes: matrix)
        }
    }

    private func cmdSetScroll(delay: UInt16) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            try await microbitBLEHandler.setLedScrolling(delay: delay)
        }
    }

    private func cmdDisplayText(text: String) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            let asciiText = String(text.filter { $0.isASCII })
            try await microbitBLEHandler.setLedText(text: asciiText)
        }
    }

    private func cmdConfigure(inputPins: [Int]) async throws {
        try await microbitBLEHandler.setIOPinConfiguration(inputPins: inputPins)
    }

    private func cmdConfigureAnalog(analogPins: [Int]) async throws {
        try await microbitBLEHandler.setIOPinADConfiguration(analogPins: analogPins)
    }

    private func cmdOutput(pins: [(pin: Int, value: UInt8)]) async throws {
        try await microbitBLEHandler.setIOPinData(pins)
    }

    private func cmdOutputAnalog(analogPins: [(pin: UInt8, (value: UInt16, period: UInt32))]) async throws {
        try await microbitBLEHandler.setIOPinDataPWM(pins: analogPins)
    }

    private func cmdWait(milliseconds: UInt) async throws {
        if microbitBLEHandler.peripheralState == .connected {
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    }
}
