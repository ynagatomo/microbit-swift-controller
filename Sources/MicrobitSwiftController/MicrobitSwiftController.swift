//
//  MicrobitSwiftController.swift
//  MicrobitSwiftController
//
//  Created by Yasuhito Nagatomo on 2023/05/06.
//

import Foundation

@MainActor
public class MicrobitSwiftController: ObservableObject {
    @Published public var errorNotification = false  // client can clear this flag
    @Published public var errorMessage = ""

    @Published public var bluetoothEnabled = false
    @Published public var connected = false
//    @Published var deviceInformation: DeviceInformation? = nil
    @Published public var services = [Service]()
    @Published public var buttonA = ButtonState.off
    @Published public var buttonB = ButtonState.off
//    @Published var temperature = 0
    @Published public var accelerometer = SIMD3<Float>.zero
    @Published public var magnetometer = SIMD3<Float>.zero
    @Published public var inputPins = [UInt8](repeating: 0, count: 20)

//    struct DeviceInformation {
//        let modelNumber: String
//        let serialNumber: String
//        let firmwareRevision: String
//    }
    public enum Service: String {
        case temperature
        case button
        case iopin
        case led
        case magnetometer
        case accelerometer
    }
    public enum NotifyService: String {
        case temperature = "E95D9250-251D-470A-A062-FA1922DFA9A8"
        case buttonA     = "E95DDA90-251D-470A-A062-FA1922DFA9A8"
        case buttonB     = "E95DDA91-251D-470A-A062-FA1922DFA9A8"
        case iopin       = "E95D8D00-251D-470A-A062-FA1922DFA9A8"
        case magnetometer = "E95DFB11-251D-470A-A062-FA1922DFA9A8"
        case accelerometer = "E95DCA4B-251D-470A-A062-FA1922DFA9A8"
    }
    // swiftlint:disable identifier_name
    public enum ButtonState: Int {
        case off = 0, on, long
    }
    public enum SensingPeriod: UInt16 {
        case one = 1        // 1 [msec]   (1kHz)
        case two = 2        // 2 [msec]   (500Hz)
        case five = 5       // 5 [msec]   (200Hz)
        case ten = 10       // 10 [msec]  (100Hz)
        case twelve = 20    // 20 [msec]  (50Hz)
        case eighty = 80    // 80 [msec]  (12.5Hz)
        case oneSixty = 160 // 160 [msec] (6.25Hz)
        case sixForty = 640 // 640 [msec] (1.5625Hz)
    }
    public struct PWMData {
        let pin: UInt8
        let value: UInt16  // [0...1024]
        let period: UInt32 // [microseconds]
        public init(pin: UInt8, value: UInt16, period: UInt32) {
            self.pin = pin
            self.value = value
            self.period = period
        }
    }

    private let microbitBLEHandler = MicrobitBLEHandler.shared
    private let executor = MicrobitExecutor()

    public init() { }
}

// MARK: - API: Manager

extension MicrobitSwiftController {
    public func start() {
        startBLE()
    }
}

// MARK: - API: Connection

extension MicrobitSwiftController {
    public func connect() {
        executor.connect()
    }

    public func disconnect() {
        executor.disconnect()
    }
}

// MARK: - API: Settings

extension MicrobitSwiftController {
//    public func setNotification(service: NotifyService, enable: Bool) {
//        executor.setNotification(uuid: service.rawValue, enable: enable)
//    }

    public func setMagnetometer(period: SensingPeriod) {
        executor.setMagnetometer(period: period.rawValue)
    }

    public func setAccelerometer(period: SensingPeriod) {
        executor.setAccelerometer(period: period.rawValue)
    }
}

// MARK: - API: LED

extension MicrobitSwiftController {
    public func display(matrix: [UInt8]) {
        executor.display(matrix: matrix)

    }

    public func setScroll(delay: UInt16) { // [msec]
        executor.setScroll(delay: delay)
    }

    public func display(text: String) {
        executor.display(text: text)
    }
}

// MARK: - API: IO PIN

extension MicrobitSwiftController {
    // Available Input/Output Pins:
    // - P0  [digital/analog input] / output * when not using buzzer
    // - P1  [digital/analog input] / output
    // - P2  [digital/analog input] / output
    // - P8  [digital input]        / output
    // - P9  [digital input]        / output * only V2 (V1 cannot)
    // - P13 [digital input]        / output
    // - P14 [digital input]        / output
    // - P15 [digital input]        / output
    // - P16 [digital input]        / output
    public func configure(inputPins: [Int]) {
        let pins = inputPins.filter { $0 >= 0 && $0 <= 16 }
        executor.configure(inputPins: pins)
    }

