#pragma once

#include <memory>

#include <QtCore/QObject>
#include <QtCore/QString>

/// Audio of one RTSP camera, kept apart from its video receiver: plays the camera's audio track and/or sends
/// the computer's microphone to the camera's speaker over the ONVIF RTSP backchannel (G.711, which Dahua,
/// Uniview and most ONVIF Profile T cameras accept). It opens its own RTSP session that sets up only the audio
/// streams, so the video pipeline is never touched and the audio can be switched on and off at any time.
///
/// All methods and signals are on the GUI thread.
class GstCameraAudio : public QObject
{
    Q_OBJECT

public:
    explicit GstCameraAudio(QObject* parent = nullptr);
    ~GstCameraAudio() override;

    /// (Re)starts the session for @p uri with the requested directions; stops it when both are false.
    void configure(const QString& uri, bool playAudio, bool talkback);
    void stop();

    bool audioPlaying() const { return _audioPlaying; }

    bool talkbackActive() const { return _talkbackActive; }

    /// Implementation detail shared with the GStreamer callbacks in the .cc file.
    struct Session;

signals:
    void audioPlayingChanged(bool playing);
    void talkbackActiveChanged(bool active);
    /// The session stopped because a requested direction failed; @p reason is user-facing.
    void failed(const QString& reason);

private:
    void _onPipelinePlaying(quint64 generation);
    void _onDecodedAudio(quint64 generation);
    void _onError(quint64 generation, const QString& reason);
    void _startMicrophone();
    void _fail(const QString& reason);
    void _setAudioPlaying(bool playing);
    void _setTalkbackActive(bool active);

    std::unique_ptr<Session> _session;
    quint64 _generation = 0;  ///< Bumped per session so queued callbacks of a stopped session are ignored.
    bool _audioPlaying = false;
    bool _talkbackActive = false;
};
