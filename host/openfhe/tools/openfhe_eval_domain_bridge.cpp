#include "openfhe.h"

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
using lbcrypto::CCParams;
using lbcrypto::Ciphertext;
using lbcrypto::CryptoContext;
using lbcrypto::CryptoContextBGVRNS;
using lbcrypto::DCRTPoly;
using lbcrypto::ILDCRTParams;
using lbcrypto::NativeInteger;
using lbcrypto::NativePoly;
using lbcrypto::Plaintext;

namespace {

constexpr std::uint32_t kN = 4096;
constexpr std::uint32_t kOrder = 8192;
constexpr std::uint64_t kPlaintextModulus = 257;
constexpr std::uint32_t kPrimeBits = 30;
constexpr std::size_t kValueCount = 16;
constexpr std::size_t kInputComponents = 2;
constexpr std::size_t kOutputComponents = 3;
constexpr std::size_t kInputWordsPerCoefficient = 4;
constexpr std::size_t kOutputWordsPerCoefficient = 3;

using Params = ILDCRTParams<BigInteger>;
using Towers = std::vector<std::vector<std::uint32_t>>;

[[noreturn]] void Fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::uint64_t ParseUnsigned(
    const std::string& text,
    std::string_view label
) {
    std::size_t consumed = 0;
    const std::uint64_t value =
        std::stoull(text, &consumed, 0);

    if (consumed != text.size()) {
        Fail(
            "Invalid "
            + std::string(label)
            + ": "
            + text
        );
    }

    return value;
}

std::uint64_t BarrettMu(std::uint64_t modulus) {
    return (
        static_cast<unsigned __int128>(1) << 60U
    ) / modulus;
}

void RequireHardwareModulus(std::uint64_t modulus) {
    if (
        modulus <= (UINT64_C(1) << 29U)
        || modulus >= (UINT64_C(1) << 30U)
    ) {
        Fail(
            "Hardware requires 2^29 < q < 2^30; q="
            + std::to_string(modulus)
        );
    }

    const std::uint64_t mu =
        BarrettMu(modulus);

    if (mu >= (UINT64_C(1) << 31U)) {
        Fail(
            "Barrett reciprocal does not fit 31 bits for q="
            + std::to_string(modulus)
        );
    }
}

CryptoContext<DCRTPoly> MakeCryptoContext(
    std::size_t requested_tower_count
) {
    if (requested_tower_count < 2) {
        Fail(
            "requested_tower_count must be at least two"
        );
    }

    CCParams<CryptoContextBGVRNS> parameters;

    parameters.SetPlaintextModulus(
        kPlaintextModulus
    );

    parameters.SetMultiplicativeDepth(
        static_cast<std::uint32_t>(
            requested_tower_count - 1
        )
    );

    parameters.SetScalingTechnique(
        lbcrypto::FIXEDMANUAL
    );

    parameters.SetFirstModSize(
        kPrimeBits
    );

    parameters.SetScalingModSize(
        kPrimeBits
    );

    parameters.SetSecurityLevel(
        lbcrypto::HEStd_NotSet
    );

    parameters.SetRingDim(
        kN
    );

    parameters.SetBatchSize(
        kValueCount
    );

    auto context =
        lbcrypto::GenCryptoContext(parameters);

    context->Enable(lbcrypto::PKE);
    context->Enable(lbcrypto::LEVELEDSHE);

    if (context->GetRingDimension() != kN) {
        Fail(
            "OpenFHE generated the wrong ring dimension"
        );
    }

    const std::size_t actual_tower_count =
        context->GetElementParams()
            ->GetParams()
            .size();

    if (actual_tower_count != requested_tower_count) {
        Fail(
            "OpenFHE generated "
            + std::to_string(actual_tower_count)
            + " Q towers; requested "
            + std::to_string(requested_tower_count)
        );
    }

    for (
        const auto& tower_params :
            context->GetElementParams()->GetParams()
    ) {
        RequireHardwareModulus(
            tower_params
                ->GetModulus()
                .ConvertToInt<std::uint64_t>()
        );
    }

    return context;
}

std::vector<std::int64_t> GenerateValues(
    std::mt19937_64& generator
) {
    std::uniform_int_distribution<std::int64_t>
        distribution(0, 31);

    std::vector<std::int64_t> result(
        kValueCount
    );

    for (auto& value : result) {
        value =
            distribution(generator);
    }

    return result;
}

std::vector<DCRTPoly> EvaluationElements(
    const Ciphertext<DCRTPoly>& ciphertext,
    std::size_t expected_count,
    std::string_view label
) {
    if (!ciphertext) {
        Fail(
            std::string(label) + " is null"
        );
    }

    const auto& elements =
        ciphertext->GetElements();

    if (elements.size() != expected_count) {
        Fail(
            std::string(label)
            + " has "
            + std::to_string(elements.size())
            + " components; expected "
            + std::to_string(expected_count)
        );
    }

    std::vector<DCRTPoly> result;
    result.reserve(elements.size());

    for (const auto& element : elements) {
        if (element.GetFormat() != Format::EVALUATION) {
            Fail(
                std::string(label)
                + " component is not in evaluation format"
            );
        }

        result.emplace_back(element);
    }

    return result;
}

void RequirePolyEqual(
    const DCRTPoly& actual,
    const DCRTPoly& expected,
    std::string_view label
) {
    if (!(actual == expected)) {
        Fail(
            std::string(label)
            + " DCRTPoly mismatch"
        );
    }
}

std::array<DCRTPoly, 3> FusedEvaluationProduct(
    const std::vector<DCRTPoly>& a,
    const std::vector<DCRTPoly>& b
) {
    if (
        a.size() != kInputComponents
        || b.size() != kInputComponents
    ) {
        Fail(
            "FusedEvaluationProduct requires two-component ciphertexts"
        );
    }

    DCRTPoly c0 =
        a[0] * b[0];

    DCRTPoly c1 =
        a[0] * b[1];

    c1 +=
        a[1] * b[0];

    DCRTPoly c2 =
        a[1] * b[1];

    return {
        std::move(c0),
        std::move(c1),
        std::move(c2)
    };
}

Towers ExtractTowers(
    const DCRTPoly& poly
) {
    if (poly.GetFormat() != Format::EVALUATION) {
        Fail(
            "Attempted to export a non-evaluation DCRTPoly"
        );
    }

    Towers result(
        poly.GetNumOfElements()
    );

    for (
        std::size_t tower_index = 0;
        tower_index < result.size();
        ++tower_index
    ) {
        result[tower_index].resize(kN);

        const NativePoly& tower =
            poly.GetElementAtIndex(
                static_cast<usint>(tower_index)
            );

        if (tower.GetFormat() != Format::EVALUATION) {
            Fail(
                "Native tower is not in evaluation format"
            );
        }

        for (
            std::size_t index = 0;
            index < kN;
            ++index
        ) {
            result[tower_index][index] =
                static_cast<std::uint32_t>(
                    tower[
                        static_cast<usint>(index)
                    ].ConvertToInt<std::uint64_t>()
                );
        }
    }

    return result;
}

DCRTPoly MakeEvaluationPoly(
    const std::shared_ptr<Params>& params,
    const Towers& values
) {
    if (
        values.size()
        != params->GetParams().size()
    ) {
        Fail(
            "Evaluation tower count does not match parameters"
        );
    }

    DCRTPoly result(
        params,
        Format::EVALUATION,
        true
    );

    for (
        std::size_t tower_index = 0;
        tower_index < values.size();
        ++tower_index
    ) {
        if (values[tower_index].size() != kN) {
            Fail(
                "Evaluation tower has the wrong ring dimension"
            );
        }

        const auto& tower_params =
            params->GetParams().at(tower_index);

        const std::uint64_t modulus =
            tower_params
                ->GetModulus()
                .ConvertToInt<std::uint64_t>();

        NativePoly tower(
            tower_params,
            Format::EVALUATION,
            true
        );

        for (
            std::size_t index = 0;
            index < kN;
            ++index
        ) {
            const std::uint32_t value =
                values[tower_index][index];

            if (value >= modulus) {
                Fail(
                    "Evaluation value is outside its tower modulus"
                );
            }

            tower[
                static_cast<usint>(index)
            ] = NativeInteger(value);
        }

        result.SetElementAtIndex(
            static_cast<usint>(tower_index),
            std::move(tower)
        );
    }

    return result;
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
        reinterpret_cast<const char*>(
            bytes.data()
        ),
        static_cast<std::streamsize>(
            bytes.size()
        )
    );
}

