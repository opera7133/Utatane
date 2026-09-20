#pragma once
#include "Vendor/satori/SaoriClient.h"

class NativeSwiftSaori : public SaoriClient {
public:
    explicit NativeSwiftSaori(const string& path) : path(path) {}
    virtual bool load(const string&, const string&, const string&, const string&);
    virtual void unload();
    virtual string request(const string&);
    virtual string get_version(const string&);
    virtual int request(const std::vector<string>&, bool, string&, std::vector<string>&);
protected:
    string path;
};
