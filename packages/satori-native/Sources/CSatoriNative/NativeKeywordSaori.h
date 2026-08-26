#pragma once

#include "NativeSwiftSaori.h"

class NativeKeywordSaori : public NativeSwiftSaori {
public:
    NativeKeywordSaori() : NativeSwiftSaori("kenonoke.dll") {}
    virtual bool load(const string&, const string&, const string&, const string& dllFullPath) {
        path = dllFullPath;
        return true;
    }
};
