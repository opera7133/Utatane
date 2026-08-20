#pragma once

#include "Vendor/satori/SaoriClient.h"

class NativeKeywordSaori : public SaoriClient {
public:
    virtual bool load(const string&, const string&, const string&, const string&);
    virtual void unload();
    virtual string request(const string&);
    virtual string get_version(const string&);
    virtual int request(
        const std::vector<string>& arguments,
        bool isSecure,
        string& result,
        std::vector<string>& values);

private:
    struct Entry {
        string keyword;
        std::vector<string> expressions;
    };
    std::vector<Entry> entries;
};
