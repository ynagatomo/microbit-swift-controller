//
//  MicrobitBLEHandler.swift
//  basicmicrobitble
//
//  Created by Yasuhito Nagatomo on 2023/05/01.
//

import Foundation
import CoreBluetooth

// swiftlint:disable file_length
// swiftlint:disable line_length

final class MicrobitBLEHandler: NSObject {
    enum BLEState: String {
        case poweredOff, poweredOn, resetting, unauthorized
        case unsupported, unknown
    }
    enum BLEError: Error {
        case errPoweredOff     // BLE is powered off
        case errUnauthorized   // BLE is not authorized
        case errUnavailable    // BLE is not available (resetting, unsupported,..)
        case errWorking        // Working on an other communication
        case errNotConnected   // Not connected
        case errCanceledToConnect // Canceled
        case errNotSupported   // Not supported
        case errNotDone        // Not done for any reason
        case errUnknown
    }
    enum BLEPeripheralState: String {
        case idle, scanning
        case connecting, discovering, connected
        case disconnecting, disconnected
        case reading, writing, setting
    }

    static let shared = MicrobitBLEHandler()          // Shared object
    static let namePrefix = "BBC micro:bit"   // Micro:bit peripheral name prefix

    private var centralManager: CBCentralManager!
    private(set) var bleState = BLEState.unknown      // BLE state of the central
    private(set) var peripheralState = BLEPeripheralState.idle // State of a peripheral
    private var peripheral: CBPeripheral!
    private var peripheralRSSI: Int = 0
    private(set) var availableServices: [MicrobitBLEProfile] = [] // Service on the peripheral
//    private var characteristics: [CBCharacteristic] = []  // Discovered characteristics on the peripheral
    private var characteristics: [String: CBCharacteristic] = [:]  // Discovered characteristics on the peripheral

    private var stateStreamContinuation: AsyncStream<BLEState>.Continuation?
    private var peripheralStateStreamContinuation: AsyncStream<BLEPeripheralState>.Continuation?

    private var connectContinuation: CheckedContinuation<UUID, Error>?
    private var discoveringCharForServiceCount = 0 // the number of services
    private var disconnectContinuation: CheckedContinuation<UUID, Error>?
//    private var readStringContinuation: CheckedContinuation<String, Error>?
//    private var readInt8Continuation: CheckedContinuation<Int, Error>?
//    private var readInt16Continuation: CheckedContinuation<Int, Error>?
//    private var readIntArrayContinuation: CheckedContinuation<[Int], Error>?
    private var notifyContinuation: CheckedContinuation<Void, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var readDataContinuation: CheckedContinuation<Data?, Error>?

    private var buttonAStreamContinuation: AsyncStream<Int>.Continuation?
    private var buttonBStreamContinuation: AsyncStream<Int>.Continuation?
    private var accelerometerDataStreamContinuation: AsyncStream<[Int]>.Continuation?
    private var magnetometerDataStreamContinuation: AsyncStream<[Int]>.Continuation?
    private var iopinDataStreamContinuation: AsyncStream<[(pin: UInt8, value: UInt8)]>.Continuation?

    private override init() {}
}

// MARK: - API

extension MicrobitBLEHandler {
    public func makePeripheralStateStream() -> AsyncStream<BLEPeripheralState>? {
        guard peripheralStateStreamContinuation == nil else { return nil }

        let pstream = AsyncStream<BLEPeripheralState> { continuation in
            peripheralStateStreamContinuation = continuation
        }

        return pstream
    }

    public func start() -> AsyncStream<BLEState>? {
        guard centralManager == nil else { return nil }

        let stream = AsyncStream<BLEState> { continuation in
            stateStreamContinuation = continuation
        }

        centralManager = CBCentralManager(delegate: self, queue: nil)

        return stream
    }

    public func makeButtonAStream() -> AsyncStream<Int>? {
        guard buttonAStreamContinuation == nil else { return nil }

        let stream = AsyncStream<Int> { continuation in
            buttonAStreamContinuation = continuation
        }
        return stream
    }

    public func makeButtonBStream() -> AsyncStream<Int>? {
        guard buttonBStreamContinuation == nil else { return nil }

        let stream = AsyncStream<Int> { continuation in
            buttonBStreamContinuation = continuation
        }
        return stream
    }

    public func makeAccelerometerDataStream() -> AsyncStream<[Int]>? {
        guard accelerometerDataStreamContinuation == nil else { return nil }

        let stream = AsyncStream<[Int]> { continuation in
            accelerometerDataStreamContinuation = continuation
        }
        return stream
    }

    public func makeMagnetometerDataStream() -> AsyncStream<[Int]>? {
        guard magnetometerDataStreamContinuation == nil else { return nil }

        let stream = AsyncStream<[Int]> { continuation in
            magnetometerDataStreamContinuation = continuation
        }
        return stream
    }

    public func makeIOPinDataStream() -> AsyncStream<[(pin: UInt8, value: UInt8)]>? {
        guard iopinDataStreamContinuation == nil else { return nil }

        let stream = AsyncStream<[(pin: UInt8, value: UInt8)]> { continuation in
            iopinDataStreamContinuation = continuation
        }
        return stream
    }

    private func checkStateAndThrowErrors() throws {
        switch bleState {
        case .poweredOff: throw BLEError.errPoweredOff
        case .unauthorized: throw BLEError.errUnauthorized
        case .resetting, .unsupported: throw BLEError.errUnavailable
        case .unknown: throw BLEError.errUnknown
        case .poweredOn: break  // no error is thrown
        }
    }

