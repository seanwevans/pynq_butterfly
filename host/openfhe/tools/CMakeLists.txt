set(_tools
  openfhe_ciphertext_bridge
  openfhe_eval_domain_bridge
  openfhe_multitower_bridge
  openfhe_tower_bridge
  openfhe_two_tower_runtime_bridge
  openfhe_relinearization_probe)
foreach(tool IN LISTS _tools)
  add_executable(${tool} ${tool}.cpp)
  target_link_libraries(${tool} PRIVATE pynq_openfhe_host ${OpenFHE_SHARED_LIBRARIES})
  target_compile_options(${tool} PRIVATE ${PYNQ_OPENFHE_FLAGS} -Wall -Wextra -Wno-error)
  target_include_directories(${tool} SYSTEM PRIVATE ${OPENMP_INCLUDES} ${OpenFHE_INCLUDE} ${OpenFHE_INCLUDE}/third-party/include ${OpenFHE_INCLUDE}/core ${OpenFHE_INCLUDE}/pke ${OpenFHE_INCLUDE}/binfhe)
  target_link_directories(${tool} PRIVATE ${OpenFHE_LIBDIR} ${OPENMP_LIBRARIES})
  set_target_properties(${tool} PROPERTIES BUILD_RPATH "${OpenFHE_LIBDIR}")
  if(UNIX AND NOT APPLE)
    target_link_options(${tool} PRIVATE -Wl,--no-as-needed)
  endif()
endforeach()
