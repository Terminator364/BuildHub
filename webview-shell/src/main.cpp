#define UNICODE
#define _UNICODE
#define NOMINMAX
#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <psapi.h>
#include <dbghelp.h>
#include <wrl.h>
#include <WebView2.h>
#include <array>
#include <string>
#include <algorithm>
#include <cwctype>
#include <sstream>
#include <iomanip>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {
constexpr int kMaxTabs = 3;
constexpr int kToolbarH = 48;
constexpr int kTabsH = 38;
constexpr UINT WM_APP_LOW_MEMORY = WM_APP + 11;
constexpr UINT WM_APP_INIT_WEBVIEW = WM_APP + 12;
constexpr UINT_PTR TIMER_HEARTBEAT = 2001;
constexpr UINT_PTR TIMER_WEBVIEW_WATCHDOG = 2002;
constexpr UINT HEARTBEAT_MS = 60000;
constexpr UINT WEBVIEW_WATCHDOG_MS = 15000;
constexpr wchar_t kSchemaVersion[] = L"browser4g-error/1";
constexpr wchar_t kBuildVersion[] = L"0.1.2-beta";

enum ControlId : int {
    ID_BACK = 1001,
    ID_FORWARD,
    ID_RELOAD,
    ID_ADDRESS,
    ID_GO,
    ID_NEW_TAB,
    ID_CLOSE_TAB,
    ID_TAB1 = 1101,
    ID_TAB2,
    ID_TAB3,
};

struct TabState {
    std::wstring url;
    std::wstring title;
};

HWND g_main = nullptr;
HWND g_back = nullptr, g_forward = nullptr, g_reload = nullptr, g_address = nullptr, g_go = nullptr;
HWND g_newTab = nullptr, g_closeTab = nullptr;
std::array<HWND, kMaxTabs> g_tabButtons{};
std::array<TabState, kMaxTabs> g_tabs{};
int g_tabCount = 1;
int g_activeTab = 0;

std::wstring g_appTitle = L"BuildHub WebView Shell";
std::wstring g_appId = L"BuildHubWebViewShell";
std::wstring g_home = L"https://www.bing.com/";
std::wstring g_configPath;
std::wstring g_statePath;
std::wstring g_dataRoot;
std::wstring g_udfPath;
std::wstring g_telemetryDir;
std::wstring g_projectMemoryDir;
std::wstring g_evidenceDir;
std::wstring g_crashDir;
std::wstring g_telemetryLogPath;
std::wstring g_heartbeatPath;
std::wstring g_statusPath;
std::wstring g_latestErrorPath;
std::wstring g_updateRequestPath;
std::wstring g_ledgerPath;
std::wstring g_errorIndexPath;
std::wstring g_errorCountPath;
std::wstring g_runMarkerPath;
std::wstring g_runtimeVersion;
std::wstring g_runId;
std::wstring g_startedUtc;

ComPtr<ICoreWebView2Environment> g_environment;
ComPtr<ICoreWebView2Controller> g_controller;
ComPtr<ICoreWebView2> g_webview;
EventRegistrationToken g_navCompletedToken{};
EventRegistrationToken g_titleChangedToken{};
EventRegistrationToken g_processFailedToken{};
HANDLE g_lowMemHandle = nullptr;
HANDLE g_lowMemWait = nullptr;
volatile LONG g_bridgeWorkerActive = 0;
volatile LONG g_errorCount = 0;
volatile LONG g_cleanShutdown = 0;
std::wstring g_lastErrorFingerprint;
ULONGLONG g_lastErrorTick = 0;
volatile LONG g_suppressedSameError = 0;
std::wstring g_initStage = L"NOT_STARTED";
HFONT g_uiFont = nullptr;

std::wstring Join(const std::wstring& a, const std::wstring& b) {
    if (a.empty()) return b;
    if (a.back() == L'\\') return a + b;
    return a + L"\\" + b;
}

std::wstring ExeDir() {
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    PathRemoveFileSpecW(path);
    return path;
}

std::wstring LocalAppData() {
    PWSTR raw = nullptr;
    std::wstring result;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &raw)) && raw) {
        result = raw;
        CoTaskMemFree(raw);
    }
    return result;
}

void EnsureDir(const std::wstring& p) {
    if (!p.empty()) SHCreateDirectoryExW(nullptr, p.c_str(), nullptr);
}

