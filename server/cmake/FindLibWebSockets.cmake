# FindLibWebSockets.cmake - Find libwebsockets library
# Sets LIBWEBSOCKETS_FOUND, LIBWEBSOCKETS_INCLUDE_DIRS, LIBWEBSOCKETS_LIBRARIES

find_path(LIBWEBSOCKETS_INCLUDE_DIR NAMES libwebsockets.h)
find_library(LIBWEBSOCKETS_LIBRARY NAMES websockets websockets_static)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(LibWebSockets
  REQUIRED_VARS LIBWEBSOCKETS_LIBRARY LIBWEBSOCKETS_INCLUDE_DIR
)

if(LibWebSockets_FOUND)
  set(LIBWEBSOCKETS_INCLUDE_DIRS "${LIBWEBSOCKETS_INCLUDE_DIR}")
  set(LIBWEBSOCKETS_LIBRARIES "${LIBWEBSOCKETS_LIBRARY}")
endif()
