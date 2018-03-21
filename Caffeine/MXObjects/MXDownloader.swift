//
//  MXDownloader.swift
//  Caffeine
//
//  Created by Zaid Rahawi on 2/22/18.
//  Copyright © 2018 Zaid Rahawi. All rights reserved.
//

import UIKit

class MXDownloader: NSObject, URLSessionDownloadDelegate {
    enum Error: Swift.Error {
        case invalidUrl
        case unsupportedUrl
        case alreadyInProgress
    }
    
    static let shared = MXDownloader(sessionIdentifier: "com.zrahawi.mx-downloader")
    
    private(set) var downloads = [MXDownload]()
    
    weak var delegate: DownloaderDelegate?
    
    let sessionIdentifier: String
    
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.shouldUseExtendedBackgroundIdleMode = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    init(sessionIdentifier: String) {
        self.sessionIdentifier = sessionIdentifier
    }
    
    typealias CompletionHandler = (MXDownload?, Error?) -> Void
    
    func downloadFile(at url: URL, as fileName: String? = nil, handler: CompletionHandler? = nil) {
        guard downloads[url] == nil else {
            handler?(nil, Error.alreadyInProgress)
            return
        }
        
        guard UIApplication.shared.canOpenURL(url) else {
            handler?(nil, Error.unsupportedUrl)
            return
        }
        
        let download = MXDownload(url: url, session: session)
        if let fileName = fileName {
            download.fileName = fileName
        }
        downloads.append(download)
        download.resume()
        handler?(download, nil)
        delegate?.downloader(self, didStartDownloading: download)
    }
    
    func loadUnfinishedDownloads() {
        backgroundDownloads { (downloads) in
            self.downloads.append(contentsOf: downloads)
        }
    }
    
    private func backgroundDownloads(handler: @escaping ([MXDownload]) -> Void) {
        session.getTasksWithCompletionHandler { [unowned self] (dataTasks, uploadTasks, downloadTasks) in
            let downloads: [MXDownload] = downloadTasks.compactMap { downloadTask in
                if let url = downloadTask.response?.url, let error = downloadTask.error as NSError?, let resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    return MXDownload(url: url, session: self.session, resumeData: resumeData)
                }
                return nil
            }
            handler(downloads)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        guard let url = task.response?.url else { return }
        // Handle errors thrown by downloads that are in-progress
        if let download = downloads[url] {
            // Remove download from array if it is cancelled
            if download.state == .canceling {
                try? downloads.remove(download)
            // Remove download from array if it is unexpetedly stopped, and return an error.
            } else if download.state == .running {
                if let error = error as NSError? {
                    try? downloads.remove(download)
                    delegate?.downloader(self, failedToDownload: download, withError: error)
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let url = downloadTask.response?.url, let download = downloads[url] {            
            if let suggestedFilename = downloadTask.response?.suggestedFilename, !download.fileNameWasSet, download.fileName != suggestedFilename {
                download.fileName = suggestedFilename
            }
            
            // Should not be needed, but just in case
            if download.state == .waiting || download.state == .suspended {
                download.state = .running
            }
            
            if download.progress.isInitial {
                download.progress.totalBytes = totalBytesExpectedToWrite
            }
            download.progress.bytesReceived = totalBytesWritten
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let url = downloadTask.response?.url, let download = downloads[url] {
            download.state = .completed
            
            try? downloads.remove(download)
            
            MXFile.saveItem(at: location, fileName: download.fileName) { (file, error) in
                if let file = file {
                    self.delegate?.downloader(self, didFinishDownloading: download, as: file)
                } else if let error = error {
                    self.delegate?.downloader(self, failedToDownload: download, withError: error)
                }
            }
        }
    }
}

extension MXDownloader.Error {
    var localizedDescription: String {
        switch self {
        case .invalidUrl: return "Invalid URL address. Please make sure you're typing the address correctly."
        case .unsupportedUrl: return "Unsupported URL address. Your device cannot open this type of URLs."
        case .alreadyInProgress: return "Download already in progress."
        }
    }
}

extension MXDownload: Equatable {
    static func ==(lhs: MXDownload, rhs: MXDownload) -> Bool {
        return lhs.url == rhs.url
    }
}

extension Array where Element: Equatable {
    enum Error: Swift.Error {
        case indexOutOfRange
    }
    
    mutating func remove(_ item: Element) throws {
        guard let index = index(of: item) else { throw Error.indexOutOfRange }
        remove(at: index)
    }
}

extension Array where Element == MXDownload {
    subscript (_ url: URL) -> MXDownload? {
        return first { $0.url == url }
    }
}