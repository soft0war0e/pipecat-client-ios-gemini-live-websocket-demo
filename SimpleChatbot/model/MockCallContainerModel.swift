import SwiftUI
import PipecatClientIOS

class MockCallContainerModel: CallContainerModel {

    override init() {
    }

    override func connect(geminiAPIKey: String) {
        print("connect")
    }

    override func disconnect() {
        print("disconnect")
    }

    override func showError(message: String) {
        self.toastMessage = message
        self.showToast = true
        // Hide the toast after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.showToast = false
            self.toastMessage = nil
        }
    }
}
