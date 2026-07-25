cmake_minimum_required(VERSION 3.16.3)

project(openfhe_eval_domain_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenFHE CONFIG REQUIRED)

message(STATUS "OpenFHE Version: ${BASE_OPENFHE_VERSION}")
message(STATUS "OpenFHE include directory: ${OpenFHE_INCLUDE}")
message(STATUS "OpenFHE library directory: ${OpenFHE_LIBDIR}")
message(STATUS "OpenFHE native backend size: ${OpenFHE_NATIVE_SIZE}")

add_executable(
    openfhe_eval_domain_bridge
    openfhe_eval_domain_bridge.cpp
)

add_executable(
    openfhe_relinearization_probe
    openfhe_relinearization_probe.cpp
)

set(_openfhe_flag_entries ${OpenFHE_CXX_FLAGS})
set(_openfhe_bridge_flags)

foreach(_entry IN LISTS _openfhe_flag_entries)
    separate_arguments(
        _entry_parts
        UNIX_COMMAND
        "${_entry}"
    )

    foreach(_flag IN LISTS _entry_parts)
        if(
            _flag MATCHES "^-W"
            OR _flag STREQUAL "-pedantic"
            OR _flag STREQUAL "-pedantic-errors"
        )
            continue()
        endif()

        list(
            APPEND
            _openfhe_bridge_flags
            "${_flag}"
        )
    endforeach()
endforeach()

function(configure_openfhe_bridge_target target_name)
    target_compile_options(
        "${target_name}"
        PRIVATE
            ${_openfhe_bridge_flags}
            -Wall
            -Wextra
            -Wconversion
            -Wno-error
    )

    target_include_directories(
        "${target_name}"
        SYSTEM PRIVATE
            ${OPENMP_INCLUDES}
            ${OpenFHE_INCLUDE}
            ${OpenFHE_INCLUDE}/third-party/include
            ${OpenFHE_INCLUDE}/core
            ${OpenFHE_INCLUDE}/pke
            ${OpenFHE_INCLUDE}/binfhe
    )

    target_link_directories(
        "${target_name}"
        PRIVATE
            ${OpenFHE_LIBDIR}
            ${OPENMP_LIBRARIES}
    )

    if(UNIX AND NOT APPLE)
        target_link_options(
            "${target_name}"
            PRIVATE
                -Wl,--no-as-needed
        )
    endif()

    target_link_libraries(
        "${target_name}"
        PRIVATE
            ${OpenFHE_SHARED_LIBRARIES}
    )

    set_target_properties(
        "${target_name}"
        PROPERTIES
            BUILD_RPATH "${OpenFHE_LIBDIR}"
    )
endfunction()

configure_openfhe_bridge_target(
    openfhe_eval_domain_bridge
)

configure_openfhe_bridge_target(
    openfhe_relinearization_probe
)
