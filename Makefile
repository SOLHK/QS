ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QS
QS_FILES = src/QS.m src/QSPlayer.m src/QSMode.m src/QSLog.m src/QSDiagnostics.m
QS_FRAMEWORKS = CoreGraphics Foundation QuartzCore UIKit UniformTypeIdentifiers
QS_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/tweak.mk