    @discardableResult
    public func connect() async throws -> UUID {
        assert(centralManager != nil)
        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .idle && peripheralState != .disconnected {
            throw BLEError.errWorking   // Working on an other communication
        }

        peripheralState = .scanning
//        if let peripheralStateStreamContinuation {
//            peripheralStateStreamContinuation.yield(peripheralState)
//        } else {
//        }
        peripheralStateStreamContinuation?.yield(peripheralState)

        return try await withCheckedThrowingContinuation { continuation in
            assert(connectContinuation == nil)
            connectContinuation = continuation

            // Scan BLE devices and will connect to the found Micro:bit device.
            centralManager.scanForPeripherals(withServices: nil)
            // [Note] Since Micro:bit does not advertise their services, below does not work. :(
            //    let cbUUIDs = MicrobitBLEProfile.serviceUUIDs.keys.map { CBUUID(string: $0) }
            //    centralManager.scanForPeripherals(withServices: cbUUIDs)
        }
    }

    @discardableResult
    public func cancelToConnect() throws -> Bool {
        assert(centralManager != nil)
        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .scanning {
            return false  // Did nothing
        }

        centralManager.stopScan()              // Stop scanning
        peripheralState = .idle
        peripheralStateStreamContinuation?.yield(peripheralState)

        assert(connectContinuation != nil)
        connectContinuation?.resume(throwing: BLEError.errCanceledToConnect)
        connectContinuation = nil
        return true   // Did cancel
    }

    @discardableResult
    public func disconnect() async throws -> UUID {
        assert(centralManager != nil)
        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errNotConnected   // not connected
        }

        peripheralState = .disconnecting
        peripheralStateStreamContinuation?.yield(peripheralState)

        return try await withCheckedThrowingContinuation { continuation in
            assert(disconnectContinuation == nil)
            disconnectContinuation = continuation

            assert(peripheral != nil)
            centralManager.cancelPeripheralConnection(peripheral) // BLE Disconnect
        }
    }
}

// MARK: - Delegate : CBCentralManagerDelegate

extension MicrobitBLEHandler: CBCentralManagerDelegate {
    // BLE State Updating
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[CB-Delegate] Updated the state to \(central.state)")

        var state: BLEState  = .unknown
        switch central.state {
        case .poweredOff: state = .poweredOff
        case .poweredOn:  state = .poweredOn
        case .resetting:  state = .resetting
        case .unauthorized: state = .unauthorized
        case .unsupported:  state = .unsupported
        case .unknown:    state = .unknown
        default:          state = .unknown
        }
        bleState = state

        if let stateStreamContinuation {
            stateStreamContinuation.yield(state)
        }
    }

    // BLE Discovering a peripheral
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("[CB-Delegate] Discovered a peripheral \(peripheral), RSSI = \(RSSI)")

        if let name = peripheral.name, name.hasPrefix(MicrobitBLEHandler.namePrefix) { // "BBC micro:bit [togut]"
            print("[CB-Delegate] Discovered a Micro:bit \(peripheral) name = \(peripheral.name ?? ""), UUID = \(peripheral.identifier)")

            assert(self.peripheral == nil)
            peripheralState = .connecting    // scanning => connecting
            peripheralStateStreamContinuation?.yield(peripheralState)
            self.peripheral = peripheral  // Should keep the instance here
            self.peripheralRSSI = Int(truncating: RSSI)

            central.stopScan()              // Stop scanning
            central.connect(peripheral)     // Start connecting
            print("[CB-Delegate] Stopped scanning and started connecting.")
        }
    }

    // BLE Connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[CB-Delegate] Connected to the peripheral. \(peripheral)")
        assert(self.peripheral == peripheral)

        assert(self.peripheral != nil)
        peripheralState = .discovering    // connecting => discovering
        peripheralStateStreamContinuation?.yield(peripheralState)
        peripheral.delegate = self

        // Discover the specific Micro:bit services
        let cbUUIDs = MicrobitBLEProfile.serviceUUIDs.keys.compactMap { CBUUID(string: $0) }
        peripheral.discoverServices(cbUUIDs)    // Started discovering the services
        print("[CB-Delegate] Started discovering the Micro:bit's services.")
    }

    // BLE Failed to connect
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[CB-Delegate] Failed to connected to the peripheral. \(peripheral) Error: \(error?.localizedDescription ?? "none")")
        assert(error != nil)
        assert(self.peripheral != nil)
        self.peripheral = nil
        peripheralState = .idle         // connecting => idle
        peripheralStateStreamContinuation?.yield(peripheralState)

        print("[CB-Delegate] Error will be thrown and will terminate this continuation.")
        assert(connectContinuation != nil)
        connectContinuation?.resume(throwing: error != nil ? error! : BLEError.errUnknown)
        connectContinuation = nil
    }

    // BLE Disconnect
    // The `error` represents the reason of the disconnect. It does not represent API errors.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[CB-Delegate] Disconnected. \(peripheral) Error: \(error?.localizedDescription ?? "none")")

        peripheralState = .disconnected    // disconnecting => disconnected
        peripheralStateStreamContinuation?.yield(peripheralState)

        // This function is called from disconnectContinuation
        // or internal of CoreBluetooth when peripheral disconnects the connection.
        if disconnectContinuation != nil {
            // During continuation
            print("[CB-Delegate] Disconnected and will finish this continuation.")
            disconnectContinuation?.resume(returning: peripheral.identifier)
            disconnectContinuation = nil
        } else {
            // do nothing
        }

        self.peripheral = nil
        peripheralRSSI = 0
        characteristics = [:]
        availableServices = []
    }
}

// MARK: - Delegate : CBPeripheralDelegate

extension MicrobitBLEHandler: CBPeripheralDelegate {
    // BLE Discovering services on the peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("[CB-Delegate] Discovered \(peripheral.services?.count ?? 0) services. Error: \(error?.localizedDescription ?? "none")")

