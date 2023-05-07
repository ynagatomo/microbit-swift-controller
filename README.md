# microbit-swift-controller

An experimental Swift Package for developing apps that communicate with BBC Micro:bit via Bluetooth Low Energy (BLE).

- Target devices: iPhone / iPad / Mac with Apple Silicon (Designed for iPad)
- Target OS: iOS 16.0+, iPadOS 16.0+, macOS 13.0+
- Build system: Xcode 14.3+, Swift Playground 4 on iPadOS
- SDK: CoreBluetooth
- BBC Micro:bit: V1/V2

![AppIcon](assets/overview.png)

The Swift Package helps you create apps that interact with BBC Micro:bit via BLE.

The Micro:bit runs a general BLE peripheral program that enables BLE services you want such as LED, ACCELEROMETER, and IO PIN.
Once you download the program into your Micro:bit, you can use it commonly for any iOS apps that communicate with the BLE services.

By using the Apple CoreBluetooth framework, you can make any apps that communicate with Micro:bit via BLE.
However, you need to follow many procedures to match the Micro:bit's BLE Profile requirements.

This swift package provide two levels APIs to make easy creating such apps.

1. State-less Synchronous APIs ... With these APIs, you don't need to care about BLE states and Asynchronous behaviour. This is suitable for programming education for beginners.
1. State-full Asynchronous APIs ... With these APIs, you can handle precise BLE states and errors. You use Swift Concurrency for their asynchronous functions.

Please check the sample iOS apps that use this Swift Package.

1. microbit-swift-sample  : an iOS app that uses State-less Synchronous APIs. https://github.com/ynagatomo/microbit-swift-sample
1. microbit-swift-sample2 : an iOS app that uses State-full Asynchronous APIs. (coming...)

## State-less API

@MainActor public class MicrobitSwiftController: ObservableObject

The properties reflect the Bluetooth and Micro:bit's state.
As they are `@Published` properties, you can easily bind them to SwiftUI views.

| Property | Description |
| -------- | ----------- |
| @Published public var bluetoothEnabled: Bool | true: Bluetooth enable, false: disable |
| @Published public var connected: Bool | true : connected, false: not connected |
| @Published public var services: [Service] | detected BLE services when connected |
| @Published public var buttonA: ButtonState | {.off, .on, .long (long pressed)} |
| @Published public var buttonB: ButtonState | {.off, .on, .long (long pressed)} |
| @Published public var accelerometer: SIMD3<Float> | accelerometer data {x,y,z} |
| @Published public var magnetometer: SIMD3<Float> | magnetometer data {x, y, z} |
| @Published public var inputPins: [UInt8] | input data of each IO Pins [0...19] |

The commands invoked below methods will be queued and will be executed one by one.
Therefore, the methods return immediately. When occurred any error, the commands
in the queue will be just ignored.  

| Method | Description |
| ------ | ----------- |
| public func start() | starts the microbit-swift-controller. Call this once first. |
| public func wait(milliseconds: UInt) | waits for the specified period. |
| public func connect() | connects to the Micro:bit found first. |
| public func disconnect() | disconnect from the Micro:bit. |
| public func setMagnetometor(period: SensingPeriod) | sets the sensing period. |
| public func setAccelerometer(period: SensingPeriod) | sets the sensing period. |
| public func display(matrix: [UInt8]) | displays the LED dot matrix. |
| public func setScroll(delay: UInt16) | sets the delay of scrolling text. |
| public func display(text: String) | displays the text on the LED matrix. |
| public func configure(inputPins: [Int]) | configures the pins input or output. |
| public func configure(analogPins: [Int]) | configures the pins digital or analog. |
| public func output(pins: [(pin: Int, value: UInt8)]) | outputs digital signals via output pins. |
| public func output(analogPins: [PWMData]) | outputs analog signals via output pins. |

Please check the source code in detail.

## State-full API



## References

1. BBC micro:bit Bluetooth Profile, Lancaster University: https://lancaster-university.github.io/microbit-docs/ble/profile/

License: MIT
