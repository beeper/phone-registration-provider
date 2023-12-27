TARGET := iphone:clang:latest:16.0

THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = beepserv
INSTALL_TARGET_PROCESSES = identityservicesd

LINK_DIRS := $(shell sh -c "find SocketRocket/SocketRocket -type d | xargs -I % echo -I%")
M_FILES := $(shell find SocketRocket/SocketRocket -type f -name '*.m')

# Yes I know I should probably use cocoapods or whatever for SocketRocket, but ruby is not nice
beepserv_FILES = Tweak.x State.x $(M_FILES)
beepserv_CFLAGS = -fobjc-arc -I./SocketRocket -Wno-deprecated $(LINK_DIRS)
beepserv_LIBRARIES = MobileGestalt

include $(THEOS_MAKE_PATH)/tweak.mk

# try to apply the patch that will make it work. If it exits with non-zero, that just means
# the patch is already applied, so we can safely ignore it with `|| :`
before-all::
	cd SocketRocket && git apply -q ../SocketRocket.patch || :

after-install::
	install.exec "killall identityservicesd"
