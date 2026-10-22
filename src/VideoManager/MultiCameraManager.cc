#include "MultiCameraManager.h"

#include <chrono>

#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QSet>

#include "Fact.h"
#include "MavlinkCameraControlInterface.h"
#include "MultiCameraStream.h"
#include "MultiVehicleManager.h"
#include "QGCCameraManager.h"
#include "QGCLoggingCategory.h"
#include "QGCNetworkHelper.h"
#include "QGCVideoStreamInfo.h"
#include "SettingsManager.h"
#include "Vehicle.h"
#include "VideoSettings.h"

QGC_LOGGING_CATEGORY(MultiCameraManagerLog, "Video.MultiCameraManager")

namespace {

// Camera and stream discovery arrive as bursts of signals; coalesce them into one rebuild.
constexpr std::chrono::milliseconds kRebuildDelay{250};

}  // namespace

MultiCameraManager::MultiCameraManager(QObject* parent)
    : QObject(parent)
    , _videoSettings(SettingsManager::instance()->videoSettings())
{
    _rebuildTimer.setSingleShot(true);
    _rebuildTimer.setInterval(kRebuildDelay);
    (void) connect(&_rebuildTimer, &QTimer::timeout, this, &MultiCameraManager::_rebuild);
}

MultiCameraManager::~MultiCameraManager()
{
    cleanup();
}

void MultiCameraManager::init()
{
    if (_initialized) {
        return;
    }
    _initialized = true;

    (void) connect(_videoSettings->multiCameraEnabled(), &Fact::rawValueChanged, this, [this]() {
        emit enabledChanged();
        _scheduleRebuild();
    });
    (void) connect(_videoSettings->multiCameraStreams(), &Fact::rawValueChanged, this,
                   &MultiCameraManager::_scheduleRebuild);
    (void) connect(_videoSettings->multiCameraMaxStreams(), &Fact::rawValueChanged, this,
                   &MultiCameraManager::_scheduleRebuild);

    MultiVehicleManager* const multiVehicleManager = MultiVehicleManager::instance();
    (void) connect(multiVehicleManager, &MultiVehicleManager::vehicleAdded, this, &MultiCameraManager::_vehicleAdded);
    (void) connect(multiVehicleManager, &MultiVehicleManager::vehicleRemoved, this,
                   &MultiCameraManager::_scheduleRebuild);

    QmlObjectListModel* const vehicles = multiVehicleManager->vehicles();
    for (int i = 0; i < vehicles->count(); i++) {
        _vehicleAdded(vehicles->value<Vehicle*>(i));
    }

    _scheduleRebuild();
}

void MultiCameraManager::setBackendReady()
{
    if (_backendReady) {
        return;
    }

    _backendReady = true;
    for (int i = 0; i < _streams.count(); i++) {
        _streams.value<MultiCameraStream*>(i)->setBackendReady(true);
    }
}

void MultiCameraManager::cleanup()
{
    _rebuildTimer.stop();
    _backendReady = false;
    while (_streams.count() > 0) {
        _removeStream(_streams.value<MultiCameraStream*>(_streams.count() - 1));
    }
}

bool MultiCameraManager::enabled() const
{
    return _videoSettings->multiCameraEnabled()->rawValue().toBool();
}

int MultiCameraManager::mainIndex() const
{
    for (int i = 0; i < _streams.count(); i++) {
        if (_streams.value<MultiCameraStream*>(i)->key() == _mainKey) {
            return i;
        }
    }
    return _streams.count() > 0 ? 0 : -1;
}

void MultiCameraManager::setMainIndex(int index)
{
    if ((index < 0) || (index >= _streams.count())) {
        return;
    }

    const QString key = _streams.value<MultiCameraStream*>(index)->key();
    if (key != _mainKey) {
        _mainKey = key;
        emit mainIndexChanged();
    }
}

MultiCameraStream* MultiCameraManager::mainStream() const
{
    const int index = mainIndex();
    return (index >= 0) ? _streams.value<MultiCameraStream*>(index) : nullptr;
}

void MultiCameraManager::stopAll()
{
    for (int i = 0; i < _streams.count(); i++) {
        _streams.value<MultiCameraStream*>(i)->stop();
    }
}

void MultiCameraManager::restartAll()
{
    for (int i = 0; i < _streams.count(); i++) {
        _streams.value<MultiCameraStream*>(i)->restart();
    }
}

