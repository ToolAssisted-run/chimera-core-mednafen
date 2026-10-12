// chimera-core-mednafen: Mednafen's Saturn, Virtual Boy, PC-FX and Lynx as a
// Chimera core.
//
// Mednafen describes each of its systems in one structure (MDFNGI): how to
// load a game, how to run a frame, which ports it has, what may be plugged
// into each and every button and axis of each device, and its settings. This
// file is one frontend over that description, the same for the four systems:
// the package's "machine" setting picks the system, and everything else is
// read from Mednafen's own tables.
//
// Compiles identically for the guest (miniBox emulibc) and for the native
// reference build (native-shim/emulibc.h): the same frontend, one in the
// sandbox and one out of it.
#include <mednafen/mednafen.h>
#include <mednafen/general.h>
#include <mednafen/FileStream.h>
#include <mednafen/NativeVFS.h>
#include <mednafen/cdrom/CDInterface.h>
#include <mednafen/cdrom/CDInterface_ST.h>
#include <mednafen/cdrom/CDAccess.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "frontend.h"

using namespace Mednafen;

// the four systems' descriptions, as their own source files define them
extern const Mednafen::MDFNGI EmulatedSS, EmulatedVB, EmulatedPCFX, EmulatedLynx;

namespace
{

char g_loadError[2048];
std::string g_machine;
MDFNGI *g_system;                 // this run's copy of the system's description
std::map<std::string, std::string> g_settings;   // Mednafen settings the project sets
int64_t g_time = 946684800;       // 2000-01-01 00:00:00 UTC

// ---- the systems -------------------------------------------------------------
struct system_entry
{
	const char *machine;          // the package's "machine" value
	const MDFNGI *gi;
	bool disc;                    // its games are discs
};
const system_entry kSystems[] = {
	{ "saturn", &EmulatedSS, true },
	{ "virtualboy", &EmulatedVB, false },
	{ "pcfx", &EmulatedPCFX, true },
	{ "lynx", &EmulatedLynx, false },
};
const system_entry *g_entry;

// ---- one frame's results ---------------------------------------------------
constexpr int kSampleRate = 48000;
constexpr int kMaxSamples = 4096;
MDFN_Surface *g_surface;
EmulateSpecStruct g_spec;
std::vector<int32> g_lineWidths;
ECL_INVISIBLE int16_t g_audio[kMaxSamples * 2];
int g_audioFrames;
std::vector<uint32_t> g_picture;
int g_width, g_height;
bool g_render = true;

// ---- the ports ---------------------------------------------------------------
// A control of the panel: one input of one device in one port, as Mednafen's
// tables describe it. The port's bytes are the block Mednafen reads.
struct control
{
	std::string name;
	int port;
	const InputDeviceInputInfoStruct *input;
};
std::vector<std::vector<uint8_t>> g_portData;     // one block a port
std::vector<const InputDeviceInfoStruct *> g_plugged;
std::vector<control> g_buttons, g_axes;

void set_bits(std::vector<uint8_t> &data, unsigned offset, unsigned size, uint32_t value)
{
	for (unsigned i = 0; i < size; i++)
	{
		unsigned const bit = offset + i;
		if (bit / 8 >= data.size()) return;
		if (value & (1u << i)) data[bit / 8] |= uint8_t(1u << (bit % 8));
		else data[bit / 8] &= uint8_t(~(1u << (bit % 8)));
	}
}

// what is plugged into a port: the project's choice ("port1" = a device's
// short name), or the first device Mednafen lists that is not "none"
const InputDeviceInfoStruct *device_for(unsigned port)
{
	auto const &info = g_system->PortInfo[port];
	char key[32], val[64];
	snprintf(key, sizeof key, "port%u", port + 1);
	if (wbx_setting_str(key, val, sizeof val) > 0)
		for (auto const &device : info.DeviceInfo)
			if (!strcmp(device.ShortName, val)) return &device;
	for (auto const &device : info.DeviceInfo)
		if (strcmp(device.ShortName, "none")) return &device;
	return info.DeviceInfo.empty() ? nullptr : &info.DeviceInfo[0];
}

void build_panel()
{
	g_portData.clear();
	g_plugged.clear();
	g_buttons.clear();
	g_axes.clear();
	for (unsigned port = 0; port < g_system->PortInfo.size(); port++)
	{
		const InputDeviceInfoStruct *device = device_for(port);
		g_plugged.push_back(device);
		g_portData.emplace_back(device ? std::max<uint32>(device->IDII.InputByteSize, 1) : 1, 0);
		if (!device) continue;
		std::string const prefix = g_system->PortInfo.size() > 1 || true ? "P" + std::to_string(port + 1) + " " : "";
		for (auto const &input : device->IDII)
		{
			if (!input.Name) continue;
			switch (input.Type)
			{
			case IDIT_BUTTON:
			case IDIT_BUTTON_CAN_RAPID:
			case IDIT_RESET_BUTTON:
				g_buttons.push_back({ prefix + input.Name, int(port), &input });
				break;
			case IDIT_AXIS:
			case IDIT_AXIS_REL:
			case IDIT_BUTTON_ANALOG:
			case IDIT_POINTER_X:
			case IDIT_POINTER_Y:
				g_axes.push_back({ prefix + input.Name, int(port), &input });
				// an axis rests at its centre
				if (input.Type == IDIT_AXIS) set_bits(g_portData[port], input.BitOffset, 16, 32768);
				break;
			case IDIT_SWITCH:
				set_bits(g_portData[port], input.BitOffset, input.BitSize, input.Switch.DefPos);
				break;
			default:
				break;
			}
		}
	}
	// the blocks do not move after this: Mednafen keeps the pointers
	for (unsigned port = 0; port < g_system->PortInfo.size(); port++)
		if (g_plugged[port])
			g_system->SetInput(port, g_plugged[port]->ShortName, g_portData[port].data());
}

// ---- the files ---------------------------------------------------------------
std::vector<std::string> slot_files(const char *slot)
{
	std::vector<std::string> out;
	char entry[512];
	const int32_t n = wbx_slot_count(slot);
	for (int32_t i = 0; i < n; i++)
		if (wbx_slot_name(slot, i, entry, sizeof entry) != nullptr)
			out.emplace_back(entry);
	return out;
}

// a game opened with no project is mounted under its own name
std::string lone_rom()
{
	char entry[512];
	FILE *f = fopen("rom.name", "rb");
	if (!f) return "";
	size_t const got = fread(entry, 1, sizeof entry - 1, f);
	fclose(f);
	entry[got] = '\0';
	return entry;
}

std::vector<CDInterface *> g_discs;

void load_discs(std::vector<std::string> const &images)
{
	for (std::string const &image : images)
	{
		// Mednafen's own reader of disc images, on the emulation thread: a
		// sector is read from the image's files when the machine asks for it
		std::unique_ptr<CDAccess> access(CDAccess_Open(&NVFS, image, false));
		g_discs.push_back(new CDInterface_ST(std::move(access)));
	}
	g_system->LoadCD(&g_discs);

	// what Mednafen's own program does next: say what the drive is, and put
	// the first disc in it with the tray closed
	auto *rmd = new RMD_Layout();
	RMD_Drive drive;
	drive.Name = "Virtual CD Drive";
	drive.PossibleStates.push_back(RMD_State({ "Tray Open", false, false, true }));
	drive.PossibleStates.push_back(RMD_State({ "Tray Closed (Empty)", false, false, false }));
	drive.PossibleStates.push_back(RMD_State({ "Tray Closed", true, true, false }));
	drive.CompatibleMedia.push_back(0);
	drive.MediaMtoPDelay = 2000;
	rmd->Drives.push_back(drive);
	rmd->DrivesDefaults.push_back(RMD_DriveDefaults({ 2, 0, 0 }));
	rmd->MediaTypes.push_back(RMD_MediaType({ "CD" }));
	for (size_t i = 0; i < g_discs.size(); i++)
		rmd->Media.push_back(RMD_Media({ "Disc " + std::to_string(i + 1), 0 }));
	g_system->RMD = rmd;
	if (g_system->SetMedia) g_system->SetMedia(0, 2, 0, 0);
}

void load_cart(std::string const &path)
{
	size_t const slash = path.find_last_of('/');
	std::string const name = slash == std::string::npos ? path : path.substr(slash + 1);
	size_t const dot = name.rfind('.');
	std::string ext = dot == std::string::npos ? "" : name.substr(dot);
	for (char &c : ext) c = char(tolower((unsigned char)c));
	std::string const base = dot == std::string::npos ? name : name.substr(0, dot);
	std::unique_ptr<Stream> stream(new FileStream(path, FileStream::MODE_READ));
	GameFile gf({ &NVFS, "", path, stream.get(), ext, base, { &NVFS, "", base } });
	g_system->Load(&gf);
}

void start_frame_buffers()
{
	g_surface = new MDFN_Surface(nullptr, g_system->fb_width, g_system->fb_height, g_system->fb_width,
		MDFN_PixelFormat(MDFN_COLORSPACE_RGB, 4, 16, 8, 0, 24));
	g_lineWidths.assign(g_system->fb_height, 0);
	g_spec.surface = g_surface;
	g_spec.LineWidths = g_lineWidths.data();
	g_spec.SoundBuf = g_audio;
	g_spec.SoundBufMaxSize = kMaxSamples;
	g_spec.SoundRate = kSampleRate;
	g_spec.VideoFormatChanged = true;
	g_spec.SoundFormatChanged = true;
}

// the picture of the frame just run: the rectangle Mednafen says was drawn,
// each line as wide as the system made it, the widest line setting the width
void take_picture()
{
	MDFN_Rect const r = g_spec.DisplayRect;
	if (r.h <= 0) return;
	// a system that gives each line its own width overwrites the mark
	// FrameAdvance leaves in the first line's width
	bool const perLine = g_lineWidths[0] != ~0;
	int w = r.w;
	if (perLine)
	{
		w = 0;
		for (int y = r.y; y < r.y + r.h; y++) w = std::max(w, int(g_lineWidths[y]));
	}
	if (w <= 0) return;
	g_width = w;
	g_height = r.h;
	g_picture.assign(size_t(w) * r.h, 0);
	const uint32 *src = g_surface->pixels + r.x + r.y * g_surface->pitchinpix;
	for (int y = 0; y < r.h; y++, src += g_surface->pitchinpix)
	{
		int const lw = perLine ? std::min(int(g_lineWidths[r.y + y]), w) : w;
		if (lw > 0) memcpy(&g_picture[size_t(y) * w], src, size_t(lw) * 4);
	}
}

} // namespace

