import SwiftUI

import RTVIClientIOSGeminiLiveWebSocket
import RTVIClientIOS

class CallContainerModel: ObservableObject {
    
    @Published var voiceClientStatus: String = TransportState.disconnected.description
    @Published var isInCall: Bool = false
    @Published var isBotReady: Bool = false
    @Published var timerCount = 0
    
    @Published var isMicEnabled: Bool = false
    
    @Published var toastMessage: String? = nil
    @Published var showToast: Bool = false
    
    @Published
    var remoteAudioLevel: Float = 0
    @Published
    var localAudioLevel: Float = 0
    
    private var meetingTimer: Timer?
    
    var rtviClientIOS: RTVIClient?
    
    init() {
        // Changing the log level
        RTVIClientIOS.setLogLevel(.warn)
    }
    
    @MainActor
    func connect(geminiAPIKey: String) {
        let geminiAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if(geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty){
            self.showError(message: "Need to provide a Gemini API key")
            return
        }
        
        let currentSettings = SettingsManager.getSettings()
        let rtviClientOptions = RTVIClientOptions.init(
            enableMic: currentSettings.enableMic,
            enableCam: false,
            params: .init(config: [
                .init(
                    service: "llm",
                    options: [
                        .init(name: "api_key", value: .string(geminiAPIKey)),
                        .init(name: "initial_messages", value: .array([
                            .object([
                                "role": .string("user"), // "user" | "system"
                                "content": .string("You are Chatbot, a friendly, helpful robot. Your goal is to demonstrate your capabilities in a succinct way. Your output will be converted to audio so don't include special characters in your answers. Respond to what the user said in a creative and helpful way, but keep your responses brief. Start by introducing yourself.")
                            ])
                        ])),
                        .init(name: "generation_config", value: .object([
                            "speech_config": .object([
                                "voice_config": .object([
                                    "prebuilt_voice_config": .object([
                                        "voice_name": .string("Puck") // "Puck" | "Charon" | "Kore" | "Fenrir" | "Aoede"
                                    ])
                                ])
                            ])
                        ]))
                    ]
                )
            ])
        )
        self.rtviClientIOS = RTVIClient.init(
            transport: GeminiLiveWebSocketTransport.init(options: rtviClientOptions),
            options: rtviClientOptions
        )
        self.rtviClientIOS?.delegate = self
        self.rtviClientIOS?.start() { result in
            if case .failure(let error) = result {
                self.showError(message: error.localizedDescription)
                self.rtviClientIOS = nil
            }
        }
        // Selecting the mic based on the preferences
        if let selectedMic = currentSettings.selectedMic {
            self.rtviClientIOS?.updateMic(micId: MediaDeviceId(id:selectedMic), completion: nil)
        }
        self.saveCredentials(geminiAPIKey: geminiAPIKey)
    }
    
    @MainActor
    func disconnect() {
        self.rtviClientIOS?.disconnect(completion: nil)
    }
    
    func showError(message: String) {
        self.toastMessage = message
        self.showToast = true
        // Hide the toast after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.showToast = false
            self.toastMessage = nil
        }
    }
    
    @MainActor
    func toggleMicInput() {
        self.rtviClientIOS?.enableMic(enable: !self.isMicEnabled) { result in
            switch result {
            case .success():
                self.isMicEnabled = self.rtviClientIOS?.isMicEnabled ?? false
            case .failure(let error):
                self.showError(message: error.localizedDescription)
            }
        }
    }
    
    private func startTimer(withExpirationTime expirationTime: Int) {
        let currentTime = Int(Date().timeIntervalSince1970)
        self.timerCount = expirationTime - currentTime
        self.meetingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                self.timerCount -= 1
            }
        }
    }
    
    private func stopTimer() {
        self.meetingTimer?.invalidate()
        self.meetingTimer = nil
        self.timerCount = 0
    }
    
    func saveCredentials(geminiAPIKey: String) {
        var currentSettings = SettingsManager.getSettings()
        currentSettings.geminiAPIKey = geminiAPIKey
        // Saving the settings
        SettingsManager.updateSettings(settings: currentSettings)
    }
    
}

extension CallContainerModel:RTVIClientDelegate, LLMHelperDelegate {
    
    private func handleEvent(eventName: String, eventValue: Any? = nil) {
        if let value = eventValue {
            print("RTVI Demo, received event:\(eventName), value:\(value)")
        } else {
            print("RTVI Demo, received event: \(eventName)")
        }
    }
    
    func onTransportStateChanged(state: TransportState) {
        self.handleEvent(eventName: "onTransportStateChanged", eventValue: state)
        self.voiceClientStatus = state.description
        self.isInCall = ( state == .connecting || state == .connected || state == .ready || state == .authenticating )
    }
    
    @MainActor
    func onBotReady(botReadyData: BotReadyData) {
        self.handleEvent(eventName: "onBotReady.")
        self.isBotReady = true
        if let expirationTime = self.rtviClientIOS?.expiry() {
            self.startTimer(withExpirationTime: expirationTime)
        }
    }
    
    @MainActor
    func onConnected() {
        self.isMicEnabled = self.rtviClientIOS?.isMicEnabled ?? false
    }
    
    func onDisconnected() {
        self.stopTimer()
        self.isBotReady = false
    }
    
    func onRemoteAudioLevel(level: Float, participant: Participant) {
        self.remoteAudioLevel = level
    }
    
    func onUserAudioLevel(level: Float) {
        self.localAudioLevel = level
    }
    
    func onUserTranscript(data: Transcript) {
        if (data.final ?? false) {
            self.handleEvent(eventName: "onUserTranscript", eventValue: data.text)
        }
    }
    
    func onBotTranscript(data: String) {
        self.handleEvent(eventName: "onBotTranscript", eventValue: data)
    }
    
    func onError(message: String) {
        self.handleEvent(eventName: "onError", eventValue: message)
        self.showError(message: message)
    }
    
    func onTracksUpdated(tracks: Tracks) {
        self.handleEvent(eventName: "onTracksUpdated", eventValue: tracks)
    }
    
}
