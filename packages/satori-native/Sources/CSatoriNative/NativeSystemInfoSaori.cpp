#include "NativeSystemInfoSaori.h"

#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>

#include <algorithm>
#include <sstream>

namespace {
string sysctlString(const char* name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) return "";
    std::vector<char> buffer(size);
    if (sysctlbyname(name, buffer.data(), &size, NULL, 0) != 0) return "";
    return string(buffer.data());
}

template <typename T>
T sysctlNumber(const char* name, T fallback = 0) {
    T value = fallback;
    size_t size = sizeof(value);
    return sysctlbyname(name, &value, &size, NULL, 0) == 0 ? value : fallback;
}

string number(uint64_t value) {
    std::ostringstream stream;
    stream << value;
    return stream.str();
}

uint64_t physicalMemoryMB() {
    return sysctlNumber<uint64_t>("hw.memsize") / (1024 * 1024);
}

uint64_t availableMemoryMB() {
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t statistics = {};
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
        reinterpret_cast<host_info64_t>(&statistics), &count) != KERN_SUCCESS) return 0;
    const uint64_t pages = statistics.free_count + statistics.inactive_count;
    return pages * static_cast<uint64_t>(vm_kernel_page_size) / (1024 * 1024);
}

string feature(const char* name) {
    return sysctlNumber<int>(name) != 0 ? "1" : "0";
}
}

bool NativeSystemInfoSaori::load(const string&, const string&, const string&, const string&) { return true; }
void NativeSystemInfoSaori::unload() {}
string NativeSystemInfoSaori::request(const string&) { return ""; }
string NativeSystemInfoSaori::get_version(const string&) { return "SAORI/1.0"; }

int NativeSystemInfoSaori::request(
    const std::vector<string>& arguments,
    bool,
    string& result,
    std::vector<string>&)
{
    if (arguments.empty()) return 400;
    const string& command = arguments[0];
    struct utsname systemInfo = {};
    uname(&systemInfo);

    if (command == "os.name") result = "macOS";
    else if (command == "os.version") result = systemInfo.release;
    else if (command == "os.build") result = sysctlString("kern.osversion");
    else if (command == "platform") result = "macOS";
    else if (command == "cpu.vender") result = sysctlString("machdep.cpu.vendor");
    else if (command == "cpu.name") result = sysctlString("machdep.cpu.brand_string");
    else if (command == "cpu.clock" || command == "cpu.clockex")
        result = number(sysctlNumber<uint64_t>("hw.cpufrequency") / 1000000);
    else if (command == "cpu.num") result = number(sysctlNumber<uint32_t>("hw.logicalcpu"));
    else if (command == "cpu.ptype") result = systemInfo.machine;
    else if (command == "cpu.family") result = number(sysctlNumber<uint32_t>("hw.cpufamily"));
    else if (command == "cpu.model") result = number(sysctlNumber<uint32_t>("machdep.cpu.model"));
    else if (command == "cpu.stepping") result = number(sysctlNumber<uint32_t>("machdep.cpu.stepping"));
    else if (command == "cpu.mmx") result = feature("hw.optional.mmx");
    else if (command == "cpu.mmx+") result = feature("hw.optional.mmx");
    else if (command == "cpu.sse") result = feature("hw.optional.sse");
    else if (command == "cpu.sse2") result = feature("hw.optional.sse2");
    else if (command == "cpu.tdn") result = "0";
    else if (command == "cpu.htt")
        result = sysctlNumber<uint32_t>("hw.logicalcpu") > sysctlNumber<uint32_t>("hw.physicalcpu") ? "1" : "0";
    else if (command == "mem.os") {
        const uint64_t total = physicalMemoryMB();
        const uint64_t available = availableMemoryMB();
        result = total == 0 ? "0" : number((total - std::min(total, available)) * 100 / total);
    }
    else if (command == "mem.phyt" || command == "mem.pagt" || command == "mem.virt") result = number(physicalMemoryMB());
    else if (command == "mem.phya" || command == "mem.paga" || command == "mem.vira") result = number(availableMemoryMB());
    else return 204;
    return 200;
}
