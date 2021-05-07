//
//  SourceManager.swift
//  PoseDetector
//
//  Created by WuLei on 2021/4/1.
//

import AVFoundation

class SourceManager {
    
    static let shared = SourceManager()
    
    private init() {
    }
    
    func delete(sourceUrl: URL) {
        if FileManager.default.fileExists(atPath: sourceUrl.path) {
            try! FileManager.default.removeItem(atPath: sourceUrl.path)
        }
    }
    
    @discardableResult
    func downloadVideo(videoId: String, completionHandler: @escaping (_ videoId: String, _ videoUrl: URL?, _ errorMessage: String?) -> Void) -> URLSessionDownloadTask {
        let serverUrl = UserDefaults.standard.string(forKey: SettingKey.serverUrl.rawValue)!
        let token = UserDefaults.standard.string(forKey: SettingKey.token.rawValue)!
        let requestUrl = "\(serverUrl)/media/video/\(videoId)"
        guard let url = URL(string: requestUrl) else {
            fatalError("invalid url: \(requestUrl)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token=\(token)", forHTTPHeaderField: "Cookie")
        let urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        let task = urlSession.downloadTask(with: request) { downloadedFileUrl, urlResponse, error in
            print("download thread: \(Thread.current)")

            var videoUrl: URL? = nil
            var errorMessage: String? = nil
            if error != nil {
                errorMessage = "\(error?.localizedDescription ?? "error"), requestUrl: \(requestUrl)"
            } else {
                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    fatalError("not a httpUrlResponse")
                }
                if httpResponse.statusCode != 200 {
                    errorMessage = "statusCode: \(httpResponse.statusCode), requestUrl: \(requestUrl)"
                } else {
                    if let downloadedUrl = downloadedFileUrl {
                        do {
                            videoUrl = try self.moveVideoToDocument(sourceUrl: downloadedUrl, targetName: "\(videoId).mp4")
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } else {
                        errorMessage = "downloaded file not found"
                    }
                }
            }
            completionHandler(videoId, videoUrl, errorMessage)
        }
        task.resume()
        return task
    }
    
    func moveVideoToDocument(sourceUrl: URL, targetName: String) throws -> URL {
        return try copyVideoToDocument(sourceUrl: sourceUrl, targetName: targetName, deleteSource: true)
    }
    
    func copyVideoToDocument(sourceUrl: URL, targetName: String, deleteSource: Bool = false) throws -> URL {
        assert(FileManager.default.fileExists(atPath: sourceUrl.path), "invalid url: \(sourceUrl)")
        if var documentUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            documentUrl.appendPathComponent(targetName)
            delete(sourceUrl: documentUrl)
            if deleteSource {
                try! FileManager.default.moveItem(atPath: sourceUrl.path, toPath: documentUrl.path)
            } else {
                try! FileManager.default.copyItem(atPath: sourceUrl.path, toPath: documentUrl.path)
            }
            return documentUrl
        } else {
            throw "document directory not exists"
        }
    }
}

extension String: Error {
}
