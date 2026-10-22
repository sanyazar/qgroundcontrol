#include "MultiCameraManagerTest.h"

#include <cstring>

#include <QtCore/QRegularExpression>

#include "Fact.h"
#include "MultiCameraManager.h"
#include "MultiCameraStream.h"
#include "QGCVideoStreamInfo.h"
#include "SettingsManager.h"
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

UT_REGISTER_TEST(MultiCameraManagerTest, TestLabel::Unit)
