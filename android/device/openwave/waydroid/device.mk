WAYDROID_DEVICE_PATH := device/waydroid/waydroid

$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
$(call inherit-product, vendor/lineage/config/common_mini_tablet_wifionly.mk)

$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_p.mk)

OVERRIDE_PRODUCT_COMPRESSED_APEX := false

PRODUCT_EXTRA_VNDK_VERSIONS := 34

PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true

PRODUCT_PACKAGES += com.android.hardware.audio

$(call inherit-product, frameworks/av/services/audiopolicy/audio_policy_config_vendor_1.mk)
$(call inherit-product, hardware/interfaces/audio/aidl/default/audio_effects.mk)

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/manifest_waydroid.xml:$(TARGET_COPY_OUT_VENDOR)/etc/vintf/manifest/manifest_waydroid.xml \
    $(WAYDROID_DEVICE_PATH)/configs/empty_vintf.xml:$(TARGET_COPY_OUT_VENDOR)/etc/vintf/manifest.disabled/empty_vintf.xml \
    $(WAYDROID_DEVICE_PATH)/configs/empty_vintf.xml:$(TARGET_COPY_OUT_VENDOR)/etc/vintf/manifest/manifest_host.xml \
    $(WAYDROID_DEVICE_PATH)/configs/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    $(WAYDROID_DEVICE_PATH)/configs/primary_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/primary_audio_policy_configuration.xml

PRODUCT_PACKAGES += \
    android.hardware.bluetooth@1.1-service.sim

USE_CAMERA_V4L2_HAL := true

PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.7-external-service \
    camera.v4l2

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/external_camera_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/external_camera_config.xml

PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.composer@2.4-service \
    android.hardware.graphics.mapper@2.0-impl-2.1 \
    vendor.waydroid.task@1.0-service \
    hwcomposer.drm_minigbm \
    hwcomposer.waydroid

PRODUCT_PACKAGES += \
    android.hardware.graphics.common-V4-ndk

ifeq ($(ANDROID_BUILD_REDROID_HWC),true)
PRODUCT_PACKAGES += \
    hwcomposer.redroid
endif

PRODUCT_PACKAGES += \
    libEGL_angle \
    libGLESv1_CM_angle \
    libGLESv2_angle \
    vulkan.pastel

ifneq ($(TARGET_USE_MESA),false)

ifeq ($(filter %_waydroid_x86 %_waydroid_x86_64 %_waydroid_x86_64_only,$(TARGET_PRODUCT)),)
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@4.0-service.minigbm_dmabuf \
    android.hardware.graphics.mapper@4.0-impl.minigbm_dmabuf \
    gralloc.minigbm_dmabuf
endif

PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@4.0-service.minigbm \
    android.hardware.graphics.allocator@4.0-service.minigbm_gbm_mesa \
    android.hardware.graphics.mapper@4.0-impl.minigbm \
    android.hardware.graphics.mapper@4.0-impl.minigbm_gbm_mesa \
    gralloc.minigbm \
    gralloc.minigbm_gbm_mesa

PRODUCT_PACKAGES += \
    dri_gbm \
    libEGL_mesa \
    libGLESv1_CM_mesa \
    libGLESv2_mesa \
    libgallium_dri \
    libgbm_mesa_wrapper \
    vulkan.lvp \
    vulkan.virtio

ifneq ($(filter %_x86_64_only,$(TARGET_PRODUCT)),)
PRODUCT_PACKAGES += \
    vulkan.intel
else ifneq ($(filter %_x86 %_x86_64,$(TARGET_PRODUCT)),)
PRODUCT_PACKAGES += \
    vulkan.intel \
    vulkan.intel_hasvk \
    vulkan.radeon \
    vulkan.nouveau
else
PRODUCT_PACKAGES += \
    vulkan.freedreno \
    vulkan.broadcom \
    vulkan.panfrost
endif

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml
endif

$(call inherit-product, frameworks/av/drm/mediadrm/plugins/clearkey/service-lazy.mk)

PRODUCT_PACKAGES += \
    com.android.hardware.gatekeeper.nonsecure

PRODUCT_PACKAGES += \
    android.hardware.health-service.example

PRODUCT_PACKAGES += \
    waydroid-init \
    waydroid-preinit

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/init.waydroid.vendor.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.waydroid.vendor.rc

