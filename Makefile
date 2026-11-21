TARGET := iphone:clang:latest:16.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Spotify

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SptTermTweak
SptTermTweak_FILES = $(shell find SptTermTweak -name '*.swift') $(shell find SptTerm -name '*.swift' ! -name 'SptTermApp.swift')
SptTermTweak_SWIFTFLAGS = -warnings-as-errors

include $(THEOS_MAKE_PATH)/tweak.mk