QString MultiCameraManager::uriForStreamInfo(const QGCVideoStreamInfo* info)
{
    if (!info || info->uri().isEmpty()) {
        return QString();
    }

    const QString uri = info->uri();
    switch (info->type()) {
        case VIDEO_STREAM_TYPE_RTSP:
        case VIDEO_STREAM_TYPE_TCP_MPEG:
            return uri;
        case VIDEO_STREAM_TYPE_RTPUDP:
            if (info->encoding() == VIDEO_STREAM_ENCODING_H265) {
                return uri.contains(QStringLiteral("udp265://")) ? uri : QStringLiteral("udp265://0.0.0.0:%1").arg(uri);
            }
            return uri.contains(QStringLiteral("udp://")) ? uri : QStringLiteral("udp://0.0.0.0:%1").arg(uri);
        case VIDEO_STREAM_TYPE_MPEG_TS:
            return uri.contains(QStringLiteral("mpegts://")) ? uri : QStringLiteral("mpegts://0.0.0.0:%1").arg(uri);
        default:
            qCWarning(MultiCameraManagerLog) << "Unknown VIDEO_STREAM_TYPE" << info->type();
            return QString();
    }
}

void MultiCameraManager::_scheduleRebuild()
{
    _rebuildTimer.start();
}

void MultiCameraManager::_vehicleAdded(Vehicle* vehicle)
{
    if (!vehicle) {
        return;
    }

    const auto connectCameraManager = [this, vehicle]() {
        QGCCameraManager* const cameraManager = vehicle->cameraManager();
        if (!cameraManager) {
            return;
        }
        (void) connect(cameraManager, &QGCCameraManager::camerasChanged, this, &MultiCameraManager::_scheduleRebuild,
                       Qt::UniqueConnection);
        (void) connect(cameraManager, &QGCCameraManager::streamChanged, this, &MultiCameraManager::_scheduleRebuild,
                       Qt::UniqueConnection);
    };

    connectCameraManager();
    (void) connect(vehicle, &Vehicle::cameraManagerChanged, this, [this, connectCameraManager]() {
        connectCameraManager();
        _scheduleRebuild();
    });

    _scheduleRebuild();
}

void MultiCameraManager::_appendManualStreams(QList<StreamSpec>& specs) const
{
    const QByteArray json = _videoSettings->multiCameraStreams()->rawValue().toString().toUtf8();
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(json, &error);
    if (!doc.isArray()) {
        if (!json.trimmed().isEmpty()) {
            qCWarning(MultiCameraManagerLog) << "multiCameraStreams is not a JSON array:" << error.errorString();
        }
        return;
    }

    const QJsonArray entries = doc.array();
    for (const QJsonValue& value : entries) {
        const QJsonObject entry = value.toObject();
        const QString uri = entry.value(QStringLiteral("uri")).toString().trimmed();
        if (uri.isEmpty()) {
            continue;
        }

        const int vehicleId = entry.value(QStringLiteral("vehicleId")).toInt();
        QString name = entry.value(QStringLiteral("name")).toString().trimmed();
        if (name.isEmpty()) {
            name = QGCNetworkHelper::redactedUrlForLogging(uri);
        }

        StreamSpec spec;
        spec.key = QStringLiteral("manual:%1:%2").arg(vehicleId).arg(uri);
        spec.label = (vehicleId > 0) ? tr("Vehicle %1 · %2").arg(vehicleId).arg(name) : name;
        spec.uri = uri;
        spec.vehicleId = vehicleId;
        specs.append(spec);
    }
}

void MultiCameraManager::_appendMavlinkStreams(QList<StreamSpec>& specs)
{
    QmlObjectListModel* const vehicles = MultiVehicleManager::instance()->vehicles();
    for (int vehicleIndex = 0; vehicleIndex < vehicles->count(); vehicleIndex++) {
        Vehicle* const vehicle = vehicles->value<Vehicle*>(vehicleIndex);
        if (!vehicle) {
            continue;
        }
        QGCCameraManager* const cameraManager = vehicle->cameraManager();
        if (!cameraManager) {
            continue;
        }

        const QmlObjectListModel* const cameras = cameraManager->cameras();
        for (int cameraIndex = 0; cameraIndex < cameras->count(); cameraIndex++) {
            auto* const camera = cameras->value<MavlinkCameraControlInterface*>(cameraIndex);
            if (!camera) {
                continue;
            }
            (void) connect(camera, &MavlinkCameraControlInterface::streamsChanged, this,
                           &MultiCameraManager::_scheduleRebuild, Qt::UniqueConnection);
            (void) connect(camera, &MavlinkCameraControlInterface::thermalStreamChanged, this,
                           &MultiCameraManager::_scheduleRebuild, Qt::UniqueConnection);

            QmlObjectListModel* const cameraStreams = camera->streams();
            if (!cameraStreams) {
                continue;
            }
            for (int streamIndex = 0; streamIndex < cameraStreams->count(); streamIndex++) {
                const auto* const info = cameraStreams->value<QGCVideoStreamInfo*>(streamIndex);
                const QString uri = uriForStreamInfo(info);
                if (uri.isEmpty()) {
                    continue;
                }

                const QString name = !info->name().isEmpty() ? info->name() : camera->modelName();
                StreamSpec spec;
                spec.key =
                    QStringLiteral("mavlink:%1:%2:%3").arg(vehicle->id()).arg(camera->compID()).arg(info->streamID());
                spec.label = tr("Vehicle %1 · %2").arg(vehicle->id()).arg(name);
                spec.uri = uri;
                spec.vehicleId = static_cast<int>(vehicle->id());
                spec.compId = camera->compID();
                spec.streamId = info->streamID();
                spec.fromMavlink = true;
                specs.append(spec);
            }
        }
    }
}

