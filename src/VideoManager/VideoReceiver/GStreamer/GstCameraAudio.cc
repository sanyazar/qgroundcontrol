#include "GstCameraAudio.h"

#include <atomic>
#include <gst/gst.h>
#include <gst/rtsp/gstrtsptransport.h>

#include <QtCore/QByteArray>
#include <QtCore/QMetaObject>
#include <QtCore/QMutex>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QUrl>

#include "GstScoped.h"
#include "QGCLoggingCategory.h"
#include "QGCNetworkHelper.h"

QGC_LOGGING_CATEGORY(GstCameraAudioLog, "Video.GStreamer.GstCameraAudio")

using namespace GStreamer;

namespace {

constexpr guint kAudioLatencyMs = 200;
constexpr guint64 kRtspTcpTimeoutUs = G_GUINT64_CONSTANT(5000000);
constexpr int kNoAudioTimeoutMs = 8000;
/// One G.711 RTP packet per 20 ms, the packetization cameras expect on the backchannel.
constexpr gint64 kBackchannelPtimeNs = 20 * GST_MSECOND;

bool isAudioMedia(const GstStructure* structure)
{
    return g_strcmp0(gst_structure_get_string(structure, "media"), "audio") == 0;
}

/// Before 1.22.1 the backchannel takes the sample through "push-backchannel-buffer", which consumes the
/// caller's reference; "push-backchannel-sample" (1.22, with its handler fixed in 1.22.1) does not.
bool useSampleSignal(GstElement* rtspsrc)
{
    guint major = 0;
    guint minor = 0;
    guint micro = 0;
    guint nano = 0;
    gst_version(&major, &minor, &micro, &nano);
    const bool fixed = (major > 1) || (minor > 22) || ((minor == 22) && (micro >= 1));
    return fixed && (g_signal_lookup("push-backchannel-sample", G_OBJECT_TYPE(rtspsrc)) != 0);
}

}  // namespace

/// State shared with GStreamer's streaming threads. Created and destroyed on the GUI thread; the pipelines are
/// set to NULL (which joins their threads) before it is freed, so callbacks never outlive it.
struct GstCameraAudio::Session
{
    QPointer<GstCameraAudio> owner;
    quint64 generation = 0;
    bool playAudio = false;
    bool talkback = false;

    GstElement* pipeline = nullptr;     ///< Owned: rtspsrc and the playback branch.
    GstElement* rtspsrc = nullptr;      ///< Borrowed from pipeline.
    GstElement* micPipeline = nullptr;  ///< Owned: microphone -> G.711 RTP -> appsink.

    std::atomic<bool> audioSelected{false};
    std::atomic<int> backchannelId{-1};
    bool sampleSignal = false;

    QMutex mutex;  ///< Guards the backchannel description below, written on rtspsrc's thread.
    QByteArray backchannelEncoding;
    int backchannelClockRate = 8000;
    int backchannelPayload = 0;

    // Called on streaming threads: hand the event to the GUI thread, where a stopped session's events are
    // ignored (the owner's generation has moved on).
    void postPlaying()
    {
        post([](GstCameraAudio* target, quint64 gen) { target->_onPipelinePlaying(gen); });
    }

    void postDecodedAudio()
    {
        post([](GstCameraAudio* target, quint64 gen) { target->_onDecodedAudio(gen); });
    }

    void postError(const QString& reason)
    {
        post([reason](GstCameraAudio* target, quint64 gen) { target->_onError(gen, reason); });
    }

    template <typename Function>
    void post(Function function)
    {
        GstCameraAudio* const target = owner.data();
        if (!target) {
            return;
        }
        const quint64 gen = generation;
        (void) QMetaObject::invokeMethod(
            target, [target, gen, function]() { function(target, gen); }, Qt::QueuedConnection);
    }

