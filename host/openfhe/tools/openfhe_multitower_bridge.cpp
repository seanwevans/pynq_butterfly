#include "lattice/lat-hal.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <random>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;

using lbcrypto::BigInteger;
using lbcrypto::DCRTPoly;
using lbcrypto::ILDCRTParams;
using lbcrypto::NativeInteger;
using lbcrypto::NativePoly;

namespace {

constexpr std::uint32_t kN = 4096;
constexpr std::uint32_t kOrder = 8192;
constexpr std::uint64_t kQ0 = 1073692673;
constexpr std::uint64_t kPsi0 = 236231;
constexpr std::size_t kCompactTwiddles = kN - 1;
constexpr std::size_t kWordsPerProductPerTower = 2 * kN;

using Params = ILDCRTParams<BigInteger>;
using Coefficients = std::vector<std::vector<std::uint32_t>>;

[[noreturn]] void Fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::uint64_t ParseUnsigned(const std::string& text, std::string_view label) {
    std::size_t consumed = 0;
    const std::uint64_t value = std::stoull(text, &consumed, 0);
    if (consumed != text.size()) {
        Fail("Invalid " + std::string(label) + ": " + text);
    }
    return value;
}

std::uint64_t ModPow(
    std::uint64_t base,
    std::uint64_t exponent,
    std::uint64_t modulus
) {
    std::uint64_t result = 1;
    base %= modulus;

    while (exponent != 0) {
        if ((exponent & 1U) != 0) {
            result = static_cast<std::uint64_t>(
                (static_cast<unsigned __int128>(result) * base) % modulus
            );
        }

        base = static_cast<std::uint64_t>(
            (static_cast<unsigned __int128>(base) * base) % modulus
        );
        exponent >>= 1U;
    }

    return result;
}

std::uint64_t ModInverse(std::uint64_t value, std::uint64_t modulus) {
    return ModPow(value, modulus - 2, modulus);
}

struct TowerProfile {
    std::uint64_t modulus = 0;
    std::uint64_t psi = 0;
    std::uint64_t omega = 0;
    std::uint64_t psi_inverse = 0;
    std::uint64_t omega_inverse = 0;
    std::uint64_t n_inverse = 0;

    std::vector<std::uint32_t> twist;
    std::vector<std::uint32_t> forward_twiddles;
    std::vector<std::uint32_t> inverse_twiddles;
    std::vector<std::uint32_t> inverse_scale;
};

TowerProfile BuildProfile(std::uint64_t modulus, std::uint64_t psi) {
    if (modulus >= (UINT64_C(1) << 30U)) {
        Fail("Modulus must be below 2^30 for the current Barrett pipeline");
    }

    if (ModPow(psi, kOrder, modulus) != 1) {
        Fail("psi^8192 is not one for modulus " + std::to_string(modulus));
    }

    if (ModPow(psi, kN, modulus) != modulus - 1) {
        Fail("psi is not a primitive 8192nd root for modulus "
             + std::to_string(modulus));
    }

    TowerProfile profile;
    profile.modulus = modulus;
    profile.psi = psi;
    profile.omega = ModPow(psi, 2, modulus);
    profile.psi_inverse = ModInverse(psi, modulus);
    profile.omega_inverse = ModInverse(profile.omega, modulus);
    profile.n_inverse = ModInverse(kN, modulus);

    profile.twist.resize(kN);
    profile.inverse_scale.resize(kN);

    for (std::uint32_t index = 0; index < kN; ++index) {
        profile.twist[index] = static_cast<std::uint32_t>(
            ModPow(profile.psi, index, modulus)
        );

        const std::uint64_t psi_inverse_power =
            ModPow(profile.psi_inverse, index, modulus);

        profile.inverse_scale[index] = static_cast<std::uint32_t>(
            (static_cast<unsigned __int128>(profile.n_inverse)
             * psi_inverse_power)
            % modulus
        );
    }

    profile.forward_twiddles.reserve(kCompactTwiddles);
    profile.inverse_twiddles.reserve(kCompactTwiddles);

    for (std::uint32_t stage = 0; stage < 12; ++stage) {
        const std::uint32_t half = 1U << stage;
        const std::uint32_t span = half << 1U;
        const std::uint32_t step = kN / span;

        for (std::uint32_t index = 0; index < half; ++index) {
            const std::uint64_t exponent =
                static_cast<std::uint64_t>(index) * step;

            profile.forward_twiddles.push_back(
                static_cast<std::uint32_t>(
                    ModPow(profile.omega, exponent, modulus)
                )
            );

            profile.inverse_twiddles.push_back(
                static_cast<std::uint32_t>(
                    ModPow(profile.omega_inverse, exponent, modulus)
                )
            );
        }
    }

    if (
        profile.forward_twiddles.size() != kCompactTwiddles
        || profile.inverse_twiddles.size() != kCompactTwiddles
    ) {
        Fail("Compact twiddle generation produced the wrong length");
    }

    return profile;
}

std::vector<TowerProfile> BuildProfiles(std::size_t tower_count) {
    if (tower_count == 0) {
        Fail("tower_count must be positive");
    }

    std::vector<TowerProfile> profiles;
    profiles.reserve(tower_count);

    NativeInteger modulus(kQ0);

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        if (tower != 0) {
            modulus = lbcrypto::PreviousPrime(modulus, kOrder);
        }

        const std::uint64_t modulus_u64 =
            modulus.ConvertToInt<std::uint64_t>();

        const std::uint64_t psi =
            tower == 0
                ? kPsi0
                : lbcrypto::RootOfUnity<NativeInteger>(kOrder, modulus)
                      .ConvertToInt<std::uint64_t>();

        profiles.push_back(BuildProfile(modulus_u64, psi));
    }

