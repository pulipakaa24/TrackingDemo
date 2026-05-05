import CoreBluetooth

enum QorvoBLEUUIDs {
    static let niService        = CBUUID(string: "2E938FD0-6A61-11ED-A1EB-0242AC120002")
    // App writes accessory configuration / commands to this characteristic
    static let rxCharacteristic = CBUUID(string: "2E93998A-6A61-11ED-A1EB-0242AC120002")
    // Accessory notifies the app with ranging data / responses on this characteristic
    static let txCharacteristic = CBUUID(string: "2E939AF2-6A61-11ED-A1EB-0242AC120002")
    
    // ESP32 RescueVision BLE
    static let espService       = CBUUID(string: "6E400D00-B5A3-F393-E0A9-E50E24DC4A01")
    static let espTxChar        = CBUUID(string: "6E400D01-B5A3-F393-E0A9-E50E24DC4A01")
}