        if error != nil {
            // An error occurred : keep the connection (but no services)
            print("[CB-Delegate] Error. No service was found and will terminate this continuation.")
            assert(self.peripheral != nil)

//            self.peripheral = nil
//            peripheralState = .disconnecting
//            peripheralStateStreamContinuation?.yield(peripheralState)
//            centralManager.cancelPeripheralConnection(peripheral)
//            print("[CB-Delegate] The connection is disconnecting.")
// does not wait for the finishing to disconnect, to make code simple
//            assert(connectContinuation != nil)
//            connectContinuation?.resume(throwing: error)
//            connectContinuation = nil

            assert(connectContinuation != nil)
            connectContinuation?.resume(returning: peripheral.identifier)
            connectContinuation = nil

            peripheralState = .connected    // connecting => connected
            peripheralStateStreamContinuation?.yield(peripheralState)
            return
        }

        if peripheral.services == nil || (peripheral.services != nil && peripheral.services!.isEmpty) {
            // No services
            print("[CB-Delegate] No service was found and will finish this continuation.")
            assert(connectContinuation != nil)
            connectContinuation?.resume(returning: peripheral.identifier)
            connectContinuation = nil

            peripheralState = .connected    // connecting => connected
            peripheralStateStreamContinuation?.yield(peripheralState)
            return
        }

        if let services = peripheral.services {
            // Some services
            discoveringCharForServiceCount = 0
            self.characteristics = [:]   // clear the local characteristic cache
            availableServices = []      // clear available services
            services.forEach { service in
                print("[CB-Delegate] A service was discovered on the peripheral. \(service)")

                if let serviceID = MicrobitBLEProfile.serviceUUIDs[service.uuid.uuidString] {
                    availableServices.append(serviceID)
                } else {
                    // do nothing (unknown Service UUID)
                }

                if let uuids = MicrobitBLEProfile.characteristicUUIDs[service.uuid.uuidString] {
                    // Discover the specific characteristics for the service
                    let cbUUIDs = uuids.map { CBUUID(string: $0) }
                    discoveringCharForServiceCount += 1
                    print("[CB-Delegate] Started discovering characteristics.")
                    peripheral.discoverCharacteristics(cbUUIDs, for: service)
                } else {
                    // no characteristics for the service. This could happen.
                }
            } // ForEach
        } else {
            assertionFailure() // This should not happen.
        }
    }

    // BLE Discovering characteristics for the services on the peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        print("[CB-Delegate] Discovered \(service.characteristics?.count ?? 0) characteristics. Error: \(error?.localizedDescription ?? "none")")

        // When error is not nil, do nothing on the error
        // Check the service.characteristics and continue.

//        if let error {
            // An error occurred : keep the connection (but no characteristics for the service)
            // Do nothing for the error