    // Available Analog Input/Output Pins:
    // - P0  [digital/analog input] / output * when not using buzzer
    // - P1  [digital/analog input] / output
    // - P2  [digital/analog input] / output
    // - P8                         / output
    // - P9                         / output * only V2 (V1 cannot)
    // - P13                        / output
    // - P14                        / output
    // - P15                        / output
    // - P16                        / output
    //
    // * analog output: up to two pins. (or three?)
    // * analog input: P0/P1/P2
    public func configure(analogPins: [Int]) {
        let pins = analogPins.filter { $0 >= 0 && $0 <= 16 }
        executor.configure(analogPins: pins)
    }

    // Available Output Pins:
    // - P0  output * when not using buzzer
    // - P1  output
    // - P2  output
    // - P8  output
    // - P9  output * only V2 (V1 cannot)
    // - P13 output
    // - P14 output
    // - P15 output
    // - P16 output
    //
    // Output digital signal via digital output pins.
    // * For analog output pins, you should use PWM output.
    public func output(pins: [(pin: Int, value: UInt8)]) {
        let pinValues = pins.filter { $0.pin >= 0 && $0.pin <= 16 }
        executor.output(pins: pinValues)
    }

    // 1 or 2 analog output pins
    public func output(analogPins: [PWMData]) {
        let pwms = [(pin: UInt8, (value: UInt16, period: UInt32))]((analogPins.compactMap { pwmData in
            if pwmData.pin >= 0 && pwmData.pin <= 16 {
                return (pin: pwmData.pin, (value: pwmData.value, period: pwmData.period))
            } else {
                return nil
            }
        }).prefix(2)) // up to two
        if !pwms.isEmpty {
            executor.output(analogPins: pwms)
        }
    }
}

// MARK: - API: IO PIN

extension MicrobitSwiftController {
    public func wait(milliseconds: UInt) {
        executor.wait(milliseconds: milliseconds)
    }
}

extension MicrobitSwiftController {
    // swiftlint:disable cyclomatic_complexity
    // swiftlint:disable function_body_length
    private func startBLE() {
        executor.run()

        Task {
            if let stream = microbitBLEHandler.start() {
                for await state in stream {
                    bluetoothEnabled = state == .poweredOn
                }
            }
        }
        Task {
            if let pstream = microbitBLEHandler.makePeripheralStateStream() {
                for await state in pstream {
                    connected = (state == .connected
                                 || state == .reading
                                 || state == .writing
                                 || state == .setting)
                    if state == .connected {
//                        if deviceInformation == nil {
//                            let modelNumber = try await microbitBLEHandler.devInfoModelNumber()
//                            let serialNumber = try await microbitBLEHandler.devInfoSerialNumber()
//                            let firmwareRevision = try await microbitBLEHandler.devInfoFirmwareRevision()
//                            deviceInformation = DeviceInformation(modelNumber: modelNumber,
//                                                                  serialNumber: serialNumber,
//                                                                  firmwareRevision: firmwareRevision)
//                        } else
                        if services.isEmpty {
                            // Set available services when the first change to the connected state
                            services = microbitBLEHandler.availableServices.compactMap {
                                Service(rawValue: $0.rawValue)
                            }
                        } else {
                            // do nothing
                        }
                    } else if state == .disconnected {
//                        deviceInformation = nil // clear device-info
                        services = []           // clear available services
                    } else {
                        // do nothing
                    }
                }
            }
        }
        Task {
            if let stream = microbitBLEHandler.makeButtonAStream() {
                for await button in stream {
                    buttonA = ButtonState(rawValue: button)! // {0, 1, 2}
                }
            }
        }
        Task {
            if let stream = microbitBLEHandler.makeButtonBStream() {
                for await button in stream {
                    buttonB = ButtonState(rawValue: button)! // {0, 1, 2}
                }
            }
        }
        Task {
            if let stream = microbitBLEHandler.makeAccelerometerDataStream() {
                for await accs in stream {
                    accelerometer = SIMD3<Float>([Float(accs[0]) / 1000.0,
                                                  Float(accs[1]) / 1000.0,
                                                  Float(accs[2]) / 1000.0])
                }
            }
        }
        Task {
            if let stream = microbitBLEHandler.makeMagnetometerDataStream() {
                for await mags in stream {
                    magnetometer = SIMD3<Float>([Float(mags[0]) / 1000.0,
                                                 Float(mags[1]) / 1000.0,
                                                 Float(mags[2]) / 1000.0])
                }
            }
        }
        Task {
            if let stream = microbitBLEHandler.makeIOPinDataStream() {
                for await pinValues in stream {
                    pinValues.forEach { pinValue in
                        if pinValue.pin >= 0 && pinValue.pin < 20 {
                            inputPins[Int(pinValue.pin)] = pinValue.value
                        }
                    }
                }
            }
        }
    }
}
