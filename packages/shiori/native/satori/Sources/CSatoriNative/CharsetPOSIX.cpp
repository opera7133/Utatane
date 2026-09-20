#include <cerrno>
#include <iconv.h>
#include <string>
#include <vector>

namespace {
std::string convert(const std::string &input, const char *to, const char *from) {
    iconv_t converter = iconv_open(to, from);
    if (converter == reinterpret_cast<iconv_t>(-1)) return input;
    std::vector<char> output(input.size() * 4 + 16);
    char *source = const_cast<char *>(input.data());
    size_t sourceLength = input.size();
    char *destination = output.data();
    size_t destinationLength = output.size();
    while (sourceLength > 0) {
        if (iconv(converter, &source, &sourceLength, &destination, &destinationLength) != static_cast<size_t>(-1)) {
            break;
        }
        if (errno != E2BIG) {
            iconv_close(converter);
            return input;
        }
        const auto used = static_cast<size_t>(destination - output.data());
        output.resize(output.size() * 2);
        destination = output.data() + used;
        destinationLength = output.size() - used;
    }
    iconv_close(converter);
    return std::string(output.data(), static_cast<size_t>(destination - output.data()));
}
}

std::string SJIStoUTF8(const std::string &value) {
    return convert(value, "UTF-8", "CP932");
}

std::string UTF8toSJIS(const std::string &value) {
    std::string normalized = value;
    const std::string unicodeMinus = "\xE2\x88\x92";
    size_t position = 0;
    while ((position = normalized.find(unicodeMinus, position)) != std::string::npos) {
        normalized.replace(position, unicodeMinus.size(), "-");
        ++position;
    }
    const std::string waveDash = "\xE3\x80\x9C";
    const std::string fullwidthTilde = "\xEF\xBD\x9E";
    position = 0;
    while ((position = normalized.find(waveDash, position)) != std::string::npos) {
        normalized.replace(position, waveDash.size(), fullwidthTilde);
        position += fullwidthTilde.size();
    }
    return convert(normalized, "CP932", "UTF-8");
}
