//
//  QRScannerViewNSRepresentable.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 18.06.2026.
//

import AVFoundation
import Vision
import SwiftUI

@MainActor
class QRScannerNSViewController: NSViewController {

    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "qrScanner.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "qrScanner.frames", qos: .userInitiated)
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        let captureSession = AVCaptureSession()
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        }
        catch {
            Log(level: .warning, error.localizedDescription)
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        }
        else {
            return // In production, show an alert here
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(delegate, queue: frameQueue)
            captureSession.addOutput(videoOutput)
        }
        else {
            Log(level: .warning, "Can't add video output")
            return
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.addSublayer(previewLayer)

        self.captureSession = captureSession
        self.previewLayer = previewLayer
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()

        setCaptureRunning(true)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()

        setCaptureRunning(false)
    }

    fileprivate func setCaptureRunning(_ running: Bool) {
        guard let captureSession else { return }
        // Configuration finishes on MainActor before the session is published.
        // All subsequent running-state reads and start/stop calls use sessionQueue.
        nonisolated(unsafe) let session = captureSession
        sessionQueue.async {
            if running {
                if !session.isRunning { session.startRunning() }
            } else if session.isRunning {
                session.stopRunning()
            }
        }
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = view.bounds
        CATransaction.commit()
    }
}

extension QRScannerView: NSViewControllerRepresentable {
    
    func makeNSViewController(context: Context) -> QRScannerNSViewController {
        let vc = QRScannerNSViewController()
        vc.delegate = context.coordinator
        return vc
    }
    
    func updateNSViewController(_ vc: QRScannerNSViewController, context: Context) {
        vc.delegate = context.coordinator
    }

    static func dismantleNSViewController(_ vc: QRScannerNSViewController, coordinator: QRScannerViewCoordinator) {
        vc.setCaptureRunning(false)
    }
}

extension QRScannerViewCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Vision and the sample buffer stay on the serial frame queue.
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([barcodeRequest])
            guard let payload = barcodeRequest.results?.first(where: { $0.payloadStringValue != nil })?.payloadStringValue else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.didScanQR(payload)
            }
        }
        catch {
            Log(level: .warning, error.localizedDescription)
        }
    }
}