    void teardown()
    {
        if (micPipeline) {
            (void) gst_element_set_state(micPipeline, GST_STATE_NULL);
            gst_object_unref(micPipeline);
            micPipeline = nullptr;
        }
        if (pipeline) {
            (void) gst_element_set_state(pipeline, GST_STATE_NULL);
            const GstBusPtr bus = adoptBus(gst_element_get_bus(pipeline));
            if (bus) {
                gst_bus_set_sync_handler(bus.get(), nullptr, nullptr, nullptr);
            }
            gst_object_unref(pipeline);
            pipeline = nullptr;
            rtspsrc = nullptr;
        }
    }
};

namespace {

using Session = GstCameraAudio::Session;

// Runs before SETUP for every stream in the camera's SDP: video is left to the video receiver, the first
// audio stream is played when asked for, and the ONVIF backchannel (an audio stream marked sendonly) is set up
// for the microphone when asked for.
gboolean selectStream([[maybe_unused]] GstElement* rtspsrc, guint num, GstCaps* caps, gpointer data)
{
    auto* const session = static_cast<Session*>(data);
    if (!caps || (gst_caps_get_size(caps) == 0)) {
        return FALSE;
    }

    const GstStructure* const structure = gst_caps_get_structure(caps, 0);
    if (!isAudioMedia(structure)) {
        return FALSE;
    }

    if (gst_structure_has_field(structure, "a-sendonly")) {
        if (!session->talkback || (session->backchannelId.load() >= 0)) {
            return FALSE;
        }
        const char* const encoding = gst_structure_get_string(structure, "encoding-name");
        int clockRate = 8000;
        int payload = 0;
        (void) gst_structure_get_int(structure, "clock-rate", &clockRate);
        (void) gst_structure_get_int(structure, "payload", &payload);
        const QByteArray name = QByteArray(encoding ? encoding : "").toUpper();
        {
            QMutexLocker lock(&session->mutex);
            session->backchannelEncoding = name;
            session->backchannelClockRate = clockRate;
            session->backchannelPayload = payload;
        }
        if ((name != "PCMU") && (name != "PCMA")) {
            qCDebug(GstCameraAudioLog) << "Unsupported backchannel encoding" << name;
            return FALSE;
        }
        session->backchannelId = static_cast<int>(num);
        qCDebug(GstCameraAudioLog) << "Backchannel stream" << num << name << clockRate << "Hz";
        return TRUE;
    }

    if (!session->playAudio || session->audioSelected.exchange(true)) {
        return FALSE;
    }
    qCDebug(GstCameraAudioLog) << "Audio stream" << num;
    return TRUE;
}

void onDecodedPad([[maybe_unused]] GstElement* decodebin, GstPad* pad, gpointer data)
{
    auto* const session = static_cast<Session*>(data);

    GstCapsPtr caps = adoptCaps(gst_pad_get_current_caps(pad));
    if (!caps) {
        caps = adoptCaps(gst_pad_query_caps(pad, nullptr));
    }
    if (!caps || (gst_caps_get_size(caps.get()) == 0) ||
        !g_str_has_prefix(gst_structure_get_name(gst_caps_get_structure(caps.get(), 0)), "audio/")) {
        return;
    }

    GError* rawError = nullptr;
    GstElement* const tail = gst_parse_bin_from_description(
        "queue max-size-time=500000000 leaky=downstream ! audioconvert ! audioresample ! autoaudiosink sync=false",
        TRUE, &rawError);
    const GErrorPtr error = adoptError(rawError);
    if (!tail) {
        qCWarning(GstCameraAudioLog) << "Audio output failed:" << (error ? error->message : "unknown error");
        session->postError(GstCameraAudio::tr("no audio output device"));
        return;
    }

    if (!gst_bin_add(GST_BIN(session->pipeline), tail)) {
        gst_object_unref(tail);
        return;
    }
    (void) gst_element_sync_state_with_parent(tail);

    const GstPadPtr sink = adoptPad(gst_element_get_static_pad(tail, "sink"));
    if (!sink || (gst_pad_link(pad, sink.get()) != GST_PAD_LINK_OK)) {
        qCWarning(GstCameraAudioLog) << "Linking the decoded audio failed";
        return;
    }
    session->postDecodedAudio();
}

void onRtspPad([[maybe_unused]] GstElement* rtspsrc, GstPad* pad, gpointer data)
{
    auto* const session = static_cast<Session*>(data);
    if (GST_PAD_DIRECTION(pad) != GST_PAD_SRC) {
        return;
    }

    GstCapsPtr caps = adoptCaps(gst_pad_get_current_caps(pad));
    if (!caps) {
        caps = adoptCaps(gst_pad_query_caps(pad, nullptr));
    }
    if (!caps || (gst_caps_get_size(caps.get()) == 0) || !isAudioMedia(gst_caps_get_structure(caps.get(), 0))) {
        return;
    }

    GstElement* const decodebin = gst_element_factory_make("decodebin", nullptr);
    if (!decodebin) {
        qCWarning(GstCameraAudioLog) << "gst_element_factory_make('decodebin') failed";
        return;
    }
    (void) g_signal_connect(decodebin, "pad-added", G_CALLBACK(onDecodedPad), session);
    if (!gst_bin_add(GST_BIN(session->pipeline), decodebin)) {
        gst_object_unref(decodebin);
        return;
    }
    (void) gst_element_sync_state_with_parent(decodebin);

    const GstPadPtr sink = adoptPad(gst_element_get_static_pad(decodebin, "sink"));
    if (!sink || (gst_pad_link(pad, sink.get()) != GST_PAD_LINK_OK)) {
        qCWarning(GstCameraAudioLog) << "Linking the camera audio to decodebin failed";
    }
}

GstBusSyncReply onBusMessage([[maybe_unused]] GstBus* bus, GstMessage* message, gpointer data)
{
    auto* const session = static_cast<Session*>(data);

    switch (GST_MESSAGE_TYPE(message)) {
        case GST_MESSAGE_ERROR: {
            GError* rawError = nullptr;
            gchar* rawDebug = nullptr;
            gst_message_parse_error(message, &rawError, &rawDebug);
            const GErrorPtr error = adoptError(rawError);
            const GCharPtr debug = adoptGChar(rawDebug);
            const QString text = QString::fromUtf8(error ? error->message : "unknown error");
            qCWarning(GstCameraAudioLog) << "Error:" << text << (debug ? debug.get() : "");
            session->postError(text);
            break;
        }
        case GST_MESSAGE_EOS:
            session->postError(GstCameraAudio::tr("the camera ended the audio session"));
            break;
        case GST_MESSAGE_STATE_CHANGED:
            if (GST_MESSAGE_SRC(message) == GST_OBJECT(session->pipeline)) {
                GstState newState = GST_STATE_NULL;
                gst_message_parse_state_changed(message, nullptr, &newState, nullptr);
                if (newState == GST_STATE_PLAYING) {
                    session->postPlaying();
                }
            }
            break;
        default:
            break;
    }
    return GST_BUS_DROP;
}

GstFlowReturn onMicrophoneSample(GstElement* appsink, gpointer data)
{
    auto* const session = static_cast<Session*>(data);

    GstSample* sample = nullptr;
    g_signal_emit_by_name(appsink, "pull-sample", &sample);
    if (!sample) {
        return GST_FLOW_EOS;
    }

    GstElement* const rtspsrc = session->rtspsrc;
    const int id = session->backchannelId.load();
    if (!rtspsrc || (id < 0)) {
        gst_sample_unref(sample);
        return GST_FLOW_OK;
    }

    GstFlowReturn ret = GST_FLOW_OK;
    if (session->sampleSignal) {
        g_signal_emit_by_name(rtspsrc, "push-backchannel-sample", static_cast<guint>(id), sample, &ret);
        gst_sample_unref(sample);
    } else {
        // Consumes the sample (see useSampleSignal()).
        g_signal_emit_by_name(rtspsrc, "push-backchannel-buffer", static_cast<guint>(id), sample, &ret);
    }
    // A dropped packet must not stop the microphone; the RTSP session reports real failures on the bus.
    return GST_FLOW_OK;
}

}  // namespace

