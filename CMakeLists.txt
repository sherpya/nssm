cmake_minimum_required(VERSION 3.20)

project(nssm LANGUAGES CXX RC)

if(NOT WIN32)
    message(FATAL_ERROR "NSSM only supports Windows.")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

set(NSSM_SOURCES
    account.cpp
    console.cpp
    env.cpp
    event.cpp
    gui.cpp
    hook.cpp
    imports.cpp
    io.cpp
    nssm.cpp
    process.cpp
    registry.cpp
    service.cpp
    settings.cpp
    utf8.cpp
)

set(NSSM_HEADERS
    account.h
    console.h
    env.h
    event.h
    gui.h
    hook.h
    imports.h
    io.h
    nssm.h
    process.h
    registry.h
    service.h
    settings.h
    utf8.h
    resource.h
)

# version.h is regenerated on every build from `git describe`. The script
# only rewrites the file when the contents change, so the timestamp stays
# stable and dependent objects are not needlessly recompiled.
set(VERSION_HEADER "${CMAKE_CURRENT_BINARY_DIR}/version.h")
add_custom_target(nssm_version ALL
    BYPRODUCTS "${VERSION_HEADER}"
    COMMAND ${CMAKE_COMMAND}
        -DSRC_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -DDST_DIR=${CMAKE_CURRENT_BINARY_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateVersion.cmake
    COMMENT "Generating version.h"
    VERBATIM
)
# Make sure version.h exists at configure time so the first build does not
# fail before the custom target runs.
if(NOT EXISTS "${VERSION_HEADER}")
    execute_process(COMMAND ${CMAKE_COMMAND}
        -DSRC_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -DDST_DIR=${CMAKE_CURRENT_BINARY_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateVersion.cmake
    )
endif()

# messages.mc -> messages.h, messages.rc plus per-language MSG*.bin files.
# MC_COMPILER comes from the toolchain file when cross-compiling; on a
# native Windows build we fall back to Microsoft's mc.exe. The file is
# stored as UTF-16 LE without a BOM, which both mc.exe (with -u) and
# windmc accept.
if(NOT MC_COMPILER)
    # Unlike rc.exe, mc.exe is not a compiler managed by CMake's Visual
    # Studio generator.  find_program() therefore does not automatically
    # search the Windows SDK selected by the generator.
    string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" MC_HOST_PROCESSOR)
    if(MC_HOST_PROCESSOR MATCHES "arm64|aarch64")
        set(MC_HOST_ARCH arm64)
    elseif(MC_HOST_PROCESSOR MATCHES "amd64|x86_64")
        set(MC_HOST_ARCH x64)
    else()
        set(MC_HOST_ARCH x86)
    endif()

    set(WINDOWS_SDK_ROOTS)
    if(DEFINED ENV{WindowsSdkDir})
        list(APPEND WINDOWS_SDK_ROOTS "$ENV{WindowsSdkDir}")
    endif()
    if(DEFINED ENV{ProgramFiles\(x86\)})
        list(APPEND WINDOWS_SDK_ROOTS
            "$ENV{ProgramFiles\(x86\)}/Windows Kits/10")
    endif()
    list(REMOVE_DUPLICATES WINDOWS_SDK_ROOTS)

    set(MC_HINTS)
    if(CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
        foreach(WINDOWS_SDK_ROOT IN LISTS WINDOWS_SDK_ROOTS)
            list(APPEND MC_HINTS
                "${WINDOWS_SDK_ROOT}/bin/${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}/${MC_HOST_ARCH}")
        endforeach()
    endif()

    # Keep PATH lookup working, but also check the SDK selected by Visual
    # Studio.  This makes configuration from cmake-gui work without a
    # Developer Command Prompt.
    find_program(MC_COMPILER NAMES mc.exe HINTS ${MC_HINTS})

    # Non-Visual-Studio generators may not expose an SDK version.  Fall back
    # to the newest installed SDK containing a native message compiler.
    if(NOT MC_COMPILER)
        set(MC_CANDIDATES)
        foreach(WINDOWS_SDK_ROOT IN LISTS WINDOWS_SDK_ROOTS)
            file(GLOB WINDOWS_SDK_MC_CANDIDATES
                "${WINDOWS_SDK_ROOT}/bin/*/${MC_HOST_ARCH}/mc.exe")
            list(APPEND MC_CANDIDATES ${WINDOWS_SDK_MC_CANDIDATES})
        endforeach()
        if(MC_CANDIDATES)
            list(SORT MC_CANDIDATES COMPARE NATURAL ORDER DESCENDING)
            list(GET MC_CANDIDATES 0 MC_COMPILER)
            set(MC_COMPILER "${MC_COMPILER}" CACHE FILEPATH
                "Path to the Windows message compiler" FORCE)
        endif()
    endif()

    if(NOT MC_COMPILER)
        message(FATAL_ERROR
            "Could not find mc.exe. Install the Windows SDK or set "
            "MC_COMPILER to its full path.")
    endif()
endif()

set(MESSAGES_HEADER "${CMAKE_CURRENT_BINARY_DIR}/messages.h")
set(MESSAGES_RC "${CMAKE_CURRENT_BINARY_DIR}/messages.rc")

add_custom_command(
    OUTPUT "${MESSAGES_HEADER}" "${MESSAGES_RC}"
    COMMAND ${MC_COMPILER} -u -U
            -r "${CMAKE_CURRENT_BINARY_DIR}"
            -h "${CMAKE_CURRENT_BINARY_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/messages.mc"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/messages.mc"
    COMMENT "Compiling messages.mc"
    VERBATIM
)

add_executable(nssm
    ${NSSM_SOURCES}
    ${NSSM_HEADERS}
    nssm.rc
)

# nssm.rc #includes the generated messages.rc and messages.h, so make the
# resource compile depend on them. Listing messages.rc as a source would
# cause a second MESSAGETABLE to be linked in.
set_source_files_properties(nssm.rc PROPERTIES
    OBJECT_DEPENDS "${MESSAGES_HEADER};${MESSAGES_RC}"
)

add_dependencies(nssm nssm_version)

# Only the build dir on the include path -- it carries the generated
# version.h / messages.h / messages.rc. Source-dir headers are reached by
# quoted includes relative to the file, which avoids shadowing the CRT
# `<io.h>` with the project's own io.h under gcc.
target_include_directories(nssm PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
)

target_compile_definitions(nssm PRIVATE
    WIN32
    _CONSOLE
    UNICODE
    _UNICODE
)

target_link_libraries(nssm PRIVATE psapi shlwapi)

# CharacterSet="1" in the original vcproj, plus /MT(d) static runtime.
set_target_properties(nssm PROPERTIES
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)

if(MSVC)
    # /Zi + /DEBUG in every config so Release builds keep PDBs (matches the
    # vcproj's DebugInformationFormat="3" / GenerateDebugInformation="true").
    target_compile_options(nssm PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:/W3>
        $<$<COMPILE_LANGUAGE:CXX>:/Zi>
    )
    target_link_options(nssm PRIVATE /DEBUG)
else()
    # MinGW: _tmain expands to wmain under UNICODE; -municode wires the
    # CRT entry point to wmain instead of looking for main/WinMain.
    target_compile_options(nssm PRIVATE -municode)
    target_link_options(nssm PRIVATE -municode)
    target_link_options(nssm PRIVATE -static-libstdc++ -static-libgcc)
endif()

# rc.exe does not get _WIN64 from the toolchain, but nssm.rc includes nssm.h
# which keys NSSM_ARCHITECTURE off it. Pass it explicitly on 64-bit builds.
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    target_compile_definitions(nssm PRIVATE
        $<$<COMPILE_LANGUAGE:RC>:_WIN64>
    )
endif()
