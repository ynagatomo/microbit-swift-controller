//
//  MicrobitBLEProfile.swift
//  MicrobitSwiftController
//
//  Created by Yasuhito Nagatomo on 2023/05/06.
//

enum MicrobitBLEProfile: String {
    case deviceInformation
    case temperature
    case button
    case iopin
    case led
    case magnetometer
    case accelerometer

    // BLE Profile: BBC microbit V1_11
    // https://lancaster-university.github.io/microbit-docs/resources/bluetooth/bluetooth_profile.html

    // deviceInformationUUID = "0000180A-0000-1000-8000-00805F9B34FB"
    static let deviceInformationUUID = "180A" // Mandatory
    // infoCharacteristicModelNumberUUID = "00002A24-0000-1000-8000-00805F9B34FB"
    static let infoCharacteristicModelNumberUUID = "2A24" // Optional
    // infoCharacteristicSerialNumberUUID = "00002A25-0000-1000-8000-00805F9B34FB"
    static let infoCharacteristicSerialNumberUUID = "2A25" // Optional
    // infoCharacteristicHardwareRevUUID = "00002A27-0000-1000-8000-00805F9B34FB"
    static let infoCharacteristicHardwareRevUUID = "2A27" // Optional
    // infoCharacteristicFirmwareRevUUID = "00002A26-0000-1000-8000-00805F9B34FB"
    static let infoCharacteristicFirmwareRevUUID = "2A26" // Optional
    // infoCharacteristicManufactureUUID = "00002A29-0000-1000-8000-00805F9B34FB"
    static let infoCharacteristicManufactureUUID = "2A29" // Mandatory

    static let temperatureServiceUUID = "E95D6100-251D-470A-A062-FA1922DFA9A8"
    static let temperatureCharacteristicDataUUID = "E95D9250-251D-470A-A062-FA1922DFA9A8"
    static let temperatureCharacteristicPeriodUUID = "E95D1B25-251D-470A-A062-FA1922DFA9A8"

    static let buttonServiceUUID = "E95D9882-251D-470A-A062-FA1922DFA9A8"
    static let buttonCharacteristicStateAUUID = "E95DDA90-251D-470A-A062-FA1922DFA9A8"
    static let buttonCharacteristicStateBUUID = "E95DDA91-251D-470A-A062-FA1922DFA9A8"

    static let iopinServiceUUID =      "E95D127B-251D-470A-A062-FA1922DFA9A8"
    static let iopinCharacteristicData =            "E95D8D00-251D-470A-A062-FA1922DFA9A8"
    static let iopinCharacteristicADConfiguration = "E95D5899-251D-470A-A062-FA1922DFA9A8"
    static let iopinCharacteristicIOConfiguration = "E95DB9FE-251D-470A-A062-FA1922DFA9A8"
    static let iopinCharacteristicPWMControl      = "E95DD822-251D-470A-A062-FA1922DFA9A8"

    static let ledServiceUUID =          "E95DD91D-251D-470A-A062-FA1922DFA9A8"
    static let ledCharacteristicMatrix = "E95D7B77-251D-470A-A062-FA1922DFA9A8"
    static let ledCharacteristicText   = "E95D93EE-251D-470A-A062-FA1922DFA9A8"
    static let ledCharacteristicDelay  = "E95D0D2D-251D-470A-A062-FA1922DFA9A8"

    static let magnetometerServiceUUID =        "E95DF2D8-251D-470A-A062-FA1922DFA9A8"
    static let magnetometerCharacteristicData   = "E95DFB11-251D-470A-A062-FA1922DFA9A8"
    static let magnetometerCharacteristicPeriod  = "E95D386C-251D-470A-A062-FA1922DFA9A8"
    static let magnetometerCharacteristicBearing     = "E95D9715-251D-470A-A062-FA1922DFA9A8"
    static let magnetometerCharacteristicCalibration = "E95DB358-251D-470A-A062-FA1922DFA9A8"

    static let accelerometerServiceUUID =        "E95D0753-251D-470A-A062-FA1922DFA9A8"
    static let accelerometerCharacteristicData   = "E95DCA4B-251D-470A-A062-FA1922DFA9A8"
    static let accelerometerCharacteristicPeriod = "E95DFB24-251D-470A-A062-FA1922DFA9A8"

    static let serviceUUIDs = [
        deviceInformationUUID: deviceInformation,
        temperatureServiceUUID: temperature,
        buttonServiceUUID: button,
        iopinServiceUUID: iopin,
        ledServiceUUID: led,
        magnetometerServiceUUID: magnetometer,
        accelerometerServiceUUID: accelerometer
    ]

    static let characteristicUUIDs: [String: [String]] = [
        deviceInformationUUID: [
            infoCharacteristicModelNumberUUID,
            infoCharacteristicSerialNumberUUID,
            infoCharacteristicHardwareRevUUID,
            infoCharacteristicFirmwareRevUUID,
            infoCharacteristicManufactureUUID],
        temperatureServiceUUID: [
            temperatureCharacteristicDataUUID,
            temperatureCharacteristicPeriodUUID],
        buttonServiceUUID: [
            buttonCharacteristicStateAUUID,
            buttonCharacteristicStateBUUID],
        iopinServiceUUID: [
            iopinCharacteristicData,
            iopinCharacteristicADConfiguration,
            iopinCharacteristicIOConfiguration,
            iopinCharacteristicPWMControl],
        ledServiceUUID: [
            ledCharacteristicMatrix,
            ledCharacteristicText,
            ledCharacteristicDelay],
        magnetometerServiceUUID: [
            magnetometerCharacteristicData,
            magnetometerCharacteristicPeriod,
            magnetometerCharacteristicBearing,
            magnetometerCharacteristicCalibration],
        accelerometerServiceUUID: [
            accelerometerCharacteristicData,
            accelerometerCharacteristicPeriod]
    ]
}
