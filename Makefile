ARCHS = arm64 arm64e

ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
	TARGET := iphone:clang:latest:16.0
else
	OLDER_XCODE_PATH=/Applications/Xcode-11.7.app
	PREFIX=$(OLDER_XCODE_PATH)/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/
	SYSROOT=$(OLDER_XCODE_PATH)/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
	SDKVERSION = 13.7
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = beepserv
INSTALL_TARGET_PROCESSES = identityservicesd

LINK_DIRS := $(shell sh -c "find SocketRocket/SocketRocket -type d | xargs -I % echo -I%")
M_FILES := $(shell find SocketRocket/SocketRocket -type f -name '*.m')

# Yes I know I should probably use cocoapods or whatever for SocketRocket, but ruby is not nice
beepserv_FILES = Tweak.x State.x $(M_FILES)
beepserv_CFLAGS = -fobjc-arc -I./SocketRocket -Wno-deprecated $(LINK_DIRS)

include $(THEOS_MAKE_PATH)/tweak.mk

# try to apply the patch that will make it work. If it exits with non-zero, that just means
# the patch is already applied, so we can safely ignore it with `|| :`
before-all::
	cd SocketRocket && git apply -q ../SocketRocket.patch || :

after-install::
	install.exec "killall identityservicesd"