//            print("[CB-Delegate] Error will be thrown and will terminate this continuation.")
//            assert(self.peripheral != nil)
//            self.peripheral = nil
//            peripheralState = .disconnecting
//            peripheralStateStreamContinuation?.yield(peripheralState)
//
//            centralManager.cancelPeripheralConnection(peripheral)
//            print("[CB-Delegate] The connection is disconnecting.")
//
//            // does not wait for the finishing to disconnect, to make code simple
//            assert(connectContinuation != nil)
//            connectContinuation?.resume(throwing: error)
//            connectContinuation = nil
//            return
//        }

        // Some characteristics might be discovered (do even if error occurs)
        if let characteristics = service.characteristics {
            characteristics.forEach { characteristic in
                print("[CB-Delegate] Discovered a characteristics. \(characteristic)")
                print("[CB-Delegate]      - UUID = \(characteristic.uuid.uuidString)")
                // Store it into local variable for the quick access
                self.characteristics[characteristic.uuid.uuidString] = characteristic
//                self.characteristics.append(characteristic)
            }
        } else {
            // no characteristics discovered
        }

        // Finished discovering all characteristics?
        discoveringCharForServiceCount -= 1
        if discoveringCharForServiceCount <= 0 {
            // Finished
            print("[CB-Delegate] Finished discovering characteristics.")
            peripheralState = .connected
            peripheralStateStreamContinuation?.yield(peripheralState)

            assert(connectContinuation != nil)
            connectContinuation?.resume(returning: peripheral.identifier)
            connectContinuation = nil
        } else {
            // continue discovering
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // print("[CB-Delegate] UpdateValue for \(characteristic) Error: \(error?.localizedDescription ?? "none")")

        if let error {
            // An error occurred : keep the connection
            print("[CB-Delegate] Error will be thrown and will terminate this continuation.")
//            if readStringContinuation != nil {
//                readStringContinuation?.resume(throwing: error)
//                readStringContinuation = nil
//
//                peripheralState = .connected    // reading => connected
//                peripheralStateStreamContinuation?.yield(peripheralState)
//            } else
//            if readInt8Continuation != nil {
//                readInt8Continuation?.resume(throwing: error)
//                readInt8Continuation = nil
//
//                peripheralState = .connected    // reading => connected
//                peripheralStateStreamContinuation?.yield(peripheralState)
//            } else
//            if readInt16Continuation != nil {
//                readInt16Continuation?.resume(throwing: error)
//                readInt16Continuation = nil
//
//                peripheralState = .connected    // reading => connected
//                peripheralStateStreamContinuation?.yield(peripheralState)
//            } else
            if readDataContinuation != nil {
                readDataContinuation?.resume(throwing: error)
                readDataContinuation = nil

                peripheralState = .connected    // reading => connected
                peripheralStateStreamContinuation?.yield(peripheralState)
            } else {                                    // <== add another continuations here
                // Called for notification (no continuations)
                // do nothing in this case
            }

            return
        }

        // take the updated value

//        if readStringContinuation != nil {
//            var text = ""
//            if let data = characteristic.value {
//                text = String(decoding: data, as: UTF8.self)
//            } else {
//                // do nothing
//            }
//
//            readStringContinuation?.resume(returning: text)
//            readStringContinuation = nil
//
//            peripheralState = .connected    // reading => connected
//            peripheralStateStreamContinuation?.yield(peripheralState)
//        } else
//        if readInt8Continuation != nil {
//            var result = 0
//            if let data = characteristic.value {
//                var byte: CUnsignedChar = 0
//                data.copyBytes(to: &byte, count: 1)
//                result = Int(byte)
//            } else {
//                // do nothing
//                print("[CB-Delegate] UpdateValue : no Characteristic.value")
//            }
//
//            readInt8Continuation?.resume(returning: result)
//            readInt8Continuation = nil
//
//            peripheralState = .connected    // reading => connected
//            peripheralStateStreamContinuation?.yield(peripheralState)
//        } else
//        if readInt16Continuation != nil {
//            var result = 0
//            if let data = characteristic.value {
//                let bytes = [UInt8](data)
//                result = Int(bytes[1]) * 256 + Int(bytes[0])
//            } else {
//                // do nothing
//                print("[CB-Delegate] UpdateValue : no Characteristic.value")
//            }
//
//            readInt16Continuation?.resume(returning: result)
//            readInt16Continuation = nil
//
//            peripheralState = .connected    // reading => connected
//            peripheralStateStreamContinuation?.yield(peripheralState)
//        } else
        if readDataContinuation != nil {
            let data = characteristic.value

            readDataContinuation?.resume(returning: data)
            readDataContinuation = nil

            peripheralState = .connected    // reading => connected
            peripheralStateStreamContinuation?.yield(peripheralState)
        } else {                                          // <== add another continuations here
            // Called for Notification
            // Publish the value if it is subscribed
            publishUpdatedValue(uuid: characteristic.uuid.uuidString,
                                data: characteristic.value)
        }
    }

    private func publishUpdatedValue(uuid: String, data: Data?) {
        if uuid == MicrobitBLEProfile.buttonCharacteristicStateAUUID,
            let buttonAStreamContinuation,
            let data {

            var byte: CUnsignedChar = 0
            data.copyBytes(to: &byte, count: 1)
            let result = Int(byte)

            buttonAStreamContinuation.yield(result)
        } else if uuid == MicrobitBLEProfile.buttonCharacteristicStateBUUID,
            let buttonBStreamContinuation,
            let data {

            var byte: CUnsignedChar = 0
            data.copyBytes(to: &byte, count: 1)
            let result = Int(byte)

            buttonBStreamContinuation.yield(result)
        } else if uuid == MicrobitBLEProfile.accelerometerCharacteristicData,
            let accelerometerDataStreamContinuation,
            let data {

            let buf = data.withUnsafeBytes {
                Array(UnsafeBufferPointer(
                    start: $0.baseAddress!.assumingMemoryBound(to: Int16.self),
                    count: $0.count / 2))
            }

            let result = [Int(buf[0]), Int(buf[1]), Int(buf[2])]

            accelerometerDataStreamContinuation.yield(result)
        } else if uuid == MicrobitBLEProfile.magnetometerCharacteristicData,
            let magnetometerDataStreamContinuation,
            let data {

            let buf = data.withUnsafeBytes {
                Array(UnsafeBufferPointer(
                    start: $0.baseAddress!.assumingMemoryBound(to: Int16.self),
                    count: $0.count / 2))
            }

            let result = [Int(buf[0]), Int(buf[1]), Int(buf[2])]

            magnetometerDataStreamContinuation.yield(result)
        } else if uuid == MicrobitBLEProfile.iopinCharacteristicData,
            let iopinDataStreamContinuation,
            let data {

            let uint8s = [UInt8](data)
            var result = [(pin: UInt8, value: UInt8)]()
            if uint8s.count.isMultiple(of: 2) {
                for ind in stride(from: 0, to: uint8s.count, by: 2) {
                    let pinNumber = uint8s[ind]
                    let value = uint8s[ind + 1]
                    result.append((pin: pinNumber, value: value))
                }
                iopinDataStreamContinuation.yield(result)
            } else {
                // do nothing - invalid data
            }
        } else {
            // do nothing
            // add another subscriber here
        }
    }

    // BLE Discovering services on the peripheral
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("[CB-Delegate] Updated notify state. Error: \(error?.localizedDescription ?? "none")")

        if error != nil {
            // An error occurred : keep the connection
            print("[CB-Delegate] Error will be thrown and will terminate this continuation.")
            assert(notifyContinuation != nil)
            notifyContinuation?.resume(throwing: BLEError.errNotDone)
            notifyContinuation = nil

            peripheralState = .connected    // setting => connected
            peripheralStateStreamContinuation?.yield(peripheralState)
            return
        }

        // Updated the notification state
        print("[CB-Delegate] Updated notification state. \(characteristic.isNotifying)")
        peripheralState = .connected  // setting => connected
        peripheralStateStreamContinuation?.yield(peripheralState)

        assert(notifyContinuation != nil)
        notifyContinuation?.resume(returning: ())
        notifyContinuation = nil
    }

    // BLE
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        print("[CB-Delegate] Wrote value. Error: \(error?.localizedDescription ?? "none")")

        if error != nil {
            // An error occurred : keep the connection
            print("[CB-Delegate] Error will be thrown and will terminate this continuation.")
            assert(writeContinuation != nil)
            writeContinuation?.resume(throwing: BLEError.errNotDone)
            writeContinuation = nil

            peripheralState = .connected    // writing => connected
            peripheralStateStreamContinuation?.yield(peripheralState)
            return
        }

        // Done writing

        peripheralState = .connected  // writing => connected
        peripheralStateStreamContinuation?.yield(peripheralState)

        assert(writeContinuation != nil)
        writeContinuation?.resume(returning: ())
        writeContinuation = nil
    }
}

// MARK: - Device Information

extension MicrobitBLEHandler {
    // Service: Device Information
    // Characteristic: Model Number String [Optional]
    //
    // The value of this characteristic is a UTF-8 string representing
    // the model number assigned by the device vendor.
    // - Read : Mandatory / Write : Excluded
    public func devInfoModelNumber() async throws -> String {
        return try await BLEPeripheralStringRead(uuid: MicrobitBLEProfile.infoCharacteristicModelNumberUUID)
    }