bool FileExists(const std::wstring& path) {
    DWORD a = GetFileAttributesW(path.c_str());
    return a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring ReadIni(const wchar_t* section, const wchar_t* key, const std::wstring& def, const std::wstring& path) {
    wchar_t buf[4096]{};
    GetPrivateProfileStringW(section, key, def.c_str(), buf, static_cast<DWORD>(_countof(buf)), path.c_str());
    return buf;
}

int ReadIniInt(const wchar_t* section, const wchar_t* key, int def, const std::wstring& path) {
    return GetPrivateProfileIntW(section, key, def, path.c_str());
}

void WriteIni(const wchar_t* section, const wchar_t* key, const std::wstring& value, const std::wstring& path) {
    WritePrivateProfileStringW(section, key, value.c_str(), path.c_str());
}

std::string WideToUtf8(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) return {};
    std::string out(static_cast<size_t>(n), '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), n, nullptr, nullptr);
    return out;
}

std::wstring Utf8ToWide(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    if (n <= 0) return {};
    std::wstring out(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
    return out;
}

std::string JsonEscapeUtf8(const std::wstring& w) {
    std::string s = WideToUtf8(w);
    std::string out;
    out.reserve(s.size() + 16);
    static const char* hex = "0123456789abcdef";
    for (unsigned char c : s) {
        switch (c) {
        case '\\': out += "\\\\"; break;
        case '"': out += "\\\""; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                out += "\\u00";
                out.push_back(hex[(c >> 4) & 0xF]);
                out.push_back(hex[c & 0xF]);
            } else {
                out.push_back(static_cast<char>(c));
            }
        }
    }
    return out;
}

std::wstring UtcNowIso() {
    SYSTEMTIME st{};
    GetSystemTime(&st);
    wchar_t buf[64]{};
    swprintf_s(buf, L"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
    return buf;
}

std::wstring NewId() {
    GUID g{};
    if (SUCCEEDED(CoCreateGuid(&g))) {
        wchar_t buf[64]{};
        StringFromGUID2(g, buf, static_cast<int>(_countof(buf)));
        std::wstring out(buf);
        out.erase(std::remove(out.begin(), out.end(), L'{'), out.end());
        out.erase(std::remove(out.begin(), out.end(), L'}'), out.end());
        return out;
    }
    return std::to_wstring(GetTickCount64()) + L"-" + std::to_wstring(GetCurrentProcessId());
}

bool AtomicWriteUtf8(const std::wstring& path, const std::string& content) {
    std::wstring tmp = path + L".tmp";
    HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    bool ok = WriteFile(h, content.data(), static_cast<DWORD>(content.size()), &written, nullptr) &&
              written == content.size();
    if (ok) ok = FlushFileBuffers(h) != FALSE;
    CloseHandle(h);
    if (!ok) {
        DeleteFileW(tmp.c_str());
        return false;
    }
    if (!MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(tmp.c_str());
        return false;
    }
    return true;
}

bool AppendUtf8Line(const std::wstring& path, const std::string& line) {
    HANDLE h = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;
    std::string payload = line;
    payload.push_back('\n');
    DWORD written = 0;
    bool ok = WriteFile(h, payload.data(), static_cast<DWORD>(payload.size()), &written, nullptr) &&
              written == payload.size();
    if (ok) FlushFileBuffers(h);
    CloseHandle(h);
    return ok;
}

std::string ReadWholeFileUtf8(const std::wstring& path, size_t maxBytes = 1024 * 1024) {
    HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return {};
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(h, &size) || size.QuadPart <= 0 || static_cast<ULONGLONG>(size.QuadPart) > maxBytes) {
        CloseHandle(h);
        return {};
    }
    std::string out(static_cast<size_t>(size.QuadPart), '\0');
    DWORD got = 0;
    bool ok = ReadFile(h, out.data(), static_cast<DWORD>(out.size()), &got, nullptr) != FALSE;
    CloseHandle(h);
    if (!ok) return {};
    out.resize(got);
    if (out.size() >= 3 && static_cast<unsigned char>(out[0]) == 0xEF &&
        static_cast<unsigned char>(out[1]) == 0xBB && static_cast<unsigned char>(out[2]) == 0xBF) {
        out.erase(0, 3);
    }
    return out;
}

std::wstring ExtractJsonString(const std::string& json, const std::string& key) {
    const std::string needle = "\"" + key + "\"";
    size_t p = json.find(needle);
    if (p == std::string::npos) return {};
    p = json.find(':', p + needle.size());
    if (p == std::string::npos) return {};
    p = json.find('"', p + 1);
    if (p == std::string::npos) return {};
    ++p;
    std::string raw;
    bool esc = false;
    for (; p < json.size(); ++p) {
        char c = json[p];
        if (esc) {
            switch (c) {
            case '\\': raw.push_back('\\'); break;
            case '"': raw.push_back('"'); break;
            case '/': raw.push_back('/'); break;
            case 'n': raw.push_back('\n'); break;
            case 'r': raw.push_back('\r'); break;
            case 't': raw.push_back('\t'); break;
            default: raw.push_back(c); break;
            }
            esc = false;
        } else if (c == '\\') {
            esc = true;
        } else if (c == '"') {
            break;
        } else {
            raw.push_back(c);
        }
    }
    return Utf8ToWide(raw);
}

std::wstring SanitizeUrl(const std::wstring& input) {
    std::wstring s = input;
    if (s.empty()) return L"";
    auto lower = s;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    if (lower.rfind(L"file:", 0) == 0) return L"file://[redacted]";
    if (lower.rfind(L"about:", 0) == 0) return s.substr(0, std::min<size_t>(s.size(), 64));
    size_t scheme = s.find(L"://");
    if (scheme != std::wstring::npos) {
        size_t authorityStart = scheme + 3;
        size_t end = s.find_first_of(L"/?#", authorityStart);
        std::wstring authority = s.substr(authorityStart, end == std::wstring::npos ? std::wstring::npos : end - authorityStart);
        size_t at = authority.rfind(L'@');
        if (at != std::wstring::npos) authority = authority.substr(at + 1);
        return s.substr(0, scheme + 3) + authority;
    }
    size_t colon = s.find(L':');
    if (colon != std::wstring::npos) return s.substr(0, std::min<size_t>(colon + 1, 32)) + L"[redacted]";
    return L"[redacted]";
}

struct MemorySnapshot {
    DWORD load = 0;
    ULONGLONG availMb = 0;
    SIZE_T workingSetMb = 0;
    SIZE_T privateMb = 0;
};

MemorySnapshot MemoryNow() {
    MemorySnapshot m{};
    MEMORYSTATUSEX ms{};
    ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        m.load = ms.dwMemoryLoad;
        m.availMb = ms.ullAvailPhys / (1024ull * 1024ull);
    }
    PROCESS_MEMORY_COUNTERS_EX pmc{};
    if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&pmc), sizeof(pmc))) {
        m.workingSetMb = pmc.WorkingSetSize / (1024ull * 1024ull);
        m.privateMb = pmc.PrivateUsage / (1024ull * 1024ull);
    }
    return m;
}

void SetupTelemetryPaths() {
    g_telemetryDir = Join(g_dataRoot, L"telemetry");
    g_projectMemoryDir = Join(g_dataRoot, L".project-memory");
    g_evidenceDir = Join(g_projectMemoryDir, L"ERROR_EVIDENCE");
    g_crashDir = Join(g_telemetryDir, L"crashes");
    EnsureDir(g_telemetryDir);
    EnsureDir(g_projectMemoryDir);
    EnsureDir(g_evidenceDir);
    EnsureDir(g_crashDir);

    g_telemetryLogPath = Join(g_telemetryDir, L"events.jsonl");
    g_heartbeatPath = Join(g_telemetryDir, L"heartbeat.json");
    g_statusPath = Join(g_telemetryDir, L"status.json");
    g_latestErrorPath = Join(g_telemetryDir, L"LATEST_ERROR_REPORT.json");
    g_updateRequestPath = Join(g_telemetryDir, L"UPDATE_REQUEST.json");
    g_ledgerPath = Join(g_projectMemoryDir, L"ERROR_LEDGER.jsonl");
    g_errorIndexPath = Join(g_projectMemoryDir, L"ERROR_INDEX.md");
    g_errorCountPath = Join(g_projectMemoryDir, L"ERROR_COUNTS.ini");
    g_runMarkerPath = Join(g_dataRoot, L"RUNNING.json");

    AtomicWriteUtf8(Join(g_projectMemoryDir, L"ERROR_SCHEMA_VERSION.txt"), WideToUtf8(kSchemaVersion) + "\n");
    if (!FileExists(g_errorIndexPath)) {
        AtomicWriteUtf8(g_errorIndexPath,
            "# BROWSER4G Error Index\n\n"
            "Runtime-maintained beta error memory. No page content, cookies, tokens, form data, or full browsing URLs are recorded.\n\n"
            "| UTC | Severity | Error class | Event ID | Status |\n"
            "|---|---|---|---|---|\n");
    }
}

void WriteHealthStatus();
void QueueBridge();

