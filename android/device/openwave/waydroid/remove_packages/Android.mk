LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := OpenWaveRemovePackages
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_OVERRIDES_PACKAGES := \
    Launcher3 \
    Launcher3QuickStep \
    Launcher3QuickStepGo \
    Launcher3Overlay \
    Trebuchet \
    TrebuchetQuickStep \
    Backgrounds \
    LiveWallpapersPicker \
    WallpaperCropper \
    WallpaperPicker \
    WallpaperPicker2 \
    ThemePicker \
    LineageSetupWizard \
    SetupWizard \
    Updater \
    Camera2 \
    Gallery2 \
    Music \
    Calendar \
    Browser2 \
    Glimpse \
    Jelly \
    DeskClock \
    EyeDropper \
    QuickSearchBox \
    PhotoTable \
    BasicDreams \
    EasterEgg \
    AvatarPicker \
    EmergencyInfo \
    QuickAccessWallet \
    Canvas \
    DeviceDiagnostics \
    PrivateSpace
LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_SRC_FILES := /dev/null
include $(BUILD_PREBUILT)