    // Service: Device Information
    // Characteristic: Serial Number String [Optional]
    //
    // The value of this characteristic is a variable-length
    // UTF-8 string representing the serial number for a particular instance of the device.
    // - Read : Mandatory / Write : Excluded
    public func devInfoSerialNumber() async throws -> String {
        return try await BLEPeripheralStringRead(uuid: MicrobitBLEProfile.infoCharacteristicSerialNumberUUID)
    }

    // Service: Device Information
    // Characteristic: Firmware Revision String [Optional]
    //
    // The value of this characteristic is a UTF-8 string representing
    // the firmware revision for the firmware within the device.
    // - Read : Mandatory / Write : Excluded
    public func devInfoFirmwareRevision() async throws -> String {
        return try await BLEPeripheralStringRead(uuid: MicrobitBLEProfile.infoCharacteristicFirmwareRevUUID)
    }
}

// MARK: Temperature

extension MicrobitBLEHandler {

    // Service: Temperature [Optional]
    // Characteristic: Temperature [Mandatory]
    //
    // Ambient temperature derived from several internal temperature sensors on the micro:bit.
    //
    // Signed integer 8 bit value in degrees celsius.
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func temperatureData() async throws -> Int {
        return try await BLEPeripheralInt8Read(uuid:
                                                MicrobitBLEProfile.temperatureCharacteristicDataUUID)
    }
}

// MARK: Button

extension MicrobitBLEHandler {
    // Service: Button [Optional]
    // Characteristic: Button A State [Mandatory]
    //
    // Exposes the two Micro Bit buttons and allows 'commands' associated with button
    // state changes to be associated with button states and notified to a connected client.
    //
    // State of Button A may be read on demand by a connected client or the client may
    // subscribe to notifications of state change.
    // 3 button states are defined and represented by a simple numeric enumeration:
    // 0 = not pressed, 1 = pressed, 2 = long press.
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func buttonAState() async throws -> Int {
        return try await BLEPeripheralInt8Read(uuid:
                                                MicrobitBLEProfile.buttonCharacteristicStateAUUID)
    }

    // Service: Button [Optional]
    // Characteristic: Button B State [Mandatory]
    //
    // Exposes the two Micro Bit buttons and allows 'commands' associated with button
    // state changes to be associated with button states and notified to a connected client.
    //
    // State of Button B may be read on demand by a connected client or the client may
    // subscribe to notifications of state change.
    // 3 button states are defined and represented by a simple numeric enumeration:
    // 0 = not pressed, 1 = pressed, 2 = long press.
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func buttonBState() async throws -> Int {
        return try await BLEPeripheralInt8Read(uuid:
                                        MicrobitBLEProfile.buttonCharacteristicStateBUUID)
    }

    public func buttonASetNotify(enable: Bool) async throws {
        return try await BLEPeripheralSetNotify(
            enable: enable,
            uuid: MicrobitBLEProfile.buttonCharacteristicStateAUUID)
    }

    public func buttonBSetNotify(enable: Bool) async throws {
        return try await BLEPeripheralSetNotify(
            enable: enable,
            uuid: MicrobitBLEProfile.buttonCharacteristicStateBUUID)
    }
}

// MARK: Magnetometer

extension MicrobitBLEHandler {
    // Service: Magnetometer [Optional]
    // Characteristic: Magnetometer Data [Mandatory]
    //
    // Exposes magnetometer data.
    // A magnetometer measures a magnetic field such as the earth's magnetic field in 3 axes.
    //
    // Contains magnetometer measurements for X, Y and Z axes as 3 signed 16 bit values
    // in that order and in little endian format.
    // Data can be read on demand or notified periodically.
    //   1. Magnetometer_X : sint16
    //   2. Magnetometer_Y : sint16
    //   3. Magnetometer_Z : sint16
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func magnetometerData() async throws -> [Int] {
        return try await BLEPeripheralIntArrayRead(uuid:
                         MicrobitBLEProfile.magnetometerCharacteristicData)
    }

    // Service: Magnetometer [Optional]
    // Characteristic: Magnetometer Bearing [Mandatory]
    //
    // Exposes magnetometer data.
    // A magnetometer measures a magnetic field such as the earth's magnetic field in 3 axes.
    //
    // Compass bearing in degrees from North.
    //   1. bearing value : uint16
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func magnetometerBearing() async throws -> Int {
        return try await BLEPeripheralInt16Read(uuid:
                         MicrobitBLEProfile.magnetometerCharacteristicBearing)
    }

    // Valid values are 1, 2, 5, 10, 20, 80, 160 and 640
    public func setMagnetometerPeriod(msec: UInt16) async throws {
        let data = Data([UInt8(msec & 0xff), UInt8((msec >> 8) & 0xff)])
        return try await BLEPeripheralWrite(uuid:
                         MicrobitBLEProfile.magnetometerCharacteristicPeriod,
                                            data: data)
    }

    public func magnetometerDataSetNotify(enable: Bool) async throws {
        return try await BLEPeripheralSetNotify(
            enable: enable,
            uuid: MicrobitBLEProfile.magnetometerCharacteristicData)
    }
}

// MARK: Accelerometer

extension MicrobitBLEHandler {
    // Service: Accelerometer [Optional]
    // Characteristic: Accelerometer Data [Mandatory]
    //
    // Exposes accelerometer data. An accelerometer is an electromechanical device
    // that will measure acceleration forces.
    // These forces may be static, like the constant force of gravity pulling at your feet,
    // or they could be dynamic - caused by moving or vibrating the accelerometer.
    //
    // Value contains fields which represent 3 separate accelerometer measurements
    // for X, Y and Z axes as 3 unsigned 16 bit values in that order and in
    // little endian format.
    //
    // Data can be read on demand or notified periodically.
    //
    // Contains accelerometer measurements for X, Y and Z axes as 3 signed 16 bit
    // values in that order and in little endian format. X, Y and Z values should be divided by 1000.
    // - Read : Mandatory / Write : Excluded / Notify : Mandatory
    public func accelerometerData() async throws -> [Int] {
        return try await BLEPeripheralIntArrayRead(uuid:
                                MicrobitBLEProfile.accelerometerCharacteristicData)
    }

