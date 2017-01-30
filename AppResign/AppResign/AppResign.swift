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
    var deleteURLSchemes = false
    
    var appBundlePath: String = ""
    var appBundleInfoPlist: String = ""
    var appBundleProvisioningFilePath: String = ""
    var appBundleExecutable: String = ""
    
    //MARK: Constants
    let defaults = UserDefaults()
    let fileManager = FileManager.default
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
    let fileCmdPath = "/usr/bin/file"
    let plistBuddyPath = "/usr/libexec/PlistBuddy"
    
    init() {
        populateProvisioningProfiles()
        populateCodesigningCerts()
    }
    
    func populateProvisioningProfiles() {
        self.provisioningProfiles = ProvisioningProfile.getProfiles().sorted {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        var newProfiles: [ProvisioningProfile] = []
        
        for profile in provisioningProfiles {
            if profile.expires.timeIntervalSince1970 > Date().timeIntervalSince1970 {
                newProfiles.append(profile)
                Log("Added profile \(profile.appID), expires (\(formatter.string(from: profile.expires)))")
            } else {
                Log("Skipped profile \(profile.appID), expired (\(formatter.string(from: profile.expires)))")
            }
        }
        self.provisioningProfiles = newProfiles
    }
    
    func populateCodesigningCerts() {
        var output: [String] = []
        
        let securityResult = Process().execute(securityPath, workingDirectory: nil, arguments: ["find-identity","-v","-p","codesigning"])
        if securityResult.output.characters.count >= 1 {
            let rawResult = securityResult.output.components(separatedBy: "\"")
            
            for index in stride(from: 0, through: rawResult.count - 2, by: 2) {
                if !(rawResult.count - 1 < index + 1) {
                    output.append(rawResult[index+1])
                }
            }
        }
        self.codesigningCerts = output
        
        Log("Found \(output.count) Codesigning Certificates")
    }
    
    func startSigning(_ input: String, output: String) {
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
            try fileManager.createDirectory(atPath: eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            Log("Error creating egg temp directory")
            Log(error.localizedDescription)
            cleanup(tempFolder)
            return
        }
        
        // MARK: Process input file
        switch(inputFile.pathExtension.lowercased()) {
        case "deb":
            // MARK: --Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                
                try fileManager.createDirectory(atPath: debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Extracting deb file")
                let debTask = Process().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                Log(debTask.output)
                if debTask.status != 0 {
                    Log("Error processing deb file")
                    cleanup(tempFolder)
                    return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar","tar.gz","tar.bz2","tar.lzma","tar.xz"]{
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExists(atPath: dataPath){
                        
                        Log("Unpacking data.\(tarFormat)")
                        let tarTask = Process().execute(tarPath, workingDirectory: debPath, arguments: ["-xf",dataPath])
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
                try fileManager.moveItem(atPath: debPath.stringByAppendingPathComponent("Applications"), toPath: payloadDirectory)
                
            } catch {
                Log("Error processing deb file")
                cleanup(tempFolder); return
            }
            
        case "ipa":
            //MARK: --Unzip ipa
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
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
                try fileManager.createDirectory(atPath: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                Log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        case "xcarchive":
            // MARK: --Copy app bundle from xcarchive
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                print("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                Log("Error copying app to payload directory")
                cleanup(tempFolder); return
            }
            
        default:
            Log("Unsupported input file")
            cleanup(tempFolder)
            return
        }
        
        if !fileManager.fileExists(atPath: payloadDirectory){
            Log("Payload directory doesn't exist")
            cleanup(tempFolder); return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectory(atPath: payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                
                fileManager.fileExists(atPath: payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory.boolValue { continue }
                
                // MARK: Bundle variables setup
                appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile == nil && fileManager.fileExists(atPath: appBundleProvisioningFilePath))
                
                // MARK: Delete CFBundleResourceSpecification from Info.plist
                Log(Process().execute(defaultsPath, workingDirectory: nil, arguments: ["delete",appBundleInfoPlist,"CFBundleResourceSpecification"]).output)
                
                // MARK: Copy Provisioning Profile
                if provisioningFile != nil {
                    if fileManager.fileExists(atPath: appBundleProvisioningFilePath) {
                        Log("Deleting embedded.mobileprovision")
                        do {
                            try fileManager.removeItem(atPath: appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            Log("Error deleting embedded.mobileprovision")
                            Log(error.localizedDescription)
                            cleanup(tempFolder); return
                        }
                    }
                    print("Copying provisioning profile to app bundle")
                    do {
                        try fileManager.copyItem(atPath: provisioningFile!, toPath: appBundleProvisioningFilePath)
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
                                try entitlements.write(toFile: entitlementsPlist, atomically: false, encoding: String.Encoding.utf8.rawValue)
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
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable") {
                    appBundleExecutable = appBundlePath.stringByAppendingPathComponent(bundleExecutable)
                    _ = Process().execute(chmodPath, workingDirectory: nil, arguments: ["755", appBundleExecutable])
                }
                
                // MARK: Change Application ID
                if newApplicationID != "" {
                    
                    if let oldAppID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier") {
                        
                        func changeAppexID(_ appexFile: String){
                            
                            func shortName(_ file: String, payloadDirectory: String) -> String {
                                return file.substring(from: payloadDirectory.endIndex)
                            }
                            
                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier"){
                                let newAppexID = "\(newApplicationID)\(appexBundleID.substring(from: oldAppID.endIndex))"
                                print("Changing \(shortName(appexFile, payloadDirectory: payloadDirectory)) id to \(newAppexID)")
                                
                                _ = setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", appexPlist,"WKCompanionAppBundleIdentifier"]).status == 0 {
                                _ = setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
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
                    print("Changing Display Name to \(newDisplayName)")
                    
                    // change CFBundleDisplayName in Info.plist
                    let displayNameChangeTask = self.setPlistKey(appBundleInfoPlist, keyName: "CFBundleDisplayName", value: newDisplayName)
                    if displayNameChangeTask.status != 0 {
                        Log("Error changing display name")
                        Log(displayNameChangeTask.output)
                        cleanup(tempFolder); return
                    }
                    
                    // change CFBundleDisplayName in InfoPlist.strings in every *.lproj
                    if let files = try? fileManager.contentsOfDirectory(atPath: appBundlePath) {
                        for file in files {
                            if file.pathExtension == "lproj" {
                                let lprojPath = appBundlePath.stringByAppendingPathComponent(file)
                                let infoPlistStringsPath = lprojPath.stringByAppendingPathComponent("InfoPlist.strings")
                                
                                let lprojDisplayNameChangeTask = self.plistBuddySet(infoPlistStringsPath, keyName: "CFBundleDisplayName", value: newDisplayName)
                                if lprojDisplayNameChangeTask.status != 0 {
                                    Log("Error changing display name")
                                    Log(lprojDisplayNameChangeTask.output)
                                    cleanup(tempFolder); return
                                }
                            }
                        }
                    }
                }
                
                // MARK: Delete URL Schemes
                if deleteURLSchemes {
                    let _ = self.plistBuddy(appBundleInfoPlist, command: "delete :CFBundleURLTypes")
                }
                
                func generateFileSignFunc(_ payloadDirectory: String, entitlementsPath: String, signingCertificate: String) -> ( (_ file: String) -> Void ) {
                    
                    let useEntitlements: Bool = ({
                        if fileManager.fileExists(atPath: entitlementsPath) {
                            return true
                        }
                        return false
                    })()
                    
                    func shortName(_ file: String, payloadDirectory: String) -> String {
                        return file.substring(from: payloadDirectory.endIndex)
                    }
                    
                    func beforeFunc(_ file: String, certificate: String, entitlements: String?) {
                        print("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements":"")")
                    }
                    
                    func afterFunc(_ file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput) {
                        if codesignOutput.status != 0 {
                            Log("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            Log(codesignOutput.output)
                            warnings += 1
                        }
                    }
                    
                    func output(_ file: String) {
                        _ = codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    
                    return output
                }
                
                // MARK: Codesigning - General
                let signableExtensions = ["dylib","so","0","vis","pvr","framework","appex","app"]
                
                // MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate)
                func signEgg(_ eggFile: String){
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    let shortName = eggFile.substring(from: payloadDirectory.endIndex)
                    Log("Extracting \(shortName)")
                    if self.unzip(eggFile, outputPath: currentEggPath).status != 0 {
                        Log("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    Log("Compressing \(shortName)")
                    _ = self.zip(currentEggPath, outputFile: eggFile)
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                // MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate)
                
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(appBundlePath)
                
                // MARK: Codesigning - Verification
                let verificationTask = Process().execute(codesignPath, workingDirectory: nil, arguments: ["-v",appBundlePath])
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
        if fileManager.fileExists(atPath: outputFile) {
            do {
                try fileManager.removeItem(atPath: outputFile)
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
        
        let cpTask = Process().execute(cpPath, workingDirectory: nil, arguments: [workingDirectory.stringByAppendingPathComponent(outputFile.lastPathComponent), outputFile])
        if cpTask.status != 0 {
            Log("Error copy IPA")
        }
        
        // MARK: Cleanup
        cleanup(tempFolder)
        print("Done, output at \(outputFile)")
    }
    
    func makeTempFolder() -> String? {
        let tempTask = Process().execute(mktempPath, workingDirectory: nil, arguments: ["-d","-t",bundleID])
        if tempTask.status != 0 {
            return nil
        }
        return tempTask.output.trim()
    }
    
    func cleanup(_ tempFolder: String) {
        do {
            Log("Deleting: \(tempFolder)")
            try fileManager.removeItem(atPath: tempFolder)
        } catch let error as NSError {
            Log("Unable to delete temp folder")
            Log(error.localizedDescription)
        }
    }
    
    func unzip(_ inputFile: String, outputPath: String) -> AppSignerTaskOutput {
        return Process().execute(unzipPath, workingDirectory: nil, arguments: ["-q",inputFile,"-d",outputPath])
    }
    
    func zip(_ inputPath: String, outputFile: String) -> AppSignerTaskOutput {
        return Process().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    func getPlistKey(_ plist: String, keyName: String) -> String? {
        let currTask = Process().execute(defaultsPath, workingDirectory: nil, arguments: ["read", plist, keyName])
        if currTask.status == 0 {
            return String(currTask.output.characters.dropLast())
        } else {
            return nil
        }
    }
    
    func setPlistKey(_ plist: String, keyName: String, value: String) -> AppSignerTaskOutput {
        return Process().execute(defaultsPath, workingDirectory: nil, arguments: ["write", plist, keyName, value])
    }
    
    func plistBuddySet(_ plist: String, keyName: String, value: String) -> AppSignerTaskOutput {
        return Process().execute(plistBuddyPath, workingDirectory: nil, arguments: ["-c", "set :\(keyName) \(value)", plist])
    }
    
    func plistBuddy(_ plist: String, command: String) -> AppSignerTaskOutput {
        return Process().execute(plistBuddyPath, workingDirectory: nil, arguments: ["-c", command, plist])
    }
    
    func recursiveDirectorySearch(_ path: String, extensions: [String], found: ((_ file: String) -> Void)){
        
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    found(currentFile)
                }
                
            }
        }
    }
    
    // MARK: Codesigning
    func codeSign(_ file: String, certificate: String, entitlements: String?, before: ((_ file: String, _ certificate: String, _ entitlements: String?)->Void)?, after: ((_ file: String, _ certificate: String, _ entitlements: String?, _ codesignTask: AppSignerTaskOutput)->Void)?) -> AppSignerTaskOutput {
        
        let useEntitlements: Bool = ({
            if entitlements == nil {
                return false
            } else {
                if fileManager.fileExists(atPath: entitlements!) {
                    return true
                } else {
                    return false
                }
            }
        })()
        
        if let beforeFunc = before {
            beforeFunc(file, certificate, entitlements)
        }
        
        var arguments = ["-vvv","-fs",certificate,"--no-strict"]
        
        // bugfix: for there has only one architecture
        // specified architecture
        if file.hasSuffix(".app") {
            let fileTask = Process().execute(fileCmdPath, workingDirectory: nil, arguments: [appBundleExecutable])
            let pattern = "for architecture (\\w+)"
            let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let res = regex.matches(in: fileTask.output, options: [], range: NSMakeRange(0, fileTask.output.characters.count))
            
            if res.count == 1 {
                arguments.append("-a")
                let arch = (fileTask.output as NSString).substring(with: res[0].rangeAt(1))
                arguments.append(arch)
            }
        }
        
        if useEntitlements {
            arguments.append("--entitlements=\(entitlements!)")
        }
        arguments.append(file)
        
        let codesignTask = Process().execute(codesignPath, workingDirectory: nil, arguments: arguments)
        if let afterFunc = after {
            afterFunc(file, certificate, entitlements, codesignTask)
        }
        return codesignTask
    }
}
