//
//  SettingsViewController.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/14.
//

import UIKit

class SettingsViewController: UIViewController {
    
    private let apiRequestManager = ApiRequestManager.shared
    
    @IBOutlet weak var serverUrlField: UITextField!
    @IBOutlet weak var tokenField: UITextField!
    
    override func viewDidLoad() {
        loadSetting(textField: serverUrlField, settingKey: SettingKey.serverUrl, defaultValue:  "http://api.squarevalleytech.com/server1/erp")
        loadSetting(textField: tokenField, settingKey: SettingKey.token)
    }
    
    @IBAction func refreshToken(_ sender: Any) {
        var data = [String: Any]()
        data["accountName"] = "swing@a.a"
        data["password"] = "111111"
        
        UserDefaults.standard.removeObject(forKey: SettingKey.token.rawValue)
        let request = ApiRequest(path: "/employee/employeeLogin", data: data)
        apiRequestManager.startApiRequest(apiRequest: request) { (apiRequest, apiResponse) in
            DispatchQueue.main.sync {
                if apiResponse.isSuccess() {
                    if let token = apiResponse.data["token"] as? String? {
                        self.tokenField.text = token
                        self.saveSetting(fieldValue: token, settingKey: SettingKey.token)
                    }
                } else {
                    DialogUtil.showAlert(viewController: self, title: nil, message: "\(apiResponse.getReasonCode() ?? "")\n \(apiResponse.getReason()  ?? "")")
                }
            }
        }
    }
    
    @IBAction func saveSettings(_ sender: Any) {
        saveSetting(fieldValue: serverUrlField.text, settingKey: SettingKey.serverUrl)
        saveSetting(fieldValue: tokenField.text, settingKey: SettingKey.token)
        NotificationCenter.default.post(name: NotificationName.settingUpdated.nsName(), object: nil)
        dismiss(animated: true)
    }
    
    private func loadSetting(textField: UITextField, settingKey: SettingKey, defaultValue: String? = nil) {
        var value = UserDefaults.standard.string(forKey: settingKey.rawValue)
        if value == nil || value!.isEmpty {
            value = defaultValue
            UserDefaults.standard.setValue(value, forKey: settingKey.rawValue)
        }
        textField.text = value
    }
    
    private func saveSetting(fieldValue: String?, settingKey: SettingKey) {
        let value: String?
        if fieldValue?.isEmpty == false {
            value = fieldValue
        } else {
            value = nil
        }
        UserDefaults.standard.setValue(value, forKey: settingKey.rawValue)
    }
}
