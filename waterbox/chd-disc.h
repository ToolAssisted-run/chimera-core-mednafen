// chimera-core-mednafen: a CHD disc image as a disc Mednafen can read.
#pragma once

#include <string>

namespace Mednafen
{
class CDAccess;
}

// Opens a .chd file of a CD. Throws (MDFN_Error) when the file is not a CHD
// of a CD or cannot be read.
Mednafen::CDAccess *open_chd_disc(const std::string &path);
