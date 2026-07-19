#include "lattice/lat-hal.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
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

constexpr std::uint32_t kRingDimension = 4096;
constexpr std::uint32_t kCyclotomicOrder = 8192;
constexpr std::uint32_t kModulus = 1073692673;
constexpr std::uint32_t kRootOfUnity = 236231;
constexpr std::size_t kTowerBytes =
    static_cast<std::size_t>(kRingDimension) * sizeof(std::uint32_t);
constexpr std::size_t kDmaInputWords =
    static_cast<std::size_t>(2) * kRingDimension;
constexpr std::size_t kDmaInputBytes =
    kDmaInputWords * sizeof(std::uint32_t);

using Params = ILDCRTParams<BigInteger>;

[[noreturn]] void Fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::uint64_t ParseSeed(const std::string& text) {
    std::size_t consumed = 0;
    const std::uint64_t value = std::stoull(text, &consumed, 0);

    if (consumed != text.size()) {
        Fail("Invalid seed: " + text);
    }

    return value;
}

std::shared_ptr<Params> MakeParams() {
    const std::vector<NativeInteger> moduli{
        NativeInteger(kModulus),
    };

    const std::vector<NativeInteger> roots{
        NativeInteger(kRootOfUnity),
    };

    auto params = std::make_shared<Params>(
        kCyclotomicOrder,
        moduli,
        roots
    );

    if (params->GetRingDimension() != kRingDimension) {
        Fail("OpenFHE returned the wrong ring dimension");
    }

    if (params->GetParams().size() != 1) {
        Fail("OpenFHE returned the wrong tower count");
    }

    const auto& tower_params = params->GetParams().at(0);

    const auto modulus =
        tower_params->GetModulus().ConvertToInt<std::uint64_t>();

    const auto root =
        tower_params->GetRootOfUnity().ConvertToInt<std::uint64_t>();

    if (modulus != kModulus) {
        Fail("OpenFHE tower modulus does not match the FPGA profile");
    }

    if (root != kRootOfUnity) {
        Fail("OpenFHE tower root does not match the FPGA profile");
    }

    return params;
}

DCRTPoly MakeCoefficientPoly(
    const std::shared_ptr<Params>& params,
    const std::vector<std::uint32_t>& coefficients
) {
    if (coefficients.size() != kRingDimension) {
        Fail("Coefficient vector does not contain 4096 words");
    }

    NativePoly tower(
        params->GetParams().at(0),
        Format::COEFFICIENT,
        true
    );

    for (std::size_t i = 0; i < coefficients.size(); ++i) {
        if (coefficients[i] >= kModulus) {
            Fail(
                "Coefficient at index "
                + std::to_string(i)
                + " is outside the tower modulus"
            );
        }

        tower[static_cast<usint>(i)] =
            NativeInteger(coefficients[i]);
    }

    DCRTPoly result(
        params,
        Format::COEFFICIENT,
        true
    );

    result.SetElementAtIndex(
        0,
        std::move(tower)
    );

    return result;
}

