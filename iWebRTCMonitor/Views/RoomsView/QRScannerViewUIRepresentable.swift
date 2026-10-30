//
//  QRScannerViewUIRepresentable.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import SwiftUI
import VisionKit
import Vision //< needed for iOS

class QRScannerUIViewController: UIViewController {
    
    weak var delegate: DataScannerViewControllerDelegate?
    
    private var scannerViewController: DataScannerViewController?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        do {
            try self.scannerViewController?.startScanning()
        }
        catch {
            Log(error.localizedDescription)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.scannerViewController?.stopScanning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let dataScannerVC = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                      isHighlightingEnabled: true)
        dataScannerVC.delegate = delegate

        self.addChild(dataScannerVC)
        
        dataScannerVC.view.frame = self.view.bounds
        dataScannerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(dataScannerVC.view)

        dataScannerVC.didMove(toParent: self)
        
        self.scannerViewController = dataScannerVC
    }
}

extension QRScannerView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> QRScannerUIViewController {
        let vc = QRScannerUIViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ vc: QRScannerUIViewController, context: Context) {
        vc.delegate = context.coordinator
    }
}

extension QRScannerViewCoordinator: DataScannerViewControllerDelegate {

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        handle(item)
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        if let firstItem = addedItems.first {
            handle(firstItem)
        }
    }
    
    private func handle(_ item: RecognizedItem) {
        if case .barcode(let barcode) = item,
           let payload = barcode.payloadStringValue {
            DispatchQueue.main.async { [weak self] in
                self?.didScanQR(payload)
            }
        }
    }
}
