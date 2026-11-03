export ARCHS = arm64 arm64e
export TARGET = iphone:clang::15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOSExtendBattery
iOSExtendBattery_FILES = Tweak.x
iOSExtendBattery_CFLAGS = -fobjc-arc -Wno-unused-function
iOSExtendBattery_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# ElleKit reads the filter plist inside the injected process (running as the
# app's user), so it must be world-readable or the tweak is silently skipped.
after-stage::
	@chmod 644 "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$(TWEAK_NAME).plist"
