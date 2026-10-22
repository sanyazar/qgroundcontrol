# ============================================================================
# CreateCPackWIX.cmake
# Windows MSI package generator (WiX Toolset v4+ .NET tool, `wix.exe`)
# ============================================================================

include(CreateCPackCommon)

# ----------------------------------------------------------------------------
# WIX Generator Configuration
# ----------------------------------------------------------------------------
set(CPACK_GENERATOR "WIX")
set(CPACK_BINARY_WIX ON)
# 4 = WiX .NET tool (v4 and later); requires CMake 3.30+. The v3 candle/light path is not supported.
set(CPACK_WIX_VERSION 4)

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _qgc_wix_processor)
if(_qgc_wix_processor MATCHES "^(arm64|aarch64)$")
    set(CPACK_WIX_ARCHITECTURE "arm64")
    set(_qgc_wix_arch "ARM64")
else()
    set(CPACK_WIX_ARCHITECTURE "x64")
    set(_qgc_wix_arch "AMD64")
endif()
set(CPACK_PACKAGE_FILE_NAME "${CMAKE_PROJECT_NAME}-${CPACK_PACKAGE_VERSION}-${_qgc_wix_arch}")

# ----------------------------------------------------------------------------
# Product Identity
# ----------------------------------------------------------------------------
# Never change: Windows Installer uses this GUID to recognize earlier versions and upgrade them in place.
set(CPACK_WIX_UPGRADE_GUID "717986C8-3F50-4E3E-85BD-24B9F1C8564E")
set(CPACK_WIX_PRODUCT_ICON "${QGC_WINDOWS_ICON_PATH}")
set(CPACK_WIX_PROGRAM_MENU_FOLDER "${CMAKE_PROJECT_NAME}")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "${CMAKE_PROJECT_NAME}")
set(CPACK_WIX_INSTALL_SCOPE "perMachine")
set(CPACK_WIX_PROPERTY_ARPURLINFOABOUT "${CPACK_PACKAGE_HOMEPAGE_URL}")
set(CPACK_WIX_PROPERTY_ARPHELPLINK "https://qgroundcontrol.com/#resources")
set(CPACK_WIX_PROPERTY_ARPCONTACT "${CPACK_PACKAGE_CONTACT}")

# CPack WIX only accepts .rtf or .txt licenses; the repo license is Markdown.
configure_file("${CMAKE_SOURCE_DIR}/.github/COPYING.md" "${CMAKE_BINARY_DIR}/wix/COPYING.txt" COPYONLY)
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_BINARY_DIR}/wix/COPYING.txt")

# ----------------------------------------------------------------------------
# Shortcuts
# ----------------------------------------------------------------------------
# CPACK_PACKAGE_EXECUTABLES (from CreateCPackCommon) adds the Start menu entry for bin/${CMAKE_PROJECT_NAME}.exe.
set(CPACK_CREATE_DESKTOP_LINKS "${CMAKE_PROJECT_NAME}")

include(CPack)
