add_library(pynq_openfhe_host STATIC frame.cpp)
target_include_directories(pynq_openfhe_host PUBLIC include)
target_compile_features(pynq_openfhe_host PUBLIC cxx_std_17)
target_compile_options(pynq_openfhe_host PRIVATE -Wall -Wextra -Wconversion)
