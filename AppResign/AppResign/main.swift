//
//  main.swift
//  AppResign
//
//  Created by Eular on 6/7/16.
//  Copyright © 2016 Eular. All rights reserved.
//

import Foundation

let argv = Process.arguments
let appName = argv[0].pathComponents.last!
LogMode = false

func Usage() {
    print("Usage:")
    print("./\(appName) [-options] [INPUT] [OUTPUT]")
    print("\nOptions:")
    print("-h \t help")
    print("-v \t verbose mode, print all logs")
    print("\nExample:")
    print("./\(appName) xxx.ipa xxx-out.ipa")
    print("./\(appName) -v xxx.ipa xxx-out.ipa")
}

func raw_input(prompt: String = "> ") -> String {
    print(prompt, terminator:"")
    var input: String = ""
    
    while true {
        let c = Character(UnicodeScalar(UInt32(fgetc(stdin))))
        if c == "\n" {
            return input
        } else {
            input.append(c)
        }
    }
}

func mainRoutine(input: String, output: String) {
    let support = ["deb", "ipa", "app", "xcarchive"]
    if support.contains(input.pathExtension) {
        if output.pathExtension == "ipa" {
            let appResign = AppResign()
            
            print("=============================")
            print("[*] Configure Resigning")
            // Show signing ceritificates
            print("Choose Signing Ceritificate:")
            var n = appResign.codesigningCerts.count
            for i in 0..<n {
                print("[\(i)] \(appResign.codesigningCerts[i])")
            }
            
            if n == 1 {
                appResign.curSigningCert = appResign.codesigningCerts[0]
                print("Use Certificate: \(appResign.curSigningCert)\n")
            } else {
                while true {
                    let r = Int(raw_input())
                    if r != nil && r >= 0 && r < n {
                        appResign.curSigningCert = appResign.codesigningCerts[r!]
                        print("Use Certificate: \(appResign.curSigningCert)\n")
                        break
                    } else {
                        print("Please input number 0-\(n-1)")
                    }
                }
            }
            
            // Show provisioning profiles
            print("Choose Provisioning Profile:")
            n = appResign.provisioningProfiles.count
            for i in 0..<n {
                let profile = appResign.provisioningProfiles[i]
                print("[\(i)] \(profile.name) (\(profile.teamID))")
            }
            
            var profile: ProvisioningProfile? = nil
            
            if n == 1 {
                profile = appResign.provisioningProfiles[0]
                appResign.profileFilename = profile!.filename
                print("Use Profile: \(profile!.name) (\(profile!.teamID))")
                print("Position: \(profile!.filename)\n")
            } else {
                while true {
                    let r = Int(raw_input())
                    if r != nil && r >= 0 && r < n {
                        profile = appResign.provisioningProfiles[r!]
                        appResign.profileFilename = profile!.filename
                        print("Use Profile: \(profile!.name) (\(profile!.teamID))")
                        print("Position: \(profile!.filename)\n")
                        break
                    } else {
                        print("Please input number 0-\(n-1)")
                    }
                }
            }
            
            // Set app bundle ID
            if profile!.appID.characters.indexOf("*") == nil {
                // Not a wildcard profile
                appResign.newApplicationID = profile!.appID
                print("Use default bundle ID: \(profile!.appID)\n")
            } else {
                let r = raw_input("Set App Bundle ID: ")
                if !r.isEmpty {
                    appResign.newApplicationID = r
                }
                print()
            }
            
            // Set app display name
            let r = raw_input("Set App Display Name: ")
            if !r.isEmpty {
                appResign.newDisplayName = r
            }
            print("=============================")
            
            // Start signing
            print("[*] Start Resigning App")
            appResign.startSigning(input, output: output)
            
        } else {
            print("[*] Error! \nOnly support output ipa file.")
        }
    } else {
        print("[*] Error! \nThis tool can only support input file with format: \(support.joinWithSeparator(", ")).")
    }
}

switch argv.count {
case 2:
    if argv[1] == "-h" { Usage() }
case 3:
    let input = argv[1]
    let output = argv[2]
    mainRoutine(input, output: output)
case 4:
    if argv[1] == "-v" {
        LogMode = true
        let input = argv[2]
        let output = argv[3]
        mainRoutine(input, output: output)
    }
default:
    Usage()
}



