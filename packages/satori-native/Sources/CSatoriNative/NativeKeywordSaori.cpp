#include "NativeKeywordSaori.h"

#include <algorithm>
#include <fstream>

namespace {
string trim(const string& value) {
    const string whitespace = " \t\r\n";
    const string::size_type first = value.find_first_not_of(whitespace);
    if (first == string::npos) return "";
    const string::size_type last = value.find_last_not_of(whitespace);
    return value.substr(first, last - first + 1);
}

std::vector<string> split(const string& value, const string& separator) {
    std::vector<string> parts;
    string::size_type start = 0;
    while (start <= value.size()) {
        const string::size_type end = value.find(separator, start);
        parts.push_back(trim(value.substr(start, end == string::npos ? string::npos : end - start)));
        if (end == string::npos) break;
        start = end + separator.size();
    }
    return parts;
}

string parentDirectory(const string& path) {
    const string::size_type separator = path.find_last_of("/\\");
    return separator == string::npos ? "" : path.substr(0, separator + 1);
}
}

bool NativeKeywordSaori::load(
    const string&,
    const string&,
    const string&,
    const string& dllFullPath)
{
    entries.clear();
    std::ifstream input((parentDirectory(dllFullPath) + "keyword.txt").c_str(), std::ios::binary);
    if (!input) return false;

    string line;
    const string comma = "\x81\x41";
    const string equals = "\x81\x81";
    while (std::getline(input, line)) {
        line = trim(line);
        if (line.empty() || line.compare(0, 2, "//") == 0) continue;
        const string::size_type equalsPosition = line.find(equals);
        if (equalsPosition == string::npos) continue;

        Entry entry;
        entry.keyword = trim(line.substr(0, equalsPosition));
        entry.expressions = split(line.substr(equalsPosition + equals.size()), comma);
        entry.expressions.erase(
            std::remove(entry.expressions.begin(), entry.expressions.end(), ""),
            entry.expressions.end());
        if (!entry.keyword.empty() && !entry.expressions.empty()) entries.push_back(entry);
    }
    return true;
}

void NativeKeywordSaori::unload() { entries.clear(); }
string NativeKeywordSaori::request(const string&) { return ""; }
string NativeKeywordSaori::get_version(const string&) { return "SAORI/1.0"; }

int NativeKeywordSaori::request(
    const std::vector<string>& arguments,
    bool,
    string& result,
    std::vector<string>& values)
{
    if (arguments.size() < 2 || arguments[0] != "GETKEYWORD") return 400;

    struct Match {
        string keyword;
        string::size_type position;
        string::size_type length;
    };
    std::vector<Match> matches;
    const string& source = arguments[1];
    for (std::vector<Entry>::const_iterator entry = entries.begin(); entry != entries.end(); ++entry) {
        Match best = { entry->keyword, string::npos, 0 };
        for (std::vector<string>::const_iterator expression = entry->expressions.begin();
             expression != entry->expressions.end(); ++expression) {
            const string::size_type position = source.find(*expression);
            if (position != string::npos && (best.position == string::npos || position < best.position
                || (position == best.position && expression->size() > best.length))) {
                best.position = position;
                best.length = expression->size();
            }
        }
        if (best.position != string::npos) matches.push_back(best);
    }

    std::sort(matches.begin(), matches.end(), [](const Match& lhs, const Match& rhs) {
        if (lhs.position != rhs.position) return lhs.position < rhs.position;
        return lhs.length > rhs.length;
    });
    for (std::vector<Match>::const_iterator match = matches.begin(); match != matches.end(); ++match) {
        if (std::find(values.begin(), values.end(), match->keyword) == values.end()) {
            values.push_back(match->keyword);
        }
    }
    if (!values.empty()) result = values[0];
    return 200;
}