    return profiles;
}

std::shared_ptr<Params> MakeParams(
    const std::vector<TowerProfile>& profiles
) {
    std::vector<NativeInteger> moduli;
    std::vector<NativeInteger> roots;
    moduli.reserve(profiles.size());
    roots.reserve(profiles.size());

    for (const auto& profile : profiles) {
        moduli.emplace_back(profile.modulus);
        roots.emplace_back(profile.psi);
    }

    auto params = std::make_shared<Params>(kOrder, moduli, roots);

    if (params->GetRingDimension() != kN) {
        Fail("OpenFHE returned the wrong ring dimension");
    }

    if (params->GetParams().size() != profiles.size()) {
        Fail("OpenFHE returned the wrong tower count");
    }

    return params;
}

DCRTPoly MakeCoefficientPoly(
    const std::shared_ptr<Params>& params,
    const Coefficients& coefficients
) {
    if (coefficients.size() != params->GetParams().size()) {
        Fail("Coefficient tower count does not match parameters");
    }

    DCRTPoly result(params, Format::COEFFICIENT, true);

    for (std::size_t tower_index = 0;
         tower_index < coefficients.size();
         ++tower_index) {
        const auto& values = coefficients[tower_index];
        if (values.size() != kN) {
            Fail("Coefficient tower has the wrong ring dimension");
        }

        const auto& tower_params = params->GetParams().at(tower_index);
        const std::uint64_t modulus =
            tower_params->GetModulus().ConvertToInt<std::uint64_t>();

        NativePoly tower(tower_params, Format::COEFFICIENT, true);

        for (std::size_t index = 0; index < kN; ++index) {
            if (values[index] >= modulus) {
                Fail("Coefficient is outside its tower modulus");
            }

            tower[static_cast<usint>(index)] =
                NativeInteger(values[index]);
        }

        result.SetElementAtIndex(
            static_cast<usint>(tower_index),
            std::move(tower)
        );
    }

    return result;
}

Coefficients ExtractTowers(const DCRTPoly& poly) {
    if (poly.GetFormat() != Format::COEFFICIENT) {
        Fail("Attempted to export a non-coefficient DCRTPoly");
    }

    Coefficients result(poly.GetNumOfElements());

    for (std::size_t tower_index = 0;
         tower_index < result.size();
         ++tower_index) {
        result[tower_index].resize(kN);

        const NativePoly& tower = poly.GetElementAtIndex(
            static_cast<usint>(tower_index)
        );

        for (std::size_t index = 0; index < kN; ++index) {
            result[tower_index][index] = static_cast<std::uint32_t>(
                tower[static_cast<usint>(index)]
                    .ConvertToInt<std::uint64_t>()
            );
        }
    }

    return result;
}

