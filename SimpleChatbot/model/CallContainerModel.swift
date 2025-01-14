import SwiftUI

import RTVIClientIOSGeminiLiveWebSocket
import RTVIClientIOS

class CallContainerModel: ObservableObject {
    
    @Published var voiceClientStatus: String = TransportState.disconnected.description
    @Published var isInCall: Bool = false
    @Published var isBotReady: Bool = false
    
    @Published var isMicEnabled: Bool = false
    
    @Published var toastMessage: String? = nil
    @Published var showToast: Bool = false
    
    @Published
    var remoteAudioLevel: Float = 0
    @Published
    var localAudioLevel: Float = 0
    
    var rtviClientIOS: RTVIClient?
    
    @Published var selectedMic: MediaDeviceId? = nil {
        didSet {
            guard let selectedMic else { return } // don't store nil
            var settings = SettingsManager.getSettings()
            settings.selectedMic = selectedMic.id
            SettingsManager.updateSettings(settings: settings)
        }
    }
    @Published var availableMics: [MediaDeviceInfo] = []
    
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
            switch result {
            case .failure(let error):
                self.showError(message: error.localizedDescription)
                self.rtviClientIOS = nil
            case .success():
                // Apply initial mic preference
                if let selectedMic = currentSettings.selectedMic {
                    self.selectMic(MediaDeviceId(id: selectedMic))
                }
                // Populate available devices list
                self.availableMics = self.rtviClientIOS?.getAllMics() ?? []
            }
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
    
    func saveCredentials(geminiAPIKey: String) {
        var currentSettings = SettingsManager.getSettings()
        currentSettings.geminiAPIKey = geminiAPIKey
        // Saving the settings
        SettingsManager.updateSettings(settings: currentSettings)
    }
    
    @MainActor
    func selectMic(_ mic: MediaDeviceId) {
        self.selectedMic = mic
        self.rtviClientIOS?.updateMic(micId: mic, completion: nil)
    }
}

extension CallContainerModel:RTVIClientDelegate, LLMHelperDelegate {
    
    private func handleEvent(eventName: String, eventValue: Any? = nil) {
        if let value = eventValue {
            print("Pipecat Demo, received event:\(eventName), value:\(value)")
        } else {
            print("Pipecat Demo, received event: \(eventName)")
        }
    }
    
    func onTransportStateChanged(state: TransportState) {
        Task { @MainActor in
            self.handleEvent(eventName: "onTransportStateChanged", eventValue: state)
            self.voiceClientStatus = state.description
            self.isInCall = ( state == .connecting || state == .connected || state == .ready || state == .authenticating )
        }
    }
    
    func onBotReady(botReadyData: BotReadyData) {
        Task { @MainActor in
            self.handleEvent(eventName: "onBotReady")
            self.isBotReady = true
        }
    }
    
    func onConnected() {
        Task { @MainActor in
            self.handleEvent(eventName: "onConnected")
            self.isMicEnabled = self.rtviClientIOS?.isMicEnabled ?? false
        }
    }
    
    func onDisconnected() {
        Task { @MainActor in
            self.handleEvent(eventName: "onDisconnected")
            self.isBotReady = false
        }
    }
    
    func onError(message: String) {
        Task { @MainActor in
            self.handleEvent(eventName: "onError", eventValue: message)
            self.showError(message: message)
        }
    }
    
    func onRemoteAudioLevel(level: Float, participant: Participant) {
        Task { @MainActor in
            self.remoteAudioLevel = level
        }
    }
    
    func onUserAudioLevel(level: Float) {
        Task { @MainActor in
            self.localAudioLevel = level
        }
    }
    
    func onAvailableMicsUpdated(mics: [MediaDeviceInfo]) {
        Task { @MainActor in
            self.availableMics = mics
        }
    }
    
    func onMicUpdated(mic: MediaDeviceInfo?) {
        Task { @MainActor in
            self.selectedMic = mic?.id
        }
    }
}