QList<MultiCameraManager::StreamSpec> MultiCameraManager::_collectStreams()
{
    QList<StreamSpec> candidates;
    _appendManualStreams(candidates);
    _appendMavlinkStreams(candidates);

    const int maxStreams = qMax(1, _videoSettings->multiCameraMaxStreams()->rawValue().toInt());
    QList<StreamSpec> result;
    QSet<QString> usedUris;
    for (const StreamSpec& spec : std::as_const(candidates)) {
        // Two receivers on one UDP port or RTSP session would fight; the manual entry wins.
        if (usedUris.contains(spec.uri)) {
            continue;
        }
        if (result.count() >= maxStreams) {
            qCWarning(MultiCameraManagerLog) << "Stream limit" << maxStreams << "reached, skipping" << spec.label;
            continue;
        }
        usedUris.insert(spec.uri);
        result.append(spec);
    }
    return result;
}

MultiCameraStream* MultiCameraManager::_findStream(const QString& key) const
{
    for (int i = 0; i < _streams.count(); i++) {
        MultiCameraStream* const stream = _streams.value<MultiCameraStream*>(i);
        if (stream->key() == key) {
            return stream;
        }
    }
    return nullptr;
}

void MultiCameraManager::_removeStream(MultiCameraStream* stream)
{
    if (!stream) {
        return;
    }

    // Release the receiver while its VideoOutput still exists; removing the model row destroys the tile.
    stream->releaseReceiver();
    (void) _streams.removeOne(stream);
    stream->deleteLater();
}

void MultiCameraManager::_requestMavlinkStreamStart(const StreamSpec& spec) const
{
    QmlObjectListModel* const vehicles = MultiVehicleManager::instance()->vehicles();
    for (int i = 0; i < vehicles->count(); i++) {
        Vehicle* const vehicle = vehicles->value<Vehicle*>(i);
        if (vehicle && (static_cast<int>(vehicle->id()) == spec.vehicleId)) {
            vehicle->sendMavCommand(spec.compId, MAV_CMD_VIDEO_START_STREAMING, false,
                                    static_cast<float>(spec.streamId));
            return;
        }
    }
}

void MultiCameraManager::_rebuild()
{
    const QList<StreamSpec> specs = enabled() ? _collectStreams() : QList<StreamSpec>();
    const int oldMainIndex = mainIndex();
    bool changed = false;

    QSet<QString> wantedKeys;
    for (const StreamSpec& spec : specs) {
        wantedKeys.insert(spec.key);
    }
    for (int i = _streams.count() - 1; i >= 0; i--) {
        MultiCameraStream* const stream = _streams.value<MultiCameraStream*>(i);
        if (!wantedKeys.contains(stream->key())) {
            qCDebug(MultiCameraManagerLog) << "Removing stream" << stream->key();
            _removeStream(stream);
            changed = true;
        }
    }

    for (const StreamSpec& spec : specs) {
        MultiCameraStream* stream = _findStream(spec.key);
        if (!stream) {
            qCDebug(MultiCameraManagerLog)
                << "Adding stream" << spec.key << QGCNetworkHelper::redactedUrlForLogging(spec.uri);
            stream = new MultiCameraStream(spec.key, spec.vehicleId, spec.fromMavlink, this);
            stream->setLabel(spec.label);
            stream->setUri(spec.uri);
            stream->setBackendReady(_backendReady);
            _streams.append(stream);
            if (spec.fromMavlink) {
                _requestMavlinkStreamStart(spec);
            }
            changed = true;
        } else {
            stream->setLabel(spec.label);
            stream->setUri(spec.uri);
        }
    }

    if (changed || (mainIndex() != oldMainIndex)) {
        emit mainIndexChanged();
    }
}
