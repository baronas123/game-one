// swift-tools-version: 5.9

// Swift Playgrounds / Xcode app paketas.
// Atidaryti: dukart spustelėti Arkada.swiftpm (Mac su Xcode 15+)
// arba perkelti į Swift Playgrounds programėlę iPad'e / Mac'e.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Arkada",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Arkada",
            targets: ["AppModule"],
            bundleIdentifier: "lt.barons.arkada",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .gamepad),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
