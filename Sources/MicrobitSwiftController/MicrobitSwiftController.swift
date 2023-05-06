//
//  MicrobitSwiftController.swift
//  MicrobitSwiftController
//
//  Created by Yasuhito Nagatomo on 2023/05/06.
//

import Foundation

/// A SwiftUI friendly class to control your Micro:bit via BLE.
@MainActor
public class MicrobitSwiftController: ObservableObject {
    // @Published public var errorNotification = false  // client can clear this flag
    // @Published public var errorMessage = ""

    @Published public var bluetoothEnabled = false
    @Published public var connected = false
    @Published public var services = [Service]()
    @Published public var buttonA = ButtonState.off
    @Published public var buttonB = ButtonState.off
    @Published public var accelerometer = SIMD3<Float>.zero
    @Published public var magnetometer = SIMD3<Float>.zero
    @Published public var inputPins = [UInt8](repeating: 0, count: 20)

    // The services that Micro:bit can provide.
    public enum Service: String {
        case temperature
        case button
        case iopin
        case led
        case magnetometer
        case accelerometer
    }

    // The BLE characteristic UUIDs that Micro:bit can provide for notifications.
    public enum NotifyService: String {
        case temperature = "E95D9250-251D-470A-A062-FA1922DFA9A8"
        case buttonA     = "E95DDA90-251D-470A-A062-FA1922DFA9A8"
        case buttonB     = "E95DDA91-251D-470A-A062-FA1922DFA9A8"
        case iopin       = "E95D8D00-251D-470A-A062-FA1922DFA9A8"
        case magnetometer = "E95DFB11-251D-470A-A062-FA1922DFA9A8"
        case accelerometer = "E95DCA4B-251D-470A-A062-FA1922DFA9A8"
    }

    // Button state
    // swiftlint:disable identifier_name
    public enum ButtonState: Int {
        case off = 0, on, long
    }

    // Sensing period for accelerometer and magnetometer
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

    // PWM data for Analog IO Pin outout
    public struct PWMData {
        let pin: UInt8     // Analog output pin
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
    /// Starts the Micro:bit Controller
    ///
    /// This function must be called once first to control a Micro:bit.
    /// It starts BLE services to communicate with the Micro:bit.
    public func start() {
        startBLE()
    }

    /// Waits for the specified period
    /// - Parameter milliseconds: wait period [milliseconds]
    public func wait(milliseconds: UInt) {
        executor.wait(milliseconds: milliseconds)
    }
}

// MARK: - API: Connection

extension MicrobitSwiftController {
    /// Connects to a Micro:bit
    ///
    /// The first found Micro:bit will be connected.
    public func connect() {
        executor.connect()
    }

    /// Disconnect from a Micro:bit
    public func disconnect() {
        executor.disconnect()
    }
}

// MARK: - API: Settings

extension MicrobitSwiftController {
    /// Sets the sensing period of the magnetometer on the Micro:bit
    /// - Parameter period: sensing period [milliseconds] Valid values are 1, 2, 5, 10, 20, 80, 160 and 640.
    public func setMagnetometer(period: SensingPeriod) {
        executor.setMagnetometer(period: period.rawValue)
    }

    /// Sets the sensing period of the accelerometer on the Micro:bit
    /// - Parameter period: sensing period [milliseconds] Valid values are 1, 2, 5, 10, 20, 80, 160 and 640.
    public func setAccelerometer(period: SensingPeriod) {
        executor.setAccelerometer(period: period.rawValue)
    }
}

// MARK: - API: LED

extension MicrobitSwiftController {
    /// Displays dots on the LED matrix
    /// - Parameter matrix: dot pattern of 5 x 5
    /// matrix[0] : row 0 - 000x xxxx    x: 0 (LED off) or 1 (LED on)
    /// matrix[1] : row 1 - 000x xxxx
    /// matrix[2] : row 2 - 000x xxxx
    /// matrix[3] : row 3 - 000x xxxx
    /// matrix[4] : row 4 - 000x xxxx
    public func display(matrix: [UInt8]) {
        executor.display(matrix: matrix)

    }

    /// Sets the delay of scrolling text
    /// - Parameter delay: delay time [milliseconds]
    public func setScroll(delay: UInt16) {
        executor.setScroll(delay: delay)
    }

    /// Displays a scrolling text on LED Matrix
    /// - Parameter text: text (maximum length is twenty)
    public func display(text: String) {
        executor.display(text: text)
    }
}

// MARK: - API: IO PIN

extension MicrobitSwiftController {
    /// Configures the IO Pins for input or output
    /// - Parameter inputPins: input pin numbers
    /// The other pins are set for output.
    ///
    /// Available Input/Output Pins:
    /// - P0  [digital/analog input] / output * when not using buzzer
    /// - P1  [digital/analog input] / output
    /// - P2  [digital/analog input] / output
    /// - P8  [digital input]        / output
    /// - P9  [digital input]        / output * only V2 (V1 cannot)
    /// - P13 [digital input]        / output
    /// - P14 [digital input]        / output
    /// - P15 [digital input]        / output
    /// - P16 [digital input]        / output
    public func configure(inputPins: [Int]) {
        let pins = inputPins.filter { $0 >= 0 && $0 <= 16 }
        executor.configure(inputPins: pins)
    }

    /// Configure the IO Pins for digital or analog
    /// - Parameter analogPins: analog pin numbers for input or output
    /// The other pins are set for digital for input or output.
    ///
    /// Available Analog Input/Output Pins:
    /// - P0  [digital/analog input] / output * when not using buzzer
    /// - P1  [digital/analog input] / output
    /// - P2  [digital/analog input] / output
    /// - P8                         / output
    /// - P9                         / output * only V2 (V1 cannot)
    /// - P13                        / output
    /// - P14                        / output
    /// - P15                        / output
    /// - P16                        / output
    ///
    /// * Up to two pins can be assigned as digital output pins.
    /// * Only P0/P1/P2 pins can be assigned as analog input pins.
    public func configure(analogPins: [Int]) {
        let pins = analogPins.filter { $0 >= 0 && $0 <= 16 }
        executor.configure(analogPins: pins)
    }

    /// Outputs digital signals from digital output pins
    /// - Parameter pins: pairs of pin number and output value (0: Low or 1: Hight)
    ///
    /// Available Output Pins:
    /// - P0  output * when not using buzzer
    /// - P1  output
    /// - P2  output
    /// - P8  output
    /// - P9  output * only V2 (V1 cannot)
    /// - P13 output
    /// - P14 output
    /// - P15 output
    /// - P16 output
    ///
    /// The pins you specify must be configured as digital output.
    public func output(pins: [(pin: Int, value: UInt8)]) {
        let pinValues = pins.filter { $0.pin >= 0 && $0.pin <= 16 }
        executor.output(pins: pinValues)
    }

    /// Outputs analog signals from analog output pins
    /// - Parameter analogPins: PWM data
    /// PWMData.pin : analog output pin number
    /// PWMData.value : high level width {0...1024}
    /// PWMData.period : pulse duration [milliseconds]
    ///
    /// You can output analog signals with one or two analog output pins.
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

// MARK: - Private functions

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
                        if services.isEmpty {
                            // Set available services when the first change to the connected state
                            services = microbitBLEHandler.availableServices.compactMap {
                                Service(rawValue: $0.rawValue)
                            }
                        } else {
                            // do nothing
                        }
                    } else if state == .disconnected {
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
