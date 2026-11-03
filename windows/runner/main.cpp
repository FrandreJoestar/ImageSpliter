#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"imagespliter", origin, size)) {
    return EXIT_FAILURE;
  }

  // Center the window in the work area of its monitor (excluding the taskbar).
  if (HWND handle = window.GetHandle()) {
    RECT window_rect;
    ::GetWindowRect(handle, &window_rect);
    HMONITOR monitor = ::MonitorFromWindow(handle, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (::GetMonitorInfo(monitor, &monitor_info)) {
      const int width = window_rect.right - window_rect.left;
      const int height = window_rect.bottom - window_rect.top;
      const int work_width =
          monitor_info.rcWork.right - monitor_info.rcWork.left;
      const int work_height =
          monitor_info.rcWork.bottom - monitor_info.rcWork.top;
      const int x =
          monitor_info.rcWork.left +
          (work_width > width ? (work_width - width) / 2 : 0);
      const int y =
          monitor_info.rcWork.top +
          (work_height > height ? (work_height - height) / 2 : 0);
      ::SetWindowPos(handle, nullptr, x, y, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
