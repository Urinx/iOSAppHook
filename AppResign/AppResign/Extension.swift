//
//  Extension.swift
//  AppResign
//
//  Created by Eular on 6/7/16.
//  Copyright © 2016 Eular. All rights reserved.
//

import Foundation

var LogMode = false
func Log<T>(message: T, file: String = #file, function: String = #function, line: Int = #line) {
    if LogMode {
        let formatter = NSDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        print("\(formatter.stringFromDate(NSDate())) \(file.lastPathComponent)[\(line)], \(function): \(message)")
    }
}

struct AppSignerTaskOutput {
    var output: String
    var status: Int32
    init(status: Int32, output: String){
        self.status = status
        self.output = output
    }
}

extension NSTask {
    func launchSyncronous() -> AppSignerTaskOutput {
        self.standardInput = NSFileHandle.fileHandleWithNullDevice()
        let pipe = NSPipe()
        self.standardOutput = pipe
        self.standardError = pipe
        let pipeFile = pipe.fileHandleForReading
        self.launch()
        
        let data = NSMutableData()
        while self.running {
            data.appendData(pipeFile.availableData)
        }
        
        let output = NSString(data: data, encoding: NSUTF8StringEncoding) as! String
        
        return AppSignerTaskOutput(status: self.terminationStatus, output: output)
        
    }
    
    func execute(launchPath: String, workingDirectory: String?, arguments: [String]?)->AppSignerTaskOutput{
        self.launchPath = launchPath
        if arguments != nil {
            self.arguments = arguments
        }
        if workingDirectory != nil {
            self.currentDirectoryPath = workingDirectory!
        }
        return self.launchSyncronous()
    }
    
}

extension String {
    
    var lastPathComponent: String {
        
        get {
            return (self as NSString).lastPathComponent
        }
    }
    var pathExtension: String {
        
        get {
            
            return (self as NSString).pathExtension
        }
    }
    var stringByDeletingLastPathComponent: String {
        
        get {
            
            return (self as NSString).stringByDeletingLastPathComponent
        }
    }
    var stringByDeletingPathExtension: String {
        
        get {
            
            return (self as NSString).stringByDeletingPathExtension
        }
    }
    var pathComponents: [String] {
        
        get {
            
            return (self as NSString).pathComponents
        }
    }
    
    func stringByAppendingPathComponent(path: String) -> String {
        
        let nsSt = self as NSString
        
        return nsSt.stringByAppendingPathComponent(path)
    }
    
    func stringByAppendingPathExtension(ext: String) -> String? {
        
        let nsSt = self as NSString
        
        return nsSt.stringByAppendingPathExtension(ext)
    }
    
    func trim() -> String {
        return self.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
    }
}