std::vector<std::uint32_t> ExtractCoefficientTower(
    const DCRTPoly& poly
) {
    if (poly.GetFormat() != Format::COEFFICIENT) {
        Fail("Attempted to export an OpenFHE tower outside coefficient format");
    }

    if (poly.GetNumOfElements() != 1) {
        Fail("Attempted to export an OpenFHE object with more than one tower");
    }

    const NativePoly& tower =
        poly.GetElementAtIndex(0);

    std::vector<std::uint32_t> result(kRingDimension);

    for (std::size_t i = 0; i < result.size(); ++i) {
        const std::uint64_t value =
            tower[static_cast<usint>(i)]
                .ConvertToInt<std::uint64_t>();

        if (value >= kModulus) {
            Fail("OpenFHE exported a non-reduced residue");
        }

        result[i] =
            static_cast<std::uint32_t>(value);
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

    if (
        evaluation_a.GetFormat() != Format::EVALUATION
        || evaluation_b.GetFormat() != Format::EVALUATION
    ) {
        Fail("OpenFHE did not enter evaluation format");
    }

    DCRTPoly evaluation_product =
        evaluation_a * evaluation_b;

    evaluation_product.SwitchFormat();

    if (
        evaluation_product.GetFormat()
        != Format::COEFFICIENT
    ) {
        Fail("OpenFHE did not return the product to coefficient format");
    }

    return evaluation_product;
}

void WriteU32LE(
    std::ostream& output,
    std::uint32_t value
) {
    const std::array<unsigned char, 4> bytes{
        static_cast<unsigned char>(value & 0xffU),
        static_cast<unsigned char>((value >> 8U) & 0xffU),
        static_cast<unsigned char>((value >> 16U) & 0xffU),
        static_cast<unsigned char>((value >> 24U) & 0xffU),
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
        Fail("Unexpected end of binary coefficient file");
    }

    return
        static_cast<std::uint32_t>(bytes[0])
        | (
            static_cast<std::uint32_t>(bytes[1])
            << 8U
        )
        | (
            static_cast<std::uint32_t>(bytes[2])
            << 16U
        )
        | (
            static_cast<std::uint32_t>(bytes[3])
            << 24U
        );
}

void WriteWords(
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

    for (const std::uint32_t value : words) {
        WriteU32LE(output, value);
    }

    output.close();

    if (!output) {
        Fail("Failed while writing: " + path.string());
    }
}

std::vector<std::uint32_t> ReadWords(
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
    const std::streamoff byte_count =
        input.tellg();
    input.seekg(0, std::ios::beg);

    const std::streamoff expected_bytes =
        static_cast<std::streamoff>(
            expected_words * sizeof(std::uint32_t)
        );

    if (byte_count != expected_bytes) {
        Fail(
            path.string()
            + " contains "
            + std::to_string(byte_count)
            + " bytes; expected "
            + std::to_string(expected_bytes)
        );
    }

    std::vector<std::uint32_t> result(expected_words);

    for (std::uint32_t& value : result) {
        value = ReadU32LE(input);
    }

    return result;
}

std::uint64_t Fnv1a64(
    const std::vector<std::uint32_t>& words
) {
    std::uint64_t hash =
        UINT64_C(14695981039346656037);

    constexpr std::uint64_t prime =
        UINT64_C(1099511628211);

    for (const std::uint32_t value : words) {
        for (unsigned int shift = 0; shift < 32; shift += 8) {
            hash ^=
                static_cast<std::uint8_t>(
                    value >> shift
                );

            hash *=
                prime;
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

std::vector<std::uint32_t> GenerateCoefficients(
    std::mt19937_64& generator
) {
    std::uniform_int_distribution<std::uint32_t> distribution(
        0,
        kModulus - 1
    );

    std::vector<std::uint32_t> result(kRingDimension);

    for (std::uint32_t& value : result) {
        value =
            distribution(generator);
    }

    return result;
}

void RequireEqual(
    const std::vector<std::uint32_t>& actual,
    const std::vector<std::uint32_t>& expected,
    std::string_view label
) {
    if (actual.size() != expected.size()) {
        Fail(
            std::string(label)
            + " vector sizes differ"
        );
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

void WriteMetadata(
    const fs::path& path,
    std::uint64_t seed,
    const std::vector<std::uint32_t>& coefficient_a,
    const std::vector<std::uint32_t>& coefficient_b,
    const std::vector<std::uint32_t>& expected
) {
    std::ofstream output(
        path,
        std::ios::trunc
    );

    if (!output) {
        Fail("Could not open metadata output: " + path.string());
    }

    output
        << "{\n"
        << "  \"format\": \"openfhe-dcrtpoly-single-tower-v1\",\n"
        << "  \"openfhe_version_target\": \"1.5.1\",\n"
        << "  \"ring\": \"Z_q[X]/(X^4096+1)\",\n"
        << "  \"ring_dimension\": " << kRingDimension << ",\n"
        << "  \"cyclotomic_order\": " << kCyclotomicOrder << ",\n"
        << "  \"tower_count\": 1,\n"
        << "  \"modulus\": " << kModulus << ",\n"
        << "  \"root_of_unity\": " << kRootOfUnity << ",\n"
        << "  \"seed\": " << seed << ",\n"
        << "  \"word_encoding\": \"uint32-little-endian\",\n"
        << "  \"tower_words\": " << kRingDimension << ",\n"
        << "  \"tower_bytes\": " << kTowerBytes << ",\n"
        << "  \"dma_input_words\": " << kDmaInputWords << ",\n"
        << "  \"dma_input_bytes\": " << kDmaInputBytes << ",\n"
        << "  \"result_words\": " << kRingDimension << ",\n"
        << "  \"result_bytes\": " << kTowerBytes << ",\n"
        << "  \"fnv1a64_a\": \"" << Hex64(Fnv1a64(coefficient_a)) << "\",\n"
        << "  \"fnv1a64_b\": \"" << Hex64(Fnv1a64(coefficient_b)) << "\",\n"
        << "  \"fnv1a64_expected\": \"" << Hex64(Fnv1a64(expected)) << "\"\n"
        << "}\n";
}

int Generate(
    const fs::path& output_directory,
    std::uint64_t seed
) {
    fs::create_directories(output_directory);

    const auto params =
        MakeParams();

    std::mt19937_64 generator(seed);

    const auto generated_a =
        GenerateCoefficients(generator);

    const auto generated_b =
        GenerateCoefficients(generator);

    const DCRTPoly coefficient_poly_a =
        MakeCoefficientPoly(params, generated_a);

    const DCRTPoly coefficient_poly_b =
        MakeCoefficientPoly(params, generated_b);

    /*
     * Export from the OpenFHE objects themselves, rather than writing
     * the temporary random-number vectors.
     */
    const auto coefficient_a =
        ExtractCoefficientTower(coefficient_poly_a);

    const auto coefficient_b =
        ExtractCoefficientTower(coefficient_poly_b);

    const auto software_start =
        std::chrono::steady_clock::now();

    const DCRTPoly expected_poly =
        MultiplyWithOpenFHE(
            coefficient_poly_a,
            coefficient_poly_b
        );

    const auto software_stop =
        std::chrono::steady_clock::now();

    const auto expected =
        ExtractCoefficientTower(expected_poly);

    std::vector<std::uint32_t> dma_input;
    dma_input.reserve(kDmaInputWords);

    dma_input.insert(
        dma_input.end(),
        coefficient_a.begin(),
        coefficient_a.end()
    );

    dma_input.insert(
        dma_input.end(),
        coefficient_b.begin(),
        coefficient_b.end()
    );

    WriteWords(
        output_directory / "tower_a.bin",
        coefficient_a
    );

    WriteWords(
        output_directory / "tower_b.bin",
        coefficient_b
    );

    WriteWords(
        output_directory / "dma_input.bin",
        dma_input
    );

    WriteWords(
        output_directory / "openfhe_expected.bin",
        expected
    );

    WriteMetadata(
        output_directory / "metadata.json",
        seed,
        coefficient_a,
        coefficient_b,
        expected
    );

    const double software_microseconds =
        std::chrono::duration<double, std::micro>(
            software_stop - software_start
        ).count();

    std::cout
        << "PASS: constructed one-tower OpenFHE DCRTPoly operands\n"
        << "PASS: OpenFHE evaluation-domain multiplication returned to coefficient format\n"
        << "PASS: exported exact little-endian DMA and expected-result files\n"
        << "Ring dimension: " << kRingDimension << '\n'
        << "Cyclotomic order: " << kCyclotomicOrder << '\n'
        << "Tower modulus: " << kModulus << '\n'
        << "Tower root: " << kRootOfUnity << '\n'
        << "Seed: " << seed << '\n'
        << "DMA input: " << kDmaInputBytes << " bytes\n"
        << "Expected result: " << kTowerBytes << " bytes\n"
        << std::fixed << std::setprecision(2)
        << "OpenFHE software product: "
        << software_microseconds
        << " us\n"
        << "Output directory: "
        << fs::absolute(output_directory).string()
        << '\n';

    return 0;
}

int Verify(
    const fs::path& vector_directory,
    const fs::path& fpga_result_path
) {
    const auto dma_input =
        ReadWords(
            vector_directory / "dma_input.bin",
            kDmaInputWords
        );

    const auto stored_expected =
        ReadWords(
            vector_directory / "openfhe_expected.bin",
            kRingDimension
        );

    const auto fpga_result =
        ReadWords(
            fpga_result_path,
            kRingDimension
        );

    const std::vector<std::uint32_t> coefficient_a(
        dma_input.begin(),
        dma_input.begin() + kRingDimension
    );

    const std::vector<std::uint32_t> coefficient_b(
        dma_input.begin() + kRingDimension,
        dma_input.end()
    );

    const auto params =
        MakeParams();

    const DCRTPoly coefficient_poly_a =
        MakeCoefficientPoly(params, coefficient_a);

    const DCRTPoly coefficient_poly_b =
        MakeCoefficientPoly(params, coefficient_b);

    const DCRTPoly recomputed_expected_poly =
        MultiplyWithOpenFHE(
            coefficient_poly_a,
            coefficient_poly_b
        );

    const auto recomputed_expected =
        ExtractCoefficientTower(
            recomputed_expected_poly
        );

    RequireEqual(
        stored_expected,
        recomputed_expected,
        "Stored OpenFHE expected result"
    );

    RequireEqual(
        fpga_result,
        recomputed_expected,
        "FPGA result"
    );

    /*
     * Import the FPGA result as a real one-tower OpenFHE DCRTPoly and
     * require object-level equality with OpenFHE's software product.
     */
    const DCRTPoly fpga_result_poly =
        MakeCoefficientPoly(
            params,
            fpga_result
        );

    if (!(fpga_result_poly == recomputed_expected_poly)) {
        Fail(
            "Imported FPGA DCRTPoly is not equal to the OpenFHE software DCRTPoly"
        );
    }

    std::cout
        << "PASS: regenerated OpenFHE product from transmitted DMA operands\n"
        << "PASS: stored OpenFHE expected file is internally consistent\n"
        << "PASS: all 4096 FPGA coefficients equal OpenFHE\n"
        << "PASS: imported FPGA result equals the OpenFHE DCRTPoly object\n"
        << "FPGA result FNV-1a: "
        << Hex64(Fnv1a64(fpga_result))
        << '\n'
        << "Verified ring: Z_q[X]/(X^4096+1)\n"
        << "Verified modulus: " << kModulus << '\n'
        << "PASS end to end OpenFHE tower bridge\n";

    return 0;
}

void PrintUsage(const char* executable) {
    std::cerr
        << "Usage:\n"
        << "  " << executable
        << " generate OUTPUT_DIRECTORY [SEED]\n"
        << "  " << executable
        << " verify VECTOR_DIRECTORY FPGA_RESULT.bin\n";
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc < 2) {
            PrintUsage(argv[0]);
            return 2;
        }

        const std::string command =
            argv[1];

        if (command == "generate") {
            if (argc != 3 && argc != 4) {
                PrintUsage(argv[0]);
                return 2;
            }

            const std::uint64_t seed =
                argc == 4
                    ? ParseSeed(argv[3])
                    : UINT64_C(0x4096f1e2026);

            return Generate(
                fs::path(argv[2]),
                seed
            );
        }

        if (command == "verify") {
            if (argc != 4) {
                PrintUsage(argv[0]);
                return 2;
            }

            return Verify(
                fs::path(argv[2]),
                fs::path(argv[3])
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
