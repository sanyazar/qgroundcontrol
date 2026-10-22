#pragma once

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QSize>
#include <QtCore/QString>
#include <QtQmlIntegration/QtQmlIntegration>

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
    Q_PROPERTY(bool recording READ recording NOTIFY recordingChanged)
    Q_PROPERTY(QSize videoSize READ videoSize NOTIFY videoSizeChanged)

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

    bool recording() const { return _recording; }

    QSize videoSize() const { return _videoSize; }

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

private:
    void _createReceiver();
    void _connectReceiver();
    void _startReceiver();
    void _setStreaming(bool streaming);
    void _setDecoding(bool decoding);
    void _setRecording(bool recording);
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
    bool _recording = false;
    QSize _videoSize;
};