std::uint32_t ReadU32LE(
    std::istream& input
) {
    std::array<unsigned char, 4> bytes{};

    input.read(
        reinterpret_cast<char*>(
            bytes.data()
        ),
        static_cast<std::streamsize>(
            bytes.size()
        )
    );

    if (!input) {
        Fail(
            "Unexpected end of binary file"
        );
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

void WriteBinary(
    const fs::path& path,
    const std::vector<std::uint32_t>& words
) {
    fs::create_directories(
        path.parent_path()
    );

    std::ofstream output(
        path,
        std::ios::binary
        | std::ios::trunc
    );

    if (!output) {
        Fail(
            "Could not open output file: "
            + path.string()
        );
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
        Fail(
            "Could not open input file: "
            + path.string()
        );
    }

    input.seekg(0, std::ios::end);

    const std::streamoff bytes =
        static_cast<std::streamoff>(
            input.tellg()
        );

    input.seekg(0, std::ios::beg);

    const std::streamoff expected_bytes =
        static_cast<std::streamoff>(
            expected_words
            * sizeof(std::uint32_t)
        );

    if (bytes != expected_bytes) {
        Fail(
            path.string()
            + " has the wrong size"
        );
    }

    std::vector<std::uint32_t> result(
        expected_words
    );

    for (auto& word : result) {
        word =
            ReadU32LE(input);
    }

    return result;
}

std::string TowerName(
    std::size_t tower_index
) {
    std::ostringstream output;

    output
        << "tower"
        << std::setw(3)
        << std::setfill('0')
        << tower_index;

    return output.str();
}

std::string ReadText(
    const fs::path& path
) {
    std::ifstream input(path);

    if (!input) {
        Fail(
            "Could not open text file: "
            + path.string()
        );
    }

    std::ostringstream output;
    output << input.rdbuf();
    return output.str();
}

std::uint64_t ReadJsonUnsigned(
    const fs::path& path,
    std::string_view key
) {
    const std::string text =
        ReadText(path);

    const std::regex pattern(
        "\\\""
        + std::string(key)
        + "\\\"\\s*:\\s*([0-9]+)"
    );

    std::smatch match;

    if (!std::regex_search(
        text,
        match,
        pattern
    )) {
        Fail(
            "Missing JSON integer "
            + std::string(key)
            + " in "
            + path.string()
        );
    }

    return ParseUnsigned(
        match[1].str(),
        key
    );
}

std::vector<std::uint32_t> Slice(
    const std::vector<std::uint32_t>& source,
    std::size_t offset,
    std::size_t count
) {
    if (
        offset > source.size()
        || count > source.size() - offset
    ) {
        Fail(
            "Binary slice is outside the source vector"
        );
    }

    return std::vector<std::uint32_t>(
        source.begin()
            + static_cast<std::ptrdiff_t>(offset),
        source.begin()
            + static_cast<std::ptrdiff_t>(
                offset + count
            )
    );
}

int Generate(
    const fs::path& output_directory,
    std::size_t requested_tower_count,
    std::size_t ciphertext_count,
    std::uint64_t seed
) {
    if (ciphertext_count == 0) {
        Fail(
            "ciphertext_count must be positive"
        );
    }

    fs::remove_all(output_directory);
    fs::create_directories(output_directory);

    const auto setup_start =
        std::chrono::steady_clock::now();

    const CryptoContext<DCRTPoly> context =
        MakeCryptoContext(
            requested_tower_count
        );

    const auto key_pair =
        context->KeyGen();

    if (!key_pair.good()) {
        Fail(
            "OpenFHE key generation failed"
        );
    }

    const auto params =
        context->GetElementParams();

    const std::size_t tower_count =
        params->GetParams().size();

    const auto setup_stop =
        std::chrono::steady_clock::now();

    std::vector<std::vector<std::uint32_t>>
        input_by_tower(tower_count);

    std::vector<std::vector<std::uint32_t>>
        expected_by_tower(tower_count);

    for (
        std::size_t tower = 0;
        tower < tower_count;
        ++tower
    ) {
        input_by_tower[tower].reserve(
            ciphertext_count
            * kN
            * kInputWordsPerCoefficient
        );

        expected_by_tower[tower].reserve(
            ciphertext_count
            * kN
            * kOutputWordsPerCoefficient
        );
    }

    std::mt19937_64 generator(seed);
    double openfhe_us = 0.0;

    for (
        std::size_t ciphertext_index = 0;
        ciphertext_index < ciphertext_count;
        ++ciphertext_index
    ) {
        Plaintext plaintext_a =
            context->MakeCoefPackedPlaintext(
                GenerateValues(generator)
            );

        Plaintext plaintext_b =
            context->MakeCoefPackedPlaintext(
                GenerateValues(generator)
            );

        const Ciphertext<DCRTPoly> ciphertext_a =
            context->Encrypt(
                key_pair.publicKey,
                plaintext_a
            );

        const Ciphertext<DCRTPoly> ciphertext_b =
            context->Encrypt(
                key_pair.publicKey,
                plaintext_b
            );

        const std::vector<DCRTPoly> a =
            EvaluationElements(
                ciphertext_a,
                kInputComponents,
                "ciphertext A"
            );

        const std::vector<DCRTPoly> b =
            EvaluationElements(
                ciphertext_b,
                kInputComponents,
                "ciphertext B"
            );

        const auto software_start =
            std::chrono::steady_clock::now();

        const Ciphertext<DCRTPoly> expected_ciphertext =
            context->EvalMultNoRelin(
                ciphertext_a,
                ciphertext_b
            );

        const auto software_stop =
            std::chrono::steady_clock::now();

        openfhe_us +=
            std::chrono::duration<
                double,
                std::micro
            >(
                software_stop
                - software_start
            ).count();

        const std::vector<DCRTPoly> expected =
            EvaluationElements(
                expected_ciphertext,
                kOutputComponents,
                "EvalMultNoRelin output"
            );

        const std::array<DCRTPoly, 3> fused =
            FusedEvaluationProduct(a, b);

        for (
            std::size_t component = 0;
            component < kOutputComponents;
            ++component
        ) {
            RequirePolyEqual(
                fused[component],
                expected[component],
                "fused evaluation component "
                    + std::to_string(component)
            );
        }

        const Towers a0 =
            ExtractTowers(a[0]);

        const Towers a1 =
            ExtractTowers(a[1]);

        const Towers b0 =
            ExtractTowers(b[0]);

        const Towers b1 =
            ExtractTowers(b[1]);

        const Towers c0 =
            ExtractTowers(expected[0]);

        const Towers c1 =
            ExtractTowers(expected[1]);

        const Towers c2 =
            ExtractTowers(expected[2]);

        for (
            std::size_t tower = 0;
            tower < tower_count;
            ++tower
        ) {
            for (
                std::size_t index = 0;
                index < kN;
                ++index
            ) {
                input_by_tower[tower].push_back(
                    a0[tower][index]
                );

                input_by_tower[tower].push_back(
                    a1[tower][index]
                );

                input_by_tower[tower].push_back(
                    b0[tower][index]
                );

                input_by_tower[tower].push_back(
                    b1[tower][index]
                );

                expected_by_tower[tower].push_back(
                    c0[tower][index]
                );

                expected_by_tower[tower].push_back(
                    c1[tower][index]
                );

                expected_by_tower[tower].push_back(
                    c2[tower][index]
                );
            }
        }
    }

    for (
        std::size_t tower = 0;
        tower < tower_count;
        ++tower
    ) {
        const auto& tower_params =
            params->GetParams().at(tower);

        const std::uint64_t modulus =
            tower_params
                ->GetModulus()
                .ConvertToInt<std::uint64_t>();

        const std::uint64_t root =
            tower_params
                ->GetRootOfUnity()
                .ConvertToInt<std::uint64_t>();

        const std::uint64_t mu =
            BarrettMu(modulus);

        const fs::path tower_directory =
            output_directory
            / TowerName(tower);

        WriteBinary(
            tower_directory / "dma_input.bin",
            input_by_tower[tower]
        );

        WriteBinary(
            tower_directory / "openfhe_expected.bin",
            expected_by_tower[tower]
        );

        std::ofstream profile(
            tower_directory / "profile.json",
            std::ios::trunc
        );

        if (!profile) {
            Fail(
                "Could not write tower profile"
            );
        }

        profile
            << "{\n"
            << "  \"tower_index\": "
            << tower << ",\n"
            << "  \"ring_dimension\": "
            << kN << ",\n"
            << "  \"cyclotomic_order\": "
            << kOrder << ",\n"
            << "  \"modulus\": "
            << modulus << ",\n"
            << "  \"mu\": "
            << mu << ",\n"
            << "  \"psi\": "
            << root << "\n"
            << "}\n";
    }

    std::ofstream metadata(
        output_directory / "metadata.json",
        std::ios::trunc
    );

    if (!metadata) {
        Fail(
            "Could not write metadata.json"
        );
    }

    metadata
        << "{\n"
        << "  \"format\": "
        << "\"openfhe-bgvrns-evalmul3-v1\",\n"
        << "  \"openfhe_version_target\": "
        << "\"1.5.1\",\n"
        << "  \"scheme\": \"BGVRNS\",\n"
        << "  \"ring_dimension\": "
        << kN << ",\n"
        << "  \"cyclotomic_order\": "
        << kOrder << ",\n"
        << "  \"plaintext_modulus\": "
        << kPlaintextModulus << ",\n"
        << "  \"tower_count\": "
        << tower_count << ",\n"
        << "  \"tower_pair_count\": "
        << ((tower_count + 1) / 2) << ",\n"
        << "  \"ciphertext_count\": "
        << ciphertext_count << ",\n"
        << "  \"input_components\": "
        << kInputComponents << ",\n"
        << "  \"output_components\": "
        << kOutputComponents << ",\n"
        << "  \"input_words_per_coefficient\": "
        << kInputWordsPerCoefficient << ",\n"
        << "  \"output_words_per_coefficient\": "
        << kOutputWordsPerCoefficient << ",\n"
        << "  \"input_order\": "
        << "\"a0,a1,b0,b1\",\n"
        << "  \"output_order\": "
        << "\"c0,c1,c2\",\n"
        << "  \"domain\": \"EVALUATION\",\n"
        << "  \"seed\": "
        << seed << "\n"
        << "}\n";

    const double setup_us =
        std::chrono::duration<
            double,
            std::micro
        >(
            setup_stop
            - setup_start
        ).count();

    std::cout
        << "PASS: generated "
        << ciphertext_count
        << " pairs of real encrypted BGVRNS ciphertexts\n"
        << "PASS: all input components remained in evaluation format\n"
        << "PASS: c0=a0*b0 exactly in evaluation format\n"
        << "PASS: c1=a0*b1+a1*b0 exactly in evaluation format\n"
        << "PASS: c2=a1*b1 exactly in evaluation format\n"
        << "PASS: fused components equal OpenFHE EvalMultNoRelin\n"
        << "ring_dimension="
        << kN << '\n'
        << "tower_count="
        << tower_count << '\n'
        << "ciphertext_count="
        << ciphertext_count << '\n'
        << "scalar_modular_products="
        << ciphertext_count
            * tower_count
            * kN
            * 4
        << '\n'
        << "setup_us="
        << std::fixed
        << std::setprecision(2)
        << setup_us << '\n'
        << "openfhe_EvalMultNoRelin_us_total="
        << openfhe_us << '\n'
        << "openfhe_EvalMultNoRelin_us_per_ciphertext="
        << (
            openfhe_us
            / static_cast<double>(
                ciphertext_count
            )
        ) << '\n'
        << "output_directory="
        << fs::absolute(
            output_directory
        ).string()
        << '\n';

    return 0;
}

int Verify(
    const fs::path& vector_directory,
    const fs::path& result_directory
) {
    const fs::path metadata_path =
        vector_directory
        / "metadata.json";

    const std::size_t tower_count =
        static_cast<std::size_t>(
            ReadJsonUnsigned(
                metadata_path,
                "tower_count"
            )
        );

    const std::size_t ciphertext_count =
        static_cast<std::size_t>(
            ReadJsonUnsigned(
                metadata_path,
                "ciphertext_count"
            )
        );

    std::vector<NativeInteger> moduli;
    std::vector<NativeInteger> roots;

    moduli.reserve(tower_count);
    roots.reserve(tower_count);

    std::vector<std::vector<std::uint32_t>>
        input_by_tower(tower_count);

    std::vector<std::vector<std::uint32_t>>
        expected_by_tower(tower_count);

    std::vector<std::vector<std::uint32_t>>
        fpga_by_tower(tower_count);

    const std::size_t input_words_per_tower =
        ciphertext_count
        * kN
        * kInputWordsPerCoefficient;

    const std::size_t output_words_per_tower =
        ciphertext_count
        * kN
        * kOutputWordsPerCoefficient;

    for (
        std::size_t tower = 0;
        tower < tower_count;
        ++tower
    ) {
        const std::string name =
            TowerName(tower);

        const fs::path profile_path =
            vector_directory
            / name
            / "profile.json";

        const std::uint64_t modulus =
            ReadJsonUnsigned(
                profile_path,
                "modulus"
            );

        RequireHardwareModulus(modulus);

        moduli.emplace_back(modulus);

        roots.emplace_back(
            ReadJsonUnsigned(
                profile_path,
                "psi"
            )
        );

        input_by_tower[tower] =
            ReadBinary(
                vector_directory
                    / name
                    / "dma_input.bin",
                input_words_per_tower
            );

        expected_by_tower[tower] =
            ReadBinary(
                vector_directory
                    / name
                    / "openfhe_expected.bin",
                output_words_per_tower
            );

        fpga_by_tower[tower] =
            ReadBinary(
                result_directory
                    / (name + ".bin"),
                output_words_per_tower
            );
    }

    const auto params =
        std::make_shared<Params>(
            kOrder,
            moduli,
            roots
        );

    std::size_t verified_components = 0;

    for (
        std::size_t ciphertext_index = 0;
        ciphertext_index < ciphertext_count;
        ++ciphertext_index
    ) {
        Towers a0(tower_count);
        Towers a1(tower_count);
        Towers b0(tower_count);
        Towers b1(tower_count);

        Towers expected_c0(tower_count);
        Towers expected_c1(tower_count);
        Towers expected_c2(tower_count);

        Towers fpga_c0(tower_count);
        Towers fpga_c1(tower_count);
        Towers fpga_c2(tower_count);

        for (
            std::size_t tower = 0;
            tower < tower_count;
            ++tower
        ) {
            a0[tower].resize(kN);
            a1[tower].resize(kN);
            b0[tower].resize(kN);
            b1[tower].resize(kN);

            expected_c0[tower].resize(kN);
            expected_c1[tower].resize(kN);
            expected_c2[tower].resize(kN);

            fpga_c0[tower].resize(kN);
            fpga_c1[tower].resize(kN);
            fpga_c2[tower].resize(kN);

            for (
                std::size_t index = 0;
                index < kN;
                ++index
            ) {
                const std::size_t input_base =
                    (
                        ciphertext_index * kN
                        + index
                    )
                    * kInputWordsPerCoefficient;

                const std::size_t output_base =
                    (
                        ciphertext_index * kN
                        + index
                    )
                    * kOutputWordsPerCoefficient;

                a0[tower][index] =
                    input_by_tower[tower][
                        input_base + 0
                    ];

                a1[tower][index] =
                    input_by_tower[tower][
                        input_base + 1
                    ];

                b0[tower][index] =
                    input_by_tower[tower][
                        input_base + 2
                    ];

                b1[tower][index] =
                    input_by_tower[tower][
                        input_base + 3
                    ];

                expected_c0[tower][index] =
                    expected_by_tower[tower][
                        output_base + 0
                    ];

                expected_c1[tower][index] =
                    expected_by_tower[tower][
                        output_base + 1
                    ];

                expected_c2[tower][index] =
                    expected_by_tower[tower][
                        output_base + 2
                    ];

                fpga_c0[tower][index] =
                    fpga_by_tower[tower][
                        output_base + 0
                    ];

                fpga_c1[tower][index] =
                    fpga_by_tower[tower][
                        output_base + 1
                    ];

                fpga_c2[tower][index] =
                    fpga_by_tower[tower][
                        output_base + 2
                    ];
            }
        }

        const std::vector<DCRTPoly> a{
            MakeEvaluationPoly(params, a0),
            MakeEvaluationPoly(params, a1)
        };

        const std::vector<DCRTPoly> b{
            MakeEvaluationPoly(params, b0),
            MakeEvaluationPoly(params, b1)
        };

        const std::array<DCRTPoly, 3> recomputed =
            FusedEvaluationProduct(a, b);

        const std::array<DCRTPoly, 3> stored{
            MakeEvaluationPoly(
                params,
                expected_c0
            ),
            MakeEvaluationPoly(
                params,
                expected_c1
            ),
            MakeEvaluationPoly(
                params,
                expected_c2
            )
        };

        const std::array<DCRTPoly, 3> fpga{
            MakeEvaluationPoly(
                params,
                fpga_c0
            ),
            MakeEvaluationPoly(
                params,
                fpga_c1
            ),
            MakeEvaluationPoly(
                params,
                fpga_c2
            )
        };

        for (
            std::size_t component = 0;
            component < kOutputComponents;
            ++component
        ) {
            RequirePolyEqual(
                stored[component],
                recomputed[component],
                "stored evaluation component"
            );

            RequirePolyEqual(
                fpga[component],
                recomputed[component],
                "FPGA evaluation component"
            );

            ++verified_components;
        }
    }

    std::cout
        << "PASS: every FPGA c0 component equals OpenFHE\n"
        << "PASS: every FPGA c1 component equals OpenFHE\n"
        << "PASS: every FPGA c2 component equals OpenFHE\n"
        << "PASS: evaluation-domain ciphertext fusion verified exactly\n"
        << "tower_count="
        << tower_count << '\n'
        << "ciphertext_count="
        << ciphertext_count << '\n'
        << "verified_components="
        << verified_components << '\n'
        << "verified_tower_components="
        << verified_components
            * tower_count
        << '\n';

    return 0;
}

void PrintUsage(
    const char* executable
) {
    std::cerr
        << "Usage:\n"
        << "  "
        << executable
        << " generate OUTPUT_DIRECTORY "
        << "TOWER_COUNT CIPHERTEXT_COUNT [SEED]\n"
        << "  "
        << executable
        << " verify VECTOR_DIRECTORY "
        << "FPGA_RESULT_DIRECTORY\n";
}

}  // namespace

int main(
    int argc,
    char** argv
) {
    try {
        if (argc < 2) {
            PrintUsage(argv[0]);
            return 2;
        }

        const std::string command =
            argv[1];

        if (command == "generate") {
            if (
                argc != 5
                && argc != 6
            ) {
                PrintUsage(argv[0]);
                return 2;
            }

            const std::size_t tower_count =
                static_cast<std::size_t>(
                    ParseUnsigned(
                        argv[3],
                        "tower count"
                    )
                );

            const std::size_t ciphertext_count =
                static_cast<std::size_t>(
                    ParseUnsigned(
                        argv[4],
                        "ciphertext count"
                    )
                );

            const std::uint64_t seed =
                argc == 6
                ? ParseUnsigned(
                    argv[5],
                    "seed"
                )
                : UINT64_C(0xe1a140962026);

            return Generate(
                fs::path(argv[2]),
                tower_count,
                ciphertext_count,
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
    catch (
        const std::exception& error
    ) {
        std::cerr
            << "FAIL: "
            << error.what()
            << '\n';

        return 1;
    }
}
