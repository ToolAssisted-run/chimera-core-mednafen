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
// A memory of the machine kept as bytes, at the address its processor finds
// it (what a system tells through Mednafen's MDFNMP_AddRAM).
void frontend_add_memory(uint32_t address, uint8_t *bytes, uint32_t size);
// The file a save memory starts from, by the extension Mednafen names it
// with ("bkr"): the project's save data file of that extension, or a name
// that is nowhere when the project has none.
std::string frontend_save_path(const char *ext);
