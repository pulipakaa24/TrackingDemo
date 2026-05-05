import Foundation
import simd
import Combine

struct RadarBlob {
    let position: simd_float3
    let classId: UInt16
}

class RadarManager: ObservableObject {
    @Published var blobs: [RadarBlob] = []
    
    private var rxBuffer: Data = Data()
    
    func handleAccessoryData(_ data: Data) {
        guard data.count >= 12 else { return }
        
        _ = data[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) } // frameNum
        _ = data[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) } // tsMs
        _ = data[8..<10].withUnsafeBytes { $0.load(as: UInt16.self) } // hdgCdeg
        let numPoints = data[10..<12].withUnsafeBytes { $0.load(as: UInt16.self) }
        
        let expectedSize = 12 + Int(numPoints) * 8
        if data.count < expectedSize {
            return
        }
        
        var newBlobs: [RadarBlob] = []
        var offset = 12
        for _ in 0..<numPoints {
            let dist = data[offset..<offset+2].withUnsafeBytes { $0.load(as: UInt16.self) }
            let bear = data[offset+2..<offset+4].withUnsafeBytes { $0.load(as: UInt16.self) }
            let elev = data[offset+4..<offset+6].withUnsafeBytes { $0.load(as: Int16.self) }
            let cls = data[offset+6..<offset+8].withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // To Cartesian in DWM coordinate frame
            let distanceM = Float(dist) / 1000.0
            let bearingRad = Float(bear) * .pi / 18000.0
            let elevRad = Float(elev) * .pi / 18000.0
            
            let ce = cos(elevRad)
            // ESP32 dwm_geom output: +X is East, +Y is North, +Z is Up.
            // ARKit .gravityAndHeading: +X is East, +Y is Up, -Z is North.
            let espX = distanceM * ce * sin(bearingRad)
            let espY = distanceM * ce * cos(bearingRad)
            let espZ = distanceM * sin(elevRad)
            
            // Map to ARKit space
            let x = espX
            let y = espZ
            let z = -espY
            
            newBlobs.append(RadarBlob(position: simd_float3(x, y, z), classId: cls))
            offset += 8
        }
        
        DispatchQueue.main.async {
            self.blobs = newBlobs
        }
    }
}
