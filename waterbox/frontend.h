// chimera-core-mednafen: what the stand-ins for Mednafen's program
// (mdfn-interfaces.cpp) ask of the frontend (cinterface.cpp).
#pragma once

#include <cstdint>
#include <string>

// A Mednafen setting by its own name ("ss.cart"): true, with the value, when
// the project sets it. False leaves the system's default.
bool frontend_setting(const char *name, std::string &value);
// Where a firmware file Mednafen names ("sega_101.bin") is.
std::string frontend_firmware_path(const char *name);
// The time the machine's clock starts from, in seconds since 1970.
int64_t frontend_time();
