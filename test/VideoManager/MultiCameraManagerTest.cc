#include "MultiCameraManagerTest.h"

#include <cstring>
#include <memory>

#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QRegularExpression>
#include <QtTest/QSignalSpy>

#include "Fact.h"
#include "MultiCameraManager.h"
#include "MultiCameraStream.h"
#include "QGCVideoStreamInfo.h"
#include "SettingsManager.h"
#include "UDPLink.h"
#include "VideoSettings.h"

namespace {

constexpr int kRebuildTimeoutMs = 2000;

QGCVideoStreamInfo* makeStreamInfo(uint8_t type, uint16_t encoding, const char* uri, QObject* parent)
{
    mavlink_video_stream_information_t info{};
    info.stream_id = 1;
    info.type = type;
    info.encoding = encoding;
    (void) strncpy(info.uri, uri, sizeof(info.uri) - 1);
    return new QGCVideoStreamInfo(info, parent);
}

}  // namespace

void MultiCameraManagerTest::cleanup()
{
    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    videoSettings->multiCameraEnabled()->setRawValue(false);
    videoSettings->multiCameraStreams()->setRawValue(QStringLiteral("[]"));
    videoSettings->multiCameraMaxStreams()->setRawValue(4);

    UnitTest::cleanup();
}

void MultiCameraManagerTest::_testUriForStreamInfo_data()
{
    QTest::addColumn<int>("type");
    QTest::addColumn<int>("encoding");
    QTest::addColumn<QString>("uri");
    QTest::addColumn<QString>("expected");

    QTest::newRow("rtsp") << int(VIDEO_STREAM_TYPE_RTSP) << int(VIDEO_STREAM_ENCODING_H264)
                          << QStringLiteral("rtsp://10.0.0.2:8554/main") << QStringLiteral("rtsp://10.0.0.2:8554/main");
    QTest::newRow("udp h264 port") << int(VIDEO_STREAM_TYPE_RTPUDP) << int(VIDEO_STREAM_ENCODING_H264)
                                   << QStringLiteral("5600") << QStringLiteral("udp://0.0.0.0:5600");
    QTest::newRow("udp h265 port") << int(VIDEO_STREAM_TYPE_RTPUDP) << int(VIDEO_STREAM_ENCODING_H265)
                                   << QStringLiteral("5601") << QStringLiteral("udp265://0.0.0.0:5601");
    QTest::newRow("udp full uri") << int(VIDEO_STREAM_TYPE_RTPUDP) << int(VIDEO_STREAM_ENCODING_H264)
                                  << QStringLiteral("udp://0.0.0.0:5602") << QStringLiteral("udp://0.0.0.0:5602");
    QTest::newRow("mpegts port") << int(VIDEO_STREAM_TYPE_MPEG_TS) << int(VIDEO_STREAM_ENCODING_H264)
                                 << QStringLiteral("5603") << QStringLiteral("mpegts://0.0.0.0:5603");
    QTest::newRow("empty uri") << int(VIDEO_STREAM_TYPE_RTSP) << int(VIDEO_STREAM_ENCODING_H264) << QString()
                               << QString();
}

void MultiCameraManagerTest::_testUriForStreamInfo()
{
    QFETCH(int, type);
    QFETCH(int, encoding);
    QFETCH(QString, uri);
    QFETCH(QString, expected);

    QObject parent;
    const QGCVideoStreamInfo* const info =
        makeStreamInfo(static_cast<uint8_t>(type), static_cast<uint16_t>(encoding), uri.toUtf8().constData(), &parent);
    QCOMPARE(MultiCameraManager::uriForStreamInfo(info), expected);
}

void MultiCameraManagerTest::_testManualStreams()
{
    ignoreLogMessage("Video.MultiCameraManager", QtWarningMsg, QRegularExpression(QStringLiteral("Stream limit")));

    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    MultiCameraManager manager;
    manager.init();

    // Duplicate URI and empty URI are dropped; the limit cuts the rest.
    videoSettings->multiCameraStreams()->setRawValue(
        QStringLiteral(R"([{"vehicleId":1,"name":"Front","uri":"rtsp://10.0.0.2/front"},)"
                       R"({"vehicleId":1,"name":"Down","uri":"udp://0.0.0.0:5600"},)"
                       R"({"vehicleId":2,"name":"Copy","uri":"rtsp://10.0.0.2/front"},)"
                       R"({"vehicleId":2,"name":"Empty","uri":""},)"
                       R"({"vehicleId":0,"name":"Ground","uri":"udp://0.0.0.0:5601"}])"));
    videoSettings->multiCameraMaxStreams()->setRawValue(2);
    videoSettings->multiCameraEnabled()->setRawValue(true);

    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 2, kRebuildTimeoutMs);
    const auto* const first = manager.streams()->value<MultiCameraStream*>(0);
    QCOMPARE(first->uri(), QStringLiteral("rtsp://10.0.0.2/front"));
    QCOMPARE(first->vehicleId(), 1);
    QVERIFY(first->label().contains(QStringLiteral("Front")));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(1)->uri(), QStringLiteral("udp://0.0.0.0:5600"));
    QCOMPARE(manager.mainIndex(), 0);

    manager.setMainIndex(1);
    QCOMPARE(manager.mainIndex(), 1);

    videoSettings->multiCameraMaxStreams()->setRawValue(9);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 3, kRebuildTimeoutMs);
    QCOMPARE(manager.mainStream()->uri(), QStringLiteral("udp://0.0.0.0:5600"));

    videoSettings->multiCameraEnabled()->setRawValue(false);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 0, kRebuildTimeoutMs);
    QCOMPARE(manager.mainIndex(), -1);
}

