// chimera-core-mednafen: what Mednafen's systems ask of the program around
// them. Mednafen's own program (mednafen.cpp, its settings store, its window,
// its sound and input back ends, movies, cheats, netplay) is not compiled;
// this file answers the calls the systems make into it:
//
//  * settings come from the project (frontend_setting, cinterface.cpp), or
//    are the system's own default;
//  * a firmware or save file is named by Mednafen and opened in the current
//    directory, where Chimera mounts a project's files by name;
//  * the time is the project's, never the host's;
//  * a savestate is the sandbox's memory, so Mednafen's own state functions
//    are never called;
//  * cheats and the music player do nothing.
#include <mednafen/mednafen.h>
#include <mednafen/general.h>
#include <mednafen/state.h>
#include <mednafen/settings.h>
#include <mednafen/mempatcher.h>
#include <mednafen/mednafen-driver.h>
#include <mednafen/player.h>
#include <mednafen/Time.h>
#include <mednafen/NativeVFS.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

#include "frontend.h"

namespace Mednafen
{

MDFNGI *MDFNGameInfo = nullptr;
NativeVFS NVFS;

// A file Mednafen names for itself: the firmware by its file name, which is
// the id the package declares it under.
std::string MDFN_MakeFName(MakeFName_Type type, int id1, const char *cd1)
{
	if (type == MDFNMKF_FIRMWARE)
		return frontend_firmware_path(cd1 ? cd1 : "");
	// a save memory starts from the project's save data, when it has some
	if (type == MDFNMKF_SAV)
		return frontend_save_path(cd1 ? cd1 : "");
	// snapshots, palettes: nothing of these is read from or written to files
	// by this core. A name that exists nowhere is "not there".
	return std::string("chimera-no-such-file/") + (cd1 ? cd1 : "");
}

static int s_indent;
void MDFN_indent(int indent)
{
	s_indent += indent;
	if (s_indent < 0) s_indent = 0;
}

void MDFN_printf(const char *format, ...) noexcept
{
	for (int i = 0; i < s_indent; i++) fputc(' ', stderr);
	va_list ap;
	va_start(ap, format);
	vfprintf(stderr, format, ap);
	va_end(ap);
}

void MDFND_OutputNotice(MDFN_NoticeType t, const char *s) noexcept
{
	fputs(s, stderr);
	fputc('\n', stderr);
}

void MDFND_OutputInfo(const char *s) noexcept
{
	fputs(s, stderr);
	fputc('\n', stderr);
}

void MDFN_Notify(MDFN_NoticeType t, const char *format, ...) noexcept
{
	va_list ap;
	va_start(ap, format);
	vfprintf(stderr, format, ap);
	va_end(ap);
	fputc('\n', stderr);
}

void MDFN_MidSync(EmulateSpecStruct *espec, const unsigned flags) { }
void MDFN_MidLineUpdate(EmulateSpecStruct *espec, int y) { }

// never called: a savestate is the sandbox's memory
bool MDFNSS_StateAction(StateMem *sm, const unsigned load, const bool data_only, const SFORMAT *sf, const char *sname, const bool optional) noexcept
{
	abort();
}
void MDFNSS_SaveSM(Stream *st, bool data_only, const MDFN_Surface *surface, const MDFN_Rect *DisplayRect, const int32 *LineWidths) { abort(); }
void MDFNSS_LoadSM(Stream *st, bool data_only, const bool fuzz) { abort(); }

// ---- settings --------------------------------------------------------------
static const MDFNSetting *find_setting(const char *name)
{
	if (!MDFNGameInfo || !MDFNGameInfo->Settings) return nullptr;
	for (const MDFNSetting *s = MDFNGameInfo->Settings; s->name; s++)
		if (!strcmp(s->name, name)) return s;
	return nullptr;
}

// the value as text: the project's, or the system's default
static std::string setting_text(const char *name)
{
	std::string value;
	if (frontend_setting(name, value)) return value;
	const MDFNSetting *s = find_setting(name);
	return s && s->default_value ? s->default_value : "";
}

static bool enum_number(const MDFNSetting *s, std::string const &text, int64 &out)
{
	if (!s || s->type != MDFNST_ENUM || !s->enum_list) return false;
	for (int pass = 0; pass < 2; pass++)
	{
		std::string const &want = pass == 0 ? text : std::string(s->default_value ? s->default_value : "");
		for (const MDFNSetting_EnumList *e = s->enum_list; e->string; e++)
			if (want == e->string) { out = e->number; return true; }
	}
	out = 0;
	return true;
}

uint64 MDFN_GetSettingUI(const char *name)
{
	std::string const text = setting_text(name);
	int64 n;
	if (enum_number(find_setting(name), text, n)) return uint64(n);
	return strtoull(text.c_str(), nullptr, 0);
}

int64 MDFN_GetSettingI(const char *name)
{
	std::string const text = setting_text(name);
	int64 n;
	if (enum_number(find_setting(name), text, n)) return n;
	return strtoll(text.c_str(), nullptr, 0);
}

double MDFN_GetSettingF(const char *name) { return strtod(setting_text(name).c_str(), nullptr); }
bool MDFN_GetSettingB(const char *name) { return MDFN_GetSettingUI(name) != 0; }
std::string MDFN_GetSettingS(const char *name) { return setting_text(name); }
std::vector<uint64> MDFN_GetSettingMultiUI(const char *name) { return std::vector<uint64>(); }
std::vector<int64> MDFN_GetSettingMultiI(const char *name) { return std::vector<int64>(); }
uint64 MDFN_GetSettingMultiM(const char *name) { return MDFN_GetSettingUI(name); }

// ---- cheats, the music player: nothing ---------------------------------------
void MDFNMP_Init(uint32 ps, uint32 numpages) { }
// a system's RAM, told for cheat searches: it is what RAM Watch and RAM Search read
void MDFNMP_AddRAM(uint32 size, uint32 address, uint8 *RAM, bool use_in_search) { frontend_add_memory(address, RAM, size); }
void MDFNMP_RegSearchable(uint32 addr, uint32 size) { }
void MDFNMP_Kill(void) { }
void MDFN_LoadGameCheats(Stream *override) { }
void MDFNMP_InstallReadPatches(void) { }
void MDFNMP_RemoveReadPatches(void) { }
void MDFNMP_ApplyPeriodicCheats(void) { }
std::vector<SUBCHEAT> SubCheats[8];
bool SubCheatsOn;

void Player_Init(int tsongs, const std::string &album, const std::string &artist, const std::string &copyright, const std::vector<std::string> &snames, bool override_gi) { }
void Player_Draw(MDFN_Surface *surface, MDFN_Rect *dr, int CurrentSong, int16 *samples, int32 sampcount) { }

// ---- the time: the project's -------------------------------------------------
namespace Time
{
void Time_Init() { }
int64 EpochTime() { return frontend_time(); }
int64 MonoUS() { return frontend_time() * 1000000; }
struct tm UTCTime(const int64 ept)
{
	struct tm out;
	time_t t = time_t(ept);
	memset(&out, 0, sizeof out);
	gmtime_r(&t, &out);
	return out;
}
// no time zone: the machine's clock is the project's time as it is written
struct tm LocalTime(const int64 ept) { return UTCTime(ept); }
// nothing waits on the host: the one place left that would (the Saturn's
// state code, waiting for a queue this core keeps empty) never gets here
void SleepMS(uint32 amount) noexcept { }
}

}
