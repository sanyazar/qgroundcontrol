#include "MultiCameraStream.h"

#include <chrono>

#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QRegularExpression>
#include <QtCore/QTimer>
#include <QtQuick/QQuickItem>
#if QT_CONFIG(permissions)
#include <QtCore/QPermissions>
#endif

#include "AppMessages.h"
#include "AppSettings.h"
#include "Fact.h"
#include "QGCCorePlugin.h"
#include "QGCLoggingCategory.h"
#include "QGCNetworkHelper.h"
#include "SettingsManager.h"
#include "VideoBackend.h"
#include "VideoManager.h"
#include "VideoReceiver.h"
#include "VideoSettings.h"
#ifdef QGC_GST_STREAMING
#include "GstCameraAudio.h"
#endif

QGC_LOGGING_CATEGORY(MultiCameraStreamLog, "Video.MultiCameraStream")

namespace {

// Stall timeout for every source but RTSP, whose timeout is a setting (matches VideoManager).
constexpr uint32_t kDefaultStreamTimeoutSec = 3;
constexpr std::chrono::seconds kRestartDelay{1};

}  // namespace

MultiCameraStream::MultiCameraStream(const QString& key, int vehicleId, bool fromMavlink, QObject* parent)
    : QObject(parent)
    , _key(key)
    , _vehicleId(vehicleId)
    , _fromMavlink(fromMavlink)
{
    qCDebug(MultiCameraStreamLog) << _key;
}

MultiCameraStream::~MultiCameraStream()
{
    releaseReceiver();
}

void MultiCameraStream::setLabel(const QString& label)
{
    if (label != _label) {
        _label = label;
        emit labelChanged();
    }
}

void MultiCameraStream::setUri(const QString& uri)
{
    if (uri == _uri) {
        return;
    }

    _uri = uri;
    emit uriChanged();
    _updateAudio();

    if (_receiver) {
        _receiver->setUri(_uri);
        restart();
    }
}

void MultiCameraStream::setBackendReady(bool ready)
{
    if (ready == _backendReady) {
        return;
    }

    _backendReady = ready;
    if (_backendReady) {
        _createReceiver();
    } else {
        releaseReceiver();
    }
}

void MultiCameraStream::attachVideoOutput(QQuickItem* videoOutput)
{
    if (!videoOutput) {
        qCWarning(MultiCameraStreamLog) << "null VideoOutput for" << _key;
        return;
    }
    if (videoOutput == _videoOutput) {
        return;
    }

    releaseReceiver();
    _videoOutput = videoOutput;
    _createReceiver();
}

void MultiCameraStream::detachVideoOutput(QQuickItem* videoOutput)
{
    if (!videoOutput || (videoOutput != _videoOutput)) {
        return;
    }

    releaseReceiver();
    _videoOutput.clear();
}

void MultiCameraStream::_createReceiver()
{
    if (_receiver || !_backendReady || !_videoOutput) {
        return;
    }

    QGCCorePlugin* const plugin = QGCCorePlugin::instance();
    VideoReceiver* const receiver = plugin->createVideoReceiver(this);
    if (!receiver) {
        qCWarning(MultiCameraStreamLog) << "createVideoReceiver() failed" << _key;
        return;
    }

    receiver->setName(_key);
    receiver->setWidget(_videoOutput);

    void* const sink = plugin->createVideoSink(_videoOutput, receiver);
    if (!sink) {
        qCWarning(MultiCameraStreamLog) << "createVideoSink() failed" << _key;
        delete receiver;
        return;
    }

    _receiver = receiver;
    _sink = sink;
    _receiver->setSink(_sink);
    VideoBackend::attachSink(_receiver, _sink, _videoOutput);

    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    _receiver->setLowLatency(videoSettings->lowLatencyMode()->rawValue().toBool());
    _receiver->setRtpJitterLatencyMs(videoSettings->rtpJitterLatencyMs()->rawValue().toInt());
    _receiver->setAutoReconnect(videoSettings->rtspAutoReconnect()->rawValue().toBool());
    _receiver->setUri(_uri);

    _connectReceiver();
    _startReceiver();
}