GstCameraAudio::GstCameraAudio(QObject* parent)
    : QObject(parent)
{}

GstCameraAudio::~GstCameraAudio()
{
    stop();
}

void GstCameraAudio::configure(const QString& uri, bool playAudio, bool talkback)
{
    stop();
    if (!playAudio && !talkback) {
        return;
    }

    const QUrl url(uri);
    if (!url.scheme().startsWith(QLatin1String("rtsp"), Qt::CaseInsensitive)) {
        _fail(tr("audio is only available for RTSP cameras"));
        return;
    }

    auto session = std::make_unique<Session>();
    session->owner = this;
    session->generation = ++_generation;
    session->playAudio = playAudio;
    session->talkback = talkback;

    GstElementPtr pipeline = adoptElement(gst_pipeline_new("camera-audio"));
    GstElement* const rtspsrc = gst_element_factory_make("rtspsrc", "source");
    if (!pipeline || !rtspsrc) {
        if (rtspsrc) {
            gst_object_unref(rtspsrc);
        }
        _fail(tr("GStreamer RTSP support is missing"));
        return;
    }
    (void) gst_object_ref_sink(pipeline.get());

    QUrl cleanUrl(url);
    cleanUrl.setUserInfo(QString());
    constexpr GstRTSPLowerTrans kProtocols =
        static_cast<GstRTSPLowerTrans>(GST_RTSP_LOWER_TRANS_UDP | GST_RTSP_LOWER_TRANS_TCP);
    g_object_set(rtspsrc, "location", cleanUrl.toEncoded().constData(), "latency", kAudioLatencyMs, "tcp-timeout",
                 kRtspTcpTimeoutUs, "protocols", kProtocols, nullptr);
    const QString user = url.userName(QUrl::FullyDecoded);
    if (!user.isEmpty()) {
        g_object_set(rtspsrc, "user-id", user.toUtf8().constData(), "user-pw",
                     url.password(QUrl::FullyDecoded).toUtf8().constData(), nullptr);
    }
    if (talkback) {
        if (!g_object_class_find_property(G_OBJECT_GET_CLASS(rtspsrc), "backchannel")) {
            gst_object_unref(rtspsrc);
            _fail(tr("this GStreamer version cannot send audio to cameras"));
            return;
        }
        // Asks the camera for its ONVIF backchannel ("Require: www.onvif.org/ver20/backchannel").
        gst_util_set_object_arg(G_OBJECT(rtspsrc), "backchannel", "onvif");
    }

    (void) gst_bin_add(GST_BIN(pipeline.get()), rtspsrc);
    session->pipeline = pipeline.release();
    session->rtspsrc = rtspsrc;
    session->sampleSignal = useSampleSignal(rtspsrc);

    Session* const raw = session.get();
    (void) g_signal_connect(rtspsrc, "select-stream", G_CALLBACK(selectStream), raw);
    (void) g_signal_connect(rtspsrc, "pad-added", G_CALLBACK(onRtspPad), raw);
    const GstBusPtr bus = adoptBus(gst_element_get_bus(raw->pipeline));
    gst_bus_set_sync_handler(bus.get(), onBusMessage, raw, nullptr);

    _session = std::move(session);
    qCDebug(GstCameraAudioLog) << "Starting" << QGCNetworkHelper::redactedUrlForLogging(cleanUrl)
                               << "play:" << playAudio << "talkback:" << talkback;

    if (gst_element_set_state(_session->pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        _fail(tr("could not open the camera's audio"));
        return;
    }

    if (playAudio) {
        const quint64 gen = _generation;
        QTimer::singleShot(kNoAudioTimeoutMs, this, [this, gen]() {
            if ((gen == _generation) && _session && _session->playAudio && !_audioPlaying) {
                _fail(_session->audioSelected ? tr("the camera sends no audio") : tr("the camera has no audio stream"));
            }
        });
    }
}

void GstCameraAudio::stop()
{
    ++_generation;
    if (_session) {
        _session->teardown();
        _session.reset();
    }
    _setAudioPlaying(false);
    _setTalkbackActive(false);
}

void GstCameraAudio::_onPipelinePlaying(quint64 generation)
{
    if ((generation != _generation) || !_session || !_session->talkback || _session->micPipeline) {
        return;
    }

    if (_session->backchannelId.load() < 0) {
        QByteArray encoding;
        {
            QMutexLocker lock(&_session->mutex);
            encoding = _session->backchannelEncoding;
        }
        _fail(encoding.isEmpty() ? tr("the camera offers no ONVIF audio backchannel")
                                 : tr("the camera's audio backchannel uses %1, only G.711 is supported")
                                       .arg(QString::fromLatin1(encoding)));
        return;
    }
    _startMicrophone();
}

void GstCameraAudio::_startMicrophone()
{
    QByteArray encoding;
    int clockRate = 8000;
    int payload = 0;
    {
        QMutexLocker lock(&_session->mutex);
        encoding = _session->backchannelEncoding;
        clockRate = _session->backchannelClockRate;
        payload = _session->backchannelPayload;
    }
    const bool mulaw = (encoding == "PCMU");
    const QString description =
        QStringLiteral(
            "autoaudiosrc ! queue max-size-time=200000000 leaky=downstream ! audioconvert ! audioresample ! "
            "audio/x-raw,format=S16LE,channels=1,rate=%1 ! %2 ! %3 pt=%4 min-ptime=%5 max-ptime=%5 ! "
            "appsink name=out sync=false emit-signals=true max-buffers=50 drop=true")
            .arg(clockRate)
            .arg(mulaw ? QStringLiteral("mulawenc") : QStringLiteral("alawenc"))
            .arg(mulaw ? QStringLiteral("rtppcmupay") : QStringLiteral("rtppcmapay"))
            .arg(payload)
            .arg(kBackchannelPtimeNs);

    GError* rawError = nullptr;
    GstElement* const mic = gst_parse_launch(description.toUtf8().constData(), &rawError);
    const GErrorPtr error = adoptError(rawError);
    if (!mic || error) {
        if (mic) {
            gst_object_unref(mic);
        }
        qCWarning(GstCameraAudioLog) << "Microphone pipeline failed:" << (error ? error->message : "unknown error");
        _fail(tr("the microphone could not be opened"));
        return;
    }
    (void) gst_object_ref_sink(mic);

    GstElement* const appsink = gst_bin_get_by_name(GST_BIN(mic), "out");
    if (appsink) {
        (void) g_signal_connect(appsink, "new-sample", G_CALLBACK(onMicrophoneSample), _session.get());
        gst_object_unref(appsink);
    }

    _session->micPipeline = mic;
    if (gst_element_set_state(mic, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        _fail(tr("the microphone could not be opened"));
        return;
    }
    qCDebug(GstCameraAudioLog) << "Talkback running," << encoding << clockRate << "Hz";
    _setTalkbackActive(true);
}

void GstCameraAudio::_onDecodedAudio(quint64 generation)
{
    if (generation == _generation) {
        _setAudioPlaying(true);
    }
}

void GstCameraAudio::_onError(quint64 generation, const QString& reason)
{
    if (generation == _generation) {
        _fail(reason);
    }
}

void GstCameraAudio::_fail(const QString& reason)
{
    stop();
    emit failed(reason);
}

void GstCameraAudio::_setAudioPlaying(bool playing)
{
    if (playing != _audioPlaying) {
        _audioPlaying = playing;
        emit audioPlayingChanged(playing);
    }
}

void GstCameraAudio::_setTalkbackActive(bool active)
{
    if (active != _talkbackActive) {
        _talkbackActive = active;
        emit talkbackActiveChanged(active);
    }
}