DCRTPoly MultiplyWithOpenFHE(
    const DCRTPoly& coefficient_a,
    const DCRTPoly& coefficient_b
) {
    DCRTPoly evaluation_a(coefficient_a);
    DCRTPoly evaluation_b(coefficient_b);

    evaluation_a.SwitchFormat();
    evaluation_b.SwitchFormat();

    DCRTPoly product = evaluation_a * evaluation_b;
    product.SwitchFormat();

    if (product.GetFormat() != Format::COEFFICIENT) {
        Fail("OpenFHE product did not return to coefficient format");
    }

    return product;
}

std::vector<std::uint32_t> GenerateTower(
    std::mt19937_64& generator,
    std::uint64_t modulus
) {
    std::uniform_int_distribution<std::uint64_t> distribution(
        0,
        modulus - 1
    );

    std::vector<std::uint32_t> result(kN);
    for (auto& value : result) {
        value = static_cast<std::uint32_t>(distribution(generator));
    }
    return result;
}

void WriteU32LE(std::ostream& output, std::uint32_t value) {
    const std::array<unsigned char, 4> bytes{
        static_cast<unsigned char>(value),
        static_cast<unsigned char>(value >> 8U),
        static_cast<unsigned char>(value >> 16U),
        static_cast<unsigned char>(value >> 24U),
    };

    output.write(
        reinterpret_cast<const char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size())
    );
}

std::uint32_t ReadU32LE(std::istream& input) {
    std::array<unsigned char, 4> bytes{};
    input.read(
        reinterpret_cast<char*>(bytes.data()),
        static_cast<std::streamsize>(bytes.size())
    );

    if (!input) {
        Fail("Unexpected end of binary file");
    }

    return static_cast<std::uint32_t>(bytes[0])
        | (static_cast<std::uint32_t>(bytes[1]) << 8U)
        | (static_cast<std::uint32_t>(bytes[2]) << 16U)
        | (static_cast<std::uint32_t>(bytes[3]) << 24U);
}

void WriteBinary(
    const fs::path& path,
    const std::vector<std::uint32_t>& words
) {
    fs::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        Fail("Could not open output file: " + path.string());
    }

    for (const auto word : words) {
        WriteU32LE(output, word);
    }
}

std::vector<std::uint32_t> ReadBinary(
    const fs::path& path,
    std::size_t expected_words
) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        Fail("Could not open input file: " + path.string());
    }

    input.seekg(0, std::ios::end);
    const std::streamoff bytes = static_cast<std::streamoff>(input.tellg());
    input.seekg(0, std::ios::beg);

    const std::streamoff expected_bytes = static_cast<std::streamoff>(
        expected_words * sizeof(std::uint32_t)
    );

    if (bytes != expected_bytes) {
        Fail(
            path.string() + " has "
            + std::to_string(static_cast<long long>(bytes))
            + " bytes; expected "
            + std::to_string(static_cast<long long>(expected_bytes))
        );
    }

    std::vector<std::uint32_t> result(expected_words);
    for (auto& word : result) {
        word = ReadU32LE(input);
    }
    return result;
}

void WriteMem(
    const fs::path& path,
    const std::vector<std::uint32_t>& words
) {
    fs::create_directories(path.parent_path());
    std::ofstream output(path, std::ios::trunc);
    if (!output) {
        Fail("Could not open MEM output: " + path.string());
    }

    output << std::hex << std::setfill('0');
    for (const auto word : words) {
        output << std::setw(8) << word << '\n';
    }
}

std::string TowerName(std::size_t tower_index) {
    std::ostringstream output;
    output << "tower" << std::setw(3) << std::setfill('0') << tower_index;
    return output.str();
}

