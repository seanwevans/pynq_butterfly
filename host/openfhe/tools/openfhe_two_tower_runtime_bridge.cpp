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
constexpr std::size_t kTowerWords = kN;
constexpr std::size_t kDmaInputWords = 2 * kN;

using Params = ILDCRTParams<BigInteger>;

[[noreturn]] void Fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::uint64_t ParseSeed(const std::string& text) {
    std::size_t consumed = 0;
    const std::uint64_t result = std::stoull(text, &consumed, 0);

    if (consumed != text.size()) {
        Fail("Invalid seed: " + text);
    }

    return result;
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

std::uint64_t ModInverse(
    std::uint64_t value,
    std::uint64_t modulus
) {
    return ModPow(value, modulus - 2, modulus);
}

struct TowerProfile {
    std::uint64_t modulus;
    std::uint64_t psi;
    std::uint64_t omega;
    std::uint64_t psi_inverse;
    std::uint64_t omega_inverse;
    std::uint64_t n_inverse;

    std::vector<std::uint32_t> twist;
    std::vector<std::uint32_t> forward_twiddles;
    std::vector<std::uint32_t> inverse_twiddles;
    std::vector<std::uint32_t> inverse_scale;
};

TowerProfile BuildProfile(
    std::uint64_t modulus,
    std::uint64_t psi
) {
    if (ModPow(psi, kOrder, modulus) != 1) {
        Fail("psi^8192 is not one");
    }

    if (ModPow(psi, kN, modulus) != modulus - 1) {
        Fail("psi is not a primitive 8192nd root");
    }

    TowerProfile profile{
        modulus,
        psi,
        ModPow(psi, 2, modulus),
        ModInverse(psi, modulus),
        0,
        ModInverse(kN, modulus),
        {},
        {},
        {},
        {},
    };

    profile.omega_inverse =
        ModInverse(profile.omega, modulus);

    profile.twist.resize(kN);
    profile.inverse_scale.resize(kN);

    for (std::uint32_t j = 0; j < kN; ++j) {
        profile.twist[j] =
            static_cast<std::uint32_t>(
                ModPow(profile.psi, j, modulus)
            );

        const std::uint64_t psi_inverse_power =
            ModPow(profile.psi_inverse, j, modulus);

        profile.inverse_scale[j] =
            static_cast<std::uint32_t>(
                (
                    static_cast<unsigned __int128>(profile.n_inverse)
                    * psi_inverse_power
                ) % modulus
            );
    }

    profile.forward_twiddles.reserve(kCompactTwiddles);
    profile.inverse_twiddles.reserve(kCompactTwiddles);

    for (std::uint32_t stage = 0; stage < 12; ++stage) {
        const std::uint32_t half =
            1U << stage;

        const std::uint32_t span =
            half << 1U;

        const std::uint32_t step =
            kN / span;

        for (std::uint32_t j = 0; j < half; ++j) {
            const std::uint64_t exponent =
                static_cast<std::uint64_t>(j) * step;

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

std::shared_ptr<Params> MakeParams(
    const TowerProfile& q0,
    const TowerProfile& q1
) {
    const std::vector<NativeInteger> moduli{
        NativeInteger(q0.modulus),
        NativeInteger(q1.modulus),
    };

    const std::vector<NativeInteger> roots{
        NativeInteger(q0.psi),
        NativeInteger(q1.psi),
    };

    auto params = std::make_shared<Params>(
        kOrder,
        moduli,
        roots
    );

    if (params->GetRingDimension() != kN) {
        Fail("OpenFHE returned the wrong ring dimension");
    }

    if (params->GetParams().size() != 2) {
        Fail("OpenFHE returned the wrong tower count");
    }

    return params;
}

DCRTPoly MakeCoefficientPoly(
    const std::shared_ptr<Params>& params,
    const std::array<std::vector<std::uint32_t>, 2>& coefficients
) {
    DCRTPoly result(
        params,
        Format::COEFFICIENT,
        true
    );

    for (std::size_t tower_index = 0; tower_index < 2; ++tower_index) {
        const auto& tower_params =
            params->GetParams().at(tower_index);

        const std::uint64_t modulus =
            tower_params->GetModulus().ConvertToInt<std::uint64_t>();

        NativePoly tower(
            tower_params,
            Format::COEFFICIENT,
            true
        );

        for (std::size_t i = 0; i < kN; ++i) {
            if (coefficients[tower_index][i] >= modulus) {
                Fail("Coefficient is outside its tower modulus");
            }

            tower[static_cast<usint>(i)] =
                NativeInteger(coefficients[tower_index][i]);
        }

        result.SetElementAtIndex(
            static_cast<usint>(tower_index),
            std::move(tower)
        );
    }

    return result;
}

std::array<std::vector<std::uint32_t>, 2> ExtractTowers(
    const DCRTPoly& poly
) {
    if (poly.GetFormat() != Format::COEFFICIENT) {
        Fail("Attempted to export a non-coefficient DCRTPoly");
    }

    if (poly.GetNumOfElements() != 2) {
        Fail("Attempted to export a DCRTPoly with the wrong tower count");
    }

    std::array<std::vector<std::uint32_t>, 2> result;

    for (std::size_t tower_index = 0; tower_index < 2; ++tower_index) {
        result[tower_index].resize(kN);

        const NativePoly& tower =
            poly.GetElementAtIndex(
                static_cast<usint>(tower_index)
            );

        for (std::size_t i = 0; i < kN; ++i) {
            result[tower_index][i] =
                static_cast<std::uint32_t>(
                    tower[static_cast<usint>(i)]
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

    DCRTPoly product =
        evaluation_a * evaluation_b;

    product.SwitchFormat();

    if (product.GetFormat() != Format::COEFFICIENT) {
        Fail("OpenFHE product did not return to coefficient format");
    }

    return product;
}

void WriteU32LE(
    std::ostream& output,
    std::uint32_t value
) {
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

    return
        static_cast<std::uint32_t>(bytes[0])
        | (static_cast<std::uint32_t>(bytes[1]) << 8U)
        | (static_cast<std::uint32_t>(bytes[2]) << 16U)
        | (static_cast<std::uint32_t>(bytes[3]) << 24U);
}

void WriteBinary(
    const fs::path& path,
    const std::vector<std::uint32_t>& words
) {
    std::ofstream output(
        path,
        std::ios::binary | std::ios::trunc
    );

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
    std::ifstream input(
        path,
        std::ios::binary
    );

    if (!input) {
        Fail("Could not open input file: " + path.string());
    }

    input.seekg(0, std::ios::end);
    const auto bytes = input.tellg();
    input.seekg(0, std::ios::beg);

    const auto expected_bytes =
        static_cast<std::streamoff>(
            expected_words * sizeof(std::uint32_t)
        );

    if (bytes != expected_bytes) {
        Fail(path.string() + " has the wrong size");
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
    std::ofstream output(path, std::ios::trunc);

    if (!output) {
        Fail("Could not open MEM output: " + path.string());
    }

    output
        << std::hex
        << std::setfill('0');

    for (const auto word : words) {
        output
            << std::setw(8)
            << word
            << '\n';
    }
}

std::uint64_t Fnv1a64(
    const std::vector<std::uint32_t>& words
) {
    std::uint64_t hash =
        UINT64_C(14695981039346656037);

    constexpr std::uint64_t prime =
        UINT64_C(1099511628211);

    for (const auto word : words) {
        for (unsigned shift = 0; shift < 32; shift += 8) {
            hash ^= static_cast<std::uint8_t>(word >> shift);
            hash *= prime;
        }
    }

    return hash;
}

std::string Hex64(std::uint64_t value) {
    std::ostringstream output;

    output
        << "0x"
        << std::hex
        << std::setw(16)
        << std::setfill('0')
        << value;

    return output.str();
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
        value =
            static_cast<std::uint32_t>(
                distribution(generator)
            );
    }

    return result;
}

void RequireEqual(
    const std::vector<std::uint32_t>& actual,
    const std::vector<std::uint32_t>& expected,
    std::string_view label
) {
    if (actual.size() != expected.size()) {
        Fail(std::string(label) + " size mismatch");
    }

    for (std::size_t i = 0; i < actual.size(); ++i) {
        if (actual[i] != expected[i]) {
            Fail(
                std::string(label)
                + " mismatch at coefficient "
                + std::to_string(i)
                + ": result="
                + std::to_string(actual[i])
                + ", expected="
                + std::to_string(expected[i])
            );
        }
    }
}

void ExportProfile(
    const fs::path& directory,
    const TowerProfile& profile,
    std::size_t tower_index
) {
    fs::create_directories(directory);

    WriteMem(
        directory / "twist_factors.mem",
        profile.twist
    );

    WriteMem(
        directory / "forward_twiddles.mem",
        profile.forward_twiddles
    );

    WriteMem(
        directory / "inverse_twiddles.mem",
        profile.inverse_twiddles
    );

    WriteMem(
        directory / "inverse_scale_factors.mem",
        profile.inverse_scale
    );

    std::ofstream metadata(
        directory / "profile.json",
        std::ios::trunc
    );

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

int Generate(
    const fs::path& output_directory,
    std::uint64_t seed
) {
    fs::create_directories(output_directory);

    const NativeInteger q1_native =
        lbcrypto::PreviousPrime(
            NativeInteger(kQ0),
            kOrder
        );

    const std::uint64_t q1 =
        q1_native.ConvertToInt<std::uint64_t>();

    const NativeInteger psi1_native =
        lbcrypto::RootOfUnity<NativeInteger>(
            kOrder,
            q1_native
        );

    const std::uint64_t psi1 =
        psi1_native.ConvertToInt<std::uint64_t>();

    const TowerProfile profile0 =
        BuildProfile(kQ0, kPsi0);

    const TowerProfile profile1 =
        BuildProfile(q1, psi1);

    const auto params =
        MakeParams(profile0, profile1);

    std::mt19937_64 generator(seed);

    std::array<std::vector<std::uint32_t>, 2> a{
        GenerateTower(generator, profile0.modulus),
        GenerateTower(generator, profile1.modulus),
    };

    std::array<std::vector<std::uint32_t>, 2> b{
        GenerateTower(generator, profile0.modulus),
        GenerateTower(generator, profile1.modulus),
    };

    const DCRTPoly coefficient_a =
        MakeCoefficientPoly(params, a);

    const DCRTPoly coefficient_b =
        MakeCoefficientPoly(params, b);

    const auto software_start =
        std::chrono::steady_clock::now();

    const DCRTPoly expected_poly =
        MultiplyWithOpenFHE(
            coefficient_a,
            coefficient_b
        );

    const auto software_stop =
        std::chrono::steady_clock::now();

    const auto exported_a =
        ExtractTowers(coefficient_a);

    const auto exported_b =
        ExtractTowers(coefficient_b);

    const auto expected =
        ExtractTowers(expected_poly);

    for (std::size_t tower_index = 0; tower_index < 2; ++tower_index) {
        const fs::path tower_directory =
            output_directory
            / ("tower" + std::to_string(tower_index));

        fs::create_directories(tower_directory);

        std::vector<std::uint32_t> dma_input;
        dma_input.reserve(kDmaInputWords);

        dma_input.insert(
            dma_input.end(),
            exported_a[tower_index].begin(),
            exported_a[tower_index].end()
        );

        dma_input.insert(
            dma_input.end(),
            exported_b[tower_index].begin(),
            exported_b[tower_index].end()
        );

        WriteBinary(
            tower_directory / "dma_input.bin",
            dma_input
        );

        WriteBinary(
            tower_directory / "openfhe_expected.bin",
            expected[tower_index]
        );
    }

    ExportProfile(
        output_directory / "profile0",
        profile0,
        0
    );

    ExportProfile(
        output_directory / "profile1",
        profile1,
        1
    );

    std::ofstream metadata(
        output_directory / "metadata.json",
        std::ios::trunc
    );

    metadata
        << "{\n"
        << "  \"format\": \"openfhe-dcrtpoly-two-tower-runtime-v1\",\n"
        << "  \"openfhe_version_target\": \"1.5.1\",\n"
        << "  \"ring_dimension\": " << kN << ",\n"
        << "  \"cyclotomic_order\": " << kOrder << ",\n"
        << "  \"tower_count\": 2,\n"
        << "  \"seed\": " << seed << ",\n"
        << "  \"moduli\": [" << profile0.modulus << ", " << profile1.modulus << "],\n"
        << "  \"roots\": [" << profile0.psi << ", " << profile1.psi << "],\n"
        << "  \"expected_fnv1a64\": [\""
        << Hex64(Fnv1a64(expected[0]))
        << "\", \""
        << Hex64(Fnv1a64(expected[1]))
        << "\"]\n"
        << "}\n";

    const double software_us =
        std::chrono::duration<double, std::micro>(
            software_stop - software_start
        ).count();

    std::cout
        << "PASS: constructed a two-tower OpenFHE DCRTPoly\n"
        << "PASS: generated runtime profiles for q0 and q1\n"
        << "PASS: exported two independent FPGA tower products\n"
        << "q0=" << profile0.modulus << '\n'
        << "psi0=" << profile0.psi << '\n'
        << "q1=" << profile1.modulus << '\n'
        << "psi1=" << profile1.psi << '\n'
        << "seed=" << seed << '\n'
        << std::fixed << std::setprecision(2)
        << "OpenFHE two-tower software product: "
        << software_us
        << " us\n"
        << "Output directory: "
        << fs::absolute(output_directory).string()
        << '\n';

    return 0;
}

int Verify(
    const fs::path& vector_directory,
    const fs::path& fpga_tower0,
    const fs::path& fpga_tower1
) {
    const std::ifstream metadata_input(
        vector_directory / "metadata.json"
    );

    if (!metadata_input) {
        Fail("metadata.json is missing");
    }

    const NativeInteger q1_native =
        lbcrypto::PreviousPrime(
            NativeInteger(kQ0),
            kOrder
        );

    const std::uint64_t q1 =
        q1_native.ConvertToInt<std::uint64_t>();

    const std::uint64_t psi1 =
        lbcrypto::RootOfUnity<NativeInteger>(
            kOrder,
            q1_native
        ).ConvertToInt<std::uint64_t>();

    const TowerProfile profile0 =
        BuildProfile(kQ0, kPsi0);

    const TowerProfile profile1 =
        BuildProfile(q1, psi1);

    const auto params =
        MakeParams(profile0, profile1);

    std::array<std::vector<std::uint32_t>, 2> a;
    std::array<std::vector<std::uint32_t>, 2> b;
    std::array<std::vector<std::uint32_t>, 2> stored_expected;

    for (std::size_t tower_index = 0; tower_index < 2; ++tower_index) {
        const fs::path tower_directory =
            vector_directory
            / ("tower" + std::to_string(tower_index));

        const auto dma_input =
            ReadBinary(
                tower_directory / "dma_input.bin",
                kDmaInputWords
            );

        a[tower_index] =
            std::vector<std::uint32_t>(
                dma_input.begin(),
                dma_input.begin() + kN
            );

        b[tower_index] =
            std::vector<std::uint32_t>(
                dma_input.begin() + kN,
                dma_input.end()
            );

        stored_expected[tower_index] =
            ReadBinary(
                tower_directory / "openfhe_expected.bin",
                kN
            );
    }

    const DCRTPoly coefficient_a =
        MakeCoefficientPoly(params, a);

    const DCRTPoly coefficient_b =
        MakeCoefficientPoly(params, b);

    const DCRTPoly expected_poly =
        MultiplyWithOpenFHE(
            coefficient_a,
            coefficient_b
        );

    const auto recomputed_expected =
        ExtractTowers(expected_poly);

    const std::array<std::vector<std::uint32_t>, 2> fpga{
        ReadBinary(fpga_tower0, kN),
        ReadBinary(fpga_tower1, kN),
    };

    for (std::size_t tower_index = 0; tower_index < 2; ++tower_index) {
        RequireEqual(
            stored_expected[tower_index],
            recomputed_expected[tower_index],
            "Stored expected tower " + std::to_string(tower_index)
        );

        RequireEqual(
            fpga[tower_index],
            recomputed_expected[tower_index],
            "FPGA tower " + std::to_string(tower_index)
        );
    }

    const DCRTPoly imported_fpga =
        MakeCoefficientPoly(
            params,
            fpga
        );

    if (!(imported_fpga == expected_poly)) {
        Fail("Imported two-tower FPGA DCRTPoly does not equal OpenFHE");
    }

    std::cout
        << "PASS: tower 0 FPGA result equals OpenFHE\n"
        << "PASS: tower 1 FPGA result equals OpenFHE\n"
        << "PASS: imported two-tower FPGA result equals the OpenFHE DCRTPoly object\n"
        << "tower0_fnv1a64=" << Hex64(Fnv1a64(fpga[0])) << '\n'
        << "tower1_fnv1a64=" << Hex64(Fnv1a64(fpga[1])) << '\n'
        << "PASS end to end two-tower runtime-profile OpenFHE bridge\n";

    return 0;
}

void PrintUsage(const char* executable) {
    std::cerr
        << "Usage:\n"
        << "  " << executable
        << " generate OUTPUT_DIRECTORY [SEED]\n"
        << "  " << executable
        << " verify VECTOR_DIRECTORY FPGA_TOWER0.bin FPGA_TOWER1.bin\n";
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
            if (argc != 3 && argc != 4) {
                PrintUsage(argv[0]);
                return 2;
            }

            const std::uint64_t seed =
                argc == 4
                    ? ParseSeed(argv[3])
                    : UINT64_C(0x2f40962026);

            return Generate(
                fs::path(argv[2]),
                seed
            );
        }

        if (command == "verify") {
            if (argc != 5) {
                PrintUsage(argv[0]);
                return 2;
            }

            return Verify(
                fs::path(argv[2]),
                fs::path(argv[3]),
                fs::path(argv[4])
            );
        }

        PrintUsage(argv[0]);
        return 2;
    }
    catch (const std::exception& error) {
        std::cerr
            << "FAIL: "
            << error.what()
            << '\n';

        return 1;
    }
}