// ---- for mdfn-interfaces.cpp -------------------------------------------------
bool frontend_setting(const char *name, std::string &value)
{
	auto const found = g_settings.find(name);
	if (found == g_settings.end()) return false;
	value = found->second;
	return true;
}

std::string frontend_firmware_path(const char *name) { return name; }
int64_t frontend_time() { return g_time; }

// ---- the exports -----------------------------------------------------------------
extern "C" {

ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	char val[512];
	g_machine = wbx_setting_str("machine", val, sizeof val) > 0 ? val : "saturn";
	g_entry = nullptr;
	for (auto const &entry : kSystems)
		if (g_machine == entry.machine) g_entry = &entry;
	if (!g_entry)
	{
		snprintf(g_loadError, sizeof g_loadError, "unknown machine \"%s\"", g_machine.c_str());
		return 0;
	}
	try
	{
		// this run's own copy: a system writes into its description as it loads
		g_system = new MDFNGI(*g_entry->gi);
		MDFNGameInfo = g_system;

		// Mednafen's settings the project sets, by Mednafen's own names
		for (const MDFNSetting *s = g_system->Settings; s && s->name; s++)
			if (wbx_setting_str(s->name, val, sizeof val) > 0)
				g_settings[s->name] = val;

		std::vector<std::string> files = slot_files(g_entry->disc ? "disc" : "cart");
		if (files.empty() && !lone_rom().empty()) files.push_back(lone_rom());
		if (files.empty())
		{
			snprintf(g_loadError, sizeof g_loadError, "no %s was given", g_entry->disc ? "disc" : "game");
			return 0;
		}
		if (g_entry->disc) load_discs(files);
		else load_cart(files[0]);

		start_frame_buffers();
		build_panel();
	}
	catch (std::exception const &e)
	{
		snprintf(g_loadError, sizeof g_loadError, "%s", e.what());
		return 0;
	}
	return 1;
}

