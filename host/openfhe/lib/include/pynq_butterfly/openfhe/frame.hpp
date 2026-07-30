#pragma once
#include <cstdint>
#include <filesystem>
#include <string_view>
#include <vector>

namespace pynq_butterfly::openfhe {
constexpr std::uint32_t kRingDimension = 4096;
std::uint64_t pack_lanes(std::uint32_t lane0, std::uint32_t lane1) noexcept;
std::pair<std::uint32_t, std::uint32_t> decode_lanes(std::uint64_t word) noexcept;
std::vector<std::uint32_t> read_u32_le(const std::filesystem::path& path);
void write_u32_le(const std::filesystem::path& path, const std::vector<std::uint32_t>& words);
std::uint64_t parse_unsigned(std::string_view text, std::string_view label);
void require_hardware_modulus(std::uint64_t modulus);
}  // namespace pynq_butterfly::openfhe