void AppendTelemetry(const std::wstring& eventName, const std::wstring& severity, const std::wstring& detail = L"") {
    MemorySnapshot m = MemoryNow();
    std::ostringstream os;
    os << "{\"schema\":\"browser4g-telemetry/1\""
       << ",\"utc\":\"" << JsonEscapeUtf8(UtcNowIso()) << "\""
       << ",\"run_id\":\"" << JsonEscapeUtf8(g_runId) << "\""
       << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
       << ",\"event\":\"" << JsonEscapeUtf8(eventName) << "\""
       << ",\"severity\":\"" << JsonEscapeUtf8(severity) << "\""
       << ",\"detail\":\"" << JsonEscapeUtf8(detail) << "\""
       << ",\"memory_load_pct\":" << m.load
       << ",\"memory_available_mb\":" << m.availMb
       << ",\"process_working_set_mb\":" << m.workingSetMb
       << ",\"process_private_mb\":" << m.privateMb
       << "}";
    AppendUtf8Line(g_telemetryLogPath, os.str());
}

std::wstring CountKeyFor(const std::wstring& errorClass, const std::wstring& rawCode) {
    std::wstring key = errorClass + L"_" + rawCode;
    for (auto& c : key) {
        if (!(iswalnum(c) || c == L'_' || c == L'-')) c = L'_';
    }
    if (key.size() > 120) key.resize(120);
    return key;
}

void RecordError(const std::wstring& errorClass,
                 const std::wstring& rawCode,
                 const std::wstring& severity,
                 const std::wstring& intent,
                 const std::wstring& expected,
                 const std::wstring& observed,
                 const std::wstring& rootCauseStatus,
                 const std::wstring& rootCause,
                 const std::wstring& regressionTest,
                 const std::wstring& lesson,
                 const std::wstring& evidenceRef = L"") {
    const std::wstring utc = UtcNowIso();
    const std::wstring countKey = CountKeyFor(errorClass, rawCode);
    int occurrence = ReadIniInt(L"counts", countKey.c_str(), 0, g_errorCountPath) + 1;
    WriteIni(L"counts", countKey.c_str(), std::to_wstring(occurrence), g_errorCountPath);

    const std::wstring fingerprint = errorClass + L"|" + rawCode + L"|" + observed;
    const ULONGLONG nowTick = GetTickCount64();
    if (fingerprint == g_lastErrorFingerprint && (nowTick - g_lastErrorTick) < 60000ull) {
        InterlockedIncrement(&g_suppressedSameError);
        AppendTelemetry(L"ERROR_DEDUPED", severity, errorClass + L" / occurrence=" + std::to_wstring(occurrence));
        WriteHealthStatus();
        QueueBridge();
        return;
    }
    g_lastErrorFingerprint = fingerprint;
    g_lastErrorTick = nowTick;

    const std::wstring eventId = NewId();
    InterlockedIncrement(&g_errorCount);

    std::ostringstream os;
    os << "{\"schema\":\"browser4g-error/1\""
       << ",\"event_id\":\"" << JsonEscapeUtf8(eventId) << "\""
       << ",\"utc\":\"" << JsonEscapeUtf8(utc) << "\""
       << ",\"project\":\"BROWSER4G\""
       << ",\"phase\":\"RUNTIME\""
       << ",\"intent\":\"" << JsonEscapeUtf8(intent) << "\""
       << ",\"expected\":\"" << JsonEscapeUtf8(expected) << "\""
       << ",\"observed\":\"" << JsonEscapeUtf8(observed) << "\""
       << ",\"error_class\":\"" << JsonEscapeUtf8(errorClass) << "\""
       << ",\"raw_code\":\"" << JsonEscapeUtf8(rawCode) << "\""
       << ",\"severity\":\"" << JsonEscapeUtf8(severity) << "\""
       << ",\"root_cause_status\":\"" << JsonEscapeUtf8(rootCauseStatus) << "\""
       << ",\"root_cause\":\"" << JsonEscapeUtf8(rootCause) << "\""
       << ",\"attempts\":[]"
       << ",\"resolution\":\"OPEN\""
       << ",\"regression_test\":\"" << JsonEscapeUtf8(regressionTest) << "\""
       << ",\"lesson\":\"" << JsonEscapeUtf8(lesson) << "\""
       << ",\"anticipation_candidate\":\"Prevent recurrence of " << JsonEscapeUtf8(errorClass) << " under equivalent causal conditions.\""
       << ",\"evidence_refs\":[\"" << JsonEscapeUtf8(evidenceRef.empty() ? (L"run:" + g_runId) : evidenceRef) << "\"]"
       << ",\"cross_project_tags\":[\"browser-runtime\",\"beta-field\",\"automatic-capture\"]"
       << ",\"occurrence\":" << occurrence
       << ",\"run_id\":\"" << JsonEscapeUtf8(g_runId) << "\""
       << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
       << "}";
    const std::string payload = os.str();
    AppendUtf8Line(g_ledgerPath, payload);
    AtomicWriteUtf8(g_latestErrorPath, payload + "\n");

    std::ostringstream idx;
    idx << "| " << WideToUtf8(utc) << " | " << WideToUtf8(severity) << " | "
        << WideToUtf8(errorClass) << " | " << WideToUtf8(eventId) << " | OPEN |\n";
    AppendUtf8Line(g_errorIndexPath, idx.str().substr(0, idx.str().size() - 1));

    if (severity == L"HIGH" || severity == L"P0") {
        std::ostringstream req;
        req << "{\"schema\":\"browser4g-update-request/1\""
            << ",\"utc\":\"" << JsonEscapeUtf8(utc) << "\""
            << ",\"project\":\"BROWSER4G\""
            << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
            << ",\"event_id\":\"" << JsonEscapeUtf8(eventId) << "\""
            << ",\"error_class\":\"" << JsonEscapeUtf8(errorClass) << "\""
            << ",\"severity\":\"" << JsonEscapeUtf8(severity) << "\""
            << ",\"requested_action\":\"ANALYZE_BUILD_CANDIDATE\""
            << ",\"auto_install\":false"
            << ",\"reason\":\"Deployment remains transactional: build, verify, hash, readback, then controlled promotion.\""
            << "}";
        AtomicWriteUtf8(g_updateRequestPath, req.str() + "\n");
    }

    AppendTelemetry(L"ERROR_CAPTURED", severity, errorClass + L" / " + rawCode);
    WriteHealthStatus();
    QueueBridge();
}