void ExportProfile(
    const fs::path& directory,
    const TowerProfile& profile,
    std::size_t tower_index
) {
    fs::create_directories(directory);

    WriteMem(directory / "twist_factors.mem", profile.twist);
    WriteMem(directory / "forward_twiddles.mem", profile.forward_twiddles);
    WriteMem(directory / "inverse_twiddles.mem", profile.inverse_twiddles);
    WriteMem(
        directory / "inverse_scale_factors.mem",
        profile.inverse_scale
    );

    std::ofstream metadata(directory / "profile.json", std::ios::trunc);
    if (!metadata) {
        Fail("Could not write profile metadata");
    }

    metadata
        << "{\n"
        << "  \"tower_index\": " << tower_index << ",\n"
        << "  \"ring_dimension\": " << kN << ",\n"
        << "  \"cyclotomic_order\": " << kOrder << ",\n"
        << "  \"modulus\": " << profile.modulus << ",\n"
        << "  \"psi\": " << profile.psi << ",\n"
        << "  \"omega\": " << profile.omega << ",\n"
        << "  \"psi_inverse\": " << profile.psi_inverse << ",\n"
        << "  \"omega_inverse\": " << profile.omega_inverse << ",\n"
        << "  \"n_inverse\": " << profile.n_inverse << "\n"
        << "}\n";
}

std::string ReadText(const fs::path& path) {
    std::ifstream input(path);
    if (!input) {
        Fail("Could not open text file: " + path.string());
    }

    std::ostringstream output;
    output << input.rdbuf();
    return output.str();
}

std::uint64_t ReadJsonUnsigned(
    const fs::path& path,
    std::string_view key
) {
    const std::string text = ReadText(path);
    const std::regex pattern(
        "\\\"" + std::string(key) + "\\\"\\s*:\\s*([0-9]+)"
    );
    std::smatch match;

    if (!std::regex_search(text, match, pattern)) {
        Fail("Missing JSON integer " + std::string(key) + " in "
             + path.string());
    }

    return ParseUnsigned(match[1].str(), key);
}

void RequireEqual(
    const std::vector<std::uint32_t>& actual,
    const std::vector<std::uint32_t>& expected,
    std::string_view label
) {
    if (actual.size() != expected.size()) {
        Fail(std::string(label) + " size mismatch");
    }

    for (std::size_t index = 0; index < actual.size(); ++index) {
        if (actual[index] != expected[index]) {
            Fail(
                std::string(label)
                + " mismatch at coefficient " + std::to_string(index)
                + ": result=" + std::to_string(actual[index])
                + ", expected=" + std::to_string(expected[index])
            );
        }
    }
}

std::vector<std::uint32_t> Slice(
    const std::vector<std::uint32_t>& source,
    std::size_t offset,
    std::size_t count
) {
    if (offset > source.size() || count > source.size() - offset) {
        Fail("Binary slice is outside the source vector");
    }

    return std::vector<std::uint32_t>(
        source.begin() + static_cast<std::ptrdiff_t>(offset),
        source.begin() + static_cast<std::ptrdiff_t>(offset + count)
    );
}

