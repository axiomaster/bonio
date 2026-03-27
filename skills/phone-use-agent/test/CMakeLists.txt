# Test executables

# CLI Test
add_executable(test_cli
    test_cli.cpp
    ${CMAKE_SOURCE_DIR}/src/CliArgs.cpp
)
target_include_directories(test_cli PRIVATE ${COMMON_HEADERS})
target_link_libraries(test_cli c++ m z)
set_target_properties(test_cli PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# GLM API Test
add_executable(test_glm
    test_glm.cpp
    ${CMAKE_SOURCE_DIR}/src/AutoGLMClient.cpp
    ${CMAKE_SOURCE_DIR}/src/HttpClient.cpp
    ${CMAKE_SOURCE_DIR}/src/ConfigManager.cpp
)
target_include_directories(test_glm PRIVATE ${COMMON_HEADERS} ${PLATFORM_INCLUDE_DIRS})
target_link_libraries(test_glm ${PLATFORM_LIBRARIES})
set_target_properties(test_glm PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Network Test
add_executable(network_test
    network_test.cpp
    ${CMAKE_SOURCE_DIR}/src/HttpClient.cpp
)
target_include_directories(network_test PRIVATE ${COMMON_HEADERS} ${PLATFORM_INCLUDE_DIRS})
target_link_libraries(network_test ${PLATFORM_LIBRARIES})
set_target_properties(network_test PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# Note: test_agent_flow, test_autoglm_logic, test_executor_ut, and size_check
# are disabled for Android builds as they depend on HarmonyOS-specific components
# (UIInspector, AppManager, AccessibilityHelper, net_http.h)