bool AtomicCopy(const std::wstring& src, const std::wstring& dst) {
    if (!FileExists(src)) return true;
    std::wstring tmp = dst + L".tmp";
    DeleteFileW(tmp.c_str());
    if (!CopyFileW(src.c_str(), tmp.c_str(), FALSE)) return false;
    if (!MoveFileExW(tmp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(tmp.c_str());
        return false;
    }
    return true;
}

bool DiscoverChatGptPcBridge(std::wstring& controlFolder, std::wstring& deviceId) {
    std::wstring root = Join(LocalAppData(), L"Tunnel_PC_G4");
    std::wstring state = Join(root, L"state");
    std::string config = ReadWholeFileUtf8(Join(state, L"config.json"), 256 * 1024);
    std::string device = ReadWholeFileUtf8(Join(state, L"device.json"), 256 * 1024);
    if (config.empty() || device.empty()) return false;
    controlFolder = ExtractJsonString(config, "control_folder");
    deviceId = ExtractJsonString(device, "device_id");
    if (controlFolder.empty() || deviceId.empty()) return false;
    DWORD attrs = GetFileAttributesW(controlFolder.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY);
}

DWORD WINAPI BridgeWorker(LPVOID) {
    std::wstring control, device;
    if (DiscoverChatGptPcBridge(control, device)) {
        std::wstring root = Join(Join(Join(control, L"03_TELEMETRY"), device), L"BROWSER4G");
        EnsureDir(Join(control, L"03_TELEMETRY"));
        EnsureDir(Join(Join(control, L"03_TELEMETRY"), device));
        EnsureDir(root);
        AtomicCopy(g_statusPath, Join(root, L"status.json"));
        AtomicCopy(g_heartbeatPath, Join(root, L"heartbeat.json"));
        AtomicCopy(g_latestErrorPath, Join(root, L"LATEST_ERROR_REPORT.json"));
        AtomicCopy(g_updateRequestPath, Join(root, L"UPDATE_REQUEST.json"));
        AtomicCopy(g_ledgerPath, Join(root, L"ERROR_LEDGER.jsonl"));
        AtomicCopy(g_errorIndexPath, Join(root, L"ERROR_INDEX.md"));
        AtomicCopy(Join(g_projectMemoryDir, L"ERROR_SCHEMA_VERSION.txt"), Join(root, L"ERROR_SCHEMA_VERSION.txt"));
    }
    InterlockedExchange(&g_bridgeWorkerActive, 0);
    return 0;
}

void QueueBridge() {
    if (InterlockedCompareExchange(&g_bridgeWorkerActive, 1, 0) != 0) return;
    HANDLE h = CreateThread(nullptr, 0, BridgeWorker, nullptr, 0, nullptr);
    if (h) CloseHandle(h);
    else InterlockedExchange(&g_bridgeWorkerActive, 0);
}

void WriteHealthStatus() {
    MemorySnapshot m = MemoryNow();
    std::wstring control, device;
    bool bridge = DiscoverChatGptPcBridge(control, device);
    std::ostringstream os;
    os << "{\"schema\":\"browser4g-status/1\""
       << ",\"utc\":\"" << JsonEscapeUtf8(UtcNowIso()) << "\""
       << ",\"project\":\"BROWSER4G\""
       << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
       << ",\"run_id\":\"" << JsonEscapeUtf8(g_runId) << "\""
       << ",\"started_utc\":\"" << JsonEscapeUtf8(g_startedUtc) << "\""
       << ",\"runtime_version\":\"" << JsonEscapeUtf8(g_runtimeVersion) << "\""
       << ",\"init_stage\":\"" << JsonEscapeUtf8(g_initStage) << "\""
       << ",\"webview_ready\":" << (g_webview ? "true" : "false")
       << ",\"tab_count\":" << g_tabCount
       << ",\"active_tab\":" << g_activeTab
       << ",\"memory_load_pct\":" << m.load
       << ",\"memory_available_mb\":" << m.availMb
       << ",\"process_working_set_mb\":" << m.workingSetMb
       << ",\"process_private_mb\":" << m.privateMb
       << ",\"error_count_session\":" << g_errorCount
       << ",\"deduped_error_repeats_session\":" << g_suppressedSameError
       << ",\"chatgpt_pc_bridge_detected\":" << (bridge ? "true" : "false")
       << ",\"privacy\":\"NO_PAGE_CONTENT_NO_COOKIES_NO_TOKENS_NO_FORM_DATA_NO_FULL_URLS\""
       << "}";
    AtomicWriteUtf8(g_statusPath, os.str() + "\n");
}

void WriteHeartbeat() {
    MemorySnapshot m = MemoryNow();
    std::ostringstream os;
    os << "{\"schema\":\"browser4g-heartbeat/1\""
       << ",\"utc\":\"" << JsonEscapeUtf8(UtcNowIso()) << "\""
       << ",\"run_id\":\"" << JsonEscapeUtf8(g_runId) << "\""
       << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
       << ",\"state\":\"RUNNING\""
       << ",\"memory_load_pct\":" << m.load
       << ",\"memory_available_mb\":" << m.availMb
       << ",\"process_working_set_mb\":" << m.workingSetMb
       << ",\"process_private_mb\":" << m.privateMb
       << ",\"init_stage\":\"" << JsonEscapeUtf8(g_initStage) << "\""
       << ",\"webview_ready\":" << (g_webview ? "true" : "false")
       << "}";
    AtomicWriteUtf8(g_heartbeatPath, os.str() + "\n");
    WriteHealthStatus();
    QueueBridge();
}

void SaveState() {
    if (g_statePath.empty()) return;
    WriteIni(L"session", L"tab_count", std::to_wstring(g_tabCount), g_statePath);
    WriteIni(L"session", L"active_tab", std::to_wstring(g_activeTab), g_statePath);
    for (int i = 0; i < kMaxTabs; ++i) {
        const std::wstring section = L"tab" + std::to_wstring(i + 1);
        WriteIni(section.c_str(), L"url", g_tabs[i].url, g_statePath);
        WriteIni(section.c_str(), L"title", g_tabs[i].title, g_statePath);
    }
    HANDLE h = CreateFileW(g_statePath.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h != INVALID_HANDLE_VALUE) { FlushFileBuffers(h); CloseHandle(h); }
}

void LoadConfigAndState() {
    g_configPath = Join(ExeDir(), L"browser4g.ini");
    g_appTitle = ReadIni(L"app", L"title", g_appTitle, g_configPath);
    g_appId = ReadIni(L"app", L"app_id", g_appId, g_configPath);
    g_home = ReadIni(L"app", L"home", g_home, g_configPath);

    g_dataRoot = Join(LocalAppData(), g_appId);
    g_udfPath = Join(g_dataRoot, L"WebView2");
    g_statePath = Join(g_dataRoot, L"state.ini");
    EnsureDir(g_dataRoot);
    EnsureDir(g_udfPath);
    SetupTelemetryPaths();

    g_tabCount = std::clamp(ReadIniInt(L"session", L"tab_count", 1, g_statePath), 1, kMaxTabs);
    g_activeTab = std::clamp(ReadIniInt(L"session", L"active_tab", 0, g_statePath), 0, g_tabCount - 1);
    for (int i = 0; i < kMaxTabs; ++i) {
        const std::wstring section = L"tab" + std::to_wstring(i + 1);
        g_tabs[i].url = ReadIni(section.c_str(), L"url", (i == 0 ? g_home : L"about:blank"), g_statePath);
        g_tabs[i].title = ReadIni(section.c_str(), L"title", L"", g_statePath);
        if (g_tabs[i].url.empty()) g_tabs[i].url = (i == 0 ? g_home : L"about:blank");
    }
}

std::wstring UrlEncodeBasic(const std::wstring& s) {
    std::wstring out;
    wchar_t buf[8];
    for (wchar_t ch : s) {
        if ((ch >= L'a' && ch <= L'z') || (ch >= L'A' && ch <= L'Z') || (ch >= L'0' && ch <= L'9') ||
            ch == L'-' || ch == L'_' || ch == L'.' || ch == L'~') {
            out.push_back(ch);
        } else if (ch == L' ') {
            out += L"%20";
        } else if (ch < 128) {
            swprintf_s(buf, L"%%%02X", static_cast<unsigned int>(ch));
            out += buf;
        } else {
            out.push_back(ch);
        }
    }
    return out;
}

std::wstring NormalizeAddress(std::wstring s) {
    while (!s.empty() && iswspace(s.front())) s.erase(s.begin());
    while (!s.empty() && iswspace(s.back())) s.pop_back();
    if (s.empty()) return g_home;
    if (s.find(L' ') != std::wstring::npos) {
        return L"https://www.bing.com/search?q=" + UrlEncodeBasic(s);
    }
    if (s.find(L"://") == std::wstring::npos && s.rfind(L"about:", 0) != 0 && s.rfind(L"file:", 0) != 0) {
        if (s.find(L'.') == std::wstring::npos) return L"https://www.bing.com/search?q=" + UrlEncodeBasic(s);
        return L"https://" + s;
    }
    return s;
}

void UpdateTabButtons() {
    for (int i = 0; i < kMaxTabs; ++i) {
        ShowWindow(g_tabButtons[i], i < g_tabCount ? SW_SHOW : SW_HIDE);
        if (i < g_tabCount) {
            std::wstring label = (i == g_activeTab ? L"● " : L"") + std::to_wstring(i + 1);
            if (!g_tabs[i].title.empty()) {
                std::wstring t = g_tabs[i].title.substr(0, 16);
                label += L"  " + t;
            }
            SetWindowTextW(g_tabButtons[i], label.c_str());
        }
    }
}

void UpdateWindowTitle() {
    std::wstring title = g_tabs[g_activeTab].title;
    if (!title.empty()) title += L" — ";
    title += g_appTitle;
    title += L" [β ";
    title += kBuildVersion;
    title += L"]";
    SetWindowTextW(g_main, title.c_str());
}

void NavigateActive(const std::wstring& raw) {
    std::wstring url = NormalizeAddress(raw);
    g_tabs[g_activeTab].url = url;
    SetWindowTextW(g_address, url.c_str());
    SaveState();
    if (g_webview) {
        HRESULT hr = g_webview->Navigate(url.c_str());
        if (FAILED(hr)) {
            wchar_t code[32]{};
            swprintf_s(code, L"0x%08X", static_cast<unsigned int>(hr));
            RecordError(L"NAVIGATE_CALL_FAILED", code, L"MEDIUM",
                        L"Navigate active tab", L"Navigation request accepted",
                        L"WebView2 Navigate returned failure for " + SanitizeUrl(url),
                        L"STRONG_CANDIDATE", L"WebView2 navigation call rejected synchronously",
                        L"Navigate invalid/edge inputs and assert graceful error capture",
                        L"Every synchronous WebView2 API failure must be captured with a sanitized origin.");
        }
    }
}

void SyncCurrentUrlFromWebView() {
    if (!g_webview) return;
    LPWSTR source = nullptr;
    if (SUCCEEDED(g_webview->get_Source(&source)) && source) {
        g_tabs[g_activeTab].url = source;
        SetWindowTextW(g_address, source);
        CoTaskMemFree(source);
        SaveState();
    }
}

void SyncTitleFromWebView() {
    if (!g_webview) return;
    LPWSTR title = nullptr;
    if (SUCCEEDED(g_webview->get_DocumentTitle(&title)) && title) {
        g_tabs[g_activeTab].title = title;
        CoTaskMemFree(title);
        UpdateTabButtons();
        UpdateWindowTitle();
        SaveState();
    }
}

void SwitchTab(int idx) {
    if (idx < 0 || idx >= g_tabCount || idx == g_activeTab) return;
    SyncCurrentUrlFromWebView();
    g_activeTab = idx;
    UpdateTabButtons();
    UpdateWindowTitle();
    SetWindowTextW(g_address, g_tabs[g_activeTab].url.c_str());
    SaveState();
    AppendTelemetry(L"TAB_SWITCH", L"INFO", L"logical_tab=" + std::to_wstring(idx));
    if (g_webview) g_webview->Navigate(g_tabs[g_activeTab].url.c_str());
}

void NewTab() {
    if (g_tabCount >= kMaxTabs) {
        AppendTelemetry(L"TAB_LIMIT_REACHED", L"INFO", L"max=3");
        MessageBeep(MB_ICONINFORMATION);
        return;
    }
    SyncCurrentUrlFromWebView();
    int idx = g_tabCount++;
    g_tabs[idx].url = g_home;
    g_tabs[idx].title.clear();
    g_activeTab = idx;
    UpdateTabButtons();
    UpdateWindowTitle();
    SaveState();
    AppendTelemetry(L"TAB_CREATED", L"INFO", L"logical_tab=" + std::to_wstring(idx));
    NavigateActive(g_home);
}

void CloseTab() {
    if (g_tabCount <= 1) {
        NavigateActive(L"about:blank");
        g_tabs[0].title.clear();
        UpdateTabButtons();
        return;
    }
    for (int i = g_activeTab; i < g_tabCount - 1; ++i) g_tabs[i] = g_tabs[i + 1];
    g_tabs[g_tabCount - 1] = TabState{L"about:blank", L""};
    --g_tabCount;
    if (g_activeTab >= g_tabCount) g_activeTab = g_tabCount - 1;
    UpdateTabButtons();
    UpdateWindowTitle();
    SaveState();
    AppendTelemetry(L"TAB_CLOSED", L"INFO", L"remaining=" + std::to_wstring(g_tabCount));
    NavigateActive(g_tabs[g_activeTab].url);
}

void Layout() {
    if (!g_main) return;
    RECT rc{};
    GetClientRect(g_main, &rc);
    int w = rc.right - rc.left;
    int viewTop = kToolbarH + kTabsH;

    int x = 6;
    MoveWindow(g_back, x, 6, 34, 28, TRUE); x += 38;
    MoveWindow(g_forward, x, 6, 34, 28, TRUE); x += 38;
    MoveWindow(g_reload, x, 6, 34, 28, TRUE); x += 40;
    int rightButtons = 6 + 42 + 42 + 72;
    int addressW = std::max(120, w - x - rightButtons);
    MoveWindow(g_address, x, 6, addressW, 28, TRUE); x += addressW + 4;
    MoveWindow(g_go, x, 6, 42, 28, TRUE); x += 46;
    MoveWindow(g_newTab, x, 6, 42, 28, TRUE); x += 46;
    MoveWindow(g_closeTab, x, 6, 68, 28, TRUE);

    int tabW = std::max(90, std::min(220, (w - 12) / 3));
    for (int i = 0; i < kMaxTabs; ++i) {
        MoveWindow(g_tabButtons[i], 6 + i * tabW, kToolbarH + 2, tabW - 4, 26, TRUE);
    }

    if (g_controller) {
        RECT bounds{0, viewTop, w, std::max(viewTop, static_cast<int>(rc.bottom))};
        g_controller->put_Bounds(bounds);
    }
}

void ShowRuntimeMissing(HRESULT hr) {
    wchar_t code[32]{};
    swprintf_s(code, L"0x%08X", static_cast<unsigned int>(hr));
    RecordError(L"WEBVIEW2_RUNTIME_INIT_FAILED", code, L"HIGH",
                L"Initialize WebView2 runtime", L"Runtime environment created",
                L"WebView2 environment/controller initialization failed",
                L"UNKNOWN", L"Runtime missing, damaged, incompatible, or initialization failure",
                L"Cold-start with runtime present/missing/damaged and assert durable diagnostic",
                L"A browser beta must turn runtime bootstrap failures into durable evidence, not screenshots.");

    wchar_t msg[1024]{};
    swprintf_s(msg,
        L"%s could not start Microsoft Edge WebView2 Runtime.\n\nHRESULT: 0x%08X\n\n"
        L"A diagnostic report has already been written locally and queued to the ChatGPT-PC telemetry bridge when available.",
        g_appTitle.c_str(), static_cast<unsigned int>(hr));
    MessageBoxW(g_main, msg, g_appTitle.c_str(), MB_OK | MB_ICONERROR);
}

VOID CALLBACK LowMemoryWaitCallback(PVOID, BOOLEAN) {
    if (g_main) PostMessageW(g_main, WM_APP_LOW_MEMORY, 0, 0);
}

void SetupLowMemorySignal() {
    g_lowMemHandle = CreateMemoryResourceNotification(LowMemoryResourceNotification);
    if (g_lowMemHandle) {
        RegisterWaitForSingleObject(&g_lowMemWait, g_lowMemHandle, LowMemoryWaitCallback, nullptr, INFINITE, WT_EXECUTEDEFAULT);
    } else {
        RecordError(L"LOW_MEMORY_WATCH_SETUP_FAILED", std::to_wstring(GetLastError()), L"LOW",
                    L"Register Windows low-memory notification", L"Notification handle registered",
                    L"CreateMemoryResourceNotification failed",
                    L"UNKNOWN", L"Windows API setup failure",
                    L"Exercise startup with notification API available/unavailable",
                    L"Resource guards must fail open and leave evidence.");
    }
}

void CleanupLowMemorySignal() {
    if (g_lowMemWait) {
        UnregisterWaitEx(g_lowMemWait, INVALID_HANDLE_VALUE);
        g_lowMemWait = nullptr;
    }
    if (g_lowMemHandle) {
        CloseHandle(g_lowMemHandle);
        g_lowMemHandle = nullptr;
    }
}

void RecordRuntimeVersion() {
    LPWSTR version = nullptr;
    HRESULT hr = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
    if (SUCCEEDED(hr) && version) {
        g_runtimeVersion = version;
        std::wstring runtimePath = Join(g_dataRoot, L"runtime.ini");
        std::wstring previous = ReadIni(L"runtime", L"version", L"", runtimePath);
        if (previous != version) {
            WriteIni(L"runtime", L"previous", previous, runtimePath);
            WriteIni(L"runtime", L"version", version, runtimePath);
            WriteIni(L"runtime", L"changed", L"1", runtimePath);
            AppendTelemetry(L"WEBVIEW2_RUNTIME_CHANGED", L"INFO",
                            (previous.empty() ? L"first_seen" : previous) + L" -> " + std::wstring(version));
        } else {
            WriteIni(L"runtime", L"changed", L"0", runtimePath);
        }
        CoTaskMemFree(version);
    } else {
        wchar_t code[32]{};
        swprintf_s(code, L"0x%08X", static_cast<unsigned int>(hr));
        AppendTelemetry(L"WEBVIEW2_RUNTIME_VERSION_UNAVAILABLE", L"WARNING", code);
    }
}

void InitWebView() {
    if (g_webview || g_initStage == L"ENV_REQUESTED" || g_initStage == L"CONTROLLER_REQUESTED") return;
    g_initStage = L"ENV_REQUESTED";
    AppendTelemetry(L"WEBVIEW2_INIT_BEGIN", L"INFO", L"message_loop_ready=1 hwnd_valid=" + std::to_wstring(g_main != nullptr));
    WriteHealthStatus();
    RecordRuntimeVersion();
    HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr,
        g_udfPath.c_str(),
        nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                if (FAILED(result) || !env) {
                    g_initStage = L"ENV_FAILED";
                    ShowRuntimeMissing(result);
                    return S_OK;
                }
                g_environment = env;
                g_initStage = L"ENV_READY";
                AppendTelemetry(L"WEBVIEW2_ENV_READY", L"INFO", g_runtimeVersion);
                WriteHealthStatus();
                g_initStage = L"CONTROLLER_REQUESTED";
                env->CreateCoreWebView2Controller(
                    g_main,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [](HRESULT result2, ICoreWebView2Controller* controller) -> HRESULT {
                            if (FAILED(result2) || !controller) {
                                g_initStage = L"CONTROLLER_FAILED";
                                ShowRuntimeMissing(result2);
                                return S_OK;
                            }
                            g_controller = controller;
                            g_controller->get_CoreWebView2(g_webview.GetAddressOf());
                            if (!g_webview) {
                                g_initStage = L"CORE_NULL";
                                RecordError(L"WEBVIEW2_CORE_NULL", L"E_FAIL", L"HIGH",
                                            L"Acquire CoreWebView2", L"Core interface available",
                                            L"Controller exists but CoreWebView2 is null",
                                            L"UNKNOWN", L"Unexpected controller/core initialization divergence",
                                            L"Assert controller success always yields non-null core or durable failure",
                                            L"Partial initialization must never look healthy.");
                                return E_FAIL;
                            }

                            ComPtr<ICoreWebView2Settings> settings;
                            if (SUCCEEDED(g_webview->get_Settings(&settings)) && settings) {
                                settings->put_IsStatusBarEnabled(FALSE);
                                settings->put_AreDefaultContextMenusEnabled(TRUE);
                                settings->put_AreDevToolsEnabled(FALSE);
                                settings->put_IsZoomControlEnabled(TRUE);
                            }

                            g_webview->add_NavigationCompleted(
                                Callback<ICoreWebView2NavigationCompletedEventHandler>(
                                    [](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                                        BOOL ok = FALSE;
                                        COREWEBVIEW2_WEB_ERROR_STATUS webStatus = COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
                                        if (args) {
                                            args->get_IsSuccess(&ok);
                                            if (!ok) args->get_WebErrorStatus(&webStatus);
                                        }
                                        SyncCurrentUrlFromWebView();
                                        SyncTitleFromWebView();
                                        if (!ok) {
                                            std::wstring origin = SanitizeUrl(g_tabs[g_activeTab].url);
                                            RecordError(L"NAVIGATION_FAILED", std::to_wstring(static_cast<int>(webStatus)), L"MEDIUM",
                                                        L"Complete web navigation", L"Navigation succeeds or reports bounded network failure",
                                                        L"Navigation failed for sanitized origin " + origin,
                                                        L"UNKNOWN", L"Network, TLS, DNS, policy, renderer, or remote endpoint failure",
                                                        L"Inject offline/DNS/TLS failures and assert automatic diagnostic without full URL leakage",
                                                        L"Navigation failures need machine-readable WebErrorStatus plus a privacy-safe origin.");
                                        }
                                        return S_OK;
                                    }).Get(),
                                &g_navCompletedToken);

                            g_webview->add_DocumentTitleChanged(
                                Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
                                    [](ICoreWebView2*, IUnknown*) -> HRESULT {
                                        SyncTitleFromWebView();
                                        return S_OK;
                                    }).Get(),
                                &g_titleChangedToken);

                            g_webview->add_ProcessFailed(
                                Callback<ICoreWebView2ProcessFailedEventHandler>(
                                    [](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) -> HRESULT {
                                        COREWEBVIEW2_PROCESS_FAILED_KIND kind = COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED;
                                        if (args) args->get_ProcessFailedKind(&kind);
                                        std::wstring sev =
                                            (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED ? L"HIGH" : L"MEDIUM");
                                        RecordError(L"WEBVIEW2_PROCESS_FAILED", std::to_wstring(static_cast<int>(kind)), sev,
                                                    L"Keep browser/render process healthy", L"WebView2 process remains available",
                                                    L"WebView2 ProcessFailed event captured",
                                                    L"UNKNOWN", L"Renderer/browser/GPU/utility process terminated or became unhealthy",
                                                    L"Force renderer/browser termination and assert process-kind evidence plus recovery path",
                                                    L"Process failures must be classified by WebView2 process kind and preserved automatically.");
                                        if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED ||
                                            kind == COREWEBVIEW2_PROCESS_FAILED_KIND_FRAME_RENDER_PROCESS_EXITED) {
                                            MessageBoxW(g_main,
                                                L"A web content process stopped. The incident has already been captured. Use Reload when ready.",
                                                g_appTitle.c_str(), MB_OK | MB_ICONWARNING);
                                        }
                                        return S_OK;
                                    }).Get(),
                                &g_processFailedToken);

                            g_initStage = L"READY";
                            if (g_main) KillTimer(g_main, TIMER_WEBVIEW_WATCHDOG);
                            Layout();
                            UpdateTabButtons();
                            UpdateWindowTitle();
                            SetWindowTextW(g_address, g_tabs[g_activeTab].url.c_str());
                            AppendTelemetry(L"WEBVIEW2_CONTROLLER_READY", L"INFO", L"physical_slots=1");
                            WriteHeartbeat();
                            g_webview->Navigate(g_tabs[g_activeTab].url.c_str());
                            return S_OK;
                        }).Get());
                return S_OK;
            }).Get());

    if (FAILED(hr)) {
        g_initStage = L"ENV_REQUEST_FAILED";
        ShowRuntimeMissing(hr);
    }
}

