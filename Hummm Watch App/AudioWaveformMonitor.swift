//
//  AudioWaveformMonitor.swift
//  Hummm Watch App
//
//  Created by Ayush Singh on 6/9/25.
//

import SwiftUI
import AVFoundation
import Accelerate
import Charts

enum Constants {
    static let sampleAmount: Int = 200
    static let downSampleFactor = 8
    static let magnitudeLimit: Float = 100
}

@MainActor
@Observable
final class AudioWaveformMonitor {
    static let shared = AudioWaveformMonitor()
    private var audioEngine = AVAudioEngine()
    var fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
    
    var downSampledMagnitudes: [Float] {
        fftMagnitudes.lazy.enumerated().compactMap { index, value in
            index.isMultiple(of: Constants.downSampleFactor) ? value : nil
            
        }
    }
    
    var isMonitoring = false
    
    private init() {}
    
    func startMonitoring() async {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, UInt(self.bufferSize), .FORWARD)
        
        let audioStream = AsyncStream<[Float]> { continuation in
            inputNode.installTap(onBus: 0, bufferSize: UInt32(bufferSize), format: inputFormat) { @Sendable buffer, _ in
               
                let channelData = buffer.floatChannelData?[0]
                let frameCount = Int(buffer.frameLength)
                let floatData = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                continuation.yield(floatData)
                
            
            }
            
        }
        
        do {
            try audioEngine.start()
            isMonitoring = true
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
            return
        }
        
        for await floatData in audioStream {
            self.fftMagnitudes = await self.performFFT(data: floatData)
        }
        
    }
    
    func stopMonitoring() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        fftMagnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
        
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }
        
        isMonitoring = false
    }
    
    func performFFT(data: [Float]) async -> [Float] {
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: Constants.sampleAmount)
        }
        
        var realIn = data
        var imagIn = [Float](repeating: 0, count: bufferSize)
        
        var realOut = [Float](repeating: 0, count: bufferSize)
        var imagOut = [Float](repeating: 0, count: bufferSize)
        
        var magnitudes = [Float](repeating: 0, count: Constants.sampleAmount)
        
        realIn.withUnsafeBufferPointer { realInPtr in
            imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        vDSP_DFT_Execute(setup, realInPtr.baseAddress!, imagInPtr.baseAddress!, realOutPtr.baseAddress!, imagOutPtr.baseAddress!)
                        
                        var complex = DSPSplitComplex(realp: realOutPtr.baseAddress!, imagp: imagOutPtr.baseAddress!)
                        
                        vDSP_zvabs(&complex, 1, &magnitudes, 1, UInt(Constants.sampleAmount))
                    }
                }
            }
        }
        return magnitudes.map { min($0, Constants.magnitudeLimit)}
    }
    
    private let bufferSize = 8192
    private var fftSetup: OpaquePointer?
    
}