void MultiCameraStream::_connectReceiver()
{
    // The receiver is the context so calls queued from its worker thread are dropped when it is deleted.
    VideoReceiver* const receiver = _receiver;

    (void) connect(receiver, &VideoReceiver::onStartComplete, receiver, [this, receiver](VideoReceiver::STATUS status) {
        qCDebug(MultiCameraStreamLog) << _key << "start complete, status:" << status;
        if (status == VideoReceiver::STATUS_OK) {
            receiver->setStarted(true);
            if (receiver->sink()) {
                receiver->startDecoding(receiver->sink());
            }
        }
    });

    (void) connect(receiver, &VideoReceiver::onStopComplete, receiver, [this, receiver](VideoReceiver::STATUS status) {
        qCDebug(MultiCameraStreamLog) << _key << "stop complete, status:" << status;
        receiver->setStarted(false);
        if (!_restartPending) {
            return;
        }
        _restartPending = false;
        if (status == VideoReceiver::STATUS_INVALID_URL) {
            qCDebug(MultiCameraStreamLog) << _key << "invalid URL, not restarting";
            return;
        }
        QTimer::singleShot(kRestartDelay, receiver, [this]() { _startReceiver(); });
    });

    (void) connect(receiver, &VideoReceiver::streamingChanged, receiver,
                   [this](bool active) { _setStreaming(active); });

    (void) connect(receiver, &VideoReceiver::decodingChanged, receiver, [this](bool active) { _setDecoding(active); });

    (void) connect(receiver, &VideoReceiver::recordingChanged, receiver,
                   [this](bool active) { _setRecording(active); });

    (void) connect(receiver, &VideoReceiver::videoSizeChanged, receiver, [this](QSize size) {
        if (size != _videoSize) {
            _videoSize = size;
            emit videoSizeChanged();
        }
    });

    (void) connect(receiver, &VideoReceiver::onTakeScreenshotComplete, receiver, [this](VideoReceiver::STATUS status) {
        if (status != VideoReceiver::STATUS_OK) {
            qCWarning(MultiCameraStreamLog) << _key << "screenshot failed";
        }
    });
}

void MultiCameraStream::_startReceiver()
{
    if (!_receiver || _receiver->started() || _uri.isEmpty()) {
        return;
    }

    const bool isRtsp = _uri.startsWith(QStringLiteral("rtsp://"), Qt::CaseInsensitive) ||
                        _uri.startsWith(QStringLiteral("rtsps://"), Qt::CaseInsensitive);
    const uint32_t timeout = isRtsp ? SettingsManager::instance()->videoSettings()->rtspTimeout()->rawValue().toUInt()
                                    : kDefaultStreamTimeoutSec;

    qCDebug(MultiCameraStreamLog) << _key << "starting" << QGCNetworkHelper::redactedUrlForLogging(_uri);
    _receiver->start(timeout);
}

void MultiCameraStream::restart()
{
    if (!_receiver) {
        _createReceiver();
        return;
    }

    if (_receiver->started()) {
        // Set before stop(): a receiver may complete the stop synchronously.
        _restartPending = true;
        _receiver->stop();
    } else {
        _startReceiver();
    }
}

void MultiCameraStream::stop()
{
    _restartPending = false;
    if (_receiver) {
        _receiver->stop();
    }
}

void MultiCameraStream::releaseReceiver()
{
    _restartPending = false;

    VideoReceiver* const receiver = _receiver;
    void* const sink = _sink;
    _receiver = nullptr;
    _sink = nullptr;

    if (receiver) {
        if (receiver->started()) {
            receiver->stopRecording();
        }
        QGCCorePlugin::instance()->releaseVideoSink(sink);
        delete receiver;
    }

    _setStreaming(false);
    _setDecoding(false);
    _setRecording(false);
}

QString MultiCameraStream::_fileTag() const
{
    static const QRegularExpression unsafe(QStringLiteral("[^A-Za-z0-9_-]+"));
    QString tag = _label.isEmpty() ? _key : _label;
    tag.replace(unsafe, QStringLiteral("_"));
    return tag;
}

void MultiCameraStream::startRecording()
{
    if (!_receiver || !_receiver->started()) {
        QGC::showAppMessage(tr("Unable to record %1: video stream is not running.").arg(_label));
        return;
    }

    VideoSettings* const videoSettings = SettingsManager::instance()->videoSettings();
    const auto fileFormat =
        static_cast<VideoReceiver::FILE_FORMAT>(videoSettings->recordingFormat()->rawValue().toInt());
    if (!VideoReceiver::isValidFileFormat(fileFormat)) {
        QGC::showAppMessage(tr("Invalid video format defined."));
        return;
    }

    const QString savePath = SettingsManager::instance()->appSettings()->videoSavePath();
    if (savePath.isEmpty()) {
        QGC::showAppMessage(tr("Unable to record video. Video save path must be specified in Settings."));
        return;
    }

    VideoManager::cleanupOldVideos();

    const QString fileName =
        QStringLiteral("%1/%2.%3.%4")
            .arg(savePath, QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_hh.mm.ss")), _fileTag(),
                 VideoManager::recordingFileExtension(fileFormat));
    qCDebug(MultiCameraStreamLog) << _key << "recording to" << fileName;
    _receiver->startRecording(fileName, fileFormat);
}

