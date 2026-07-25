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
/*
 * Keep t small enough that FIXEDMANUAL can find many Q primes below 2^30.
 * Ciphertext generation uses coefficient-packed plaintexts, so t does not
 * need to contain an 8192nd root of unity.
 */
constexpr std::uint64_t kPlaintextModulus = 257;
/*
 * The Barrett reciprocal is floor(2^60/q) and is carried in 31 bits.
 * Therefore the actual hardware modulus window is:
 *
 *     2^29 < q < 2^30
 *
 * OpenFHE's modulus-size parameter is a bit length, so request 30-bit
 * moduli; requesting 29 bits deliberately places q below 2^29.
 */
constexpr std::uint32_t kPrimeBits = 30;
constexpr std::size_t kSlots = 16;
constexpr std::size_t kCompactTwiddles = kN - 1;
constexpr std::size_t kCiphertextInputComponents = 2;
constexpr std::size_t kRawProductsPerCiphertext = 4;
constexpr std::size_t kOutputComponents = 3;
constexpr std::size_t kWordsPerRawProductPerTower = 2 * kN;

using Params = ILDCRTParams<BigInteger>;
using Coefficients = std::vector<std::vector<std::uint32_t>>;

[[noreturn]] void Fail(const std::string& message) {
    throw std::runtime_error(message);
}