    // Service: Accelerometer [Optional]
    // Characteristic: Accelerometer Period [Mandatory]
    //
    // Determines the frequency with which accelerometer data is reported in milliseconds.
    // Valid values are 1, 2, 5, 10, 20, 80, 160 and 640.
    //   1. Accelerometer_Period : uint16
    // - Read : Mandatory / Write : Mandatory / Notify : Excluded
    public func accelerometerPeriod() async throws -> Int {
        return try await BLEPeripheralInt16Read(uuid:
                                MicrobitBLEProfile.accelerometerCharacteristicPeriod)
    }

    // Valid values are 1, 2, 5, 10, 20, 80, 160 and 640
    public func setAccelerometerPeriod(msec: UInt16) async throws {
        let data = Data([UInt8(msec & 0xff), UInt8((msec >> 8) & 0xff)])
        return try await BLEPeripheralWrite(uuid:
                         MicrobitBLEProfile.accelerometerCharacteristicPeriod,
                                            data: data)
    }

    public func accelerometerDataSetNotify(enable: Bool) async throws {
        return try await BLEPeripheralSetNotify(
            enable: enable,
            uuid: MicrobitBLEProfile.accelerometerCharacteristicData)
    }
}

// MARK: LED

extension MicrobitBLEHandler {
    // Service: LED [Optional]
    // Characteristic: LED Matrix State [Mandatory]
    //
    // Provides access to and control of LED state. Allows the state (ON or OFF) of
    // all 25 LEDs to be set in a single write operation.
    // Allows short text strings to be sent by a client for display on the LED matrix and
    // scrolled across at a speed controlled by the Scrolling Delay characteristic.
    //
    // Allows the state of any|all LEDs in the 5x5 grid to be set to on or off with a single GATT operation.
    // Consists of an array of 5 x utf8 octets, each representing one row of 5 LEDs.
    // Octet 0 represents the first row of LEDs i.e. the top row when the micro:bit is
    // viewed with the edge connector at the bottom and USB connector at the top.
    // Octet 1 represents the second row and so on.
    // In each octet, bit 4 corresponds to the first LED in the row, bit 3 the second and so on.
    // Bit values represent the state of the related LED: off (0) or on (1).
    //
    // So we have:
    //
    // Octet 0, LED Row 1: bit4 bit3 bit2 bit1 bit0
    // Octet 1, LED Row 2: bit4 bit3 bit2 bit1 bit0
    // Octet 2, LED Row 3: bit4 bit3 bit2 bit1 bit0
    // Octet 3, LED Row 4: bit4 bit3 bit2 bit1 bit0
    // Octet 4, LED Row 5: bit4 bit3 bit2 bit1 bit0
    //
    //   1. LED_Matrix_State : uint8[]
    // - Read : Mandatory / Write : Mandatory / Notify : Excluded
    public func setLedMatrix(bytes: [UInt8]) async throws {
        let bytes5 = [UInt8](bytes[0...4])
        let data = Data(bytes5)
        return try await BLEPeripheralWrite(
            uuid: MicrobitBLEProfile.ledCharacteristicMatrix, data: data)
    }

    // Service: LED [Optional]
    // Characteristic: LED Text [Mandatory]
    //
    // A short UTF-8 string to be shown on the LED display. Maximum length 20 octets.
    //   1. LED_Text_Value : utf8s
    // - Read : Excluded / Write : Mandatory / Notify : Excluded
    public func setLedText(text: String) async throws {
        let asciiText = String((text.compactMap { char in
            char.isASCII ? char : nil
        }).prefix(20))

        if let data = asciiText.data(using: .ascii) {
            return try await BLEPeripheralWrite(
                uuid: MicrobitBLEProfile.ledCharacteristicText, data: data)
        } else {
            // do nothing
        }
        return
    }

    // Service: LED [Optional]
    // Characteristic: Scrolling Delay [Mandatory]
    //
    // Specifies a millisecond delay to wait for in between showing each
    // character on the display.
    //   1. Scrolling_Delay_Value : uint16
    // - Read : Mandatory / Write : Mandatory / Notify : Excluded
    public func setLedScrolling(delay: UInt16) async throws {
        var uint16 = delay
        let data = Data(bytes: &uint16, count: MemoryLayout<UInt16>.size)
        return try await BLEPeripheralWrite(
            uuid: MicrobitBLEProfile.ledCharacteristicDelay, data: data)
    }
}

// MARK: IO PIN

extension MicrobitBLEHandler {
    // Service: IO PIN [Optional]
    //
    // Provides read/write access to I/O pins, individually or collectively.
    // Allows configuration of each pin for input/output and analogue/digital use.

    // Characteristic: Pin Data [Optional]
    //
    // Contains data relating to zero or more pins. Structured as a variable
    // length array of up to 19 Pin Number / Value pairs.
    // Pin Number and Value are each uint8 fields.
    // Note however that the micro:bit has a 10 bit ADC and so values are compressed
    // to 8 bits with a loss of resolution.
    // OPERATIONS:
    // WRITE: Clients may write values to one or more pins in a single GATT write operation.
    // A pin to which a value is to be written must have been configured for output
    // using the Pin IO Configuration characteristic.
    // Any attempt to write to a pin which is configured for input will be ignored.
    //
    // NOTIFY: Notifications will deliver Pin Number / Value pairs for those
    // pins defined as input pins by the Pin IO Configuration characteristic
    // and whose value when read differs from the last read of the pin.
    //
    // READ: A client reading this characteristic will receive Pin Number / Value pairs
    // for all those pins defined as input pins by the Pin IO Configuration characteristic.
    //   1. IO_Pin_Data : uint8[]
    // - Read : Mandatory / Write : Mandatory / Notify : Mandatory
    public func getIOPinData() async throws -> [Int] {
        return try await BLEPeripheralInt8ArrayRead(uuid:
                         MicrobitBLEProfile.iopinCharacteristicData)
    }

