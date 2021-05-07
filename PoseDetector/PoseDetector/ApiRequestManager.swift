//
//  ApiRequestManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/15.
//

import UIKit

struct ApiRequest {
    let path: String
    let data: [String: Any]
}

enum ReasonCode: String {
    case ERROR
    case INTERNAL
    case API_NOT_FOUND
    case NOT_AUTHORIZED
    case SESSION_EXPIRED
    case LOGINED_FROM_OTHER_CLIENT
    case INVALID_PARAMETER
    case REQUEST_FORMAT_ERROR
    case CLIENT_VERSION_TOO_OLD
}
fileprivate let FIELD_ERROR = "error"
fileprivate let FIELD_REASON_CODE = "reasonCode"
fileprivate let FIELD_REASON = "reason"

struct ApiResponse {
    let statusCode: Int
    let data: [String: Any]
    
    func isSuccess() -> Bool {
        return statusCode == 200
    }
    
    func getReasonCode() -> String? {
        return data[FIELD_REASON_CODE] as! String?
    }
    
    func getReason() -> String? {
        return data[FIELD_REASON] as! String?
    }
    /// only has value when ReasonCode is ERROR
    func getError() -> Error? {
        return data[FIELD_ERROR] as! Error?
    }
    
}

class ApiRequestManager {
    
    static let shared = ApiRequestManager()
    private let requestQueue = OperationQueue()
    
    private init() {
        requestQueue.maxConcurrentOperationCount = 1
    }
    
    @discardableResult
    func startTestingRequest(apiRequest: ApiRequest, completionHandler: @escaping (_ apiRequest: ApiRequest, _ apiResponse: ApiResponse) -> Void) -> URLSessionDataTask {
        let serverUrl = "\(UserDefaults.standard.string(forKey: SettingKey.serverUrl.rawValue)!)/testing/"
        return startRequest(serverUrl: serverUrl, apiRequest: apiRequest, completionHandler: completionHandler)
    }
    
    @discardableResult
    func startApiRequest(apiRequest: ApiRequest, completionHandler: @escaping (_ apiRequest: ApiRequest, _ apiResponse: ApiResponse) -> Void) -> URLSessionDataTask {
        let serverUrl = "\(UserDefaults.standard.string(forKey: SettingKey.serverUrl.rawValue)!)/api/"
        return startRequest(serverUrl: serverUrl, apiRequest: apiRequest, completionHandler: completionHandler)
    }
    
    @discardableResult
    private func startRequest(serverUrl: String, apiRequest: ApiRequest, completionHandler: @escaping (_ apiRequest: ApiRequest, _ apiResponse: ApiResponse) -> Void) -> URLSessionDataTask {
        let token = UserDefaults.standard.string(forKey: SettingKey.token.rawValue)
        let requestUrl = "\(serverUrl)\(apiRequest.path)"
        guard let url = URL(string: requestUrl) else {
            fatalError("invalid requestUrl: \(requestUrl)")
        }
        let requestData = try! JSONSerialization.data(withJSONObject: apiRequest.data)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if token?.isEmpty == false {
            request.setValue(token, forHTTPHeaderField: "token")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = requestData

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        let urlSession = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        let task = urlSession.dataTask(with: request) { data, urlResponse, error in
            print("request thread: \(Thread.current)")
            var statusCode = -1
            var responseData: [String: Any]
            if error != nil {
                responseData = [ReasonCode.ERROR.rawValue: "\(error?.localizedDescription ?? "error"), requestUrl: \(requestUrl)"]
                responseData["error"] = error
            } else if let httpResponse = urlResponse as? HTTPURLResponse {
                statusCode = httpResponse.statusCode
                if data == nil || data!.isEmpty {
                    responseData = [String: Any]()
                } else {
                    do {
                        responseData = try JSONSerialization.jsonObject(with: data!) as! [String: Any]
                    } catch {
                        responseData = ["error": "\(statusCode)"]
                    }
                }
            } else {
                fatalError("not a httpUrlResponse")
            }
            
            completionHandler(apiRequest, ApiResponse(statusCode: statusCode, data: responseData))
        }
        task.resume()
        return task
    }
}