void MultiCameraManagerTest::_testHiddenStreams()
{
    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    MultiCameraManager manager;
    manager.init();
    manager.showAllStreams();

    videoSettings->multiCameraStreams()->setRawValue(
        QStringLiteral(R"([{"vehicleId":1,"name":"Front","uri":"rtsp://10.0.0.2/front"},)"
                       R"({"vehicleId":1,"name":"Down","uri":"udp://0.0.0.0:5600"}])"));
    videoSettings->multiCameraMaxStreams()->setRawValue(1);
    videoSettings->multiCameraEnabled()->setRawValue(true);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 1, kRebuildTimeoutMs);
    const QString frontKey = manager.streams()->value<MultiCameraStream*>(0)->key();

    // A hidden stream leaves the view, is listed for showing again and frees its slot under the limit.
    manager.hideStream(frontKey);
    QCOMPARE(manager.streams()->count(), 1);
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(0)->uri(), QStringLiteral("udp://0.0.0.0:5600"));
    QCOMPARE(manager.hiddenStreams().count(), 1);
    QCOMPARE(manager.hiddenStreams().constFirst().toMap().value(QStringLiteral("key")).toString(), frontKey);

    // Remembered by a new manager (next start).
    {
        MultiCameraManager other;
        other.init();
        QTRY_COMPARE_WITH_TIMEOUT(other.hiddenStreams().count(), 1, kRebuildTimeoutMs);
    }

    manager.showStream(frontKey);
    QCOMPARE(manager.hiddenStreams().count(), 0);
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(0)->key(), frontKey);

    videoSettings->multiCameraEnabled()->setRawValue(false);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 0, kRebuildTimeoutMs);
}

void MultiCameraManagerTest::_testStreamQuality()
{
    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    MultiCameraManager manager;
    manager.init();
    manager.setStreamQuality(QString());

    videoSettings->multiCameraStreams()->setRawValue(QStringLiteral(
        R"([{"type":"hikvision","name":"Front","host":"10.0.0.7","stream":"sub"},)"
        R"({"type":"custom","name":"Down","uri":"udp://0.0.0.0:5600"},)"
        R"({"type":"custom","name":"Rear","uri":"rtsp://10.0.0.9/main","subEnabled":true,"subUri":"rtsp://10.0.0.9/sub"}])"));
    videoSettings->multiCameraMaxStreams()->setRawValue(4);
    videoSettings->multiCameraEnabled()->setRawValue(true);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 3, kRebuildTimeoutMs);
    QVERIFY(manager.hasSubStreams());
    const QString rearKey = manager.streams()->value<MultiCameraStream*>(2)->key();
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(2)->uri(), QStringLiteral("rtsp://10.0.0.9/main"));
    const auto* const preset = manager.streams()->value<MultiCameraStream*>(0);
    const QString key = preset->key();
    QCOMPARE(preset->uri(), QStringLiteral("rtsp://10.0.0.7:554/Streaming/Channels/102"));

    // All presets switch to the main stream; the stream keeps its key, custom URLs without a sub stream are untouched.
    manager.setStreamQuality(QStringLiteral("main"));
    QCOMPARE(manager.streams()->count(), 3);
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(0)->key(), key);
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(0)->uri(),
             QStringLiteral("rtsp://10.0.0.7:554/Streaming/Channels/101"));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(1)->uri(), QStringLiteral("udp://0.0.0.0:5600"));

    manager.setStreamQuality(QStringLiteral("sub"));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(0)->uri(),
             QStringLiteral("rtsp://10.0.0.7:554/Streaming/Channels/102"));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(1)->uri(), QStringLiteral("udp://0.0.0.0:5600"));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(2)->uri(), QStringLiteral("rtsp://10.0.0.9/sub"));
    QCOMPARE(manager.streams()->value<MultiCameraStream*>(2)->key(), rearKey);

    manager.setStreamQuality(QString());
    videoSettings->multiCameraEnabled()->setRawValue(false);
    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 0, kRebuildTimeoutMs);
}

