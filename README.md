# beepserv

A tweak for jailbroken iPhones that can be connected with Beeper Mini to provide phone number registration functionality

## Setup

You'll need:
1. A jailbroken iPhone of iOS 9 or greater, with a hooking library installed (such as ellekit, libhooker, mobilesubstitute, or mobilesubstrate).
2. Beeper Mini set up on a separate device
2. Some time

To install:
1. Add the beeper repo (**TODO**: Make a repo) to the package manager on your jailbroken phone
2. Install the package `beepserv` (identifier `com.beeper.beepserv`) with your package manager

## Usage
This tweak should automatically run in the background, connected to Beeper's relay service, available to facilitate registering your Android's phone number with Apple as an iPhone.

To start this registration process, open the Settings App, navigate to Messages, and read off the identifier stated underneath the 'iMessage' switch. Copy this identifier into your Android app, and it should automatically start the registration process.

## Building
1. You need some hooking library installed on the target device, such as ellekit, libhooker, mobilesubstitute, or mobilesubstrate installed
2. Make sure you have ssh access to root on your device (the default password is `alpine`, you may need to log in to `mobile` over ssh first to change the password)
3. Install [theos](https://theos.dev)
4. Set the environment variable `$THEOS_DEVICE_IP` to the IP Address of the device you want to install it to (e.g. with `export THEOS_DEVICE_IP=<IP of phone>`)
5. Optional: install oslog (not the default one, but specifically [the one from noisyflake](https://github.com/NoisyFlake/oslog), as it works on the latest versions of iOS) to watch logs from ssh
6. Install with `make package install`
