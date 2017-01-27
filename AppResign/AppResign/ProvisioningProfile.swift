//
//  ProvisioningProfile.swift
//  AppResign
//
//  Created by Eular on 6/7/16.
//  Copyright © 2016 Eular. All rights reserved.
//

import Foundation

struct ProvisioningProfile {
    
    var filename: String,
        name: String,
        created: Date,
        expires: Date,
        appID: String,
        teamID: String,
        rawXML: String,
        entitlements: AnyObject?
    
    static func getProfiles() -> [ProvisioningProfile] {
        var output: [ProvisioningProfile] = []
        
        let fileManager = FileManager()
        if let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let libraryPath = libraryDirectory.path
            let provisioningProfilesPath = libraryPath.stringByAppendingPathComponent("MobileDevice/Provisioning Profiles") as NSString
            
            if let provisioningProfiles = try? fileManager.contentsOfDirectory(atPath: provisioningProfilesPath as String) {
                for provFile in provisioningProfiles {
                    if provFile.pathExtension == "mobileprovision" {
                        let profileFilename = provisioningProfilesPath.appendingPathComponent(provFile)
                        if let profile = ProvisioningProfile(filename: profileFilename) {
                            output.append(profile)
                        }
                    }
                }
            }
        }
        
        return output
    }
    
    init?(filename: String){
        let securityArgs = ["cms","-D","-i", filename]
        
        let taskOutput = Process().execute("/usr/bin/security", workingDirectory: nil, arguments: securityArgs)
        if taskOutput.status == 0 {
            
            // here is a bug on macOS
            // taskOutput.output has a error info in the first line:
            // security: SecPolicySetValue: One or more parameters passed to a function were not valid.
            // the following is dirty fix
            if taskOutput.output.hasPrefix("security:") {
                let error_str = "security: SecPolicySetValue: One or more parameters passed to a function were not valid.\n"
                self.rawXML = taskOutput.output.replacingOccurrences(of: error_str, with: "")
            } else {
                self.rawXML = taskOutput.output
            }
            
            if let results = try? PropertyListSerialization.propertyList(from: self.rawXML.data(using: String.Encoding.utf8)!, options: PropertyListSerialization.MutabilityOptions(), format: nil) as AnyObject {
                
                if let expirationDate = results.value(forKey: "ExpirationDate") as? Date,
                    let creationDate = results.value(forKey: "CreationDate") as? Date,
                    let name = results.value(forKey: "Name") as? String,
                    let entitlements = results.value(forKey: "Entitlements"),
                    let applicationIdentifier = (entitlements as AnyObject).value(forKey: "application-identifier") as? String,
                    let periodIndex = applicationIdentifier.characters.index(of: ".") {
                    
                    self.filename = filename
                    self.expires = expirationDate
                    self.created = creationDate
                    self.appID = applicationIdentifier.substring(from: applicationIdentifier.index(periodIndex, offsetBy: 1))
                    self.teamID = applicationIdentifier.substring(to: periodIndex)
                    self.name = name
                    self.entitlements = entitlements as AnyObject?
                    
                } else {
                    Log("Error processing \(filename.lastPathComponent)")
                    return nil
                }
                
            } else {
                Log("Error parsing \(filename.lastPathComponent)")
                return nil
            }
            
        } else {
            Log("Error reading \(filename.lastPathComponent)")
            return nil
        }
    }
    
    func getEntitlementsPlist(_ tempFolder: String) -> NSString? {
        let mobileProvisionPlist = tempFolder.stringByAppendingPathComponent("mobileprovision.plist")
        do {
            try self.rawXML.write(toFile: mobileProvisionPlist, atomically: false, encoding: String.Encoding.utf8)
            let plistBuddy = Process().execute("/usr/libexec/PlistBuddy", workingDirectory: nil, arguments: ["-c", "Print :Entitlements", mobileProvisionPlist, "-x"])
            if plistBuddy.status == 0 {
                return plistBuddy.output as NSString?
            } else {
                Log("PlistBuddy Failed")
                Log(plistBuddy.output)
                return nil
            }
        } catch let error as NSError {
            Log("Error writing mobileprovision.plist")
            Log(error.localizedDescription)
            return nil
        }
    }
}
