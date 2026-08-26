#pragma once

#include "NativeSwiftSaori.h"

class NativeSystemInfoSaori : public NativeSwiftSaori {
public:
    NativeSystemInfoSaori() : NativeSwiftSaori("saori_cpuid.dll") {}
};
