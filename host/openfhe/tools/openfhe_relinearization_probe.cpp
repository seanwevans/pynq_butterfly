#include "openfhe.h"
#include "scheme/bgvrns/bgvrns-cryptoparameters.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
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
using lbcrypto::CCParams;
using lbcrypto::Ciphertext;
using lbcrypto::CryptoContext;
using lbcrypto::CryptoContextBGVRNS;
using lbcrypto::CryptoContextImpl;
using lbcrypto::CryptoParametersBGVRNS;
using lbcrypto::DCRTPoly;
using lbcrypto::EvalKey;
using lbcrypto::ILDCRTParams;
using lbcrypto::NativeInteger;
using lbcrypto::Plaintext;

namespace {

constexpr std::uint32_t kN = 4096;
constexpr std::uint64_t kPlaintextModulus = 257;
constexpr std::uint32_t kPrimeBits = 30;
constexpr std::size_t kValueCount = 16;

enum class Technique {
    Hybrid,
    Bv,
};

struct Options {
    Technique technique = Technique::Hybrid;
    std::size_t tower_count = 12;
    std::uint32_t num_large_digits = 3;
    std::uint32_t digit_size = 0;
    std::uint64_t seed = UINT64_C(0x52454c494e);
    fs::path output_directory =
        "vectors/relinearization_probe";
};

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

Technique ParseTechnique(const std::string& text) {
    if (text == "hybrid") {
        return Technique::Hybrid;
    }

    if (text == "bv") {
        return Technique::Bv;
    }

    Fail(
        "Unknown key-switch technique: "
        + text
        + " (expected hybrid or bv)"
    );
}

std::string TechniqueName(Technique technique) {
    return technique == Technique::Hybrid
        ? "HYBRID"
        : "BV";
}

Options ParseOptions(int argc, char** argv) {
    Options options;

    for (int index = 1; index < argc; ++index) {
        const std::string argument =
            argv[index];

        auto require_value =
            [&]() -> std::string {
                if (index + 1 >= argc) {
                    Fail(
                        "Missing value after "
                        + argument
                    );
                }

                ++index;
                return argv[index];
            };

        if (argument == "--tech") {
            options.technique =
                ParseTechnique(
                    require_value()
                );
        }
        else if (argument == "--towers") {
            options.tower_count =
                static_cast<std::size_t>(
                    ParseUnsigned(
                        require_value(),
                        "tower count"
                    )
                );
        }
        else if (argument == "--num-large-digits") {
            options.num_large_digits =
                static_cast<std::uint32_t>(
                    ParseUnsigned(
                        require_value(),
                        "num large digits"
                    )
                );
        }
        else if (argument == "--digit-size") {
            options.digit_size =
                static_cast<std::uint32_t>(
                    ParseUnsigned(
                        require_value(),
                        "digit size"
                    )
                );
        }
        else if (argument == "--seed") {
            options.seed =
                ParseUnsigned(
                    require_value(),
                    "seed"
                );
        }
        else if (argument == "--output") {
            options.output_directory =
                require_value();
        }
        else if (
            argument == "-h"
            || argument == "--help"
        ) {
            std::cout
                << "usage: "
                << argv[0]
                << " [--tech hybrid|bv]"
                << " [--towers N]"
                << " [--num-large-digits N]"
                << " [--digit-size BITS]"
                << " [--seed N]"
                << " [--output DIR]\n";

            std::exit(0);
        }
        else {
            Fail(
                "Unknown argument: "
                + argument
            );
        }
    }

    if (options.tower_count < 2) {
        Fail(
            "--towers must be at least two"
        );
    }

    if (
        options.technique == Technique::Hybrid
        && options.num_large_digits == 0
    ) {
        Fail(
            "--num-large-digits must be positive for HYBRID"
        );
    }

    return options;
}

CryptoContext<DCRTPoly> MakeContext(
    const Options& options
) {
    CCParams<CryptoContextBGVRNS> parameters;

    parameters.SetPlaintextModulus(
        kPlaintextModulus
    );

    parameters.SetMultiplicativeDepth(
        static_cast<std::uint32_t>(
            options.tower_count - 1
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

    if (options.technique == Technique::Hybrid) {
        parameters.SetKeySwitchTechnique(
            lbcrypto::HYBRID
        );

        parameters.SetNumLargeDigits(
            options.num_large_digits
        );
    }
    else {
        parameters.SetKeySwitchTechnique(
            lbcrypto::BV
        );

        parameters.SetDigitSize(
            options.digit_size
        );
    }

    auto context =
        lbcrypto::GenCryptoContext(parameters);

    context->Enable(lbcrypto::PKE);
    context->Enable(lbcrypto::KEYSWITCH);
    context->Enable(lbcrypto::LEVELEDSHE);

    if (context->GetRingDimension() != kN) {
        Fail(
            "OpenFHE generated the wrong ring dimension"
        );
    }

    const std::size_t actual_towers =
        context->GetElementParams()
            ->GetParams()
            .size();

    if (actual_towers != options.tower_count) {
        Fail(
            "OpenFHE generated "
            + std::to_string(actual_towers)
            + " Q towers; requested "
            + std::to_string(
                options.tower_count
            )
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

const std::vector<DCRTPoly>& RequireElements(
    const Ciphertext<DCRTPoly>& ciphertext,
    std::size_t expected_count,
    std::string_view label
) {
    if (!ciphertext) {
        Fail(
            std::string(label)
            + " is null"
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

    for (const auto& element : elements) {
        if (element.GetFormat() != Format::EVALUATION) {
            Fail(
                std::string(label)
                + " contains a non-evaluation component"
            );
        }
    }

    return elements;
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

void RequirePairEqual(
    const std::shared_ptr<std::vector<DCRTPoly>>& actual,
    const std::shared_ptr<std::vector<DCRTPoly>>& expected,
    std::string_view label
) {
    if (!actual || !expected) {
        Fail(
            std::string(label)
            + " is null"
        );
    }

    if (
        actual->size() != 2
        || expected->size() != 2
    ) {
        Fail(
            std::string(label)
            + " does not contain two components"
        );
    }

    RequirePolyEqual(
        (*actual)[0],
        (*expected)[0],
        std::string(label) + " component 0"
    );

    RequirePolyEqual(
        (*actual)[1],
        (*expected)[1],
        std::string(label) + " component 1"
    );
}

void WriteU64LE(
    std::ostream& output,
    std::uint64_t value
) {
    std::array<unsigned char, 8> bytes{};

    for (
        std::size_t index = 0;
        index < bytes.size();
        ++index
    ) {
        bytes[index] =
            static_cast<unsigned char>(
                value >> (8U * index)
            );
    }

    output.write(
        reinterpret_cast<const char*>(
            bytes.data()
        ),
        static_cast<std::streamsize>(
            bytes.size()
        )
    );
}

std::string TowerName(std::size_t index) {
    std::ostringstream output;

    output
        << "tower"
        << std::setw(3)
        << std::setfill('0')
        << index;

    return output.str();
}

std::string DigitName(std::size_t index) {
    std::ostringstream output;

    output
        << "digit"
        << std::setw(3)
        << std::setfill('0')
        << index;

    return output.str();
}

void WritePoly(
    const fs::path& directory,
    const DCRTPoly& poly
) {
    fs::create_directories(directory);

    if (poly.GetFormat() != Format::EVALUATION) {
        Fail(
            "Attempted to export a non-evaluation DCRTPoly"
        );
    }

    const std::size_t tower_count =
        poly.GetNumOfElements();

    for (
        std::size_t tower_index = 0;
        tower_index < tower_count;
        ++tower_index
    ) {
        const auto& tower =
            poly.GetElementAtIndex(
                static_cast<usint>(
                    tower_index
                )
            );

        std::ofstream output(
            directory
                / (
                    TowerName(tower_index)
                    + ".u64le.bin"
                ),
            std::ios::binary
            | std::ios::trunc
        );

        if (!output) {
            Fail(
                "Could not write polynomial tower"
            );
        }

        for (
            std::size_t coefficient = 0;
            coefficient < kN;
            ++coefficient
        ) {
            WriteU64LE(
                output,
                tower[
                    static_cast<usint>(
                        coefficient
                    )
                ].ConvertToInt<std::uint64_t>()
            );
        }
    }

    std::ofstream metadata(
        directory / "poly.json",
        std::ios::trunc
    );

    if (!metadata) {
        Fail(
            "Could not write poly.json"
        );
    }

    metadata
        << "{\n"
        << "  \"format\": \"EVALUATION\",\n"
        << "  \"ring_dimension\": "
        << kN << ",\n"
        << "  \"tower_count\": "
        << tower_count << ",\n"
        << "  \"word_format\": "
        << "\"unsigned-64-little-endian\"\n"
        << "}\n";
}

void WriteParams(
    const fs::path& directory,
    const std::shared_ptr<
        ILDCRTParams<BigInteger>
    >& params
) {
    fs::create_directories(directory);

    if (!params) {
        Fail(
            "Attempted to export null CRT parameters"
        );
    }

    const auto& towers =
        params->GetParams();

    for (
        std::size_t index = 0;
        index < towers.size();
        ++index
    ) {
        const auto modulus =
            towers[index]
                ->GetModulus()
                .ConvertToInt<std::uint64_t>();

        const auto root =
            towers[index]
                ->GetRootOfUnity()
                .ConvertToInt<std::uint64_t>();

        std::ofstream output(
            directory
                / (
                    TowerName(index)
                    + ".json"
                ),
            std::ios::trunc
        );

        if (!output) {
            Fail(
                "Could not write CRT profile"
            );
        }

        output
            << "{\n"
            << "  \"index\": "
            << index << ",\n"
            << "  \"modulus\": "
            << modulus << ",\n"
            << "  \"modulus_bits\": "
            << towers[index]
                ->GetModulus()
                .GetMSB()
            << ",\n"
            << "  \"root_of_unity\": "
            << root << "\n"
            << "}\n";
    }
}

std::uint32_t MaxModulusBits(
    const std::shared_ptr<
        ILDCRTParams<BigInteger>
    >& params
) {
    if (!params) {
        return 0;
    }

    std::uint32_t result = 0;

    for (const auto& tower : params->GetParams()) {
        result =
            std::max(
                result,
                static_cast<std::uint32_t>(
                    tower->GetModulus().GetMSB()
                )
            );
    }

    return result;
}

std::uint64_t PolyBytes(
    const DCRTPoly& poly
) {
    return
        static_cast<std::uint64_t>(
            poly.GetNumOfElements()
        )
        * kN
        * sizeof(std::uint64_t);
}

std::uint64_t PolyVectorBytes(
    const std::vector<DCRTPoly>& polys
) {
    std::uint64_t result = 0;

    for (const auto& poly : polys) {
        result +=
            PolyBytes(poly);
    }

    return result;
}

template <typename Function>
double TimeMicroseconds(Function&& function) {
    const auto start =
        std::chrono::steady_clock::now();

    function();

    const auto stop =
        std::chrono::steady_clock::now();

    return std::chrono::duration<
        double,
        std::micro
    >(stop - start).count();
}

int Run(const Options& options) {
    fs::remove_all(
        options.output_directory
    );

    fs::create_directories(
        options.output_directory
    );

    const auto context =
        MakeContext(options);

    const auto crypto_parameters =
        std::dynamic_pointer_cast<
            CryptoParametersBGVRNS
        >(
            context->GetCryptoParameters()
        );

    if (!crypto_parameters) {
        Fail(
            "Could not cast BGVRNS crypto parameters"
        );
    }

    const auto key_pair =
        context->KeyGen();

    if (!key_pair.good()) {
        Fail(
            "OpenFHE key generation failed"
        );
    }

    const double eval_keygen_us =
        TimeMicroseconds(
            [&]() {
                context->EvalMultKeyGen(
                    key_pair.secretKey
                );
            }
        );

    std::mt19937_64 generator(
        options.seed
    );

    const Plaintext plaintext_a =
        context->MakeCoefPackedPlaintext(
            GenerateValues(generator)
        );

    const Plaintext plaintext_b =
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

    const auto& ciphertext_a_elements =
        RequireElements(
            ciphertext_a,
            2,
            "ciphertext A"
        );

    const auto& ciphertext_b_elements =
        RequireElements(
            ciphertext_b,
            2,
            "ciphertext B"
        );

    Ciphertext<DCRTPoly> no_relin;
    const double evalmult_no_relin_us =
        TimeMicroseconds(
            [&]() {
                no_relin =
                    context->EvalMultNoRelin(
                        ciphertext_a,
                        ciphertext_b
                    );
            }
        );

    const auto& no_relin_elements =
        RequireElements(
            no_relin,
            3,
            "EvalMultNoRelin"
        );

    const auto& eval_keys =
        CryptoContextImpl<DCRTPoly>::
            GetEvalMultKeyVector(
                ciphertext_a->GetKeyTag()
            );

    if (eval_keys.empty()) {
        Fail(
            "EvalMultKeyGen did not store a relinearization key"
        );
    }

    const EvalKey<DCRTPoly> eval_key =
        eval_keys.front();

    const auto& key_a =
        eval_key->GetAVector();

    const auto& key_b =
        eval_key->GetBVector();

    if (
        key_a.empty()
        || key_a.size() != key_b.size()
    ) {
        Fail(
            "Relinearization key A/B vectors are inconsistent"
        );
    }

    const auto scheme =
        context->GetScheme();

    std::shared_ptr<std::vector<DCRTPoly>>
        digits;

    const double precompute_us =
        TimeMicroseconds(
            [&]() {
                digits =
                    scheme
                        ->EvalKeySwitchPrecomputeCore(
                            no_relin_elements[2],
                            eval_key
                                ->GetCryptoParameters()
                        );
            }
        );

    if (!digits || digits->empty()) {
        Fail(
            "Key-switch digit decomposition is empty"
        );
    }

    if (digits->size() != key_a.size()) {
        Fail(
            "Digit count does not match evaluation-key part count"
        );
    }

    std::shared_ptr<std::vector<DCRTPoly>>
        fast_contribution;

    const double fast_keyswitch_us =
        TimeMicroseconds(
            [&]() {
                fast_contribution =
                    scheme
                        ->EvalFastKeySwitchCore(
                            digits,
                            eval_key,
                            no_relin_elements[2]
                                .GetParams()
                        );
            }
        );

    std::shared_ptr<std::vector<DCRTPoly>>
        direct_contribution;

    const double direct_keyswitch_us =
        TimeMicroseconds(
            [&]() {
                direct_contribution =
                    scheme->KeySwitchCore(
                        no_relin_elements[2],
                        eval_key
                    );
            }
        );

    RequirePairEqual(
        direct_contribution,
        fast_contribution,
        "KeySwitchCore versus precompute+fast"
    );

    std::shared_ptr<std::vector<DCRTPoly>>
        extended_contribution;

    double extended_mac_us = 0.0;

    if (options.technique == Technique::Hybrid) {
        extended_mac_us =
            TimeMicroseconds(
                [&]() {
                    extended_contribution =
                        scheme
                            ->EvalFastKeySwitchCoreExt(
                                digits,
                                eval_key,
                                no_relin_elements[2]
                                    .GetParams()
                            );
                }
            );

        if (
            !extended_contribution
            || extended_contribution->size() != 2
        ) {
            Fail(
                "HYBRID extended key-switch contribution is invalid"
            );
        }
    }

    DCRTPoly manual_c0 =
        no_relin_elements[0];

    manual_c0 +=
        (*direct_contribution)[0];

    DCRTPoly manual_c1 =
        no_relin_elements[1];

    manual_c1 +=
        (*direct_contribution)[1];

    Ciphertext<DCRTPoly> openfhe_relinearized;

    const double openfhe_evalmult_us =
        TimeMicroseconds(
            [&]() {
                openfhe_relinearized =
                    context->EvalMult(
                        ciphertext_a,
                        ciphertext_b
                    );
            }
        );

    const auto& expected_elements =
        RequireElements(
            openfhe_relinearized,
            2,
            "OpenFHE EvalMult"
        );

    RequirePolyEqual(
        manual_c0,
        expected_elements[0],
        "manual relinearized c0"
    );

    RequirePolyEqual(
        manual_c1,
        expected_elements[1],
        "manual relinearized c1"
    );

    const auto params_q =
        context->GetElementParams();

    std::shared_ptr<
        ILDCRTParams<BigInteger>
    > params_p;

    if (options.technique == Technique::Hybrid) {
        params_p =
            crypto_parameters
                ->GetParamsP();
    }

    WriteParams(
        options.output_directory
            / "profiles_q",
        params_q
    );

    if (params_p) {
        WriteParams(
            options.output_directory
                / "profiles_p",
            params_p
        );
    }

    WritePoly(
        options.output_directory
            / "input_a0_q_eval",
        ciphertext_a_elements[0]
    );

    WritePoly(
        options.output_directory
            / "input_a1_q_eval",
        ciphertext_a_elements[1]
    );

    WritePoly(
        options.output_directory
            / "input_b0_q_eval",
        ciphertext_b_elements[0]
    );

    WritePoly(
        options.output_directory
            / "input_b1_q_eval",
        ciphertext_b_elements[1]
    );

    WritePoly(
        options.output_directory
            / "no_relin_c0_q_eval",
        no_relin_elements[0]
    );

    WritePoly(
        options.output_directory
            / "no_relin_c1_q_eval",
        no_relin_elements[1]
    );

    WritePoly(
        options.output_directory
            / "c2_q_eval",
        no_relin_elements[2]
    );

    for (
        std::size_t index = 0;
        index < digits->size();
        ++index
    ) {
        WritePoly(
            options.output_directory
                / "digits"
                / DigitName(index),
            (*digits)[index]
        );

        WritePoly(
            options.output_directory
                / "eval_key_a"
                / DigitName(index),
            key_a[index]
        );

        WritePoly(
            options.output_directory
                / "eval_key_b"
                / DigitName(index),
            key_b[index]
        );
    }

    WritePoly(
        options.output_directory
            / "keyswitch_q_b",
        (*direct_contribution)[0]
    );

    WritePoly(
        options.output_directory
            / "keyswitch_q_a",
        (*direct_contribution)[1]
    );

    if (extended_contribution) {
        WritePoly(
            options.output_directory
                / "keyswitch_ext_b",
            (*extended_contribution)[0]
        );

        WritePoly(
            options.output_directory
                / "keyswitch_ext_a",
            (*extended_contribution)[1]
        );
    }

    WritePoly(
        options.output_directory
            / "relinearized_c0_q",
        expected_elements[0]
    );

    WritePoly(
        options.output_directory
            / "relinearized_c1_q",
        expected_elements[1]
    );

    const std::size_t q_towers =
        params_q
            ->GetParams()
            .size();

    const std::size_t p_towers =
        params_p
            ? params_p
                ->GetParams()
                .size()
            : 0;

    const std::size_t digit_towers =
        digits->front()
            .GetNumOfElements();

    const std::size_t key_towers =
        key_a.front()
            .GetNumOfElements();

    const std::uint64_t digit_bytes =
        PolyVectorBytes(*digits);

    const std::uint64_t eval_key_bytes =
        PolyVectorBytes(key_a)
        + PolyVectorBytes(key_b);

    std::ofstream metadata(
        options.output_directory
            / "metadata.json",
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
        << "\"openfhe-bgvrns-relinearization-probe-v1\",\n"
        << "  \"openfhe_version_target\": "
        << "\"1.5.1\",\n"
        << "  \"technique\": \""
        << TechniqueName(
            options.technique
        )
        << "\",\n"
        << "  \"ring_dimension\": "
        << kN << ",\n"
        << "  \"q_towers\": "
        << q_towers << ",\n"
        << "  \"p_towers\": "
        << p_towers << ",\n"
        << "  \"digits\": "
        << digits->size() << ",\n"
        << "  \"digit_towers\": "
        << digit_towers << ",\n"
        << "  \"eval_key_parts\": "
        << key_a.size() << ",\n"
        << "  \"eval_key_towers\": "
        << key_towers << ",\n"
        << "  \"digit_size\": "
        << options.digit_size << ",\n"
        << "  \"num_large_digits\": "
        << options.num_large_digits << ",\n"
        << "  \"max_q_modulus_bits\": "
        << MaxModulusBits(params_q)
        << ",\n"
        << "  \"max_p_modulus_bits\": "
        << MaxModulusBits(params_p)
        << ",\n"
        << "  \"digit_bytes\": "
        << digit_bytes << ",\n"
        << "  \"eval_key_bytes\": "
        << eval_key_bytes << ",\n"
        << "  \"seed\": "
        << options.seed << "\n"
        << "}\n";

    std::cout
        << "PASS: EvalMultNoRelin produced three evaluation-domain components\n"
        << "PASS: KeySwitchCore equals precompute plus EvalFastKeySwitchCore\n"
        << "PASS: manual c0/c1 relinearization exactly equals OpenFHE EvalMult\n"
        << "technique="
        << TechniqueName(options.technique)
        << '\n'
        << "q_towers="
        << q_towers << '\n'
        << "p_towers="
        << p_towers << '\n'
        << "digits="
        << digits->size() << '\n'
        << "digit_towers="
        << digit_towers << '\n'
        << "eval_key_parts="
        << key_a.size() << '\n'
        << "eval_key_towers="
        << key_towers << '\n'
        << "max_q_modulus_bits="
        << MaxModulusBits(params_q)
        << '\n'
        << "max_p_modulus_bits="
        << MaxModulusBits(params_p)
        << '\n'
        << "digit_bytes="
        << digit_bytes << '\n'
        << "eval_key_bytes="
        << eval_key_bytes << '\n'
        << std::fixed
        << std::setprecision(2)
        << "eval_keygen_us="
        << eval_keygen_us << '\n'
        << "evalmult_no_relin_us="
        << evalmult_no_relin_us << '\n'
        << "precompute_us="
        << precompute_us << '\n'
        << "fast_keyswitch_us="
        << fast_keyswitch_us << '\n'
        << "direct_keyswitch_us="
        << direct_keyswitch_us << '\n'
        << "extended_mac_us="
        << extended_mac_us << '\n'
        << "openfhe_evalmult_relinearized_us="
        << openfhe_evalmult_us << '\n'
        << "output_directory="
        << fs::absolute(
            options.output_directory
        ).string()
        << '\n';

    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        return Run(
            ParseOptions(argc, argv)
        );
    }
    catch (const std::exception& exception) {
        std::cerr
            << "ERROR: "
            << exception.what()
            << '\n';

        return 1;
    }
}