int Generate(
    const fs::path& output_directory,
    std::size_t tower_count,
    std::size_t product_count,
    std::uint64_t seed
) {
    if (product_count == 0) {
        Fail("product_count must be positive");
    }

    fs::remove_all(output_directory);
    fs::create_directories(output_directory);

    const auto profile_start = std::chrono::steady_clock::now();
    const std::vector<TowerProfile> profiles = BuildProfiles(tower_count);
    const auto params = MakeParams(profiles);
    const auto profile_stop = std::chrono::steady_clock::now();

    std::vector<std::vector<std::uint32_t>> dma_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>> expected_by_tower(tower_count);

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        dma_by_tower[tower].reserve(product_count * kWordsPerProductPerTower);
        expected_by_tower[tower].reserve(product_count * kN);
    }

    std::mt19937_64 generator(seed);
    double software_us = 0.0;

    for (std::size_t product = 0; product < product_count; ++product) {
        Coefficients a(tower_count);
        Coefficients b(tower_count);

        for (std::size_t tower = 0; tower < tower_count; ++tower) {
            a[tower] = GenerateTower(generator, profiles[tower].modulus);
            b[tower] = GenerateTower(generator, profiles[tower].modulus);
        }

        const DCRTPoly coefficient_a = MakeCoefficientPoly(params, a);
        const DCRTPoly coefficient_b = MakeCoefficientPoly(params, b);

        const auto software_start = std::chrono::steady_clock::now();
        const DCRTPoly expected_poly = MultiplyWithOpenFHE(
            coefficient_a,
            coefficient_b
        );
        const auto software_stop = std::chrono::steady_clock::now();

        software_us += std::chrono::duration<double, std::micro>(
            software_stop - software_start
        ).count();

        const Coefficients expected = ExtractTowers(expected_poly);

        for (std::size_t tower = 0; tower < tower_count; ++tower) {
            auto& dma = dma_by_tower[tower];
            dma.insert(dma.end(), a[tower].begin(), a[tower].end());
            dma.insert(dma.end(), b[tower].begin(), b[tower].end());

            auto& expected_output = expected_by_tower[tower];
            expected_output.insert(
                expected_output.end(),
                expected[tower].begin(),
                expected[tower].end()
            );
        }
    }

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        const std::string name = TowerName(tower);
        ExportProfile(
            output_directory / "profiles" / name,
            profiles[tower],
            tower
        );

        WriteBinary(
            output_directory / "towers" / name / "dma_input.bin",
            dma_by_tower[tower]
        );

        WriteBinary(
            output_directory / "towers" / name / "openfhe_expected.bin",
            expected_by_tower[tower]
        );
    }

    std::ofstream metadata(
        output_directory / "metadata.json",
        std::ios::trunc
    );
    if (!metadata) {
        Fail("Could not write metadata.json");
    }

    metadata
        << "{\n"
        << "  \"format\": \"openfhe-dcrtpoly-multitower-buffered-v1\",\n"
        << "  \"openfhe_version_target\": \"1.5.1\",\n"
        << "  \"ring_dimension\": " << kN << ",\n"
        << "  \"cyclotomic_order\": " << kOrder << ",\n"
        << "  \"tower_count\": " << tower_count << ",\n"
        << "  \"tower_pair_count\": " << ((tower_count + 1) / 2) << ",\n"
        << "  \"product_count\": " << product_count << ",\n"
        << "  \"seed\": " << seed << ",\n"
        << "  \"odd_tower_policy\": \"duplicate-final-lane-and-discard\",\n"
        << "  \"moduli\": [";

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        if (tower != 0) {
            metadata << ", ";
        }
        metadata << profiles[tower].modulus;
    }

    metadata << "],\n  \"roots\": [";

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        if (tower != 0) {
            metadata << ", ";
        }
        metadata << profiles[tower].psi;
    }

    metadata
        << "]\n"
        << "}\n";

    const double profile_us = std::chrono::duration<double, std::micro>(
        profile_stop - profile_start
    ).count();

    std::cout
        << "PASS: generated " << product_count
        << " exact OpenFHE DCRTPoly products\n"
        << "PASS: exported " << tower_count
        << " runtime tower profiles\n"
        << "PASS: packed " << ((tower_count + 1) / 2)
        << " FPGA tower pairs per DCRTPoly batch\n"
        << "ring_dimension=" << kN << '\n'
        << "tower_count=" << tower_count << '\n'
        << "product_count=" << product_count << '\n'
        << "seed=" << seed << '\n'
        << std::fixed << std::setprecision(2)
        << "profile_generation_us=" << profile_us << '\n'
        << "openfhe_software_us_total=" << software_us << '\n'
        << "openfhe_software_us_per_product="
        << (software_us / static_cast<double>(product_count)) << '\n'
        << "output_directory=" << fs::absolute(output_directory).string()
        << '\n';

    return 0;
}

