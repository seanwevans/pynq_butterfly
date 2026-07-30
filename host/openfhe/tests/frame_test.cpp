#include "pynq_butterfly/openfhe/frame.hpp"
#include <cassert>
#include <filesystem>
#include <vector>
using namespace pynq_butterfly::openfhe;
int main() {
    const auto packed = pack_lanes(0x01234567U, 0x89abcdefU);
    assert(packed == UINT64_C(0x89abcdef01234567));
    const auto decoded = decode_lanes(packed);
    assert(decoded.first == 0x01234567U);
    assert(decoded.second == 0x89abcdefU);
    const auto path = std::filesystem::temp_directory_path() / "pynq_openfhe_frame_test.bin";
    const std::vector<std::uint32_t> expected{0U, 1U, 0x89abcdefU, 0xffffffffU};
    write_u32_le(path, expected);
    assert(read_u32_le(path) == expected);
    std::filesystem::remove(path);
    require_hardware_modulus(1073692673U);
    return 0;
}