LONG WINAPI CrashFilter(EXCEPTION_POINTERS* ep) {
    if (!g_crashDir.empty()) {
        SYSTEMTIME st{};
        GetSystemTime(&st);
        wchar_t stem[128]{};
        swprintf_s(stem, L"crash-%04u%02u%02uT%02u%02u%02uZ-%lu",
                   st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, GetCurrentProcessId());
        std::wstring dumpPath = Join(g_crashDir, std::wstring(stem) + L".dmp");
        HANDLE h = CreateFileW(dumpPath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h != INVALID_HANDLE_VALUE) {
            MINIDUMP_EXCEPTION_INFORMATION mei{};
            mei.ThreadId = GetCurrentThreadId();
            mei.ExceptionPointers = ep;
            mei.ClientPointers = FALSE;
            MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), h, MiniDumpNormal,
                              ep ? &mei : nullptr, nullptr, nullptr);
            FlushFileBuffers(h);
            CloseHandle(h);
        }

        DWORD code = (ep && ep->ExceptionRecord) ? ep->ExceptionRecord->ExceptionCode : 0;
        wchar_t txt[512]{};
        swprintf_s(txt, L"utc=%s\r\nrun_id=%s\r\nversion=%s\r\nexception_code=0x%08X\r\ndump=%s\r\n",
                   UtcNowIso().c_str(), g_runId.c_str(), kBuildVersion, code, dumpPath.c_str());
        HANDLE t = CreateFileW(Join(g_crashDir, L"LAST_CRASH.txt").c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                               nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (t != INVALID_HANDLE_VALUE) {
            std::string u = WideToUtf8(txt);
            DWORD written = 0;
            WriteFile(t, u.data(), static_cast<DWORD>(u.size()), &written, nullptr);
            FlushFileBuffers(t);
            CloseHandle(t);
        }
    }
    return EXCEPTION_EXECUTE_HANDLER;
}

