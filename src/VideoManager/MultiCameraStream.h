#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QSize>
#include <QtCore/QString>
#include <QtCore/QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

class GstCameraAudio;
class QQuickItem;
class VideoReceiver;

/// One video stream shown by MultiCameraManager. Owns its own VideoReceiver, bound to the
/// QML VideoOutput that displays it, so any number of streams can decode side by side.
class MultiCameraStream : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(int vehicleId READ vehicleId CONSTANT)
    Q_PROPERTY(bool fromMavlink READ fromMavlink CONSTANT)
    Q_PROPERTY(QString label READ label NOTIFY labelChanged)
    Q_PROPERTY(QString uri READ uri NOTIFY uriChanged)
    Q_PROPERTY(bool streaming READ streaming NOTIFY streamingChanged)
    Q_PROPERTY(bool decoding READ decoding NOTIFY decodingChanged)
    /// The user is recording this stream. Stays on while the stream is lost: recording continues into a new
    /// file as soon as the stream is back (see recordingPaused).
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    /// Recording is on but waiting for the lost stream to come back.
    Q_PROPERTY(bool recordingPaused READ recordingPaused NOTIFY recordingChanged)
    Q_PROPERTY(QSize videoSize READ videoSize NOTIFY videoSizeChanged)
    /// Camera audio and talkback need an RTSP stream (and GStreamer).
    Q_PROPERTY(bool audioSupported READ audioSupported NOTIFY uriChanged)
    /// The user wants to hear the camera; audioPlaying once its audio actually plays.
    Q_PROPERTY(bool audioEnabled READ audioEnabled WRITE setAudioEnabled NOTIFY audioEnabledChanged)
    Q_PROPERTY(bool audioPlaying READ audioPlaying NOTIFY audioPlayingChanged)
    /// The user wants to talk through the camera's speaker; talkbackActive once the microphone is streaming.
    Q_PROPERTY(bool talkbackEnabled READ talkbackEnabled WRITE setTalkbackEnabled NOTIFY talkbackEnabledChanged)
    Q_PROPERTY(bool talkbackActive READ talkbackActive NOTIFY talkbackActiveChanged)
    /// Vehicle width guide lines configured for this camera (CameraGuidesOverlay settings); empty when none.
    Q_PROPERTY(QVariantMap guides READ guides NOTIFY guidesChanged)
    /// The user's on/off for the guide lines of this stream.
    Q_PROPERTY(bool guidesVisible READ guidesVisible WRITE setGuidesVisible NOTIFY guidesVisibleChanged)

public:
    MultiCameraStream(const QString& key, int vehicleId, bool fromMavlink, QObject* parent = nullptr);
    ~MultiCameraStream() override;

    /// Called by the QML tile once its VideoOutput exists; the receiver is created on demand.
    Q_INVOKABLE void attachVideoOutput(QQuickItem* videoOutput);
    /// Must be called before the VideoOutput is destroyed: the receiver renders into it.
    Q_INVOKABLE void detachVideoOutput(QQuickItem* videoOutput);
    Q_INVOKABLE void startRecording();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void grabImage();

    QString key() const { return _key; }

    int vehicleId() const { return _vehicleId; }

    bool fromMavlink() const { return _fromMavlink; }

    QString label() const { return _label; }

    QString uri() const { return _uri; }

    bool streaming() const { return _streaming; }

    bool decoding() const { return _decoding; }

    bool recording() const { return _recordingWanted; }

    bool recordingPaused() const { return _recordingWanted && !_recording; }

    /// Keep reconnecting after the stream is lost whatever the auto-reconnect setting (preview streams).
    void setAlwaysReconnect(bool always) { _alwaysReconnect = always; }

    QSize videoSize() const { return _videoSize; }

    bool audioSupported() const;

    bool audioEnabled() const { return _audioEnabled; }

    void setAudioEnabled(bool enabled);

    bool audioPlaying() const { return _audioPlaying; }

    bool talkbackEnabled() const { return _talkbackEnabled; }

    void setTalkbackEnabled(bool enabled);

    bool talkbackActive() const { return _talkbackActive; }

    QVariantMap guides() const { return _guides; }

    void setGuides(const QVariantMap& guides);

    bool guidesVisible() const { return _guidesVisible; }

    void setGuidesVisible(bool visible);

    void setLabel(const QString& label);
    void setUri(const QString& uri);
    void setBackendReady(bool ready);
    void restart();
    void stop();
    /// Destroys the receiver and its sink; safe to call repeatedly.
    void releaseReceiver();

signals:
    void labelChanged();
    void uriChanged();
    void streamingChanged();
    void decodingChanged();
    void recordingChanged();
    void videoSizeChanged();
    void audioEnabledChanged();
    void audioPlayingChanged();
    void talkbackEnabledChanged();
    void talkbackActiveChanged();
    void guidesChanged();
    void guidesVisibleChanged();

private:
    void _createReceiver();
    void _updateAudio();
    void _applyTalkbackEnabled(bool enabled);
    void _setAudioPlaying(bool playing);
    void _setTalkbackActive(bool active);
    void _connectReceiver();
    void _startReceiver();
    void _setStreaming(bool streaming);
    void _setDecoding(bool decoding);
    void _setRecording(bool recording);
    void _startRecordingFile();
    void _resumeRecording();
    QString _fileTag() const;

    const QString _key;
    const int _vehicleId;
    const bool _fromMavlink;
    QString _label;
    QString _uri;
    QPointer<QQuickItem> _videoOutput;
    VideoReceiver* _receiver = nullptr;
    void* _sink = nullptr;
    bool _backendReady = false;
    bool _restartPending = false;
    bool _streaming = false;
    bool _decoding = false;
    bool _recording = false;        ///< A file is being written.
    bool _recordingWanted = false;  ///< The user started recording and has not stopped it.
    bool _alwaysReconnect = false;
    QSize _videoSize;

    GstCameraAudio* _audio = nullptr;  ///< Created on first use; only with GStreamer.
    bool _audioEnabled = false;
    bool _audioPlaying = false;
    bool _talkbackEnabled = false;
    bool _talkbackActive = false;
    QVariantMap _guides;
    bool _guidesVisible = true;
};