PRODUCT_PACKAGES += \
    android.hardware.security.keymint-service

PRODUCT_PACKAGES += \
    com.android.hardware.security.authgraph \
    com.android.hardware.security.secretkeeper

PRODUCT_PACKAGES += \
    android.hardware.lights-service.example

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    $(WAYDROID_DEVICE_PATH)/configs/media_profiles.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_c2.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_c2.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_c2_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_c2_audio.xml \
    frameworks/av/media/libstagefright/data/media_codecs_google_c2_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_c2_video.xml

ifneq ($(TARGET_USE_MESA),false)
PRODUCT_COPY_FILES += \
    external/mesa3d/src/util/00-mesa-defaults.conf:$(TARGET_COPY_OUT_VENDOR)/etc/drirc \
    $(WAYDROID_DEVICE_PATH)/configs/mediacodec.mesa.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy \
    $(WAYDROID_DEVICE_PATH)/configs/mediacodec.mesa.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediaswcodec.policy
endif

ifneq ($(filter %64 %64_only,$(TARGET_PRODUCT)),)
PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/mediaextractor.64bit.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediaextractor.policy
else
PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/mediaextractor.32bit.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediaextractor.policy
endif

PRODUCT_PACKAGES += \
    android.hardware.media.c2-ffmpeg-service

PRODUCT_PROPERTY_OVERRIDES += \
    debug.ffmpeg-codec2.rank=0 \
    debug.ffmpeg-codec2.hwaccel.drm=0 \
    debug.ffmpeg-codec2.pixel_format=RGBX_8888

ifneq ($(filter %_waydroid_x86 %_waydroid_x86_64 %_waydroid_tv_x86 %_waydroid_tv_x86_64,$(TARGET_PRODUCT)),)
PRODUCT_PACKAGES += \
    i965_drv_video \
    iHD_drv_video \
    libgallium_dri

PRODUCT_PACKAGES += \
    android.hardware.media.c2-ffmpeg-service \
    vainfo

PRODUCT_PROPERTY_OVERRIDES += \
    media.sf.hwaccel=1
endif

PRODUCT_PACKAGES += \
    com.android.hardware.memtrack

PRODUCT_PACKAGES += \
    libwpa_client \
    hostapd \
    wificond \
    wpa_supplicant

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/wpa_supplicant.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf

DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay \
    $(WAYDROID_DEVICE_PATH)/overlay-lineage

PRODUCT_COPY_FILES += \
    $(WAYDROID_DEVICE_PATH)/configs/empty_permission.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions.disabled/empty_permission.xml \
    frameworks/native/data/etc/handheld_core_hardware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/handheld_core_hardware.xml \
    frameworks/native/data/etc/android.hardware.audio.low_latency.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.low_latency.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.full.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.full.xml \
    frameworks/native/data/etc/android.hardware.camera.raw.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.raw.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.ethernet.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.ethernet.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.sensor.ambient_temperature.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.ambient_temperature.xml \
    frameworks/native/data/etc/android.hardware.sensor.barometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.barometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.sensor.relative_humidity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.relative_humidity.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.software.sip.voip.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.sip.voip.xml \
    frameworks/native/data/etc/android.software.verified_boot.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.verified_boot.xml \
    frameworks/native/data/etc/android.hardware.vulkan.level-1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.level.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_3.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version.xml \
    frameworks/native/data/etc/android.hardware.vulkan.compute-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.compute.xml \
    frameworks/native/data/etc/android.hardware.keystore.app_attest_key.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.keystore.app_attest_key.xml \
    frameworks/native/data/etc/android.software.freeform_window_management.xml:system/etc/permissions/android.software.freeform_window_management.xml

PRODUCT_PACKAGES += \
    android.hardware.power-service.example

PRODUCT_PACKAGES += \
    com.android.hardware.sensors

PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH) \
    $(WAYDROID_DEVICE_PATH)

PRODUCT_PACKAGES += \
    vndservicemanager

PRODUCT_PACKAGES += \
    DocumentsUI

PRODUCT_DEXPREOPT_SPEED_APPS += \
    Settings \
    SystemUI

PRODUCT_PACKAGES += \
    OpenWaveRemovePackages \
    TINH \
    privapp-permissions-com.openwave.tinh.xml
