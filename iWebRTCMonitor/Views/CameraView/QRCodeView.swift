//
//  QRCodeView.swift
//  iWebRTCMonitor
//
//  Created by Kyrylo on 18.06.2026.
//

import SwiftUI
import Foundation
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    
    let qrData: Data
    
    var body: some View {
        VStack {
            if let image = generateQRCode(from: qrData) {
                Image(image, scale: 1.0, label: Text("QR Code"))
                    .interpolation(.none) // Keeps the QR code sharp
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
            }
        }
    }
}

private func generateQRCode(from data: Data) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = data

    if let outputImage = filter.outputImage {
        return CIContext().createCGImage(outputImage, from: outputImage.extent)
    }
    return nil
}
