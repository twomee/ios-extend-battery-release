export ARCHS = arm64 arm64e
export TARGET = iphone:clang::17.0
export THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = IEBProducerProbe IEBBatterySettings
IEBProducerProbe_FILES = Tweak.x IEBActivityCapture.m IEBNativeCapture.m ../Sources/Statistics/IEBNativeJournal.m ../Sources/Statistics/IEBCycleSummary.m ../Sources/Session/IEBNativePowerWindow.m ../tools/IEBProducerEvidence.m ../Sources/Statistics/IEBActivityEvidence.m ../Sources/Session/IEBSessionState.m ../Sources/Session/IEBSessionStore.m ../Sources/Session/IEBPowerObserver.m
IEBProducerProbe_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
IEBProducerProbe_FRAMEWORKS = Foundation
IEBProducerProbe_LIBRARIES = sqlite3
IEBBatterySettings_FILES = Settings.x $(wildcard ../Sources/Presentation/*.m) $(wildcard ../Sources/Diagnostics/*.m) $(wildcard ../Sources/Statistics/*.m) ../Sources/Session/IEBNativePowerWindow.m ../Sources/Session/IEBSessionStore.m ../Sources/Session/IEBSessionState.m
IEBBatterySettings_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
IEBBatterySettings_FRAMEWORKS = UIKit Foundation CoreGraphics
IEBBatterySettings_LIBRARIES = sqlite3
include $(THEOS_MAKE_PATH)/tweak.mk
TOOL_NAME = ieb-process-reader
ieb-process-reader_FILES = ../rootreader/main.m ../rootreader/IEBRootProcessServer.m ../Sources/Diagnostics/IEBProcessSnapshot.m ../Sources/Diagnostics/IEBRootProcessProtocol.m ../Sources/Diagnostics/IEBRootProcessClient.m
ieb-process-reader_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
ieb-process-reader_FRAMEWORKS = Foundation
ieb-process-reader_INSTALL_PATH = /usr/libexec
include $(THEOS_MAKE_PATH)/tool.mk
after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/usr/share/doc/com.idonamaan.iebproducerprobe"
	@cp "$(THEOS_PROJECT_DIR)/../LICENSE" "$(THEOS_STAGING_DIR)/usr/share/doc/com.idonamaan.iebproducerprobe/copyright"
	@cp "$(THEOS_PROJECT_DIR)/../THIRD_PARTY_NOTICES.md" "$(THEOS_STAGING_DIR)/usr/share/doc/com.idonamaan.iebproducerprobe/THIRD_PARTY_NOTICES.md"
	@chmod 644 "$(THEOS_STAGING_DIR)/usr/share/doc/com.idonamaan.iebproducerprobe/"*
	@chmod 755 "$(THEOS_STAGING_DIR)/usr/libexec/ieb-process-reader"
	@chmod 644 "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.idonamaan.ieb.process-reader.plist"
	@chmod 644 "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/IEBProducerProbe.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/IEBBatterySettings.plist"
after-package::
	@python3 ../tools/package_ownership.py "$(_THEOS_DEB_PACKAGE_FILENAME)"
	@python3 ../tools/package_ownership.py --check "$(_THEOS_DEB_PACKAGE_FILENAME)"
	@python3 "$(THEOS_PROJECT_DIR)/../tools/verify_release_license.py" "$(_THEOS_DEB_PACKAGE_FILENAME)"