void MultiCameraManagerTest::_testCameraPresetUris_data()
{
    QTest::addColumn<QString>("entryJson");
    QTest::addColumn<QString>("expected");

    QTest::newRow("custom") << R"({"type":"custom","uri":"rtsp://10.0.0.2/live"})"
                            << QStringLiteral("rtsp://10.0.0.2/live");
    QTest::newRow("legacy entry without type")
        << R"({"uri":"udp://0.0.0.0:5600"})" << QStringLiteral("udp://0.0.0.0:5600");
    QTest::newRow("dahua main") << R"({"type":"dahua","host":"192.168.1.108","username":"admin","password":"secret"})"
                                << QStringLiteral(
                                       "rtsp://admin:secret@192.168.1.108:554/cam/realmonitor?channel=1&subtype=0");
    QTest::newRow("dahua sub channel 3") << R"({"type":"dahua","host":"192.168.1.108","channel":3,"stream":"sub"})"
                                         << QStringLiteral(
                                                "rtsp://192.168.1.108:554/cam/realmonitor?channel=3&subtype=1");
    QTest::newRow("hikvision main custom port")
        << R"({"type":"hikvision","host":"192.168.1.64","port":8554,"username":"admin","password":"p@ss"})"
        << QStringLiteral("rtsp://admin:p%40ss@192.168.1.64:8554/Streaming/Channels/101");
    QTest::newRow("hikvision sub channel 2") << R"({"type":"hikvision","host":"cam.local","channel":2,"stream":"sub"})"
                                             << QStringLiteral("rtsp://cam.local:554/Streaming/Channels/202");
    QTest::newRow("unv main") << R"({"type":"unv","host":"10.1.1.5","username":"admin","password":"123"})"
                              << QStringLiteral("rtsp://admin:123@10.1.1.5:554/unicast/c1/s0/live");
    QTest::newRow("unv sub") << R"({"type":"unv","host":"10.1.1.5","stream":"sub"})"
                             << QStringLiteral("rtsp://10.1.1.5:554/unicast/c1/s1/live");
    QTest::newRow("invalid port falls back to 554") << R"({"type":"unv","host":"10.1.1.5","port":70000})"
                                                    << QStringLiteral("rtsp://10.1.1.5:554/unicast/c1/s0/live");
    QTest::newRow("preset without host") << R"({"type":"dahua","username":"admin"})" << QString();
    QTest::newRow("custom sub stream")
        << R"({"type":"custom","uri":"rtsp://h/main","subEnabled":true,"subUri":"rtsp://h/sub","stream":"sub"})"
        << QStringLiteral("rtsp://h/sub");
    QTest::newRow("custom sub stream disabled")
        << R"({"type":"custom","uri":"rtsp://h/main","subEnabled":false,"subUri":"rtsp://h/sub","stream":"sub"})"
        << QStringLiteral("rtsp://h/main");
}

void MultiCameraManagerTest::_testCameraPresetUris()
{
    QFETCH(QString, entryJson);
    QFETCH(QString, expected);

    const QJsonObject entry = QJsonDocument::fromJson(entryJson.toUtf8()).object();
    QCOMPARE(MultiCameraManager::manualStreamUri(entry), expected);
}

void MultiCameraManagerTest::_testPresetCredentialsStayOutOfKeys()
{
    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    MultiCameraManager manager;
    manager.init();

    const QVariantMap entry{
        {QStringLiteral("type"), QStringLiteral("hikvision")},
        {QStringLiteral("host"), QStringLiteral("192.168.1.64")},
        {QStringLiteral("username"), QStringLiteral("admin")},
        {QStringLiteral("password"), QStringLiteral("TopSecret1")},
    };
    QCOMPARE(manager.manualStreamPreview(entry),
             QStringLiteral("rtsp://admin:***@192.168.1.64:554/Streaming/Channels/101"));

    videoSettings->multiCameraStreams()->setRawValue(
        QStringLiteral(R"([{"vehicleId":1,"name":"Front","type":"hikvision","host":"192.168.1.64",)"
                       R"("username":"admin","password":"TopSecret1"}])"));
    videoSettings->multiCameraEnabled()->setRawValue(true);

    QTRY_COMPARE_WITH_TIMEOUT(manager.streams()->count(), 1, kRebuildTimeoutMs);
    const auto* const stream = manager.streams()->value<MultiCameraStream*>(0);
    QVERIFY(stream->uri().contains(QStringLiteral("TopSecret1")));
    QVERIFY(!stream->key().contains(QStringLiteral("TopSecret1")));
    QVERIFY(!stream->label().contains(QStringLiteral("TopSecret1")));
}

void MultiCameraManagerTest::_testLinkCamerasCopied()
{
    const QString cameras = QStringLiteral(R"([{"name":"Front","type":"unv","host":"10.1.1.5"}])");

    UDPConfiguration original(QStringLiteral("Drone 1"));
    QSignalSpy camerasSpy(&original, &LinkConfiguration::camerasChanged);
    original.setCameras(cameras);
    QCOMPARE(camerasSpy.count(), 1);
    original.setCameras(cameras);
    QCOMPARE(camerasSpy.count(), 1);

    // The link dialog edits a duplicate and copies it back on Save.
    const std::unique_ptr<LinkConfiguration> edited(LinkConfiguration::duplicateSettings(&original));
    QVERIFY(edited);
    QCOMPARE(edited->cameras(), cameras);

    UDPConfiguration target(QStringLiteral("Drone 1"));
    target.copyFrom(edited.get());
    QCOMPARE(target.cameras(), cameras);
}

UT_REGISTER_TEST(MultiCameraManagerTest, TestLabel::Unit)
