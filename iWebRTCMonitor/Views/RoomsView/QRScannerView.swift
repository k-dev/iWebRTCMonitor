//
//  QRScannerView.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import AVFoundation

typealias OnScannedQR = (String) -> Void

/// Defines the platform QR scanner and creates its coordinator.
@MainActor
struct QRScannerView {
    
    var onScannedQR: OnScannedQR?
    
    func makeCoordinator() -> QRScannerViewCoordinator {
        return QRScannerViewCoordinator(onScannedQR: onScannedQR)
    }
}

/// Delivers the first scanned QR value and then releases its callback.
///
/// The platform representable owns this coordinator. Both platform adapters
/// call `didScanQR` on the main queue before they change its callback state.
@MainActor
class QRScannerViewCoordinator: NSObject {

    private var onScannedQR: OnScannedQR?
    
    init(onScannedQR: OnScannedQR?) {
        self.onScannedQR = onScannedQR
    }
    
    func didScanQR(_ payload: String) {
        if let closure = self.onScannedQR {
            self.onScannedQR = nil
            closure(payload)
        }
    }
}
