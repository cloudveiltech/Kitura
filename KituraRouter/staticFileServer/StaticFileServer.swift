/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/


import KituraNet

import Foundation

// MARK: StaticFileServer

public class StaticFileServer : RouterMiddleware {
    
    //
    // If a file is not found, the given extensions will be added to the file name and searched for. The first that exists will be served. Example: ['html', 'htm'].
    //
    private var possibleExtensions : [String]?
    
    //
    // Serve "index.html" files in response to a request on a directory.  Defaults to true.
    //
    private var serveIndexForDir = true
    
    //
    // Uses the file system's last modified value.  Defaults to true.
    //
    private var addLastModifiedHeader = true
    
    //
    // Value of max-age in Cache-Control header.  Defaults to 0.
    //
    private var maxAgeCacheControlHeader = 0
    
    //
    // Redirect to trailing "/" when the pathname is a dir. Defaults to true.
    //
    private var redirect = true
    
    //
    // A setter for custom response headers.
    //
    private var customResponseHeadersSetter : ResponseHeadersSetter?
    
    private var path : String
    
    public convenience init (options: [Options]) {
        self.init(path: "/public", options: options)
    }
    
    public convenience init () {
        self.init(path: "/public", options: nil)
    }
    
    ///
    /// Initializes a StaticFileServer instance
    ///
    public init (path: String, options: [Options]?) {
        if path.hasSuffix("/") {
            self.path = String(path.characters.dropLast())
        }
        else {
            self.path = path
        }
        if !self.path.hasPrefix("/") {
            self.path = "/" + self.path
        }
        
        if let options = options {
            for option in options {
                switch option {
                case .PossibleExtensions(let value):
                    possibleExtensions = value
                case .ServeIndexForDir(let value):
                    serveIndexForDir = value
                case .AddLastModifiedHeader(let value):
                    addLastModifiedHeader = value
                case .MaxAgeCacheControlHeader(let value):
                    maxAgeCacheControlHeader = value
                case .Redirect(let value):
                    redirect = value
                case .CustomResponseHeadersSetter(let value):
                    customResponseHeadersSetter = value
                }
            }
        }
    }
    
    ///
    /// Handle the request
    ///
    /// - Parameter request: the router request
    /// - Parameter response: the router response
    /// - Parameter next: the closure for the next execution block
    ///
    public func handle (request: RouterRequest, response: RouterResponse, next: () -> Void) {
        if (request.serverRequest.method != "GET" && request.serverRequest.method != "HEAD") {
            next()
            return
        }
        
        var filePath = path
        let originalUrl = request.originalUrl
        if let requestRoute = request.route {
            var route = requestRoute
            if route.hasSuffix("*") {
                route = String(route.characters.dropLast())
            }
            if !route.hasSuffix("/") {
                route += "/"
            }

            if originalUrl.hasPrefix(route) {
                let url = String(originalUrl.characters.dropFirst(route.characters.count))
                filePath += "/" + url
            }
        }
        
        filePath = "." + filePath
        
        if filePath.hasSuffix("/") {
            if serveIndexForDir {
                filePath += "index.html"
            }
            else {
                next()
                return
            }
        }
        
        let fileManager = NSFileManager()
        var isDirectory = ObjCBool(false)
        if fileManager.fileExistsAtPath(filePath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                if redirect {
                    do {
                        try response.redirect(originalUrl + "/")
                    }
                    catch {
                        response.error = NSError(domain: "Kitura-router", code: 1, userInfo: [NSLocalizedDescriptionKey:"Failed to redirect a request for directory"])
                    }
                }
            }
            else {
                serveFile(filePath, fileManager: fileManager, response: response)
            }
        }
        else {
            if let _ = possibleExtensions {
                for ext in possibleExtensions! {
                    let newFilePath = filePath + "." + ext
                    if fileManager.fileExistsAtPath(newFilePath, isDirectory: &isDirectory) {
                        if !isDirectory.boolValue {
                            serveFile(newFilePath, fileManager: fileManager, response: response)
                            break
                        }
                    }
                }
            }
        }
        
        next()
        
    }    
    
    private func serveFile(filePath: String, fileManager: NSFileManager, response: RouterResponse) {
        do {
            var attributes : [String:AnyObject]
            try attributes = fileManager.attributesOfItemAtPath(filePath)
            response.setHeader("Cache-Control", value: "max-age=\(maxAgeCacheControlHeader)")
            if let date = attributes[NSFileModificationDate] as? NSDate where addLastModifiedHeader {
                response.setHeader("Last-Modified", value: SpiUtils.httpDate(date))
            }
            if let _ = customResponseHeadersSetter {
                customResponseHeadersSetter!.setCustomResponseHeaders(response, filePath: filePath, fileAttributes: attributes)
            }

            try response.sendFile(filePath)
        }
        catch {
            // Nothing
        }
        response.status(HttpStatusCode.OK)
    }
    
    public enum Options {
        case PossibleExtensions([String])
        case ServeIndexForDir(Bool)
        case AddLastModifiedHeader(Bool)
        case MaxAgeCacheControlHeader(Int)
        case Redirect(Bool)
        case CustomResponseHeadersSetter(ResponseHeadersSetter)
    }

}


public protocol ResponseHeadersSetter {
    
    func setCustomResponseHeaders (response: RouterResponse, filePath: String, fileAttributes: [String : AnyObject])
    
}



