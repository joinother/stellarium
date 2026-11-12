import shlex
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / 'plugins/Satellites/src/Satellites.cpp').read_text()
    header = (ROOT / 'plugins/Satellites/src/Satellites.hpp').read_text()
    records = header[header.index('struct TleSource\n'):header.index('#if(SATELLITES_PLUGIN_IRIDIUM')]
    helpers = source[source.index('static constexpr qint64 satelliteUpdateMaxBytes'):source.index('QByteArray unzipData')]
    updater = source[source.index('void Satellites::updateFromOnlineSources()'):source.index('void Satellites::updateObserverLocation')]
    ini = (ROOT / 'src/core/StelIniParser.cpp').read_text()
    ini = ini[ini.index('bool readStelIniFile'):].replace('StelUtils::getEndLineChar()', 'QStringLiteral("\\n")')
    program = r'''
#include <QtCore>
#include <QtNetwork>
#include <cassert>
#include <cmath>
#include <cstring>
#include <utility>
#define q_(value) QStringLiteral(value)
''' + ini + records + helpers + r'''
using TleDataHash = QHash<QString, QByteArray>;
struct StelProgressController {
    int value = 0, maximum = 0;
    void setValue(int next) { value = next; assert(value <= maximum); }
    void setRange(int, int next) { maximum = next; }
    void setFormat(const QString&) {}
};
struct Core { double getJD() const { return 2460000; } };
struct StelApp {
    QTemporaryDir folder;
    QSettings settings{folder.filePath("settings.ini"), QSettings::IniFormat};
    Core core;
    int progressCreated = 0, progressRemoved = 0;
    static StelApp& getInstance() { static StelApp instance; return instance; }
    QSettings* getSettings() { return &settings; }
    Core* getCore() { return &core; }
    StelProgressController* addProgressBar() { ++progressCreated; return new StelProgressController; }
    void removeProgressBar(StelProgressController* progress) { ++progressRemoved; delete progress; }
};
QByteArray unzipData(const QByteArray& data) { return data; }
class Satellites : public QObject {
public:
    enum UpdateState { Updating, CompleteNoUpdates, CompleteUpdates, DownloadError, OtherError, CompletePartial };
    UpdateState updateState = CompleteNoUpdates;
    QDateTime nextAutomaticUpdateAttempt;
    bool scheduledUpdate = false, autoAddEnabled = true;
    QStringList updateUrls;
    TleSourceList updateSources;
    int numberDownloadsComplete = 0, parseCalls = 0;
    QNetworkAccessManager* downloadMgr = nullptr;
    StelProgressController* progressBar = nullptr;
    QTemporaryDir folder;
    QDir dataDir{folder.path()};
    QStringList satellites{"preserved-user-satellite"};
    QList<UpdateState> emitted;
    void updateStateChanged(UpdateState state) { emitted.append(state); }
    void tleUpdateComplete(int, int, int, int) {}
    void updateFromOnlineSources();
    void startSourceDownloads();
    void saveMirrorSummary();
    void saveDownloadedUpdate(QNetworkReply*);
    void finishDownloadBatch();
    void parseDataFile(QFile& file, TleDataHash& data, bool, const QString& url) {
        ++parseCalls;
        const QByteArray payload = file.readAll();
        const bool valid = payload == "valid tle";
        file.setProperty("tleParseComplete", valid);
        if (valid) data[url] = payload;
    }
    void updateSatellites(TleDataHash&, bool complete) {
        updateState = complete ? CompleteUpdates : CompletePartial;
        updateStateChanged(updateState);
    }
};
''' + updater + r'''
struct Response { QByteArray payload; int status = 200; int delay = 0; bool hang = false; };
class Reply : public QNetworkReply {
    QByteArray payload;
    qint64 offset = 0;
public:
    Reply(const QNetworkRequest& request, const Response& response, QObject* parent) : QNetworkReply(parent), payload(response.payload) {
        setRequest(request);
        setUrl(request.url());
        setAttribute(QNetworkRequest::HttpStatusCodeAttribute, response.status);
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        if (!response.hang) QTimer::singleShot(response.delay, this, [this]() {
            if (isFinished()) return;
            emit readyRead();
            if (isFinished()) return;
            emit downloadProgress(payload.size(), payload.size());
            if (isFinished()) return;
            setFinished(true);
            emit finished();
        });
    }
    void abort() override {
        if (isFinished()) return;
        setError(QNetworkReply::OperationCanceledError, "aborted");
        setFinished(true);
        emit finished();
    }
    qint64 bytesAvailable() const override { return payload.size() - offset + QNetworkReply::bytesAvailable(); }
    bool isSequential() const override { return true; }
    qint64 readData(char* output, qint64 maximum) override {
        const qint64 count = qMin(maximum, payload.size() - offset);
        if (count == 0) return -1;
        std::memcpy(output, payload.constData() + offset, count);
        offset += count;
        return count;
    }
};
class Manager : public QNetworkAccessManager {
public:
    QHash<QString, Response> responses;
    QList<QNetworkRequest> requests;
    QNetworkReply* createRequest(Operation, const QNetworkRequest& request, QIODevice*) override {
        requests.append(request);
        return new Reply(request, responses.value(request.url().toString(), {"", 404}), this);
    }
};
const QString mirror = "https://skyinstrument.cn/v1/catalogs/satellites/visual.txt";
const QString custom = "file:///custom-local.tle";
const QString manifestUrl = "https://skyinstrument.cn/v1/manifest.json";
QJsonObject entry(QString status = "fresh") {
    return {{"path", QUrl(mirror).path()}, {"status", status}, {"available", status != "unavailable"},
        {"ok", status == "fresh"}, {"stale", status != "fresh"}, {"bytes", 9},
        {"sha256", QString::fromLatin1(QCryptographicHash::hash("valid tle", QCryptographicHash::Sha256).toHex())},
        {"lastSuccessAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}};
}
QByteArray manifest(const QJsonArray& entries, QDateTime date = QDateTime::currentDateTimeUtc()) {
    return QJsonDocument(QJsonObject{{"generatedAt", date.toString(Qt::ISODateWithMs)}, {"sources", entries}}).toJson();
}
void inspectManifest(QByteArray payload, QString expected, QString url = mirror) {
    TleSource source;
    source.url = QUrl(url);
    TleSourceList sources{source};
    applySatelliteManifest(payload, sources, QDateTime::currentDateTimeUtc());
    assert(sources[0].mirrorStatus == expected);
    if (expected == "fresh" || expected == "stale") {
        assert(satelliteMirrorPayloadValid(sources[0], "valid tle"));
        assert(!satelliteMirrorPayloadValid(sources[0], "wrong tle"));
        assert(!satelliteMirrorPayloadValid(sources[0], "valid tle!"));
    }
}
void scenario(const QString& name, const Response& manifestResponse, QStringList urls,
    Satellites::UpdateState expected, int expectedDownloads, int expectedParses,
    QString expectedMirror, Response mirrorResponse = {"valid tle"}, bool scheduled = false) {
    Manager manager;
    manager.responses[manifestUrl] = manifestResponse;
    manager.responses[mirror] = mirrorResponse;
    manager.responses[custom] = {"valid tle", 200, 40};
    Satellites satellites;
    satellites.downloadMgr = &manager;
    satellites.updateUrls = urls;
    satellites.scheduledUpdate = scheduled;
    QObject::connect(&manager, &QNetworkAccessManager::finished, &satellites, &Satellites::saveDownloadedUpdate);
    const int progressBefore = StelApp::getInstance().progressCreated;
    satellites.updateFromOnlineSources();
    assert(satellites.updateState == Satellites::Updating);
    if (scheduled) assert(StelApp::getInstance().progressCreated == progressBefore);
    QElapsedTimer elapsed;
    elapsed.start();
    while (satellites.updateState == Satellites::Updating && elapsed.elapsed() < 17000) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
        if (urls.contains(custom) && elapsed.elapsed() < 25) {
            assert(satellites.updateState == Satellites::Updating);
            if (satellites.progressBar) assert(satellites.progressBar->value < satellites.progressBar->maximum);
        }
        QThread::msleep(1);
    }
    assert(satellites.updateState == expected);
    assert(satellites.emitted == QList<Satellites::UpdateState>({Satellites::Updating, expected}));
    assert(satellites.satellites == QStringList{"preserved-user-satellite"});
    assert(satellites.parseCalls == expectedParses);
    assert(satellites.updateSources.isEmpty());
    assert(satellites.progressBar == nullptr);
    int manifests = 0, downloads = 0;
    for (const QNetworkRequest& request : manager.requests) {
        if (request.url() == QUrl(manifestUrl)) {
            ++manifests;
            assert(request.transferTimeout() == 15000);
            assert(request.url().query().isEmpty());
            assert(!request.hasRawHeader("Authorization"));
            assert(!request.hasRawHeader("Cookie"));
            assert(request.attribute(QNetworkRequest::CookieLoadControlAttribute) == QNetworkRequest::Manual);
            assert(request.attribute(QNetworkRequest::CookieSaveControlAttribute) == QNetworkRequest::Manual);
            assert(request.attribute(QNetworkRequest::AuthenticationReuseAttribute) == QNetworkRequest::Manual);
            assert(request.attribute(QNetworkRequest::RedirectPolicyAttribute) == QNetworkRequest::ManualRedirectPolicy);
        } else ++downloads;
    }
    assert(manifests == (urls == QStringList{custom} ? 0 : 1));
    assert(downloads == expectedDownloads);
    QSettings* settings = StelApp::getInstance().getSettings();
    assert(settings->value("Satellites/mirror_status").toString() == expectedMirror);
    assert(settings->value("Satellites/mirror_checked_at").toString().isEmpty() == expectedMirror.isEmpty());
    if (expectedMirror == "stale") assert(QJsonDocument::fromJson(settings->value("Satellites/mirror_stale_sources").toByteArray()).array().contains(mirror));
    if (expectedMirror == "unavailable") assert(!QJsonDocument::fromJson(settings->value("Satellites/mirror_unavailable_sources").toByteArray()).array().isEmpty());
    QSettings::SettingsMap original, restored;
    for (const QString& key : settings->allKeys()) original[key] = settings->value(key);
    QBuffer serialized;
    serialized.open(QIODevice::ReadWrite);
    assert(writeStelIniFile(serialized, original));
    serialized.seek(0);
    assert(readStelIniFile(serialized, restored));
    for (const QString& key : {QString("Satellites/mirror_stale_sources"), QString("Satellites/mirror_unavailable_sources")}) {
        assert(QJsonDocument::fromJson(original.value(key).toByteArray()).isArray());
        assert(restored.value(key).toString() == original.value(key).toString());
    }
    if (manifestResponse.hang) assert(elapsed.elapsed() >= 14000 && elapsed.elapsed() < 17000);
    qInfo().noquote() << "PASS" << name;
}
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    const auto fresh = entry();
    inspectManifest(manifest({fresh}), "fresh");
    inspectManifest(manifest({entry("stale")}), "stale");
    inspectManifest(manifest({entry("unavailable")}), "unavailable");
    inspectManifest(manifest({entry("unexpected")}), "unavailable");
    inspectManifest(manifest({fresh, fresh}), "unavailable");
    inspectManifest(manifest({}), "unavailable");
    inspectManifest("not JSON", "unavailable");
    inspectManifest(manifest({fresh}, QDateTime::currentDateTimeUtc().addSecs(-12 * 3600 - 1)), "unavailable");
    inspectManifest(manifest({fresh}, QDateTime::currentDateTimeUtc().addSecs(600)), "unavailable");
    inspectManifest(manifest({fresh}), "unavailable", mirror + "?id=untrusted");
    inspectManifest(manifest({fresh}), "unavailable", mirror + "#fragment");
    inspectManifest(manifest({fresh}), "", "http://127.0.0.1/v1/catalogs/satellites/visual.txt");
    inspectManifest(manifest({fresh}), "", "https://example.org/v1/catalogs/satellites/visual.txt");
    for (const QString& field : {QString("status"), QString("sha256"), QString("bytes"), QString("available"), QString("ok"), QString("stale"), QString("lastSuccessAt")}) {
        auto bad = fresh;
        bad.remove(field);
        inspectManifest(manifest({bad}), "unavailable");
    }
    for (const QJsonValue& invalidBytes : {QJsonValue(-1), QJsonValue(0), QJsonValue(9.5), QJsonValue("9"), QJsonValue(32 * 1024 * 1024 + 1)}) {
        auto bad = fresh;
        bad["bytes"] = invalidBytes;
        inspectManifest(manifest({bad}), "unavailable");
    }
    auto old = fresh;
    old["lastSuccessAt"] = QDateTime::currentDateTimeUtc().addDays(-1).toString(Qt::ISODateWithMs);
    inspectManifest(manifest({old}), "stale");
    auto cached = entry("stale");
    cached["lastSuccessAt"] = QJsonValue::Null;
    inspectManifest(manifest({cached}), "stale");
    qInfo() << "PASS metadata validation and raw payload integrity";
    scenario("fresh mirror", {manifest({fresh})}, {mirror}, Satellites::CompleteUpdates, 1, 1, "fresh");
    scenario("duplicate configured source, one manifest", {manifest({fresh})}, {mirror, "1," + mirror}, Satellites::CompleteUpdates, 2, 2, "fresh");
    scenario("stale mirror", {manifest({cached})}, {mirror}, Satellites::CompletePartial, 1, 1, "stale");
    scenario("all skipped", {manifest({entry("unavailable")})}, {mirror}, Satellites::DownloadError, 0, 0, "unavailable");
    scenario("multiple unavailable survive actual INI serialization", {manifest({})}, {mirror, mirror + "#fragment"}, Satellites::DownloadError, 0, 0, "unavailable");
    scenario("missing entry", {manifest({})}, {mirror}, Satellites::DownloadError, 0, 0, "unavailable");
    scenario("manifest error plus local", {"", 503}, {mirror, custom}, Satellites::CompletePartial, 1, 1, "unavailable");
    scenario("unavailable plus local", {manifest({entry("unavailable")})}, {mirror, custom}, Satellites::CompletePartial, 1, 1, "unavailable");
    scenario("oversized manifest", {QByteArray(1024 * 1024 + 1, 'x')}, {mirror, custom}, Satellites::CompletePartial, 1, 1, "unavailable");
    scenario("expired manifest", {manifest({fresh}, QDateTime::currentDateTimeUtc().addDays(-1))}, {mirror}, Satellites::DownloadError, 0, 0, "unavailable");
    scenario("wrong digest before parsing", {manifest({fresh})}, {mirror}, Satellites::DownloadError, 1, 0, "unavailable", {"wrong tle"});
    scenario("wrong bytes before parsing", {manifest({fresh})}, {mirror}, Satellites::DownloadError, 1, 0, "unavailable", {"valid tle!"});
    auto malformed = fresh;
    malformed["sha256"] = QString::fromLatin1(QCryptographicHash::hash("wrong tle", QCryptographicHash::Sha256).toHex());
    scenario("verified but malformed catalog", {manifest({malformed})}, {mirror}, Satellites::DownloadError, 1, 1, "unavailable", {"wrong tle"});
    scenario("HTTP failure plus local", {manifest({fresh})}, {mirror, custom}, Satellites::CompletePartial, 2, 1, "unavailable", {"valid tle", 503});
    scenario("redirect refused", {manifest({fresh}), 302}, {mirror}, Satellites::DownloadError, 0, 0, "unavailable");
    scenario("scheduled without global progress", {manifest({fresh})}, {mirror}, Satellites::CompleteUpdates, 1, 1, "fresh", {"valid tle"}, true);
    scenario("custom source only", {"", 503}, {custom}, Satellites::CompleteUpdates, 1, 1, "");
    scenario("15 second deadline plus local", {"", 200, 0, true}, {mirror, custom}, Satellites::CompletePartial, 1, 1, "unavailable");
}
'''
    with tempfile.TemporaryDirectory(prefix='satellite-manifest-') as temporary:
        folder = Path(temporary)
        path = folder / 'manifest.cpp'
        path.write_text(program)
        flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'Qt6Core', 'Qt6Network'], text=True))
        binary = folder / 'manifest'
        subprocess.run(['c++', '-std=c++17', '-fPIC', str(path), '-o', str(binary), *flags], check=True)
        subprocess.run([str(binary)], check=True, timeout=45)


if __name__ == '__main__':
    main()
