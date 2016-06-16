//
//  AppResign.swift
//  AppResign
//
//  Created by Eular on 6/11/16.
//  Copyright © 2016 Eular. All rights reserved.
//

import Foundation

class AppResign {
    
    //MARK: Variables
    var provisioningProfiles: [ProvisioningProfile] = []
    var codesigningCerts: [String] = []
    var profileFilename: String?
    var curSigningCert: String = ""
    
    var ReEnableNewApplicationID = false
    var PreviousNewApplicationID = ""
    var inputFile: String = ""
    var outputFile: String = ""
    var newApplicationID: String = ""
    var newDisplayName: String = ""
    var startSize: CGFloat?
    var NibLoaded = false
    
    //MARK: Constants
    let defaults = NSUserDefaults()
    let fileManager = NSFileManager.defaultManager()
    let bundleID = "com.eular.AppResign"
    let arPath = "/usr/bin/ar"
    let mktempPath = "/usr/bin/mktemp"
    let tarPath = "/usr/bin/tar"
    let unzipPath = "/usr/bin/unzip"
    let zipPath = "/usr/bin/zip"
    let defaultsPath = "/usr/bin/defaults"
    let codesignPath = "/usr/bin/codesign"
    let securityPath = "/usr/bin/security"
    let chmodPath = "/bin/chmod"
    let cpPath = "/bin/cp"
    
    init() {
        populateProvisioningProfiles()
        populateCodesigningCerts()
    }
    