void BeginRun() {
    g_runId = NewId();
    g_startedUtc = UtcNowIso();

    if (FileExists(g_runMarkerPath)) {
        RecordError(L"UNCLEAN_SHUTDOWN", L"RUN_MARKER_PRESENT", L"HIGH",
                    L"Complete previous browser run cleanly", L"Previous RUNNING marker removed during orderly shutdown",
                    L"Previous RUNNING marker still present at startup",
                    L"STRONG_CANDIDATE", L"Prior process terminated unexpectedly, OS/power loss, or forced kill",
                    L"Kill process/power cycle and assert next startup emits UNCLEAN_SHUTDOWN with persistent evidence",
                    L"A stale run marker is a durable crash/power-loss signal and must become an automatic field incident.");
    }

    std::ostringstream marker;
    marker << "{\"schema\":\"browser4g-run/1\""
           << ",\"run_id\":\"" << JsonEscapeUtf8(g_runId) << "\""
           << ",\"version\":\"" << JsonEscapeUtf8(kBuildVersion) << "\""
           << ",\"started_utc\":\"" << JsonEscapeUtf8(g_startedUtc) << "\""
           << ",\"pid\":" << GetCurrentProcessId()
           << "}";
    AtomicWriteUtf8(g_runMarkerPath, marker.str() + "\n");
    AppendTelemetry(L"APP_START", L"INFO", L"beta_instrumentation=1");
    WriteHeartbeat();
}