ECL_EXPORT int GetButtonCount(void) { return int(g_buttons.size()); }
ECL_EXPORT const char *GetButtonName(int32_t i) { return i >= 0 && i < int(g_buttons.size()) ? g_buttons[i].name.c_str() : ""; }
ECL_EXPORT int IsButtonActive(int32_t i) { return i >= 0 && i < int(g_buttons.size()); }
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i < 0 || i >= int(g_buttons.size())) return;
	control const &c = g_buttons[i];
	set_bits(g_portData[c.port], c.input->BitOffset, 1, state ? 1 : 0);
}

ECL_EXPORT int GetAxisCount(void) { return int(g_axes.size()); }
ECL_EXPORT const char *GetAxisName(int32_t i) { return i >= 0 && i < int(g_axes.size()) ? g_axes[i].name.c_str() : ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { return i >= 0 && i < int(g_axes.size()); }
ECL_EXPORT void SetAxis(int32_t i, int32_t value)
{
	if (i < 0 || i >= int(g_axes.size())) return;
	control const &c = g_axes[i];
	// an axis is 0 at rest for Chimera and 32768 at rest for Mednafen
	uint32_t const raw = c.input->Type == IDIT_AXIS ? uint32_t(std::min(std::max(value + 32768, 0), 65535)) : uint32_t(value) & 0xffff;
	set_bits(g_portData[c.port], c.input->BitOffset, 16, raw);
}

ECL_EXPORT void FrameAdvance(uint64_t)
{
	g_spec.skip = !g_render;
	g_spec.SoundBufSize = 0;
	g_lineWidths[0] = ~0;
	if (g_system->TransformInput) g_system->TransformInput();
	g_system->Emulate(&g_spec);
	g_spec.VideoFormatChanged = false;
	g_spec.SoundFormatChanged = false;
	g_audioFrames = g_spec.SoundBufSize;
	if (g_render) take_picture();
}

ECL_EXPORT int InputWasRead(void) { return 1; }
ECL_EXPORT void SetRenderingEnabled(int on) { g_render = on != 0; }

ECL_EXPORT uint32_t *GetVideoBgra(void) { return g_picture.data(); }
ECL_EXPORT int GetVideoWidth(void) { return g_width; }
ECL_EXPORT int GetVideoHeight(void) { return g_height; }
ECL_EXPORT int GetDisplayAspectX(void) { return g_system ? g_system->nominal_width : 4; }
ECL_EXPORT int GetDisplayAspectY(void) { return g_system ? g_system->nominal_height : 3; }

ECL_EXPORT int16_t *GetAudio(void) { return g_audio; }
ECL_EXPORT int GetAudioSampleCount(void) { return g_audioFrames; }

// Mednafen gives a system's frame rate as frames a second times 65536 * 256
ECL_EXPORT int GetVsyncNumerator(void) { return g_system ? int((uint64_t(g_system->fps) * 1000) >> 24) : 60000; }
ECL_EXPORT int GetVsyncDenominator(void) { return 1000; }

ECL_EXPORT const char *SuggestSettings(void) { return ""; }
ECL_EXPORT const char *DescribeDips(void) { return ""; }

ECL_EXPORT int32_t GetSaveDataFileCount(void) { return 0; }
ECL_EXPORT const char *GetSaveDataFileName(int32_t) { return ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t) { return 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t) { return nullptr; }

ECL_EXPORT int GetMemoryDomainCount(void) { return 0; }
ECL_EXPORT const char *GetMemoryDomainName(int) { return ""; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int) { return nullptr; }
ECL_EXPORT int64_t GetMemoryDomainSize(int) { return 0; }
ECL_EXPORT int GetMemoryDomainWritable(int) { return 0; }

} // extern "C"
