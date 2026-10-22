#pragma once

#include "UnitTest.h"

class MultiCameraManagerTest : public UnitTest
{
    Q_OBJECT

private slots:
    void cleanup() override;

    void _testUriForStreamInfo_data();
    void _testUriForStreamInfo();
    void _testManualStreams();
    void _testCameraPresetUris_data();
    void _testCameraPresetUris();
    void _testPresetCredentialsStayOutOfKeys();
};