int Verify(
    const fs::path& vector_directory,
    const fs::path& result_directory
) {
    const fs::path metadata_path = vector_directory / "metadata.json";
    const std::size_t tower_count = static_cast<std::size_t>(
        ReadJsonUnsigned(metadata_path, "tower_count")
    );
    const std::size_t product_count = static_cast<std::size_t>(
        ReadJsonUnsigned(metadata_path, "product_count")
    );

    std::vector<TowerProfile> profiles;
    profiles.reserve(tower_count);

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        const fs::path profile_path =
            vector_directory / "profiles" / TowerName(tower) / "profile.json";
        profiles.push_back(BuildProfile(
            ReadJsonUnsigned(profile_path, "modulus"),
            ReadJsonUnsigned(profile_path, "psi")
        ));
    }

    const auto params = MakeParams(profiles);

    std::vector<std::vector<std::uint32_t>> dma_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>> stored_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>> fpga_by_tower(tower_count);

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        const std::string name = TowerName(tower);
        dma_by_tower[tower] = ReadBinary(
            vector_directory / "towers" / name / "dma_input.bin",
            product_count * kWordsPerProductPerTower
        );
        stored_by_tower[tower] = ReadBinary(
            vector_directory / "towers" / name / "openfhe_expected.bin",
            product_count * kN
        );
        fpga_by_tower[tower] = ReadBinary(
            result_directory / (name + ".bin"),
            product_count * kN
        );
    }

    for (std::size_t product = 0; product < product_count; ++product) {
        Coefficients a(tower_count);
        Coefficients b(tower_count);
        Coefficients stored(tower_count);
        Coefficients fpga(tower_count);

        for (std::size_t tower = 0; tower < tower_count; ++tower) {
            const std::size_t dma_offset = product * kWordsPerProductPerTower;
            const std::size_t result_offset = product * kN;

            a[tower] = Slice(dma_by_tower[tower], dma_offset, kN);
            b[tower] = Slice(dma_by_tower[tower], dma_offset + kN, kN);
            stored[tower] = Slice(stored_by_tower[tower], result_offset, kN);
            fpga[tower] = Slice(fpga_by_tower[tower], result_offset, kN);
        }

        const DCRTPoly coefficient_a = MakeCoefficientPoly(params, a);
        const DCRTPoly coefficient_b = MakeCoefficientPoly(params, b);
        const DCRTPoly expected_poly = MultiplyWithOpenFHE(
            coefficient_a,
            coefficient_b
        );
        const Coefficients recomputed = ExtractTowers(expected_poly);

        for (std::size_t tower = 0; tower < tower_count; ++tower) {
            const std::string prefix =
                "product " + std::to_string(product)
                + " tower " + std::to_string(tower);

            RequireEqual(stored[tower], recomputed[tower], prefix + " stored");
            RequireEqual(fpga[tower], recomputed[tower], prefix + " FPGA");
        }

        const DCRTPoly imported_fpga = MakeCoefficientPoly(params, fpga);
        if (!(imported_fpga == expected_poly)) {
            Fail(
                "Imported FPGA DCRTPoly does not equal OpenFHE for product "
                + std::to_string(product)
            );
        }
    }

    std::cout
        << "PASS: every FPGA tower equals OpenFHE\n"
        << "PASS: every imported FPGA DCRTPoly equals the OpenFHE object\n"
        << "tower_count=" << tower_count << '\n'
        << "product_count=" << product_count << '\n'
        << "verified_tower_products=" << tower_count * product_count << '\n'
        << "verified_dcrt_products=" << product_count << '\n';

    return 0;
}

void PrintUsage(const char* executable) {
    std::cerr
        << "Usage:\n"
        << "  " << executable
        << " generate OUTPUT_DIRECTORY TOWER_COUNT PRODUCT_COUNT [SEED]\n"
        << "  " << executable
        << " verify VECTOR_DIRECTORY FPGA_RESULT_DIRECTORY\n";
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc < 2) {
            PrintUsage(argv[0]);
            return 2;
        }

        const std::string command = argv[1];

        if (command == "generate") {
            if (argc != 5 && argc != 6) {
                PrintUsage(argv[0]);
                return 2;
            }

            const std::size_t tower_count = static_cast<std::size_t>(
                ParseUnsigned(argv[3], "tower count")
            );
            const std::size_t product_count = static_cast<std::size_t>(
                ParseUnsigned(argv[4], "product count")
            );
            const std::uint64_t seed =
                argc == 6
                    ? ParseUnsigned(argv[5], "seed")
                    : UINT64_C(0x4096f1e2026);

            return Generate(
                fs::path(argv[2]),
                tower_count,
                product_count,
                seed
            );
        }

        if (command == "verify") {
            if (argc != 4) {
                PrintUsage(argv[0]);
                return 2;
            }

            return Verify(fs::path(argv[2]), fs::path(argv[3]));
        }

        PrintUsage(argv[0]);
        return 2;
    }
    catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
