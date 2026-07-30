#include "pynq_butterfly/openfhe/frame.hpp"
#include <fstream>
#include <limits>
#include <stdexcept>
#include <string>

namespace pynq_butterfly::openfhe {
std::uint64_t pack_lanes(std::uint32_t lane0, std::uint32_t lane1) noexcept {
    return std::uint64_t{lane0} | (std::uint64_t{lane1} << 32U);
}
std::pair<std::uint32_t, std::uint32_t> decode_lanes(std::uint64_t word) noexcept {
    return {static_cast<std::uint32_t>(word), static_cast<std::uint32_t>(word >> 32U)};
}
std::vector<std::uint32_t> read_u32_le(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("cannot open " + path.string());
    const auto size = input.tellg();
    if (size < 0 || size % 4 != 0) throw std::runtime_error("invalid u32 frame size: " + path.string());
    input.seekg(0);
    std::vector<std::uint32_t> result(static_cast<std::size_t>(size) / 4);
    for (auto& word : result) {
        unsigned char bytes[4]{};
        if (!input.read(reinterpret_cast<char*>(bytes), 4)) throw std::runtime_error("short frame: " + path.string());
        word = std::uint32_t{bytes[0]} | (std::uint32_t{bytes[1]} << 8U) |
               (std::uint32_t{bytes[2]} << 16U) | (std::uint32_t{bytes[3]} << 24U);
    }
    return result;
}
void write_u32_le(const std::filesystem::path& path, const std::vector<std::uint32_t>& words) {
    std::ofstream output(path, std::ios::binary);
    if (!output) throw std::runtime_error("cannot create " + path.string());
    for (auto word : words) {
        const unsigned char bytes[] = {static_cast<unsigned char>(word), static_cast<unsigned char>(word >> 8U), static_cast<unsigned char>(word >> 16U), static_cast<unsigned char>(word >> 24U)};
        output.write(reinterpret_cast<const char*>(bytes), 4);
    }
    if (!output) throw std::runtime_error("cannot write " + path.string());
}
std::uint64_t parse_unsigned(std::string_view text, std::string_view label) {
    std::size_t consumed{};
    const auto value = std::stoull(std::string(text), &consumed, 0);
    if (consumed != text.size()) throw std::invalid_argument("invalid " + std::string(label) + ": " + std::string(text));
    return value;
}
void require_hardware_modulus(std::uint64_t modulus) {
    if (modulus <= (std::uint64_t{1} << 29U) || modulus >= (std::uint64_t{1} << 30U))
        throw std::invalid_argument("hardware modulus must satisfy 2^29 < q < 2^30");
    const auto mu = static_cast<std::uint64_t>((static_cast<unsigned __int128>(1) << 60U) / modulus);
    if (mu >= (std::uint64_t{1} << 31U)) throw std::invalid_argument("Barrett reciprocal does not fit 31 bits");
}
}  // namespace pynq_butterfly::openfhe