std::uint64_t ParseUnsigned(
    const std::string& text,
    std::string_view label
) {
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

std::uint64_t ModInverse(
    std::uint64_t value,
    std::uint64_t modulus
) {
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

TowerProfile BuildProfile(
    std::uint64_t modulus,
    std::uint64_t psi
) {
    if (modulus >= (UINT64_C(1) << 30U)) {
        Fail(
            "CryptoContext modulus "
            + std::to_string(modulus)
            + " is not below the hardware 2^30 limit"
        );
    }

    const std::uint64_t reciprocal =
        (UINT64_C(1) << 60U) / modulus;

    if (reciprocal >= (UINT64_C(1) << 31U)) {
        Fail(
            "CryptoContext modulus "
            + std::to_string(modulus)
            + " is too small for the 31-bit Barrett reciprocal; "
            + "the hardware requires q > 2^29"
        );
    }

    if (ModPow(psi, kOrder, modulus) != 1) {
        Fail("psi^8192 is not one for modulus " + std::to_string(modulus));
    }

    if (ModPow(psi, kN, modulus) != modulus - 1) {
        Fail(
            "OpenFHE root is not a primitive 8192nd root for modulus "
            + std::to_string(modulus)
        );
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
            (
                static_cast<unsigned __int128>(profile.n_inverse)
                * psi_inverse_power
            ) % modulus
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

std::vector<TowerProfile> ProfilesFromParams(
    const std::shared_ptr<Params>& params
) {
    std::vector<TowerProfile> profiles;
    profiles.reserve(params->GetParams().size());

    for (const auto& tower_params : params->GetParams()) {
        profiles.push_back(
            BuildProfile(
                tower_params->GetModulus().ConvertToInt<std::uint64_t>(),
                tower_params->GetRootOfUnity().ConvertToInt<std::uint64_t>()
            )
        );
    }

    return profiles;
}

CryptoContext<DCRTPoly> MakeCryptoContext(
    std::size_t requested_tower_count
) {
    if (requested_tower_count < 2) {
        Fail("requested_tower_count must be at least two");
    }

    /*
     * In BGV FIXEDMANUAL, Q primes are selected modulo
     * lcm(2N, plaintext modulus).  Ensure that the selected order leaves
     * room for more than one candidate below the requested Q bit limit.
     */
    const std::uint64_t modulus_order =
        static_cast<std::uint64_t>(kOrder)
        * kPlaintextModulus;

    const std::uint64_t q_limit =
        UINT64_C(1) << kPrimeBits;

    if (2 * modulus_order + 1 >= q_limit) {
        Fail(
            "Plaintext modulus "
            + std::to_string(kPlaintextModulus)
            + " is incompatible with N=4096, "
            + std::to_string(kPrimeBits)
            + "-bit FIXEDMANUAL Q primes below 2^30"
        );
    }

    CCParams<CryptoContextBGVRNS> parameters;

    parameters.SetPlaintextModulus(kPlaintextModulus);
    parameters.SetMultiplicativeDepth(
        static_cast<std::uint32_t>(requested_tower_count - 1)
    );
    parameters.SetScalingTechnique(lbcrypto::FIXEDMANUAL);
    parameters.SetFirstModSize(kPrimeBits);
    parameters.SetScalingModSize(kPrimeBits);
    parameters.SetSecurityLevel(lbcrypto::HEStd_NotSet);
    parameters.SetRingDim(kN);
    parameters.SetBatchSize(kSlots);

    auto context = lbcrypto::GenCryptoContext(parameters);

    context->Enable(lbcrypto::PKE);
    context->Enable(lbcrypto::LEVELEDSHE);

    if (context->GetRingDimension() != kN) {
        Fail(
            "OpenFHE generated ring dimension "
            + std::to_string(context->GetRingDimension())
            + "; expected 4096"
        );
    }

    const std::size_t actual_tower_count =
        context->GetElementParams()->GetParams().size();

    if (actual_tower_count != requested_tower_count) {
        Fail(
            "OpenFHE generated "
            + std::to_string(actual_tower_count)
            + " Q towers for multiplicative depth "
            + std::to_string(requested_tower_count - 1)
            + "; requested "
            + std::to_string(requested_tower_count)
        );
    }

    return context;
}

DCRTPoly ToCoefficient(const DCRTPoly& source) {
    DCRTPoly result(source);

    if (result.GetFormat() != Format::COEFFICIENT) {
        result.SwitchFormat();
    }

    if (result.GetFormat() != Format::COEFFICIENT) {
        Fail("DCRTPoly did not switch to coefficient format");
    }

    return result;
}

std::vector<DCRTPoly> CoefficientElements(
    const Ciphertext<DCRTPoly>& ciphertext,
    std::size_t expected_count,
    std::string_view label
) {
    if (!ciphertext) {
        Fail(std::string(label) + " is null");
    }

    const auto& elements = ciphertext->GetElements();

    if (elements.size() != expected_count) {
        Fail(
            std::string(label)
            + " has " + std::to_string(elements.size())
            + " components; expected " + std::to_string(expected_count)
        );
    }

    std::vector<DCRTPoly> result;
    result.reserve(elements.size());

    for (const auto& element : elements) {
        result.emplace_back(ToCoefficient(element));
    }

    return result;
}

DCRTPoly MultiplyWithOpenFHE(
    const DCRTPoly& coefficient_a,
    const DCRTPoly& coefficient_b
) {
    DCRTPoly evaluation_a(coefficient_a);
    DCRTPoly evaluation_b(coefficient_b);

    if (evaluation_a.GetFormat() != Format::EVALUATION) {
        evaluation_a.SwitchFormat();
    }

    if (evaluation_b.GetFormat() != Format::EVALUATION) {
        evaluation_b.SwitchFormat();
    }

    DCRTPoly product = evaluation_a * evaluation_b;

    if (product.GetFormat() != Format::COEFFICIENT) {
        product.SwitchFormat();
    }

    if (product.GetFormat() != Format::COEFFICIENT) {
        Fail("OpenFHE polynomial product did not return to coefficient format");
    }

    return product;
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

std::vector<std::int64_t> GeneratePackedValues(
    std::mt19937_64& generator
) {
    std::uniform_int_distribution<std::int64_t> distribution(0, 31);
    std::vector<std::int64_t> result(kSlots);

    for (auto& value : result) {
        value = distribution(generator);
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
            path.string()
            + " has " + std::to_string(static_cast<long long>(bytes))
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

    output
        << "tower"
        << std::setw(3)
        << std::setfill('0')
        << tower_index;

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
        Fail(
            "Missing JSON integer "
            + std::string(key)
            + " in " + path.string()
        );
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
                + " mismatch at coefficient "
                + std::to_string(index)
                + ": result=" + std::to_string(actual[index])
                + ", expected=" + std::to_string(expected[index])
            );
        }
    }
}

void RequirePolyEqual(
    const DCRTPoly& actual,
    const DCRTPoly& expected,
    std::string_view label
) {
    if (!(actual == expected)) {
        Fail(std::string(label) + " DCRTPoly mismatch");
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
    std::size_t requested_tower_count,
    std::size_t ciphertext_count,
    std::uint64_t seed
) {
    if (ciphertext_count == 0) {
        Fail("ciphertext_count must be positive");
    }

    fs::remove_all(output_directory);
    fs::create_directories(output_directory);

    const auto context_start = std::chrono::steady_clock::now();

    const CryptoContext<DCRTPoly> context =
        MakeCryptoContext(requested_tower_count);

    const auto key_pair = context->KeyGen();

    if (!key_pair.good()) {
        Fail("OpenFHE key generation failed");
    }

    const auto params = context->GetElementParams();
    const std::vector<TowerProfile> profiles =
        ProfilesFromParams(params);

    const std::size_t tower_count = profiles.size();
    const std::size_t raw_product_count =
        ciphertext_count * kRawProductsPerCiphertext;

    const auto context_stop = std::chrono::steady_clock::now();

    std::vector<std::vector<std::uint32_t>> dma_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>> raw_expected_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>> component_expected_by_tower(
        tower_count
    );

    for (std::size_t tower = 0; tower < tower_count; ++tower) {
        dma_by_tower[tower].reserve(
            raw_product_count * kWordsPerRawProductPerTower
        );
        raw_expected_by_tower[tower].reserve(
            raw_product_count * kN
        );
        component_expected_by_tower[tower].reserve(
            ciphertext_count * kOutputComponents * kN
        );
    }

    std::mt19937_64 generator(seed);
    double software_us = 0.0;

    for (std::size_t ciphertext_index = 0;
         ciphertext_index < ciphertext_count;
         ++ciphertext_index) {
        const std::vector<std::int64_t> values_a =
            GeneratePackedValues(generator);
        const std::vector<std::int64_t> values_b =
            GeneratePackedValues(generator);

        Plaintext plaintext_a =
            context->MakeCoefPackedPlaintext(values_a);
        Plaintext plaintext_b =
            context->MakeCoefPackedPlaintext(values_b);

        const Ciphertext<DCRTPoly> ciphertext_a =
            context->Encrypt(key_pair.publicKey, plaintext_a);
        const Ciphertext<DCRTPoly> ciphertext_b =
            context->Encrypt(key_pair.publicKey, plaintext_b);

        const std::vector<DCRTPoly> a =
            CoefficientElements(
                ciphertext_a,
                kCiphertextInputComponents,
                "ciphertext A"
            );

        const std::vector<DCRTPoly> b =
            CoefficientElements(
                ciphertext_b,
                kCiphertextInputComponents,
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

        software_us +=
            std::chrono::duration<double, std::micro>(
                software_stop - software_start
            ).count();

        const std::vector<DCRTPoly> expected_components =
            CoefficientElements(
                expected_ciphertext,
                kOutputComponents,
                "EvalMultNoRelin output"
            );

        std::vector<DCRTPoly> raw_products;
        raw_products.reserve(kRawProductsPerCiphertext);

        raw_products.emplace_back(MultiplyWithOpenFHE(a[0], b[0]));
        raw_products.emplace_back(MultiplyWithOpenFHE(a[0], b[1]));
        raw_products.emplace_back(MultiplyWithOpenFHE(a[1], b[0]));
        raw_products.emplace_back(MultiplyWithOpenFHE(a[1], b[1]));

        DCRTPoly combined_middle(raw_products[1]);
        combined_middle += raw_products[2];

        RequirePolyEqual(
            raw_products[0],
            expected_components[0],
            "OpenFHE c0 = a0*b0"
        );

        RequirePolyEqual(
            combined_middle,
            expected_components[1],
            "OpenFHE c1 = a0*b1 + a1*b0"
        );

        RequirePolyEqual(
            raw_products[3],
            expected_components[2],
            "OpenFHE c2 = a1*b1"
        );

        const std::array<const DCRTPoly*, kRawProductsPerCiphertext> raw_a{
            &a[0],
            &a[0],
            &a[1],
            &a[1],
        };

        const std::array<const DCRTPoly*, kRawProductsPerCiphertext> raw_b{
            &b[0],
            &b[1],
            &b[0],
            &b[1],
        };

        for (std::size_t raw_index = 0;
             raw_index < kRawProductsPerCiphertext;
             ++raw_index) {
            const Coefficients input_a =
                ExtractTowers(*raw_a[raw_index]);
            const Coefficients input_b =
                ExtractTowers(*raw_b[raw_index]);
            const Coefficients expected =
                ExtractTowers(raw_products[raw_index]);

            for (std::size_t tower = 0;
                 tower < tower_count;
                 ++tower) {
                auto& dma = dma_by_tower[tower];

                dma.insert(
                    dma.end(),
                    input_a[tower].begin(),
                    input_a[tower].end()
                );

                dma.insert(
                    dma.end(),
                    input_b[tower].begin(),
                    input_b[tower].end()
                );

                auto& raw_output = raw_expected_by_tower[tower];

                raw_output.insert(
                    raw_output.end(),
                    expected[tower].begin(),
                    expected[tower].end()
                );
            }
        }

        for (std::size_t component = 0;
             component < kOutputComponents;
             ++component) {
            const Coefficients expected =
                ExtractTowers(expected_components[component]);

            for (std::size_t tower = 0;
                 tower < tower_count;
                 ++tower) {
                auto& component_output =
                    component_expected_by_tower[tower];

                component_output.insert(
                    component_output.end(),
                    expected[tower].begin(),
                    expected[tower].end()
                );
            }
        }
    }

    for (std::size_t tower = 0;
         tower < tower_count;
         ++tower) {
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
            output_directory
                / "towers"
                / name
                / "openfhe_expected.bin",
            raw_expected_by_tower[tower]
        );

        WriteBinary(
            output_directory
                / "towers"
                / name
                / "openfhe_prerelin_components.bin",
            component_expected_by_tower[tower]
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
        << "  \"format\": \"openfhe-bgvrns-ciphertext-prerelin-v1\",\n"
        << "  \"openfhe_version_target\": \"1.5.1\",\n"
        << "  \"scheme\": \"BGVRNS\",\n"
        << "  \"ring_dimension\": " << kN << ",\n"
        << "  \"cyclotomic_order\": " << kOrder << ",\n"
        << "  \"plaintext_modulus\": " << kPlaintextModulus << ",\n"
        << "  \"hardware_modulus_min_exclusive\": 536870912,\n"
        << "  \"hardware_modulus_max_exclusive\": 1073741824,\n"
        << "  \"coefficient_value_count\": " << kSlots << ",\n"
        << "  \"requested_tower_count\": "
        << requested_tower_count << ",\n"
        << "  \"tower_count\": " << tower_count << ",\n"
        << "  \"tower_pair_count\": "
        << ((tower_count + 1) / 2) << ",\n"
        << "  \"ciphertext_count\": " << ciphertext_count << ",\n"
        << "  \"input_ciphertext_components\": "
        << kCiphertextInputComponents << ",\n"
        << "  \"raw_products_per_ciphertext\": "
        << kRawProductsPerCiphertext << ",\n"
        << "  \"raw_product_count\": "
        << raw_product_count << ",\n"
        << "  \"output_ciphertext_components\": "
        << kOutputComponents << ",\n"
        << "  \"seed\": " << seed << ",\n"
        << "  \"raw_product_order\": "
        << "\"a0b0,a0b1,a1b0,a1b1\",\n"
        << "  \"prerelin_component_order\": "
        << "\"c0,c1,c2\",\n"
        << "  \"odd_tower_policy\": "
        << "\"duplicate-final-lane-and-discard\",\n"
        << "  \"moduli\": [";

    for (std::size_t tower = 0;
         tower < tower_count;
         ++tower) {
        if (tower != 0) {
            metadata << ", ";
        }

        metadata << profiles[tower].modulus;
    }

    metadata << "],\n  \"roots\": [";

    for (std::size_t tower = 0;
         tower < tower_count;
         ++tower) {
        if (tower != 0) {
            metadata << ", ";
        }

        metadata << profiles[tower].psi;
    }

    metadata
        << "]\n"
        << "}\n";

    const double context_us =
        std::chrono::duration<double, std::micro>(
            context_stop - context_start
        ).count();

    std::cout
        << "PASS: generated " << ciphertext_count
        << " pairs of real encrypted coefficient-packed BGVRNS ciphertexts\n"
        << "PASS: every OpenFHE EvalMultNoRelin output has three components\n"
        << "PASS: component convolution is exact before export\n"
        << "PASS: exported " << raw_product_count
        << " raw DCRTPoly products across "
        << tower_count << " runtime-profiled towers\n"
        << "ring_dimension=" << kN << '\n'
        << "tower_count=" << tower_count << '\n'
        << "ciphertext_count=" << ciphertext_count << '\n'
        << "raw_product_count=" << raw_product_count << '\n'
        << "seed=" << seed << '\n'
        << std::fixed << std::setprecision(2)
        << "context_key_profile_us=" << context_us << '\n'
        << "openfhe_EvalMultNoRelin_us_total="
        << software_us << '\n'
        << "openfhe_EvalMultNoRelin_us_per_ciphertext="
        << (
            software_us
            / static_cast<double>(ciphertext_count)
        ) << '\n'
        << "output_directory="
        << fs::absolute(output_directory).string()
        << '\n';

    return 0;
}

int Verify(
    const fs::path& vector_directory,
    const fs::path& result_directory
) {
    const fs::path metadata_path =
        vector_directory / "metadata.json";

    const std::size_t tower_count =
        static_cast<std::size_t>(
            ReadJsonUnsigned(metadata_path, "tower_count")
        );

    const std::size_t ciphertext_count =
        static_cast<std::size_t>(
            ReadJsonUnsigned(metadata_path, "ciphertext_count")
        );

    const std::size_t raw_products_per_ciphertext =
        static_cast<std::size_t>(
            ReadJsonUnsigned(
                metadata_path,
                "raw_products_per_ciphertext"
            )
        );

    const std::size_t output_components =
        static_cast<std::size_t>(
            ReadJsonUnsigned(
                metadata_path,
                "output_ciphertext_components"
            )
        );

    if (
        raw_products_per_ciphertext
            != kRawProductsPerCiphertext
        || output_components != kOutputComponents
    ) {
        Fail("Vector metadata uses an unsupported ciphertext layout");
    }

    const std::size_t raw_product_count =
        ciphertext_count * kRawProductsPerCiphertext;

    std::vector<TowerProfile> profiles;
    profiles.reserve(tower_count);

    for (std::size_t tower = 0;
         tower < tower_count;
         ++tower) {
        const fs::path profile_path =
            vector_directory
            / "profiles"
            / TowerName(tower)
            / "profile.json";

        profiles.push_back(
            BuildProfile(
                ReadJsonUnsigned(profile_path, "modulus"),
                ReadJsonUnsigned(profile_path, "psi")
            )
        );
    }

    std::vector<NativeInteger> moduli;
    std::vector<NativeInteger> roots;

    moduli.reserve(tower_count);
    roots.reserve(tower_count);

    for (const auto& profile : profiles) {
        moduli.emplace_back(profile.modulus);
        roots.emplace_back(profile.psi);
    }

    const auto params = std::make_shared<Params>(
        kOrder,
        moduli,
        roots
    );

    std::vector<std::vector<std::uint32_t>>
        dma_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>>
        raw_stored_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>>
        components_stored_by_tower(tower_count);
    std::vector<std::vector<std::uint32_t>>
        fpga_by_tower(tower_count);

    for (std::size_t tower = 0;
         tower < tower_count;
         ++tower) {
        const std::string name = TowerName(tower);

        dma_by_tower[tower] = ReadBinary(
            vector_directory
                / "towers"
                / name
                / "dma_input.bin",
            raw_product_count
                * kWordsPerRawProductPerTower
        );

        raw_stored_by_tower[tower] = ReadBinary(
            vector_directory
                / "towers"
                / name
                / "openfhe_expected.bin",
            raw_product_count * kN
        );

        components_stored_by_tower[tower] =
            ReadBinary(
                vector_directory
                    / "towers"
                    / name
                    / "openfhe_prerelin_components.bin",
                ciphertext_count
                    * kOutputComponents
                    * kN
            );

        fpga_by_tower[tower] = ReadBinary(
            result_directory / (name + ".bin"),
            raw_product_count * kN
        );
    }

    std::size_t verified_raw_dcrt_products = 0;
    std::size_t verified_ciphertext_components = 0;

    for (std::size_t ciphertext_index = 0;
         ciphertext_index < ciphertext_count;
         ++ciphertext_index) {
        std::vector<DCRTPoly> fpga_raw_products;
        fpga_raw_products.reserve(kRawProductsPerCiphertext);

        std::array<Coefficients, kRawProductsPerCiphertext>
            input_a;
        std::array<Coefficients, kRawProductsPerCiphertext>
            input_b;

        for (std::size_t raw_index = 0;
             raw_index < kRawProductsPerCiphertext;
             ++raw_index) {
            input_a[raw_index].resize(tower_count);
            input_b[raw_index].resize(tower_count);

            Coefficients stored(tower_count);
            Coefficients fpga(tower_count);

            const std::size_t global_raw_index =
                ciphertext_index
                    * kRawProductsPerCiphertext
                + raw_index;

            for (std::size_t tower = 0;
                 tower < tower_count;
                 ++tower) {
                const std::size_t dma_offset =
                    global_raw_index
                    * kWordsPerRawProductPerTower;

                const std::size_t result_offset =
                    global_raw_index * kN;

                input_a[raw_index][tower] =
                    Slice(
                        dma_by_tower[tower],
                        dma_offset,
                        kN
                    );

                input_b[raw_index][tower] =
                    Slice(
                        dma_by_tower[tower],
                        dma_offset + kN,
                        kN
                    );

                stored[tower] =
                    Slice(
                        raw_stored_by_tower[tower],
                        result_offset,
                        kN
                    );

                fpga[tower] =
                    Slice(
                        fpga_by_tower[tower],
                        result_offset,
                        kN
                    );
            }

            const DCRTPoly coefficient_a =
                MakeCoefficientPoly(
                    params,
                    input_a[raw_index]
                );

            const DCRTPoly coefficient_b =
                MakeCoefficientPoly(
                    params,
                    input_b[raw_index]
                );

            const DCRTPoly recomputed =
                MultiplyWithOpenFHE(
                    coefficient_a,
                    coefficient_b
                );

            const DCRTPoly stored_poly =
                MakeCoefficientPoly(params, stored);

            const DCRTPoly fpga_poly =
                MakeCoefficientPoly(params, fpga);

            const std::string prefix =
                "ciphertext "
                + std::to_string(ciphertext_index)
                + " raw product "
                + std::to_string(raw_index);

            RequirePolyEqual(
                stored_poly,
                recomputed,
                prefix + " stored"
            );

            RequirePolyEqual(
                fpga_poly,
                recomputed,
                prefix + " FPGA"
            );

            fpga_raw_products.emplace_back(fpga_poly);
            ++verified_raw_dcrt_products;
        }

        for (std::size_t tower = 0;
             tower < tower_count;
             ++tower) {
            RequireEqual(
                input_a[0][tower],
                input_a[1][tower],
                "a0 consistency"
            );

            RequireEqual(
                input_b[0][tower],
                input_b[2][tower],
                "b0 consistency"
            );

            RequireEqual(
                input_a[2][tower],
                input_a[3][tower],
                "a1 consistency"
            );

            RequireEqual(
                input_b[1][tower],
                input_b[3][tower],
                "b1 consistency"
            );
        }

        std::vector<DCRTPoly> fpga_components;
        fpga_components.reserve(kOutputComponents);

        fpga_components.emplace_back(fpga_raw_products[0]);

        DCRTPoly middle(fpga_raw_products[1]);
        middle += fpga_raw_products[2];
        fpga_components.emplace_back(std::move(middle));

        fpga_components.emplace_back(fpga_raw_products[3]);

        for (std::size_t component = 0;
             component < kOutputComponents;
             ++component) {
            Coefficients stored_component(tower_count);

            const std::size_t global_component_index =
                ciphertext_index * kOutputComponents
                + component;

            for (std::size_t tower = 0;
                 tower < tower_count;
                 ++tower) {
                stored_component[tower] =
                    Slice(
                        components_stored_by_tower[tower],
                        global_component_index * kN,
                        kN
                    );
            }

            const DCRTPoly expected_component =
                MakeCoefficientPoly(
                    params,
                    stored_component
                );

            RequirePolyEqual(
                fpga_components[component],
                expected_component,
                "FPGA pre-relinearization component "
                    + std::to_string(component)
            );

            ++verified_ciphertext_components;
        }
    }

    std::cout
        << "PASS: every FPGA raw component product equals OpenFHE\n"
        << "PASS: c0 = a0*b0 exactly\n"
        << "PASS: c1 = a0*b1 + a1*b0 exactly\n"
        << "PASS: c2 = a1*b1 exactly\n"
        << "PASS: every reconstructed three-component ciphertext "
        << "equals OpenFHE EvalMultNoRelin component-wise\n"
        << "tower_count=" << tower_count << '\n'
        << "ciphertext_count=" << ciphertext_count << '\n'
        << "verified_raw_dcrt_products="
        << verified_raw_dcrt_products << '\n'
        << "verified_tower_products="
        << tower_count * raw_product_count << '\n'
        << "verified_prerelin_components="
        << verified_ciphertext_components << '\n';

    return 0;
}

void PrintUsage(const char* executable) {
    std::cerr
        << "Usage:\n"
        << "  " << executable
        << " generate OUTPUT_DIRECTORY TOWER_COUNT "
        << "CIPHERTEXT_COUNT [SEED]\n"
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
                    ? ParseUnsigned(argv[5], "seed")
                    : UINT64_C(0xc1f40962026);

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
    catch (const std::exception& error) {
        std::cerr
            << "FAIL: "
            << error.what()
            << '\n';

        return 1;
    }
}
