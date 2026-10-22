# ============================================================================
# VideoManager Tests
# ============================================================================

add_subdirectory(GStreamer)

target_sources(${CMAKE_PROJECT_NAME} PRIVATE VideoManagerInitTest.cc VideoManagerInitTest.h VideoManagerRestartTest.cc
                                             VideoManagerRestartTest.h
)
target_sources(${CMAKE_PROJECT_NAME} PRIVATE MultiCameraManagerTest.cc MultiCameraManagerTest.h)

add_qgc_test(MultiCameraManagerTest LABELS Unit)
add_qgc_test(VideoManagerInitTest LABELS Unit)
add_qgc_test(VideoManagerRestartTest LABELS Unit)
