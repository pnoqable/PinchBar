import Cocoa

class Repository {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    
    var openUpdateLink: (()->())?
    
    func checkForUpdates(verbose: Bool) {
        let url = "https://api.github.com/repos/pnoqable/PinchBar/releases/latest"
        URLSession(configuration: .ephemeral).dataTask(with: URL(string: url)!) { data, _, error in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data),
               let dict = json as? NSDictionary, let newVersion = dict["tag_name"] as? String {
                DispatchQueue.main.async() {
                    let updateAvailable = newVersion != self.version
                    let knownVersion = UserDefaults.standard.string(forKey: "knownVersion")
                    let knownUpdate = newVersion == knownVersion
                    if updateAvailable && (verbose || !knownUpdate) {
                        self.updateAvailable(newVersion: newVersion, known: knownUpdate)
                    } else if verbose {
                        self.upToDate()
                    }
                }
            } else if verbose {
                DispatchQueue.main.async() {
                    let alert = NSAlert()
                    alert.icon.isTemplate = true
                    alert.alertStyle = .warning
                    alert.messageText = error?.localizedDescription ?? "Communication error."
                    alert.addButton(withTitle: "OK")
                    
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    
                    alert.runModal()
                }
            }
        }.resume()
    }
    
    func updateAvailable(newVersion: String, known: Bool) {
        let alert = NSAlert()
        alert.icon.isTemplate = true
        alert.messageText = "PinchBar \(newVersion) is available!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "OK")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.state = known ? .on : .off
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            openUpdateLink?()
        }
        
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(newVersion, forKey: "knownVersion")
        } else {
            UserDefaults.standard.removeObject(forKey: "knownVersion")
        }
    }
    
    func upToDate() {
        let alert = NSAlert()
        alert.icon.isTemplate = true
        alert.messageText = "PinchBar is up-to-date!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        alert.runModal()
    }
}
