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
    return convert(value, "CP932", "UTF-8");
}
