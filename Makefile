ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QS
QS_FILES = src/QS.m
QS_FRAMEWORKS = CoreGraphics Foundation UIKit
QS_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/tweak.mk
