cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# --- Window / taskbar icon -----------------------------------------------
# The embedded PNG is what GTK hands to the compositor, so the window and
# taskbar icon is correct even when the app is not launched from an installed
# .desktop entry (the usual cause of the generic "Wayland" icon).
set(APP_ICON_RESOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/resources")
set(APP_ICON_FILE "${APP_ICON_RESOURCE_DIR}/icons/${APPLICATION_ID}.png")

if(EXISTS "${APP_ICON_FILE}")
  # Force a rebuild of the runner whenever the icon changes.
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${APP_ICON_FILE}"
  )
  # Use a string literal with escaped quotes so the compiler sees a proper C
  # string. Writing the quotes literally makes CMake strip them, which turns
  # the path into invalid C++ tokens.
  add_definitions(-DAPP_ICON_EMBED=\"${APP_ICON_FILE}\")
endif()

# Install hicolor theme icons + a .desktop entry so desktop environments
# (GNOME/KDE) can map the running window back to the application, which also
# fixes the icon shown by docks and alt-tab switchers.
set(HICOLOR_ICON_SIZES 16 24 32 48 64 96 128 256 512)
foreach(icon_size ${HICOLOR_ICON_SIZES})
  set(icon_path
    "${APP_ICON_RESOURCE_DIR}/icons/${icon_size}x${icon_size}.png")
  if(EXISTS "${icon_path}")
    install(FILES "${icon_path}"
      DESTINATION
        "share/icons/hicolor/${icon_size}x${icon_size}/apps/"
      RENAME "${APPLICATION_ID}.png")
  endif()
endforeach()

install(FILES
    "${APP_ICON_RESOURCE_DIR}/${APPLICATION_ID}.desktop"
  DESTINATION "share/applications"
  RENAME "${APPLICATION_ID}.desktop")