    // return: [0] ... PIN 7 (MSB)... PIN 0 (LSB)
    //         [1] ... PIN 15     ... PIN 8
    //         [2] ... 0 0 0 0 PIN 19 ... PIN 16
    //         [3] ... 0 0 0 0 0 0 0 0
    //         0 : output / 1 : input
    public func getIOPinConfiguration() async throws -> [Int] {
        return try await BLEPeripheralInt8ArrayRead(uuid:
                         MicrobitBLEProfile.iopinCharacteristicIOConfiguration)
    }

    // inputPins: [Int]  ... { x | 0 <= x <= 19 }
    //   example: [0, 1, 2, 19] ... PIN 0/1/2/19 are set to input and others are set to output
    //
    // [Note] All Micro:bit pins are output by default.
    public func setIOPinConfiguration(inputPins: [Int]) async throws {
//        let data = Data([UInt8(0x7), UInt8(0x0), UInt8(0x0), UInt8(0x0)])

        var value32: UInt32 = 0
        inputPins.forEach { pin in
            if pin >= 0 && pin <= 19 {
                value32 |= (UInt32(0x01) << pin)
            }
        }
        let values = [ UInt8( value32 & 0xff ),
                       UInt8( (value32 >> 8) & 0xff ),
                       UInt8( (value32 >> 16) & 0xff ),
                       UInt8( (value32 >> 24) & 0xff) ]
        let data = Data(values)

        return try await BLEPeripheralWrite(
            uuid: MicrobitBLEProfile.iopinCharacteristicIOConfiguration,
            data: data)  // Each bit: 0: output/ 1: input
    }

    public func setIOPinADConfiguration(analogPins: [Int]) async throws {
        var value32: UInt32 = 0
        analogPins.forEach { pin in
            if pin >= 0 && pin <= 19 {
                value32 |= (UInt32(0x01) << pin)
            }
        }
        let values = [ UInt8( value32 & 0xff ),
                       UInt8( (value32 >> 8) & 0xff ),
                       UInt8( (value32 >> 16) & 0xff ),
                       UInt8( (value32 >> 24) & 0xff) ]
        let data = Data(values)

        return try await BLEPeripheralWrite(
            uuid: MicrobitBLEProfile.iopinCharacteristicADConfiguration,
            data: data)  // Each bit: 0: digital/ 1: analog
    }

    // (pin: Int, value: Int) : pin: 0...19, output: 0 (Low: 0[V]) or 1 (High: 3.3[V])
    //   example: [(pin: 0, value: 1), (pin: 2, value: 0)] ... PIN 0 => High, PIN 2 => Low
    public func setIOPinData(_ pinPairs: [(pin: Int, value: UInt8)]) async throws {
        // check parameters and take care of illegal values
        let pairs = pinPairs.compactMap { (pin, value) in
            if pin >= 0 && pin <= 19 {                          // PIN : 0...19
                return (UInt8(pin), UInt8(value == 0 ? 0 : 1)) // OUTPUT: 0 or 1
            } else {
                return nil
            }
        }
        let uint8s = [UInt8]()
        let values = pairs.reduce(into: uint8s) { $0 += [$1.0, $1.1] }
        let data = Data(values)
//        let data = Data([UInt8(0x0), UInt8(0x1), UInt8(0x1), UInt8(0x0)])
        return try await BLEPeripheralWrite(
            uuid: MicrobitBLEProfile.iopinCharacteristicData,
            data: data)
    }

    public func setIOPinDataPWM(pins: [(pin: UInt8, pwm: (value: UInt16, period: UInt32))]) async throws {
        var uint8s = [UInt8]()
        pins.forEach { (pin, pwm) in
            if pin >= 0 && pin <= 19 {
                uint8s.append(pin)
                uint8s.append(UInt8(pwm.value & 0xff))
                uint8s.append(UInt8((pwm.value >> 8) & 0xff))
                uint8s.append(UInt8(pwm.period & 0xff))
                uint8s.append(UInt8((pwm.period >> 8) & 0xff))
                uint8s.append(UInt8((pwm.period >> 16) & 0xff))
                uint8s.append(UInt8((pwm.period >> 24) & 0xff))
            }
        }
        if !uint8s.isEmpty {
            let data = Data(uint8s)
            try await BLEPeripheralWrite(
                uuid: MicrobitBLEProfile.iopinCharacteristicPWMControl,
                data: data)
        }
    }

    public func iopinDataSetNotify(enable: Bool) async throws {
        return try await BLEPeripheralSetNotify(
            enable: enable,
            uuid: MicrobitBLEProfile.iopinCharacteristicData)
    }
}

// MARK: Common

