# beepserv

A tweak for jailbroken iPhones that can be connected with Beeper Mini to provide phone number registration functionality

## Setup

You'll need:
1. A jailbroken iPhone of iOS 10 or greater, with a hooking library installed (such as ellekit, libhooker, mobilesubstitute, or mobilesubstrate). This is usually installed during jaibreak.
2. An Android phone with latest version of Beeper Mini installed

Tested with default [palera1n](https://ios.cfw.guide/installing-palera1n/#running-palera1n-1) settings (rootless jailbreak required)

To install:
1. Add the beeper repo https://apt.beeper.com to the package manager (Cydia/Sileo) on your jailbroken phone
2. Install the package `beepserv` (identifier `com.beeper.beepserv`) with your package manager

## Usage
This tweak should automatically run in the background, connected to Beeper's relay service, available to facilitate registering your Android's phone number with Apple as an iPhone.

To start this registration process, open the Settings App, navigate to Messages, and read off the registration code stated underneath the 'iMessage' switch. Enter this codoe into Beeper Mini, and it should automatically start the registration process.

If this code does not appear, SSH into the iPhone and run `cat /var/jb/var/mobile/.beepserv_state` to view the code.

## Building
1. You need some hooking library installed on the target device, such as ellekit, libhooker, mobilesubstitute, or mobilesubstrate installed
2. Make sure you have ssh access to root on your device (the default password is `alpine`, you may need to log in to `mobile` over ssh first to change the password)
3. Install [theos](https://theos.dev) or make sure it's up-to-date by running `$THEOS/bin/update-theos` or `make update-theos`
4. Set the environment variable `$THEOS_DEVICE_IP` to the IP Address of the device you want to install it to (e.g. with `export THEOS_DEVICE_IP=<IP of phone>`)
5. Set the environment variable `$THEOS_PACKAGE_SCHEME` to `rootless` if you're using a rootless jailbreak (e.g. with `export THEOS_PACKAGE_SCHEME=rootless`)
6. Optional: install oslog (not the default one, but specifically [the one from noisyflake](https://github.com/NoisyFlake/oslog), as it works on the latest versions of iOS) to watch logs from ssh
7. Install with `make package install`

The Makefiles currently assume you have Xcode 11.7 installed at `/Applications/Xcode_11.7.app` when not packaging for rootless to ensure compatibility with A12+ devices on iOS 12.0-13.7 ([more here](https://theos.dev/docs/arm64e-deployment)). You can either download this version from Apple or edit the Makefiles if you want to build with a different version.

## Collaboration
We are very interested in working with jailbreak developers to help improve this! Please join us in #beepserv:beeper.com Matrix channel. 
In particular, we would love some help converting this from being a tweak (with very complex UI that only shows up in Settings -> Messages) to being a normal app that shows up on home screen with UI to show logs etc.
