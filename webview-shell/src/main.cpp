#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <wrl.h>
#include <WebView2.h>
#include <array>
#include <string>
#include <algorithm>
#include <cwctype>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {
constexpr int kMaxTabs = 3;
constexpr int kToolbarH = 40;
constexpr int kTabsH = 32;
constexpr UINT WM_APP_LOW_MEMORY = WM_APP + 11;

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
ComPtr<ICoreWebView2Environment> g_environment;
ComPtr<ICoreWebView2Controller> g_controller;
ComPtr<ICoreWebView2> g_webview;
EventRegistrationToken g_navCompletedToken{};
EventRegistrationToken g_titleChangedToken{};
EventRegistrationToken g_processFailedToken{};
HANDLE g_lowMemHandle = nullptr;
HANDLE g_lowMemWait = nullptr;

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

std::wstring ReadIni(const wchar_t* section, const wchar_t* key, const std::wstring& def, const std::wstring& path) {
    wchar_t buf[2048]{};
    GetPrivateProfileStringW(section, key, def.c_str(), buf, static_cast<DWORD>(_countof(buf)), path.c_str());
    return buf;
}

int ReadIniInt(const wchar_t* section, const wchar_t* key, int def, const std::wstring& path) {
    return GetPrivateProfileIntW(section, key, def, path.c_str());
}

void WriteIni(const wchar_t* section, const wchar_t* key, const std::wstring& value, const std::wstring& path) {
    WritePrivateProfileStringW(section, key, value.c_str(), path.c_str());
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
    SetWindowTextW(g_main, title.c_str());
}

void NavigateActive(const std::wstring& raw) {
    std::wstring url = NormalizeAddress(raw);
    g_tabs[g_activeTab].url = url;
    SetWindowTextW(g_address, url.c_str());
    SaveState();
    if (g_webview) g_webview->Navigate(url.c_str());
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
    if (g_webview) g_webview->Navigate(g_tabs[g_activeTab].url.c_str());
}

void NewTab() {
    if (g_tabCount >= kMaxTabs) {
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
    wchar_t msg[1024]{};
    swprintf_s(msg,
        L"%s could not start Microsoft Edge WebView2 Runtime.\n\nHRESULT: 0x%08X\n\n"
        L"Windows 11 normally includes WebView2. If it is missing or damaged, install/repair the Microsoft Edge WebView2 Evergreen Runtime, then relaunch.",
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
    if (SUCCEEDED(GetAvailableCoreWebView2BrowserVersionString(nullptr, &version)) && version) {
        std::wstring runtimePath = Join(g_dataRoot, L"runtime.ini");
        std::wstring previous = ReadIni(L"runtime", L"version", L"", runtimePath);
        if (previous != version) {
            WriteIni(L"runtime", L"previous", previous, runtimePath);
            WriteIni(L"runtime", L"version", version, runtimePath);
            WriteIni(L"runtime", L"changed", L"1", runtimePath);
        } else {
            WriteIni(L"runtime", L"changed", L"0", runtimePath);
        }
        CoTaskMemFree(version);
    }
}

void InitWebView() {
    RecordRuntimeVersion();
    HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr,
        g_udfPath.c_str(),
        nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
                if (FAILED(result) || !env) {
                    ShowRuntimeMissing(result);
                    return S_OK;
                }
                g_environment = env;
                env->CreateCoreWebView2Controller(
                    g_main,
                    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                        [](HRESULT result2, ICoreWebView2Controller* controller) -> HRESULT {
                            if (FAILED(result2) || !controller) {
                                ShowRuntimeMissing(result2);
                                return S_OK;
                            }
                            g_controller = controller;
                            g_controller->get_CoreWebView2(g_webview.GetAddressOf());
                            if (!g_webview) return E_FAIL;

                            ComPtr<ICoreWebView2Settings> settings;
                            if (SUCCEEDED(g_webview->get_Settings(&settings)) && settings) {
                                settings->put_IsStatusBarEnabled(FALSE);
                                settings->put_AreDefaultContextMenusEnabled(TRUE);
                                settings->put_AreDevToolsEnabled(FALSE);
                                settings->put_IsZoomControlEnabled(TRUE);
                            }

                            g_webview->add_NavigationCompleted(
                                Callback<ICoreWebView2NavigationCompletedEventHandler>(
                                    [](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs*) -> HRESULT {
                                        SyncCurrentUrlFromWebView();
                                        SyncTitleFromWebView();
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
                                        COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
                                        if (args) args->get_ProcessFailedKind(&kind);
                                        if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED ||
                                            kind == COREWEBVIEW2_PROCESS_FAILED_KIND_FRAME_RENDER_PROCESS_EXITED) {
                                            MessageBoxW(g_main,
                                                L"A web content process stopped. The current address is preserved. Use Reload when ready.",
                                                g_appTitle.c_str(), MB_OK | MB_ICONWARNING);
                                        }
                                        return S_OK;
                                    }).Get(),
                                &g_processFailedToken);

                            Layout();
                            UpdateTabButtons();
                            UpdateWindowTitle();
                            SetWindowTextW(g_address, g_tabs[g_activeTab].url.c_str());
                            g_webview->Navigate(g_tabs[g_activeTab].url.c_str());
                            return S_OK;
                        }).Get());
                return S_OK;
            }).Get());

    if (FAILED(hr)) ShowRuntimeMissing(hr);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
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
        InitWebView();
        return 0;
    }
    case WM_SIZE:
        Layout();
        return 0;
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
    case WM_APP_LOW_MEMORY:
        SetProcessWorkingSetSize(GetCurrentProcess(), static_cast<SIZE_T>(-1), static_cast<SIZE_T>(-1));
        return 0;
    case WM_CLOSE:
        SyncCurrentUrlFromWebView();
        SaveState();
        DestroyWindow(hwnd);
        return 0;
    case WM_DESTROY:
        CleanupLowMemorySignal();
        if (g_controller) g_controller->Close();
        g_webview.Reset();
        g_controller.Reset();
        g_environment.Reset();
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

    WNDCLASSEXW wc{sizeof(wc)};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = instance;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.lpszClassName = L"BuildHubWebViewShellWindow";
    RegisterClassExW(&wc);

    g_main = CreateWindowExW(0, wc.lpszClassName, g_appTitle.c_str(),
                             WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                             CW_USEDEFAULT, CW_USEDEFAULT, 1180, 760,
                             nullptr, nullptr, instance, nullptr);
    if (!g_main) {
        CoUninitialize();
        return 3;
    }
    ShowWindow(g_main, show);
    UpdateWindow(g_main);

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    CoUninitialize();
    return static_cast<int>(msg.wParam);
}