extension MicrobitBLEHandler {
    private func BLEPeripheralSetNotify(enable: Bool, uuid: String) async throws {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .setting   // connected => setting
        peripheralStateStreamContinuation?.yield(peripheralState)

        return try await withCheckedThrowingContinuation { continuation in
            assert(notifyContinuation == nil)
            notifyContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.setNotifyValue(enable, for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }
    }

    private func BLEPeripheralStringRead(uuid: String) async throws -> String {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .reading   // connected => reading
        peripheralStateStreamContinuation?.yield(peripheralState)

//        return try await withCheckedThrowingContinuation { continuation in
//            assert(readStringContinuation == nil)
//            readStringContinuation = continuation
//
//            if let characteristic: CBCharacteristic
//                = self.characteristics[uuid] {
//                peripheral.readValue(for: characteristic)
//            } else {
//                // not supported on the peripheral (The characteristic was not discovered.)
//                assertionFailure()
//            }
//        }

        let data = try await withCheckedThrowingContinuation { continuation in
            assert(readDataContinuation == nil)
            readDataContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.readValue(for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }

        if let data {
            let text = String(decoding: data, as: UTF8.self)
            return text
        } else {
            // do nothing
        }

        return "" // return empty string because data could not be gotten
    }

    private func BLEPeripheralInt8Read(uuid: String) async throws -> Int {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .reading   // connected => reading
        peripheralStateStreamContinuation?.yield(peripheralState)

//        return try await withCheckedThrowingContinuation { continuation in
//            assert(readInt8Continuation == nil)
//            readInt8Continuation = continuation
//
//            if let characteristic: CBCharacteristic
//                = self.characteristics[uuid] {
//                peripheral.readValue(for: characteristic)
//            } else {
//                // not supported on the peripheral (The characteristic was not discovered.)
//                assertionFailure()
//            }
//        }

        let data = try await withCheckedThrowingContinuation { continuation in
            assert(readDataContinuation == nil)
            readDataContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.readValue(for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }

        if let data {
            var byte: CUnsignedChar = 0
            data.copyBytes(to: &byte, count: 1)
            return Int(byte)
        }

        return 0 // return zero because data could not be gotten
    }

    private func BLEPeripheralInt16Read(uuid: String) async throws -> Int {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .reading   // connected => reading
        peripheralStateStreamContinuation?.yield(peripheralState)

//        return try await withCheckedThrowingContinuation { continuation in
//            assert(readInt16Continuation == nil)
//            readInt16Continuation = continuation
//
//            if let characteristic: CBCharacteristic
//                = self.characteristics[uuid] {
//                peripheral.readValue(for: characteristic)
//            } else {
//                // not supported on the peripheral (The characteristic was not discovered.)
//                assertionFailure()
//            }
//        }

        let data = try await withCheckedThrowingContinuation { continuation in
            assert(readDataContinuation == nil)
            readDataContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.readValue(for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }

        if let data {
            let bytes = [UInt8](data)
            return Int(bytes[1]) * 256 + Int(bytes[0])
        }

        return 0 // return zero because data could not be gotten
    }

    private func BLEPeripheralIntArrayRead(uuid: String) async throws -> [Int] {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .reading   // connected => reading
        peripheralStateStreamContinuation?.yield(peripheralState)

//        return try await withCheckedThrowingContinuation { continuation in
//            assert(readIntArrayContinuation == nil)
//            readIntArrayContinuation = continuation
//
//            if let characteristic: CBCharacteristic
//                = self.characteristics[uuid] {
//                peripheral.readValue(for: characteristic)
//            } else {
//                // not supported on the peripheral (The characteristic was not discovered.)
//                assertionFailure()
//            }
//        }
        let data = try await withCheckedThrowingContinuation { continuation in
            assert(readDataContinuation == nil)
            readDataContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.readValue(for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }

        if let data {
//            var result: [Int] = []
//            let bytes = [UInt8](data)
//            var buf: [Int16]
            let buf = data.withUnsafeBytes {
                Array(UnsafeBufferPointer(
                    start: $0.baseAddress!.assumingMemoryBound(to: Int16.self),
                    count: $0.count / 2))
            }

            let result = [Int(buf[0]), Int(buf[1]), Int(buf[2])]
//            print("🔥 UpdateValue: data = \(bytes) result = \(result) buf = \(buf)")
            return result
        } else {
            // do nothing
        }
        return []
    }

    private func BLEPeripheralInt8ArrayRead(uuid: String) async throws -> [Int] {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .reading   // connected => reading
        peripheralStateStreamContinuation?.yield(peripheralState)

        let data = try await withCheckedThrowingContinuation { continuation in
            assert(readDataContinuation == nil)
            readDataContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.readValue(for: characteristic)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }
//        print("🧊🧊 data = \(data) data.count = \(data?.count)")
        if let data {
            let uint8s = [UInt8](data)
            let result = uint8s.map { Int($0) }
            return result
        } else {
            // do nothing
        }
        return []
    }

    private func BLEPeripheralWrite(uuid: String, data: Data) async throws {
        assert(centralManager != nil)

        if self.characteristics[uuid] == nil {
            // The characteristic is not supported on the peripheral.
            // The characteristic was not discovered.
            throw BLEError.errNotSupported
        }

        try checkStateAndThrowErrors()  // Check the BLE Central State
        if peripheralState != .connected {
            throw BLEError.errWorking   // illegal state
        }

        peripheralState = .writing   // connected => writing
        peripheralStateStreamContinuation?.yield(peripheralState)

        return try await withCheckedThrowingContinuation { continuation in
            assert(writeContinuation == nil)
            writeContinuation = continuation

            if let characteristic: CBCharacteristic
                = self.characteristics[uuid] {
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            } else {
                // not supported on the peripheral (The characteristic was not discovered.)
                assertionFailure()
            }
        }
    }

//    private func BLEPeripheralWrite(uuid: String, bytes: [UInt8]) async throws {
//        assert(centralManager != nil)
//
//        if self.characteristics[uuid] == nil {
//            // The characteristic is not supported on the peripheral.
//            // The characteristic was not discovered.
//            throw BLEError.errNotSupported
//        }
//
//        try checkStateAndThrowErrors()  // Check the BLE Central State
//        if peripheralState != .connected {
//            throw BLEError.errWorking   // illegal state
//        }
//
//        peripheralState = .writing   // connected => writing
//        peripheralStateStreamContinuation?.yield(peripheralState)
//
//        return try await withCheckedThrowingContinuation { continuation in
//            assert(writeContinuation == nil)
//            writeContinuation = continuation
//
//            let data = Data(bytes)
//            if let characteristic: CBCharacteristic
//                = self.characteristics[uuid] {
//                peripheral.writeValue(data, for: characteristic, type: .withResponse)
//            } else {
//                // not supported on the peripheral (The characteristic was not discovered.)
//                assertionFailure()
//            }
//        }
//    }
}
