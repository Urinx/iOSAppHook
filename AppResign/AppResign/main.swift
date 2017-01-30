//
//  main.swift
//  AppResign
//
//  Created by Eular on 6/7/16.
//  Copyright © 2016 Eular. All rights reserved.
//

import Foundation

let argv = CommandLine.arguments
let appName = argv[0].pathComponents.last!
LogMode = false

func Usage() {
    print("Version: 2.2.1\n")
    print("Usage:")
    print("./\(appName) [-options] [INPUT] [OUTPUT]")
    print("\nOptions:")
    print("-h \t help")
    print("-v \t verbose mode, print all logs")
    print("-c \t certificate")
    print("-p \t provisioning profile")
    print("-b \t bundle id")
    print("-n \t display name, '*' means default name")
    print("\nExample:")
    print("./\(appName) xxx.ipa xxx-out.ipa")
    print("./\(appName) -v xxx.ipa xxx-out.ipa")
    print("./\(appName) -v -c 'iPhone Developer: XXX XXX (ABCDE12345)' -p 'iOS Team Provisioning Profile: com.xxx.xxx (ABCDE12345)' -b 'com.xxx.xxx' -n '*' xxx.ipa xxx-out.ipa")
    exit(1)
}

// deprecated
//func raw_input(_ prompt: String = "> ") -> String {
//    print(prompt, terminator:"")
//    var input: String = ""
//    
//    while true {
//        let c = Character(UnicodeScalar(UInt32(fgetc(stdin)))!)
//        if c == "\n" {
//            return input
//        } else {
//            input.append(c)
//        }
//    }
//}

func raw_input(_ prompt: String = "> ") -> String {
    print(prompt, terminator:"")
    return readLine(strippingNewline: true) ?? ""
}


func mainRoutine(_ input: String, output: String, certificate: String, provProfile: String, bundleId: String, displayName: String) {
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
            } else if (!certificate.isEmpty) {
                for c in appResign.codesigningCerts {
                    if (c == certificate) {
                        appResign.curSigningCert = certificate
                        break
                    }
                }
                if (appResign.curSigningCert.isEmpty) {
                    print("Can't find certificate: \(certificate)\n")
                    exit(2)
                }
                print("Use Certificate: \(certificate)\n")
            } else {
                while true {
                    let r = Int(raw_input())
                    if (r != nil) && (r! >= 0) && (r! < n) {
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
            } else if (!provProfile.isEmpty) {
                for p in appResign.provisioningProfiles {
                    if ((p.name + " (" + p.teamID + ")") == provProfile) {
                        profile = p
                        appResign.profileFilename = profile!.filename
                        break
                    }
                }
                if (appResign.profileFilename == nil) {
                    print("Can't find provisioning profile: \(provProfile)\n")
                    exit(2)
                }
                print("Use Profile: \(provProfile)\n")
                print("Position: \(profile!.filename)\n")
            } else {
                while true {
                    let r = Int(raw_input())
                    if r != nil && r! >= 0 && r! < n {
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
            if profile!.appID.characters.index(of: "*") == nil {
                // Not a wildcard profile
                appResign.newApplicationID = profile!.appID
                print("Use default bundle ID: \(profile!.appID)\n")
            } else if (!bundleId.isEmpty) {
                appResign.newApplicationID = bundleId
                print("Use bundle ID: \(bundleId)\n")
            } else {
                let r = raw_input("Set App Bundle ID: ")
                if !r.isEmpty {
                    appResign.newApplicationID = r
                }
                print()
            }
            
            // Set app display name
            if (!displayName.isEmpty) {
                if (displayName == "*") {
                    print("Use default display name.")
                } else {
                    appResign.newDisplayName = displayName
                    print("Use App Display Name: \(displayName)\n")
                }
            } else {
                let r = raw_input("Set App Display Name: ")
                if !r.isEmpty {
                    appResign.newDisplayName = r
                }
            }
            
            // If delete url schemes
            let deleteQuery = raw_input("Delete url schemes (y/n): ")
            if !deleteQuery.isEmpty && deleteQuery == "y" {
                appResign.deleteURLSchemes = true
            }
            
            print("=============================")
            
            // Start signing
            print("[*] Start Resigning App")
            appResign.startSigning(input, output: output)
            
        } else {
            print("[*] Error! \nOnly support output ipa file.")
        }
    } else {
        print("[*] Error! \nThis tool can only support input file with format: \(support.joined(separator: ", ")).")
    }
}

if (argv.count < 3 || argv.count > 12) {
    Usage()
}

var certificate = ""
var provProfile = ""
var bundleId    = ""
var displayName = ""
var i = 1
while (i < argv.count - 2) {
    switch (argv[i]) {
        case "-v":
            LogMode = true
        case "-c":
            i += 1
            certificate = argv[i]
        case "-p":
            i += 1
            provProfile = argv[i]
        case "-b":
            i += 1
            bundleId    = argv[i]
        case "-n":
            i += 1
            displayName = argv[i]
        default:
            Usage()
    }
    i += 1
}
let input  = argv[argv.count - 2]
let output = argv[argv.count - 1]

mainRoutine(input, output: output, certificate: certificate, provProfile: provProfile, bundleId: bundleId, displayName: displayName)


