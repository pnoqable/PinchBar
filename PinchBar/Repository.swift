import Cocoa

class Repository {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    
    func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/pnoqable/PinchBar")!)
    }
    
    func checkForUpdates(verbose: Bool) {
        let url = URL(string: "https://api.github.com/repos/pnoqable/PinchBar/releases/latest")!
        URLSession(configuration: .ephemeral).dataTask(with: url) { data, _, error in
            self.checkUpdate(data: data, error: error, verbose: verbose)
        }.resume()
    }
    
    private func checkUpdate(data: Data?, error: Error?, verbose: Bool) {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
              let newVersion = json["tag_name"] as? String, let urlString = json["html_url"] as? String,
              let url = URL(string: urlString) else {
            return verbose ? asyncAlert("Communication error", error?.localizedDescription) : ()
        }
        
        guard version.compare(newVersion, options: .numeric) == .orderedAscending else {
            return verbose ? asyncAlert("PinchBar is up-to-date!", "Current Version: \(version)") : ()
        }
        
        let updateKnown = newVersion == UserDefaults.standard.string(forKey: "knownVersion")
        
        guard verbose || !updateKnown else { return }
        
        asyncAlert("PinchBar \(newVersion) is now available!", "Current Version: \(version)") { alert in
            alert.addButton(withTitle: "View on GitHub")
            alert.addButton(withTitle: "Ignore for now")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.state = updateKnown ? .on : .off
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
            
            if alert.suppressionButton?.state == .on {
                UserDefaults.standard.set(newVersion, forKey: "knownVersion")
            } else {
                UserDefaults.standard.removeObject(forKey: "knownVersion")
            }
        }
    }
    
    private static func addOkAndRun(alert: NSAlert) {
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func asyncAlert(_ messageText: String, _ informativeText: String?,
                            _ addButtonsAndRun: @escaping ((NSAlert)->()) = addOkAndRun) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            let alert = NSAlert()
            alert.icon.isTemplate = true
            alert.messageText = messageText
            alert.informativeText = informativeText ?? ""
            
            addButtonsAndRun(alert)
        }
    }
}
