#include "NativeSwiftSaori.h"
#include "CSatoriNative.h"
#include <cstdlib>
#include <sstream>

bool NativeSwiftSaori::load(const string&, const string&, const string&, const string&) { return true; }
void NativeSwiftSaori::unload() {}
string NativeSwiftSaori::request(const string&) { return ""; }
string NativeSwiftSaori::get_version(const string&) { return "SAORI/1.0"; }

int NativeSwiftSaori::request(const std::vector<string>& arguments, bool, string& result, std::vector<string>& values) {
    std::ostringstream request;
    request << "EXECUTE SAORI/1.0\r\nCharset: Shift_JIS\r\n";
    for (std::size_t index = 0; index < arguments.size(); ++index)
        request << "Argument" << index << ": " << arguments[index] << "\r\n";
    request << "\r\n";
    const string input = request.str();
    long length = static_cast<long>(input.size());
    char *response = utatane_satori_native_saori_request(path.c_str(), input.data(), &length);
    if (response == NULL) return 500;
    const string message(response, static_cast<std::size_t>(length));
    std::free(response);
    std::istringstream lines(message);
    string line;
    while (std::getline(lines, line)) {
        if (!line.empty() && line[line.size() - 1] == '\r') line.erase(line.size() - 1);
        if (line.compare(0, 8, "Result: ") == 0) result = line.substr(8);
        else if (line.compare(0, 5, "Value") == 0) {
            const string::size_type colon = line.find(": ");
            if (colon != string::npos) values.push_back(line.substr(colon + 2));
        }
    }
    return 200;
}
