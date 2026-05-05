# Replicates version.cmd in CMake.
# Run as: cmake -DSRC_DIR=... -DDST_DIR=... -P GenerateVersion.cmake
#
# Honours the same environment variables as version.cmd:
#   BUILD_NUMBER - Jenkins build number (defaults to 0)
#   BUILD_ID     - Jenkins build id, e.g. 2024-01-15_12-34-56 (the leading
#                  component is taken as the year; defaults to current year)

set(NSSM_DESCRIPTION "0.0-0-prerelease")

find_package(Git QUIET)
if(GIT_FOUND)
    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --tags --long
        WORKING_DIRECTORY "${SRC_DIR}"
        OUTPUT_VARIABLE GIT_DESCRIBE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE GIT_RESULT
        ERROR_QUIET
    )
    if(GIT_RESULT EQUAL 0 AND GIT_DESCRIBE)
        set(NSSM_DESCRIPTION "${GIT_DESCRIBE}")
    endif()
endif()

# Strip leading 'v', e.g. v2.21-24-g2c60e53 -> 2.21-24-g2c60e53.
string(REGEX REPLACE "^v" "" NSSM_DESCRIPTION "${NSSM_DESCRIPTION}")

# Split <version>-<n>-<commit>.
if(NSSM_DESCRIPTION MATCHES "^(.+)-([0-9]+)-([^-]+)$")
    set(NSSM_VERSION "${CMAKE_MATCH_1}")
    set(NSSM_N "${CMAKE_MATCH_2}")
    set(NSSM_COMMIT "${CMAKE_MATCH_3}")
else()
    set(NSSM_VERSION "0.0")
    set(NSSM_N "0")
    set(NSSM_COMMIT "prerelease")
endif()

if(NSSM_VERSION MATCHES "^([0-9]+)\\.([0-9]+)")
    set(NSSM_MAJOR "${CMAKE_MATCH_1}")
    set(NSSM_MINOR "${CMAKE_MATCH_2}")
else()
    set(NSSM_MAJOR "0")
    set(NSSM_MINOR "0")
endif()

set(NSSM_FILEFLAGS "0L")
if(NSSM_N STREQUAL "0")
    # Exact tag match -- drop the n-commit suffix.
    set(NSSM_DESCRIPTION "${NSSM_MAJOR}.${NSSM_MINOR}")
else()
    set(NSSM_FILEFLAGS "VS_FF_PRERELEASE")
endif()
if(NSSM_COMMIT STREQUAL "prerelease")
    set(NSSM_FILEFLAGS "VS_FF_PRERELEASE")
endif()

if(DEFINED ENV{BUILD_NUMBER} AND NOT "$ENV{BUILD_NUMBER}" STREQUAL "")
    set(NSSM_BUILD_NUMBER "$ENV{BUILD_NUMBER}")
else()
    set(NSSM_BUILD_NUMBER "0")
endif()

string(TIMESTAMP NSSM_DATE "%Y-%m-%d")

if(DEFINED ENV{BUILD_ID} AND NOT "$ENV{BUILD_ID}" STREQUAL "")
    string(REGEX REPLACE "-.*$" "" NSSM_YEAR "$ENV{BUILD_ID}")
else()
    string(TIMESTAMP NSSM_YEAR "%Y")
endif()

# configure_file only rewrites the destination when the rendered output
# differs, so timestamps stay stable across no-op rebuilds.
configure_file("${SRC_DIR}/cmake/version.h.in" "${DST_DIR}/version.h" @ONLY)
