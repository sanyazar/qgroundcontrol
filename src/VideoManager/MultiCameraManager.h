#pragma once

#include <QtCore/QJsonObject>
#include <QtCore/QObject>
#include <QtCore/QTimer>
#include <QtCore/QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

#include "QmlObjectListModel.h"

class MultiCameraStream;
class QGCVideoStreamInfo;
class Vehicle;
class VideoSettings;

/// Shows several video streams at once: manually configured URLs plus every stream reported by
/// MAVLink cameras on every connected vehicle. One stream is "main", the rest are thumbnails.
/// While enabled, VideoManager's single-stream receivers stay stopped so the two never fight
/// over the same UDP port or RTSP session.
class MultiCameraManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    Q_MOC_INCLUDE("MultiCameraStream.h")

    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)
    Q_PROPERTY(QmlObjectListModel* streams READ streams CONSTANT)
    Q_PROPERTY(int mainIndex READ mainIndex WRITE setMainIndex NOTIFY mainIndexChanged)
    Q_PROPERTY(MultiCameraStream* mainStream READ mainStream NOTIFY mainIndexChanged)

public:
    explicit MultiCameraManager(QObject* parent = nullptr);
    ~MultiCameraManager() override;

    /// Stops every stream, e.g. while the video window moves between windows.
    Q_INVOKABLE void stopAll();
    Q_INVOKABLE void restartAll();

    void init();
    /// Called by VideoManager once the video backend can create receivers.
    void setBackendReady();
    /// Receivers must be destroyed before QCoreApplication goes away (see VideoManager::cleanup).
    void cleanup();

    bool enabled() const;

    QmlObjectListModel* streams() { return &_streams; }

    int mainIndex() const;
    void setMainIndex(int index);
    MultiCameraStream* mainStream() const;

    /// Receiver URI for a MAVLink VIDEO_STREAM_INFORMATION, in the same form VideoManager uses.
    static QString uriForStreamInfo(const QGCVideoStreamInfo* info);

    /// Receiver URI for one manual stream entry: its "uri" for type "custom" (or no type), otherwise
    /// the RTSP URL of a camera preset ("dahua", "hikvision", "unv") built from host, port, username,
    /// password, channel and stream ("main"/"sub"). Empty when the entry is incomplete.
    static QString manualStreamUri(const QJsonObject& entry);
    /// manualStreamUri() with the password masked, for showing in the settings page.
    Q_INVOKABLE QString manualStreamPreview(const QVariantMap& entry) const;

signals:
    void enabledChanged();
    void mainIndexChanged();

private slots:
    void _scheduleRebuild();
    void _vehicleAdded(Vehicle* vehicle);

private:
    struct StreamSpec
    {
        QString key;
        QString label;
        QString uri;
        int vehicleId = 0;
        int compId = 0;
        int streamId = 0;
        bool fromMavlink = false;
    };

    QList<StreamSpec> _collectStreams();
    void _appendLinkStreams(QList<StreamSpec>& specs);
    void _appendManualStreams(QList<StreamSpec>& specs) const;
    void _appendMavlinkStreams(QList<StreamSpec>& specs);
    void _rebuild();
    void _removeStream(MultiCameraStream* stream);
    MultiCameraStream* _findStream(const QString& key) const;
    void _requestMavlinkStreamStart(const StreamSpec& spec) const;

    VideoSettings* _videoSettings = nullptr;
    QmlObjectListModel _streams;
    QTimer _rebuildTimer;
    QString _mainKey;
    bool _backendReady = false;
    bool _initialized = false;
};