void MultiCameraStream::stopRecording()
{
    if (_receiver) {
        _receiver->stopRecording();
    }
}

void MultiCameraStream::grabImage()
{
    if (!_receiver || !_decoding) {
        QGC::showAppMessage(tr("Unable to take a photo of %1: no video.").arg(_label));
        return;
    }

    const QString savePath = SettingsManager::instance()->appSettings()->photoSavePath();
    const QString fileName =
        QStringLiteral("%1/%2.%3.jpg")
            .arg(savePath, QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_hh.mm.ss.zzz")),
                 _fileTag());
    _receiver->takeScreenshot(fileName);
}

void MultiCameraStream::_setStreaming(bool streaming)
{
    if (streaming != _streaming) {
        _streaming = streaming;
        emit streamingChanged();
    }
}

void MultiCameraStream::_setDecoding(bool decoding)
{
    if (decoding != _decoding) {
        _decoding = decoding;
        emit decodingChanged();
    }
}

void MultiCameraStream::_setRecording(bool recording)
{
    if (recording != _recording) {
        _recording = recording;
        emit recordingChanged();
    }
}

bool MultiCameraStream::audioSupported() const
{
#ifdef QGC_GST_STREAMING
    return _uri.startsWith(QStringLiteral("rtsp://"), Qt::CaseInsensitive) ||
           _uri.startsWith(QStringLiteral("rtsps://"), Qt::CaseInsensitive);
#else
    return false;
#endif
}

void MultiCameraStream::setAudioEnabled(bool enabled)
{
    if (enabled == _audioEnabled) {
        return;
    }
    _audioEnabled = enabled;
    emit audioEnabledChanged();
    _updateAudio();
}

void MultiCameraStream::setTalkbackEnabled(bool enabled)
{
    if (enabled == _talkbackEnabled) {
        return;
    }

#if QT_CONFIG(permissions)
    if (enabled) {
        const QMicrophonePermission microphone;
        switch (qApp->checkPermission(microphone)) {
            case Qt::PermissionStatus::Granted:
                break;
            case Qt::PermissionStatus::Undetermined:
                qApp->requestPermission(microphone, this, [this](const QPermission& permission) {
                    if (permission.status() == Qt::PermissionStatus::Granted) {
                        _applyTalkbackEnabled(true);
                    } else {
                        QGC::showAppMessage(tr("Microphone access was denied."));
                    }
                });
                return;
            case Qt::PermissionStatus::Denied:
                QGC::showAppMessage(tr("Microphone access is denied; allow it in the system settings."));
                return;
        }
    }
#endif
    _applyTalkbackEnabled(enabled);
}

void MultiCameraStream::_applyTalkbackEnabled(bool enabled)
{
    if (enabled == _talkbackEnabled) {
        return;
    }
    _talkbackEnabled = enabled;
    emit talkbackEnabledChanged();
    _updateAudio();
}

void MultiCameraStream::_updateAudio()
{
#ifdef QGC_GST_STREAMING
    const bool wanted = audioSupported() && (_audioEnabled || _talkbackEnabled);
    if (!wanted) {
        if (_audio) {
            _audio->stop();
        }
        return;
    }

    if (!_audio) {
        _audio = new GstCameraAudio(this);
        (void) connect(_audio, &GstCameraAudio::audioPlayingChanged, this,
                       [this](bool playing) { _setAudioPlaying(playing); });
        (void) connect(_audio, &GstCameraAudio::talkbackActiveChanged, this,
                       [this](bool active) { _setTalkbackActive(active); });
        (void) connect(_audio, &GstCameraAudio::failed, this, [this](const QString& reason) {
            qCWarning(MultiCameraStreamLog) << _key << "audio failed:" << reason;
            QGC::showAppMessage(tr("%1: %2").arg(_label, reason));
            // Off again, so the buttons show what is really happening; the user can retry.
            if (_audioEnabled) {
                _audioEnabled = false;
                emit audioEnabledChanged();
            }
            if (_talkbackEnabled) {
                _talkbackEnabled = false;
                emit talkbackEnabledChanged();
            }
        });
    }
    _audio->configure(_uri, _audioEnabled, _talkbackEnabled);
#else
    if (_audioEnabled || _talkbackEnabled) {
        QGC::showAppMessage(tr("Camera audio needs GStreamer video streaming."));
    }
#endif
}

void MultiCameraStream::_setAudioPlaying(bool playing)
{
    if (playing != _audioPlaying) {
        _audioPlaying = playing;
        emit audioPlayingChanged();
    }
}

void MultiCameraStream::_setTalkbackActive(bool active)
{
    if (active != _talkbackActive) {
        _talkbackActive = active;
        emit talkbackActiveChanged();
    }
}