void EndRunCleanly() {
    if (InterlockedExchange(&g_cleanShutdown, 1) != 0) return;
    AppendTelemetry(L"APP_CLEAN_SHUTDOWN", L"INFO");
    SaveState();
    WriteHealthStatus();
    DeleteFileW(g_runMarkerPath.c_str());
    QueueBridge();
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        // CreateWindowExW delivers WM_CREATE before its return value is assigned to g_main.
        // Bind the actual HWND immediately, then defer WebView2 bootstrap until the message loop is active.
        g_main = hwnd;
        g_uiFont = CreateFontW(-18, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                               OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                               DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
        HFONT font = g_uiFont ? g_uiFont : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
        auto makeButton = [&](const wchar_t* text, int id) {
            HWND h = CreateWindowW(L"BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                   0, 0, 10, 10, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
            SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
            return h;
        };
        g_back = makeButton(L"←", ID_BACK);
        g_forward = makeButton(L"→", ID_FORWARD);
        g_reload = makeButton(L"↻", ID_RELOAD);
        g_address = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                    0, 0, 10, 10, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(ID_ADDRESS)), nullptr, nullptr);
        SendMessageW(g_address, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        g_go = makeButton(L"Go", ID_GO);
        g_newTab = makeButton(L"+", ID_NEW_TAB);
        g_closeTab = makeButton(L"Close", ID_CLOSE_TAB);
        g_tabButtons[0] = makeButton(L"1", ID_TAB1);
        g_tabButtons[1] = makeButton(L"2", ID_TAB2);
        g_tabButtons[2] = makeButton(L"3", ID_TAB3);
        UpdateTabButtons();
        SetupLowMemorySignal();
        SetTimer(hwnd, TIMER_HEARTBEAT, HEARTBEAT_MS, nullptr);
        SetTimer(hwnd, TIMER_WEBVIEW_WATCHDOG, WEBVIEW_WATCHDOG_MS, nullptr);
        PostMessageW(hwnd, WM_APP_INIT_WEBVIEW, 0, 0);
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
    case WM_APP_INIT_WEBVIEW:
        InitWebView();
        return 0;
    case WM_TIMER:
        if (wp == TIMER_HEARTBEAT) {
            WriteHeartbeat();
            return 0;
        }
        if (wp == TIMER_WEBVIEW_WATCHDOG) {
            KillTimer(hwnd, TIMER_WEBVIEW_WATCHDOG);
            if (!g_webview) {
                RecordError(L"WEBVIEW2_INIT_TIMEOUT", g_initStage, L"HIGH",
                            L"Initialize WebView2 after native window creation",
                            L"Environment and controller become ready within 15 seconds",
                            L"WebView2 initialization did not reach READY; init_stage=" + g_initStage,
                            L"STRONG_CANDIDATE",
                            L"Initialization stalled before environment/controller completion; previous build could start WebView2 during WM_CREATE before the final HWND assignment/message-loop readiness",
                            L"Cold-start repeatedly under 80/90/95% memory pressure and assert READY or explicit stage failure within 15 seconds",
                            L"WebView2 bootstrap must begin only after the final HWND exists and the UI message loop can service asynchronous completion.");
            }
            return 0;
        }
        break;
    case WM_COMMAND: {
        int id = LOWORD(wp);
        if (id == ID_BACK && g_webview) {
            BOOL can = FALSE; g_webview->get_CanGoBack(&can); if (can) g_webview->GoBack();
        } else if (id == ID_FORWARD && g_webview) {
            BOOL can = FALSE; g_webview->get_CanGoForward(&can); if (can) g_webview->GoForward();
        } else if (id == ID_RELOAD && g_webview) {
            g_webview->Reload();
        } else if (id == ID_GO) {
            int len = GetWindowTextLengthW(g_address);
            std::wstring text(static_cast<size_t>(len) + 1, L'\0');
            GetWindowTextW(g_address, text.data(), len + 1);
            text.resize(static_cast<size_t>(len));
            NavigateActive(text);
        } else if (id == ID_NEW_TAB) {
            NewTab();
        } else if (id == ID_CLOSE_TAB) {
            CloseTab();
        } else if (id >= ID_TAB1 && id <= ID_TAB3) {
            SwitchTab(id - ID_TAB1);
        }
        return 0;
    }
    case WM_APP_LOW_MEMORY: {
        MemorySnapshot m = MemoryNow();
        RecordError(L"LOW_MEMORY_SIGNAL", std::to_wstring(m.load), L"MEDIUM",
                    L"Keep browser usable under memory pressure", L"Maintain safe memory headroom",
                    L"Windows LowMemoryResourceNotification fired; available_mb=" + std::to_wstring(m.availMb),
                    L"CONFIRMED", L"System memory pressure crossed Windows low-memory threshold",
                    L"Stress host memory to 80/90/95% and assert notification, no second renderer allocation, and continued heartbeat",
                    L"Field memory pressure is a first-class beta incident and must be captured without user screenshots.");
        SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
        return 0;
    }
    case WM_CLOSE:
        SyncCurrentUrlFromWebView();
        EndRunCleanly();
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, TIMER_HEARTBEAT);
        KillTimer(hwnd, TIMER_WEBVIEW_WATCHDOG);
        CleanupLowMemorySignal();
        if (g_controller) g_controller->Close();
        g_webview.Reset();
        g_controller.Reset();
        g_environment.Reset();
        if (g_uiFont) {
            DeleteObject(g_uiFont);
            g_uiFont = nullptr;
        }
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    HRESULT co = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(co)) return 2;

    LoadConfigAndState();
    SetUnhandledExceptionFilter(CrashFilter);
    BeginRun();

    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = L"BuildHubWebViewShellWindow";
    if (!RegisterClassExW(&wc)) {
        RecordError(L"WINDOW_CLASS_REGISTER_FAILED", std::to_wstring(GetLastError()), L"HIGH",
                    L"Register browser window class", L"Window class registered",
                    L"RegisterClassExW failed", L"UNKNOWN", L"Win32 window bootstrap failure",
                    L"Assert bootstrap errors are durable and leave run evidence",
                    L"Native bootstrap failures require the same telemetry discipline as WebView failures.");
        CoUninitialize();
        return 3;
    }

    g_main = CreateWindowExW(0, wc.lpszClassName, g_appTitle.c_str(),
                             WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                             CW_USEDEFAULT, CW_USEDEFAULT, 1180, 760,
                             nullptr, nullptr, instance, nullptr);
    if (!g_main) {
        RecordError(L"WINDOW_CREATE_FAILED", std::to_wstring(GetLastError()), L"HIGH",
                    L"Create main browser window", L"Main window created",
                    L"CreateWindowExW failed", L"UNKNOWN", L"Win32 window creation failure",
                    L"Assert CreateWindow failure yields a durable update request",
                    L"A failed GUI bootstrap must never be silent.");
        CoUninitialize();
        return 4;
    }

    ShowWindow(g_main, show);
    UpdateWindow(g_main);

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    EndRunCleanly();
    CoUninitialize();
    return static_cast<int>(msg.wParam);
}
