# Keep the bundled application runtime private while exposing freedesktop
# metadata and a launcher in their standard system locations.

# Names come from CPack (CPACK_PACKAGE_NAME / CPACK_QGC_PACKAGE_ID) or, for makepkg,
# from -DQGC_APP_NAME / -DQGC_PACKAGE_NAME.
if(DEFINED CPACK_PACKAGE_NAME)
    set(_qgc_app_name "${CPACK_PACKAGE_NAME}")
elseif(DEFINED QGC_APP_NAME)
    set(_qgc_app_name "${QGC_APP_NAME}")
else()
    set(_qgc_app_name "QGroundControl")
endif()
if(DEFINED CPACK_QGC_PACKAGE_ID)
    set(_qgc_package_id "${CPACK_QGC_PACKAGE_ID}")
elseif(DEFINED QGC_PACKAGE_NAME)
    set(_qgc_package_id "${QGC_PACKAGE_NAME}")
else()
    set(_qgc_package_id "org.mavlink.qgroundcontrol")
endif()

set(_qgc_app_prefix "opt/${_qgc_app_name}")

if(DEFINED QGC_NATIVE_PACKAGE_ROOT AND NOT QGC_NATIVE_PACKAGE_ROOT STREQUAL "")
    set(_qgc_package_roots "${QGC_NATIVE_PACKAGE_ROOT}")
elseif(DEFINED CPACK_TEMPORARY_DIRECTORY AND IS_DIRECTORY "${CPACK_TEMPORARY_DIRECTORY}")
    file(
        GLOB_RECURSE _qgc_staged_entries
        LIST_DIRECTORIES false
        "${CPACK_TEMPORARY_DIRECTORY}/*"
    )
    set(_qgc_package_roots "")
    foreach(qgc_entry IN LISTS _qgc_staged_entries)
        if(qgc_entry MATCHES "/${_qgc_app_prefix}/bin/${_qgc_app_name}$")
            string(REGEX REPLACE "/${_qgc_app_prefix}/bin/${_qgc_app_name}$" "" _qgc_root "${qgc_entry}")
            list(APPEND _qgc_package_roots "${_qgc_root}")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES _qgc_package_roots)
else()
    message(FATAL_ERROR "QGC: native package root is unavailable")
endif()

if(NOT _qgc_package_roots)
    message(FATAL_ERROR "QGC: no staged /${_qgc_app_prefix}/bin/${_qgc_app_name} executable found")
endif()

foreach(qgc_root IN LISTS _qgc_package_roots)
    set(_qgc_private_root "${qgc_root}/${_qgc_app_prefix}")
    if(NOT EXISTS "${_qgc_private_root}/bin/${_qgc_app_name}")
        message(FATAL_ERROR "QGC: incomplete private runtime at ${_qgc_private_root}")
    endif()

    file(GLOB _qgc_qt_core "${_qgc_private_root}/lib/libQt6Core.so*" "${_qgc_private_root}/lib64/libQt6Core.so*")
    if(NOT _qgc_qt_core)
        message(
            FATAL_ERROR "QGC: bundled Qt Core is missing under ${_qgc_private_root}/lib or ${_qgc_private_root}/lib64"
        )
    endif()

    set(_qgc_launcher "${qgc_root}/usr/bin/${_qgc_app_name}")
    if(EXISTS "${_qgc_launcher}" OR IS_SYMLINK "${_qgc_launcher}")
        message(FATAL_ERROR "QGC: native package launcher already exists: ${_qgc_launcher}")
    endif()

    file(MAKE_DIRECTORY "${qgc_root}/usr/share")
    foreach(qgc_data_dir IN ITEMS applications icons metainfo)
        set(_qgc_source "${_qgc_private_root}/share/${qgc_data_dir}")
        set(_qgc_destination "${qgc_root}/usr/share/${qgc_data_dir}")
        if(NOT EXISTS "${_qgc_source}")
            message(FATAL_ERROR "QGC: required native package metadata is missing: ${_qgc_source}")
        endif()
        if(EXISTS "${_qgc_destination}")
            message(FATAL_ERROR "QGC: native package destination already exists: ${_qgc_destination}")
        endif()
        file(RENAME "${_qgc_source}" "${_qgc_destination}")
    endforeach()

    foreach(qgc_required_path IN
            ITEMS "applications/${_qgc_package_id}.desktop" "icons/hicolor/256x256/apps/${_qgc_app_name}.png"
                  "icons/hicolor/scalable/apps/${_qgc_app_name}.svg" "metainfo/${_qgc_package_id}.appdata.xml"
    )
        if(NOT EXISTS "${qgc_root}/usr/share/${qgc_required_path}")
            message(FATAL_ERROR "QGC: required native package payload is missing: /usr/share/${qgc_required_path}")
        endif()
    endforeach()

    file(
        GLOB _qgc_remaining_share_entries
        LIST_DIRECTORIES true
        "${_qgc_private_root}/share/*"
    )
    if(NOT _qgc_remaining_share_entries)
        file(REMOVE_RECURSE "${_qgc_private_root}/share")
    endif()

    file(MAKE_DIRECTORY "${qgc_root}/usr/bin")
    file(CREATE_LINK "../../${_qgc_app_prefix}/bin/${_qgc_app_name}" "${_qgc_launcher}" SYMBOLIC
         RESULT _qgc_link_result
    )
    if(NOT _qgc_link_result STREQUAL "0")
        message(FATAL_ERROR "QGC: failed to create native package launcher: ${_qgc_link_result}")
    endif()

    message(STATUS "QGC: finalized private native runtime under /${_qgc_app_prefix}")
endforeach()
