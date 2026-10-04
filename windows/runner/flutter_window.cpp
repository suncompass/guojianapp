#include "flutter_window.h"

#include <windows.h>

#include <dpapi.h>

#include <optional>
#include <vector>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// DPAPI 只把密文交给 Dart，存放位置仍由 SharedPreferences 决定。
// 这里的失败必须回传空值，让 Dart 退回原有明文路径，而不是让身份变成不可用。
std::optional<std::vector<uint8_t>> ProtectSecret(const std::string& value) {
  DATA_BLOB input{};
  input.cbData = static_cast<DWORD>(value.size());
  input.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(value.data()));
  DATA_BLOB output{};
  if (!CryptProtectData(&input, L"duanju.secret.v1", nullptr, nullptr, nullptr, 0,
                        &output)) {
    return std::nullopt;
  }
  std::vector<uint8_t> blob(output.pbData, output.pbData + output.cbData);
  LocalFree(output.pbData);
  return blob;
}

std::optional<std::string> UnprotectSecret(const std::vector<uint8_t>& blob) {
  if (blob.empty()) {
    return std::nullopt;
  }
  DATA_BLOB input{};
  input.cbData = static_cast<DWORD>(blob.size());
  input.pbData = reinterpret_cast<BYTE*>(const_cast<uint8_t*>(blob.data()));
  DATA_BLOB output{};
  if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, 0,
                          &output)) {
    return std::nullopt;
  }
  std::string value(reinterpret_cast<const char*>(output.pbData),
                    output.cbData);
  LocalFree(output.pbData);
  return value;
}

const flutter::EncodableValue* SecretArgument(
    const flutter::EncodableValue* arguments, const char* name) {
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto entry = map->find(flutter::EncodableValue(name));
  return entry == map->end() ? nullptr : &entry->second;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "duanju/device",
          &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "protectSecret") {
          const auto* value = SecretArgument(call.arguments(), "value");
          if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
            result->Error("invalid_secret", "缺少待保护的内容");
            return;
          }
          const auto blob = ProtectSecret(std::get<std::string>(*value));
          result->Success(blob ? flutter::EncodableValue(*blob)
                               : flutter::EncodableValue());
          return;
        }
        if (call.method_name() == "unprotectSecret") {
          const auto* blob = SecretArgument(call.arguments(), "blob");
          if (blob == nullptr ||
              !std::holds_alternative<std::vector<uint8_t>>(*blob)) {
            result->Error("invalid_secret", "缺少待解密的内容");
            return;
          }
          const auto value =
              UnprotectSecret(std::get<std::vector<uint8_t>>(*blob));
          result->Success(value ? flutter::EncodableValue(*value)
                                : flutter::EncodableValue());
          return;
        }
        if (call.method_name() != "playbackPower") {
          result->NotImplemented();
          return;
        }
        SYSTEM_POWER_STATUS power{};
        const bool known = GetSystemPowerStatus(&power) != 0;
        MEMORYSTATUSEX memory{};
        memory.dwLength = sizeof(memory);
        const bool memory_known = GlobalMemoryStatusEx(&memory) != 0;
        flutter::EncodableMap values;
        values[flutter::EncodableValue("batterySaver")] =
            flutter::EncodableValue(known && power.SystemStatusFlag == 1);
        values[flutter::EncodableValue("onBattery")] =
            flutter::EncodableValue(!known || power.ACLineStatus != 1);
        values[flutter::EncodableValue("lowMemory")] =
            flutter::EncodableValue(!memory_known || memory.ullTotalPhys < 4ULL * 1024 * 1024 * 1024);
        result->Success(flutter::EncodableValue(values));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  device_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
