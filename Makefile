ARCHS ?= arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = DMKJ

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DMKJNoSplash
DMKJNoSplash_FILES = Tweak.xm
DMKJNoSplash_CFLAGS = -fobjc-arc
DMKJNoSplash_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