    func populateProvisioningProfiles() {
        self.provisioningProfiles = ProvisioningProfile.getProfiles().sort {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        
        let formatter = NSDateFormatter()
        formatter.dateStyle = .ShortStyle
        formatter.timeStyle = .MediumStyle
        var newProfiles: [ProvisioningProfile] = []
        
        for profile in provisioningProfiles {
            if profile.expires.timeIntervalSince1970 > NSDate().timeIntervalSince1970 {
                newProfiles.append(profile)
                Log("Added profile \(profile.appID), expires (\(formatter.stringFromDate(profile.expires)))")
            } else {
                Log("Skipped profile \(profile.appID), expired (\(formatter.stringFromDate(profile.expires)))")
            }
        }
        self.provisioningProfiles = newProfiles
    }
    
    func populateCodesigningCerts() {
        var output: [String] = []
        
        let securityResult = NSTask().execute(securityPath, workingDirectory: nil, arguments: ["find-identity","-v","-p","codesigning"])
        if securityResult.output.characters.count >= 1 {
            let rawResult = securityResult.output.componentsSeparatedByString("\"")
            
            for index in 0.stride(through: rawResult.count - 2, by: 2) {
                if !(rawResult.count - 1 < index + 1) {
                    output.append(rawResult[index+1])
                }
            }
        }
        self.codesigningCerts = output
        
        Log("Found \(output.count) Codesigning Certificates")
    }
    
    func startSigning(input: String, output: String) {
        self.inputFile = input
        self.outputFile = output
        signingThread()
    }
    
    func signingThread() {
        
        // MARK: Set up variables
        var warnings = 0
        var provisioningFile = self.profileFilename
        let signingCertificate = self.curSigningCert
        var eggCount: Int = 0
        
        // MARK: Create working temp folder
        var tempFolder: String! = nil
        if let tmpFolder = makeTempFolder() {
            tempFolder = tmpFolder
        } else {
            Log("Error creating temp folder")
            return
        }
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let eggDirectory = tempFolder.stringByAppendingPathComponent("eggs")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        Log("Temp folder: \(tempFolder)")
        Log("Working directory: \(workingDirectory)")
        Log("Payload directory: \(payloadDirectory)")
        
        // MARK: Create Egg Temp Directory
        do {
            try fileManager.createDirectoryAtPath(eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            Log("Error creating egg temp directory")
            Log(error.localizedDescription)
            cleanup(tempFolder)
            return
        }
        
        // MARK: Process input file
        switch(inputFile.pathExtension.lowercaseString) {
        case "deb":
            // MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectoryAtPath(debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Extracting deb file")
                let debTask = NSTask().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Log(debTask.output)
                if debTask.status != 0 {
                    Log("Error processing deb file")
                    cleanup(tempFolder); return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExistsAtPath(dataPath){
                        
                        Log("Unpacking data.\(tarFormat)")
                        let tarTask = NSTask().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
                        Log(tarTask.output)
                        if tarTask.status == 0 {
                            tarUnpacked = true
                        }
                        break
                    }
                }
                if !tarUnpacked {
                    Log("Error unpacking data.tar")
                    cleanup(tempFolder); return
                }
                try fileManager.moveItemAtPath(debPath.stringByAppendingPathComponent("Applications"), toPath: payloadDirectory)
                
            } catch {
                Log("Error processing deb file")
                cleanup(tempFolder); return
            }
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Extracting ipa file")
                
                let unzipTask = self.unzip(inputFile, outputPath: workingDirectory)
                if unzipTask.status != 0 {
                    Log("Error extracting ipa file")
                    cleanup(tempFolder); return
                }
            } catch {
                Log("Error extracting ipa file")
                cleanup(tempFolder); return
            }
            
        case "app":
            // MARK: --Copy app bundle
            do {
                try fileManager.createDirectoryAtPath(payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Copying app to payload directory")
                try fileManager.copyItemAtPath(inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                Log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        case "xcarchive":
            // MARK: --Copy app bundle from xcarchive
            do {
                try fileManager.createDirectoryAtPath(workingDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Copying app to payload directory")
                try fileManager.copyItemAtPath(inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                Log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        default:
            Log("Unsupported input file")
            cleanup(tempFolder)
            return
        }
        
        if !fileManager.fileExistsAtPath(payloadDirectory){
            Log("Payload directory doesn't exist")
            cleanup(tempFolder); return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectoryAtPath(payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExistsAtPath(payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory { continue }
                
                // MARK: Bundle variables setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExistsAtPath(appBundleProvisioningFilePath))
                
                // MARK: Delete CFBundleResourceSpecification from Info.plist
                Log(NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                // MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExistsAtPath(appBundleProvisioningFilePath) {
                        Log("Deleting embedded.mobileprovision")
                        do {
                            try fileManager.removeItemAtPath(appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            Log("Error deleting embedded.mobileprovision")
                            Log(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    print("Copying provisioning profile to app bundle")
                    do {
                        try fileManager.copyItemAtPath(provisioningFile!, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        Log("Error copying provisioning profile")
                        Log(error.localizedDescription)
                        cleanup(tempFolder); return
                    }
                }
                
                // MARK: Generate entitlements.plist
                if provisioningFile != nil || useAppBundleProfile {
                    print("Parsing entitlements")
                    
                    if let profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile!){
                        if let entitlements = profile.getEntitlementsPlist(tempFolder) {
                            Log("–––––––––––––––––––––––\n\(entitlements)")
                            Log("–––––––––––––––––––––––")
                            do {
                                try entitlements.writeToFile(entitlementsPlist, atomically: false, encoding: NSUTF8StringEncoding)
                                Log("Saved entitlements to \(entitlementsPlist)")
                            } catch let error as NSError {
                                Log("Error writing entitlements.plist, \(error.localizedDescription)")
                            }
                        } else {
                            Log("Unable to read entitlements from provisioning profile")
                            warnings += 1
                        }
                        if profile.appID != "*" && (newApplicationID != "" && newApplicationID != profile.appID) {
                            Log("Unable to change App ID to \(newApplicationID), provisioning profile won't allow it")
                            cleanup(tempFolder); return
                        }
                    } else {
                        Log("Unable to parse provisioning profile, it may be corrupt")
                        warnings += 1
                    }
                    
                }
                
                // MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable"){
                    NSTask().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                // MARK: Change Application ID
                if newApplicationID != "" {
                    
                    if let oldAppID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier") {
                        
                        func changeAppexID(appexFile: String){
                            
                            func shortName(file: String, payloadDirectory: String) -> String {
                                return file.substringFromIndex(payloadDirectory.endIndex)
                            }
                            
                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newApplicationID)\(appexBundleID.substringFromIndex(oldAppID.endIndex))"
                                print("Changing \(shortName(appexFile, payloadDirectory: payloadDirectory)) id to \(newAppexID)")
                                
                                setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
                            }
                            recursiveDirectorySearch(appexFile, extensions: ["app"], found: changeAppexID)
                        }
                        
                        recursiveDirectorySearch(appBundlePath, extensions: ["appex"], found: changeAppexID)
                    }
                    
                    print("Changing App ID to \(newApplicationID)")
                    let IDChangeTask = setPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier", value: newApplicationID)
                    if IDChangeTask.status != 0 {
                        Log("Error changing App ID")
                        Log(IDChangeTask.output)
                        cleanup(tempFolder); return
                    }
                    
                    
                }
                
                // MARK: Change Display Name
                if newDisplayName != "" {
                    print("Changing Display Name to \(newDisplayName))")
                    let displayNameChangeTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write",appBundleInfoPlist,"CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        Log("Error changing display name")
                        Log(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                }
                
                
                func generateFileSignFunc(payloadDirectory: String, entitlementsPath: String, signingCertificate: String) -> ( (file: String) -> Void ) {
                    
                    let useEntitlements: Bool = ({
                        if fileManager.fileExistsAtPath(entitlementsPath) {
                            return true
                        }
                        return false
                    })()
                    
                    func shortName(file: String, payloadDirectory: String) -> String {
                        return file.substringFromIndex(payloadDirectory.endIndex)
                    }
                    
                    func beforeFunc(file: String, certificate: String, entitlements: String?) {
                        print("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements":"")")
                    }
                    
                    func afterFunc(file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput) {
                        if codesignOutput.status != 0 {
                            Log("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            Log(codesignOutput.output)
                            warnings += 1
                        }
                    }
                    
                    func output(file: String) {
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    
                    return output
                }
                
                // MARK: Codesigning - General
                let signableExtensions = ["dylib","so","0","vis","pvr","framework","appex","app"]
                
                // MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate)
                func signEgg(eggFile: String){
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substringFromIndex(payloadDirectory.endIndex)
                    Log("Extracting \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Log("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    Log("Compressing \(shortName)")
                    self.zip(currentEggPath, outputFile: eggFile)
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                // MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate)
                
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(file: appBundlePath)
                
                // MARK: Codesigning - Verification
                let verificationTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
                if verificationTask.status != 0 {
                    Log("Error verifying code signature")
                    Log(verificationTask.output)
                    cleanup(tempFolder); return
                }
            }
        } catch let error as NSError {
            Log("Error listing files in payload directory")
            Log(error.localizedDescription)
            cleanup(tempFolder); return
        }
        
        // MARK: Packaging
        // Check if output already exists and delete if so
        if fileManager.fileExistsAtPath(outputFile) {
            do {
                try fileManager.removeItemAtPath(outputFile)
            } catch let error as NSError {
                Log("Error deleting output file")
                Log(error.localizedDescription)
                cleanup(tempFolder); return
            }
        }
        print("Packaging IPA")
        let zipTask = self.zip(workingDirectory, outputFile: outputFile.lastPathComponent)
        if zipTask.status != 0 {
            Log("Error packaging IPA")
        }
        
        let cpTask = NSTask().execute(cpPath, workingDirectory: nil, arguments: [workingDirectory.stringByAppendingPathComponent(outputFile.lastPathComponent), outputFile])
        if cpTask.status != 0 {
            Log("Error copy IPA")
        }
        
        // MARK: Cleanup
        cleanup(tempFolder)
        print("Done, output at \(outputFile)")
    }
    
    func makeTempFolder() -> String? {
        let tempTask = NSTask().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.trim()
    }
    
    func cleanup(tempFolder: String) {
        do {
            Log("Deleting: \(tempFolder)")
            try fileManager.removeItemAtPath(tempFolder)
        } catch let error as NSError {
            Log("Unable to delete temp folder")
            Log(error.localizedDescription)
        }
    }
    
    func unzip(inputFile: String, outputPath: String) -> AppSignerTaskOutput {
        return NSTask().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    
    func zip(inputPath: String, outputFile: String) -> AppSignerTaskOutput {
        return NSTask().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    func getPlistKey(plist: String, keyName: String) -> String? {
        let currTask = NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["read", plist, keyName])
        if currTask.status == 0 {
            return String(currTask.output.characters.dropLast())
        } else {
            return nil
        }
    }
    
    func setPlistKey(plist: String, keyName: String, value: String) -> AppSignerTaskOutput {
        return NSTask().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }
    
    func recursiveDirectorySearch(path: String, extensions: [String], found: ((file: String) -> Void)){
        
        if let files = try? fileManager.contentsOfDirectoryAtPath(path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExistsAtPath(currentFile, isDirectory: &isDirectory)
                if isDirectory {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    found(file: currentFile)
                }
                
            }
        }
    }
    
    // MARK: Codesigning
    func codeSign(file: String, certificate: String, entitlements: String?,before:((file: String, certificate: String, entitlements: String?)->Void)?, after: ((file: String, certificate: String, entitlements: String?, codesignTask: AppSignerTaskOutput)->Void)?)->AppSignerTaskOutput{
        
        let useEntitlements: Bool = ({
            if entitlements == nil {
                return false
            } else {
                if fileManager.fileExistsAtPath(entitlements!) {
                    return true
                } else {
                    return false
                }
            }
        })()
        
        if let beforeFunc = before {
            beforeFunc(file: file, certificate: certificate, entitlements: entitlements)
        }
        
        var arguments = ["-vvv","-fs",certificate,"--no-strict"]
        if useEntitlements {
            arguments.append("--entitlements=\(entitlements!)")
        }
        arguments.append(file)
        
        let codesignTask = NSTask().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if let afterFunc = after {
            afterFunc(file: file, certificate: certificate, entitlements: entitlements, codesignTask: codesignTask)
        }
        return codesignTask
    }
}