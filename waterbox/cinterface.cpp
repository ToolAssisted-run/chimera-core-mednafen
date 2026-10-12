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

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <strings.h>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <emulibc.h>
#include <waterbox_settings.h>
#include <waterbox_slots.h>

#include "chd-disc.h"
#include "frontend.h"

using namespace Mednafen;

// the four systems' descriptions, as their own source files define them
extern const Mednafen::MDFNGI EmulatedSS, EmulatedVB, EmulatedPCFX, EmulatedLynx;

// what a Saturn disc says of the console it wants (patches/0005)
namespace MDFN_IEN_SS
{
void SS_ChimeraDiscFacts(std::vector<Mednafen::CDInterface *> *discs, int *japan, const char **cart_rom_setting);
}

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

// ---- the machine's memory ---------------------------------------------------
// What the systems tell of their RAM as they start. A memory kept as bytes is
// a memory domain: Chimera reads it where it lies. The Saturn keeps its RAM
// as 16-bit words in the host's byte order, so its bytes are not where the
// console's processor finds them; those memories are read through a bus, at
// the console's own addresses, a byte at a time in the console's order.
struct memory_area
{
	std::string name;
	uint32_t address;
	uint8_t *bytes;
	uint32_t size;
	bool words;                   // 16-bit words in the host's order
};
std::vector<memory_area> g_memory;

// The memories the machine keeps while it is off, as the systems tell of
// them. Each is a file of the save data: Mednafen's own extension names it
// ("bkr" is the Saturn's internal backup memory), and a memory kept as words
// is written high byte first, which is the file Mednafen itself reads.
struct save_memory
{
	std::string ext;
	uint8_t *bytes;
	uint64_t size;
	bool words;
};
std::vector<save_memory> g_saves;
struct save_file
{
	std::string name;
	std::vector<uint8_t> bytes;
};
std::vector<save_file> g_saveFiles;   // what the last export listed
bool g_inputRead;                 // the game took a controller's state this frame

const memory_area *domain_at(int index)
{
	for (auto const &m : g_memory)
		if (!m.words && index-- == 0) return &m;
	return nullptr;
}

// the byte the console's processor finds at an address of the bus
uint8_t *bus_byte(int64_t address)
{
	for (auto const &m : g_memory)
		if (m.words && address >= m.address && address < int64_t(m.address) + m.size)
			return &m.bytes[(address - m.address) ^ 1];   // the host is little-endian, the console is not
	return nullptr;
}
bool has_bus()
{
	for (auto const &m : g_memory)
		if (m.words) return true;
	return false;
}

std::vector<CDInterface *> g_discs;
std::vector<std::string> g_discNames;

// ---- the drive ---------------------------------------------------------------
// The project's discs are all in reach of the drive. Previous Disc and Next
// Disc move a selector and touch nothing; Disc Swap is the lid, up for as
// long as it is held, and closing on the selected disc - or on the next one
// when the selector was not moved. All of it is the machine's state: a
// rewind takes it back.
enum { kDiscPrevious, kDiscNext, kDiscSwap, kDiscControls };
bool g_discHeld[kDiscControls], g_discWasHeld[kDiscControls];
int g_discSelected, g_discInserted;
bool g_selectorMoved;
bool g_driveRead;                 // a sector was read this frame: the drive's light

// the states of the drive Mednafen is told of (load_discs)
enum { kTrayOpen = 0, kTrayClosedEmpty = 1, kTrayClosed = 2 };

void run_drive()
{
	int const count = int(g_discs.size());
	if (!count || !g_system->SetMedia) return;
	if (g_discHeld[kDiscNext] && !g_discWasHeld[kDiscNext]) { g_discSelected = (g_discSelected + 1) % count; g_selectorMoved = true; }
	if (g_discHeld[kDiscPrevious] && !g_discWasHeld[kDiscPrevious]) { g_discSelected = (g_discSelected + count - 1) % count; g_selectorMoved = true; }
	if (g_discHeld[kDiscSwap] && !g_discWasHeld[kDiscSwap])
	{
		g_system->SetMedia(0, kTrayOpen, 0, 0);
		g_discInserted = -1;
		g_selectorMoved = false;
	}
	if (!g_discHeld[kDiscSwap] && g_discWasHeld[kDiscSwap])
	{
		if (!g_selectorMoved) g_discSelected = (g_discSelected + 1) % count;
		g_system->SetMedia(0, kTrayClosed, uint32(g_discSelected), 0);
		g_discInserted = g_discSelected;
	}
	for (int i = 0; i < kDiscControls; i++) g_discWasHeld[i] = g_discHeld[i];
}

// Mednafen's reader of a disc image, with the drive's light on it
class lit_disc : public CDInterface_ST
{
public:
	using CDInterface_ST::CDInterface_ST;
	bool ReadRawSector(uint8 *buf, int32 lba) override
	{
		g_driveRead = true;
		return CDInterface_ST::ReadRawSector(buf, lba);
	}
};

// ---- the ports ---------------------------------------------------------------
// panel.inc is the package's list of controls, written by gen-config.py from
// Mednafen's own tables: for each system, every button and axis, and for each
// the input of each device it stands for ("P1 A" is the A of whichever pad is
// in port 1). A control is live when its port is connected and the device
// plugged into it has such an input; Chimera shows the live ones.
struct panel_row
{
	const char *machine;
	char kind;                    // 'B' a button, 'A' an axis
	int index;                    // in the machine's list of that kind
	int port;
	const char *device;           // Mednafen's short name of the device
	int input;                    // in the device's table
	const char *sname;            // Mednafen's name of the input, to check the table by
	char mode;                    // how a value is written: see write_value
	const char *name;
	const char *label;            // this device's own words for the control
};
const panel_row kPanel[] = {
#define PANEL_ROW(machine, kind, index, port, device, input, sname, mode, name, label) { machine, kind, index, port, device, input, sname, mode, name, label },
#define PANEL_TAPS(machine, rule, first, second, ports)
#include "panel.inc"
#undef PANEL_ROW
#undef PANEL_TAPS
};
struct tap_rule
{
	const char *machine, *rule, *setting[2];
	int portsOnTap;
};
const tap_rule kTaps[] = {
#define PANEL_ROW(machine, kind, index, port, device, input, sname, mode, name, label)
#define PANEL_TAPS(machine, rule, first, second, ports) { machine, rule, { first, second }, ports },
#include "panel.inc"
#undef PANEL_ROW
#undef PANEL_TAPS
};

struct control
{
	const char *name = "";
	int port = 0;
	std::vector<const panel_row *> rows;
	const panel_row *live = nullptr;                    // the row of what is plugged in
	const InputDeviceInputInfoStruct *input = nullptr;  // and its input
};
std::vector<std::vector<uint8_t>> g_portData;     // one block a port: what Mednafen reads
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

bool setting_on(const char *name)
{
	char val[16];
	if (wbx_setting_str(name, val, sizeof val) <= 0) return false;
	return val[0] == 't' || val[0] == 'T' || (val[0] >= '1' && val[0] <= '9');
}

// Is this port wired to the console? A multitap adds ports, and each system
// numbers them its own way:
//   "sequential" (Saturn, ss/smpc.cpp MapPorts): the ports are handed out in
//     order, six to a socket with a multitap and one to a socket without;
//   "pcfx" (pcfx/input.cpp TapMap): ports 1 and 2 are the sockets, a multitap
//     in the first adds ports 3 to 5 and one in the second ports 6 to 8.
// A port that belongs to no player (the console's own switches) always is.
bool port_connected(unsigned port)
{
	for (auto const &taps : kTaps)
	{
		if (g_machine != taps.machine) continue;
		bool const first = setting_on(taps.setting[0]), second = setting_on(taps.setting[1]);
		if (!strcmp(taps.rule, "sequential"))
		{
			unsigned const players = (first ? taps.portsOnTap : 1) + (second ? taps.portsOnTap : 1);
			unsigned const playerPorts = 2 * taps.portsOnTap;
			return port >= playerPorts || port < players;
		}
		if (!strcmp(taps.rule, "pcfx"))
			return port < 2 || (port < 5 ? first : port < 8 ? second : true);
	}
	return true;
}

// what is plugged into a port: the project's choice (Mednafen's own name for
// it, "ss.input.port1" = a device's short name), or Mednafen's default
const InputDeviceInfoStruct *device_for(unsigned port)
{
	auto const &info = g_system->PortInfo[port];
	char key[96], val[64];
	snprintf(key, sizeof key, "%s.input.%s", g_system->shortname, info.ShortName);
	const char *want = wbx_setting_str(key, val, sizeof val) > 0 ? val : info.DefaultDevice;
	for (auto const &device : info.DeviceInfo)
		if (want && !strcmp(device.ShortName, want)) return &device;
	return info.DeviceInfo.empty() ? nullptr : &info.DeviceInfo[0];
}

// Chimera's value of a control, written into the port's block as Mednafen
// reads it
void write_value(control const &c, int32_t value)
{
	if (!c.live) return;
	if (c.live->mode == 'd')   // one of the drive's controls
	{
		g_discHeld[!strcmp(c.live->sname, "disc_previous") ? kDiscPrevious : !strcmp(c.live->sname, "disc_next") ? kDiscNext : kDiscSwap] = value != 0;
		return;
	}
	std::vector<uint8_t> &data = g_portData[c.port];
	const InputDeviceInputInfoStruct &in = *c.input;
	switch (c.live->mode)
	{
	case 'b':   // a button: one bit
		set_bits(data, in.BitOffset, 1, value ? 1 : 0);
		break;
	case 's':   // a two-way switch, shown as a button: held is the second position
		set_bits(data, in.BitOffset, in.BitSize, value ? 1 : 0);
		break;
	case 'n':   // a switch of several positions: the position's number
		set_bits(data, in.BitOffset, in.BitSize, uint32_t(std::min(std::max(value, 0), int32_t(in.Switch.NumPos) - 1)));
		break;
	case 'x':   // a stick: 0 at rest for Chimera, 32768 for Mednafen
		set_bits(data, in.BitOffset, 16, uint32_t(std::min(std::max(value + 32768, 0), 65535)));
		break;
	case 'u':   // a trigger: 0 released, 65535 fully pressed
		set_bits(data, in.BitOffset, 16, uint32_t(std::min(std::max(value, 0), 65535)));
		break;
	case 'r':   // a mouse: the movement this frame
		set_bits(data, in.BitOffset, 16, uint32_t(uint16_t(int16_t(std::min(std::max(value, -32768), 32767)))));
		break;
	case 'p':   // a pointer: a fraction of the picture (0..65535), turned into
	case 'q':   // the system's own units as Mednafen's program does
	{
		double const fraction = std::min(std::max(value, 0), 65535) / 65536.0;
		double const scaled = c.live->mode == 'p'
			? fraction * g_system->mouse_scale_x + g_system->mouse_offs_x
			: fraction * g_system->mouse_scale_y + g_system->mouse_offs_y;
		int32_t const units = int32_t(floor(0.5 + scaled));
		set_bits(data, in.BitOffset, 16, uint32_t(uint16_t(int16_t(std::min(std::max(units, -32768), 32767)))));
		break;
	}
	}
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
		// every switch at the position it rests in, every stick at its centre
		for (auto const &input : device->IDII)
		{
			if (input.Type == IDIT_SWITCH) set_bits(g_portData[port], input.BitOffset, input.BitSize, input.Switch.DefPos);
			if (input.Type == IDIT_AXIS) set_bits(g_portData[port], input.BitOffset, 16, 32768);
		}
	}
	for (auto const &row : kPanel)
	{
		if (g_machine != row.machine) continue;
		std::vector<control> &list = row.kind == 'B' ? g_buttons : g_axes;
		if (size_t(row.index) >= list.size()) list.resize(row.index + 1);
		control &c = list[row.index];
		c.name = row.name;
		c.port = row.port;
		c.rows.push_back(&row);
		if (row.port < 0)
		{
			// the drive's controls: the lid always, the selector with more than one disc
			if (!strcmp(row.sname, "disc_swap") ? !g_discs.empty() : g_discs.size() > 1) c.live = &row;
			continue;
		}
		const InputDeviceInfoStruct *device = size_t(row.port) < g_plugged.size() ? g_plugged[row.port] : nullptr;
		if (!device || strcmp(device->ShortName, row.device) || !port_connected(row.port)) continue;
		// the table was made from this very Mednafen: a row that does not find
		// its input means panel.inc is stale
		if (size_t(row.input) >= device->IDII.size() || !device->IDII[row.input].SettingName
			|| strcmp(device->IDII[row.input].SettingName, row.sname))
			throw MDFN_Error(0, "the control table (panel.inc) is not this Mednafen's: %s of %s", row.sname, row.device);
		c.live = &row;
		c.input = &device->IDII[row.input];
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

// Mednafen's own reader of disc images, on the emulation thread: a sector is
// read from the image's files when the machine asks for it. Opened once: the
// question of which firmware a disc needs is asked before the machine is built.
void open_discs(std::vector<std::string> const &images)
{
	if (!g_discs.empty()) return;
	for (std::string const &image : images)
	{
		// a .chd goes through this core's reader, anything else through
		// Mednafen's own
		bool const chd = image.size() > 4 && !strcasecmp(image.c_str() + image.size() - 4, ".chd");
		std::unique_ptr<CDAccess> access(chd ? open_chd_disc(image) : CDAccess_Open(&NVFS, image, false));
		g_discs.push_back(new lit_disc(std::move(access)));
		g_discNames.push_back(image);
	}
}

void load_discs(std::vector<std::string> const &images)
{
	open_discs(images);
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
	if (g_system->SetMedia) g_system->SetMedia(0, kTrayClosed, 0, 0);
	g_discSelected = g_discInserted = 0;
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

// ---- the description the package is generated from -------------------------
// Every system's ports, devices, inputs and settings as Mednafen's tables
// have them, as JSON. waterbox/gen-config.py turns it into the package's
// declarations, so nothing about a controller or a setting is typed by hand.
std::string json_text(const char *text)
{
	std::string out = "\"";
	for (const char *c = text ? text : ""; *c; c++)
	{
		if (*c == '"' || *c == '\\') { out += '\\'; out += *c; }
		else if (*c == '\n') out += "\\n";
		else if (*c == '\t') out += ' ';
		else if ((unsigned char)*c >= 0x20) out += *c;
	}
	return out + "\"";
}

const char *input_type_name(InputDeviceInputType t)
{
	switch (t)
	{
	case IDIT_BUTTON: return "button";
	case IDIT_BUTTON_CAN_RAPID: return "button";
	case IDIT_RESET_BUTTON: return "reset";
	case IDIT_SWITCH: return "switch";
	case IDIT_STATUS: return "status";
	case IDIT_AXIS: return "axis";
	case IDIT_AXIS_REL: return "relative";
	case IDIT_POINTER_X: return "pointerx";
	case IDIT_POINTER_Y: return "pointery";
	case IDIT_BUTTON_ANALOG: return "analogbutton";
	case IDIT_RUMBLE: return "rumble";
	case IDIT_BYTE_SPECIAL: return "bytes";
	default: return "padding";
	}
}

const char *setting_type_name(MDFNSettingType t)
{
	switch (t)
	{
	case MDFNST_INT: return "int";
	case MDFNST_UINT: return "uint";
	case MDFNST_BOOL: return "bool";
	case MDFNST_FLOAT: return "float";
	case MDFNST_STRING: return "string";
	case MDFNST_ENUM: return "enum";
	case MDFNST_MULTI_ENUM: return "multienum";
	default: return "alias";
	}
}

std::string g_description;
const char *describe_systems()
{
	std::string &o = g_description;
	o = "[";
	for (auto const &entry : kSystems)
	{
		const MDFNGI &gi = *entry.gi;
		if (&entry != kSystems) o += ",";
		o += "\n{\"machine\":" + json_text(entry.machine) + ",\"shortname\":" + json_text(gi.shortname)
			+ ",\"fullname\":" + json_text(gi.fullname) + ",\"disc\":" + (entry.disc ? "true" : "false")
			+ ",\"fps\":" + std::to_string(gi.fps) + ",\"fb\":[" + std::to_string(gi.fb_width) + "," + std::to_string(gi.fb_height)
			+ "],\"nominal\":[" + std::to_string(gi.nominal_width) + "," + std::to_string(gi.nominal_height) + "],\"extensions\":[";
		for (const FileExtensionSpecStruct *e = gi.FileExtensions; e && e->extension; e++)
			o += std::string(e == gi.FileExtensions ? "" : ",") + json_text(e->extension);
		o += "],\n \"ports\":[";
		for (size_t p = 0; p < gi.PortInfo.size(); p++)
		{
			auto const &port = gi.PortInfo[p];
			o += std::string(p ? "," : "") + "\n  {\"short\":" + json_text(port.ShortName) + ",\"full\":" + json_text(port.FullName)
				+ ",\"default\":" + json_text(port.DefaultDevice) + ",\"devices\":[";
			for (size_t d = 0; d < port.DeviceInfo.size(); d++)
			{
				auto const &device = port.DeviceInfo[d];
				o += std::string(d ? "," : "") + "\n   {\"short\":" + json_text(device.ShortName) + ",\"full\":" + json_text(device.FullName)
					+ ",\"description\":" + json_text(device.Description) + ",\"bytes\":" + std::to_string(device.IDII.InputByteSize) + ",\"inputs\":[";
				bool first = true;
				for (size_t n = 0; n < device.IDII.size(); n++)
				{
					auto const &input = device.IDII[n];
					if (!input.Name && input.Type != IDIT_SWITCH) continue;
					o += std::string(first ? "" : ",") + "\n    {\"index\":" + std::to_string(n) + ",\"sname\":" + json_text(input.SettingName) + ",\"name\":" + json_text(input.Name)
						+ ",\"type\":\"" + input_type_name(input.Type) + "\",\"offset\":" + std::to_string(input.BitOffset)
						+ ",\"bits\":" + std::to_string(input.BitSize) + ",\"order\":" + std::to_string(input.ConfigOrder);
					if (input.Type == IDIT_AXIS || input.Type == IDIT_AXIS_REL)
						o += ",\"negative\":" + json_text(input.Axis.name_dir[0]) + ",\"positive\":" + json_text(input.Axis.name_dir[1]);
					if (input.Type == IDIT_SWITCH)
					{
						o += ",\"default\":" + std::to_string(input.Switch.DefPos) + ",\"positions\":[";
						for (uint32 i = 0; i < input.Switch.NumPos; i++)
							o += std::string(i ? "," : "") + "{\"sname\":" + json_text(input.Switch.Pos[i].SettingName) + ",\"name\":" + json_text(input.Switch.Pos[i].Name)
								+ ",\"description\":" + json_text(input.Switch.Pos[i].Description) + "}";
						o += "]";
					}
					o += "}";
					first = false;
				}
				o += "]}";
			}
			o += "]}";
		}
		o += "],\n \"settings\":[";
		bool first = true;
		for (const MDFNSetting *st = gi.Settings; st && st->name; st++)
		{
			o += std::string(first ? "" : ",") + "\n  {\"name\":" + json_text(st->name) + ",\"flags\":" + std::to_string(st->flags)
				+ ",\"description\":" + json_text(st->description) + ",\"extra\":" + json_text(st->description_extra)
				+ ",\"type\":\"" + setting_type_name(st->type) + "\",\"default\":" + json_text(st->default_value)
				+ ",\"minimum\":" + json_text(st->minimum) + ",\"maximum\":" + json_text(st->maximum) + ",\"options\":[";
			for (const MDFNSetting_EnumList *e = st->enum_list; e && e->string; e++)
				o += std::string(e == st->enum_list ? "" : ",") + "{\"value\":" + json_text(e->string) + ",\"number\":" + std::to_string(e->number)
					+ ",\"description\":" + json_text(e->description) + ",\"extra\":" + json_text(e->description_extra) + "}";
			o += "]}";
			first = false;
		}
		o += "]}";
	}
	o += "\n]\n";
	return o.c_str();
}

// The firmware files, by the names they are mounted under. The Saturn's two
// BIOS files are asked for under names of this core's own, not Mednafen's
// defaults ("sega_101.bin"): Mednafen refuses a file whose name is that of one
// known BIOS and whose contents are another's, and a project may hold any of
// the BIOS versions of a region.
const char *const kFirmwareNames[][2] = {
	{ "ss.bios_jp", "saturn_jp.bin" },
	{ "ss.bios_na_eu", "saturn_na_eu.bin" },
};

// the machine the project is for, and the settings it sets
bool choose_machine()
{
	char val[512];
	g_machine = wbx_setting_str("machine", val, sizeof val) > 0 ? val : "saturn";
	g_entry = nullptr;
	for (auto const &entry : kSystems)
		if (g_machine == entry.machine) g_entry = &entry;
	if (!g_entry)
	{
		snprintf(g_loadError, sizeof g_loadError, "unknown machine \"%s\"", g_machine.c_str());
		return false;
	}
	if (!g_system)
	{
		// this run's own copy: a system writes into its description as it loads
		g_system = new MDFNGI(*g_entry->gi);
		MDFNGameInfo = g_system;
	}
	// Mednafen's settings the project sets, by Mednafen's own names
	g_settings.clear();
	for (const MDFNSetting *s = g_system->Settings; s && s->name; s++)
		if (wbx_setting_str(s->name, val, sizeof val) > 0)
		{
			// a project writes a switch as true or false, Mednafen as 1 or 0
			if (s->type == MDFNST_BOOL) g_settings[s->name] = (val[0] == 't' || val[0] == 'T' || val[0] == '1') ? "1" : "0";
			else g_settings[s->name] = val;
		}
	for (auto const &name : kFirmwareNames) g_settings[name[0]] = name[1];
	// the machine's clock starts at a time the project sets, never the host's
	if (wbx_setting_str("initialTime", val, sizeof val) > 0) g_time = strtoll(val, nullptr, 10);
	return true;
}

std::vector<std::string> game_files()
{
	std::vector<std::string> files = slot_files(g_entry->disc ? "disc" : "cart");
	if (files.empty() && !lone_rom().empty()) files.push_back(lone_rom());
	return files;
}

std::string g_suggestion;

std::string firmware_entry(const char *id, const char *display, const char *description, const char *name, std::string const &when)
{
	return std::string("{\"id\":") + json_text(id) + ",\"display\":" + json_text(display) + ",\"description\":" + json_text(description)
		+ ",\"name\":" + json_text(name) + ",\"requiredWhen\":" + when + "}";
}

// The firmware a Saturn disc needs. Which BIOS depends on the disc's region
// and on two settings that can overrule it, and the wizard asks before the
// settings are final, so each file is given with the settings it is needed
// under (ss.cpp LoadCD: the region is the disc's when "ss.region_autodetect"
// is on and the disc names one, and "ss.region_default" otherwise).
std::string saturn_firmware(std::string &note)
{
	int japan = -1;
	const char *cartRom = nullptr;
	MDFN_IEN_SS::SS_ChimeraDiscFacts(&g_discs, &japan, &cartRom);

	const std::string fromDisc = "{\"setting\":\"ss.region_autodetect\",\"is\":true}";
	const std::string notFromDisc = "{\"setting\":\"ss.region_autodetect\",\"is\":false}";
	const std::string setJapan = "{\"setting\":\"ss.region_default\",\"in\":[\"jp\",\"tw\"]}";
	const std::string setOther = "{\"setting\":\"ss.region_default\",\"in\":[\"na\",\"eu\",\"kr\",\"as\",\"br\",\"la\"]}";
	std::string whenJapan, whenOther;
	if (japan == 1)
	{
		whenJapan = "{\"any\":[" + fromDisc + "," + setJapan + "]}";
		whenOther = "{\"all\":[" + notFromDisc + "," + setOther + "]}";
		note = "This disc is for a Japanese or Taiwanese console, which starts with the Japanese BIOS.";
	}
	else if (japan == 0)
	{
		whenJapan = "{\"all\":[" + notFromDisc + "," + setJapan + "]}";
		whenOther = "{\"any\":[" + fromDisc + "," + setOther + "]}";
		note = "This disc is for a console outside Japan and Taiwan, which starts with the North American and European BIOS.";
	}
	else
	{
		whenJapan = setJapan;
		whenOther = setOther;
		note = "This disc does not say which region it is for, so the Region setting decides which BIOS the console starts with.";
	}
	std::string out = "["
		+ firmware_entry("saturn_jp.bin", "Saturn BIOS (Japan)",
			"The BIOS of a Japanese Saturn (512 KB). The console starts from it. Version 1.01 is usually named sega_101.bin; versions 1.00 and 1.003 work as well. It is Sega's and you have to supply it.",
			"sega_101.bin", whenJapan)
		+ "," + firmware_entry("saturn_na_eu.bin", "Saturn BIOS (North America and Europe)",
			"The BIOS of a North American or European Saturn (512 KB). The console starts from it. It is usually named mpr-17933.bin. It is Sega's and you have to supply it.",
			"mpr-17933.bin", whenOther);
	if (cartRom)
	{
		// the game is known to need the ROM cartridge it was sold with
		std::string const file = MDFN_GetSettingS(cartRom);
		out += "," + firmware_entry(file.c_str(), "Game cartridge ROM",
			"This game was sold with a ROM cartridge and reads part of itself from it. The file is the cartridge's ROM, under the name MAME gives it. It is needed while the Cartridge setting is 'auto'.",
			file.c_str(), "{\"setting\":\"ss.cart\",\"is\":\"auto\"}");
		note += " The game needs its ROM cartridge (" + file + ").";
	}
	return out + "]";
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

// a system's name for nothing but an address: the names Chimera shows
void frontend_add_memory(uint32_t address, uint8_t *bytes, uint32_t size)
{
	static const struct { const char *machine; uint32_t address; const char *name; } kNames[] = {
		{ "virtualboy", 0x05000000, "WRAM" },
		{ "virtualboy", 0x06000000, "Cartridge RAM" },
		{ "pcfx", 0x00000000, "RAM" },
		{ "lynx", 0x00000000, "RAM" },
	};
	if (!bytes || !size) return;
	char name[32];
	snprintf(name, sizeof name, "RAM %08X", unsigned(address));
	for (auto const &n : kNames)
		if (g_machine == n.machine && address == n.address) snprintf(name, sizeof name, "%s", n.name);
	g_memory.push_back({ name, address, bytes, size, false });
}

std::string frontend_save_path(const char *ext)
{
	std::string const tail = std::string(".") + ext;
	for (std::string const &file : slot_files("savedata"))
		if (file.size() > tail.size() && !strcasecmp(file.c_str() + file.size() - tail.size(), tail.c_str()))
			return file;
	return std::string("chimera-no-such-file/") + ext;
}

// the hooks of patches/0006 and 0007
namespace Mednafen
{
void MDFN_ChimeraSaveMemory(const char *ext, void *memory, uint64 bytes, bool words)
{
	g_saves.push_back({ ext, static_cast<uint8_t *>(memory), bytes, words });
}
void MDFN_ChimeraInputRead(void) { g_inputRead = true; }
void MDFN_ChimeraWordMemory(const char *name, uint32 address, uint16 *words, uint32 bytes)
{
	g_memory.push_back({ name, address, reinterpret_cast<uint8_t *>(words), bytes, true });
}
}
int64_t frontend_time() { return g_time; }

// ---- the exports -----------------------------------------------------------------
extern "C" {

ECL_EXPORT const char *GetLoadError(void) { return g_loadError; }

// What the New Project window and a load are told of the game before the
// machine is built: the firmware it needs. Nothing is run.
ECL_EXPORT const char *SuggestSettings(void)
{
	g_loadError[0] = '\0';
	std::string note, firmware = "[]";
	try
	{
		if (!choose_machine()) note = g_loadError;
		else if (g_machine == "saturn")
		{
			std::vector<std::string> const files = game_files();
			if (files.empty()) note = "No disc was given.";
			else
			{
				open_discs(files);
				firmware = saturn_firmware(note);
			}
		}
	}
	catch (std::exception const &e)
	{
		note = e.what();
	}
	g_suggestion = "{\"values\":{},\"note\":" + json_text(note.c_str()) + ",\"firmware\":" + firmware + "}";
	return g_suggestion.c_str();
}

ECL_EXPORT int Init(void)
{
	g_loadError[0] = '\0';
	if (!choose_machine()) return 0;
	try
	{
		std::vector<std::string> const files = game_files();
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
ECL_EXPORT const char *GetButtonName(int32_t i) { return i >= 0 && i < int(g_buttons.size()) ? g_buttons[i].name : ""; }
ECL_EXPORT int IsButtonActive(int32_t i) { return i >= 0 && i < int(g_buttons.size()) && g_buttons[i].live; }
// this device's own words for the control ("L Gear Shift" for a wheel's Up)
ECL_EXPORT const char *GetButtonLabel(int32_t i) { return i >= 0 && i < int(g_buttons.size()) && g_buttons[i].live ? g_buttons[i].live->label : ""; }
ECL_EXPORT void SetButton(int32_t i, int32_t state)
{
	if (i >= 0 && i < int(g_buttons.size())) write_value(g_buttons[i], state);
}

ECL_EXPORT int GetAxisCount(void) { return int(g_axes.size()); }
ECL_EXPORT const char *GetAxisName(int32_t i) { return i >= 0 && i < int(g_axes.size()) ? g_axes[i].name : ""; }
ECL_EXPORT int IsAxisActive(int32_t i) { return i >= 0 && i < int(g_axes.size()) && g_axes[i].live; }
ECL_EXPORT const char *GetAxisLabel(int32_t i) { return i >= 0 && i < int(g_axes.size()) && g_axes[i].live ? g_axes[i].live->label : ""; }
ECL_EXPORT void SetAxis(int32_t i, int32_t value)
{
	if (i >= 0 && i < int(g_axes.size())) write_value(g_axes[i], value);
}

ECL_EXPORT void FrameAdvance(uint64_t)
{
	g_spec.skip = !g_render;
	g_spec.SoundBufSize = 0;
	g_lineWidths[0] = ~0;
	g_inputRead = false;
	g_driveRead = false;
	run_drive();
	if (g_system->TransformInput) g_system->TransformInput();
	g_system->Emulate(&g_spec);
	g_spec.VideoFormatChanged = false;
	g_spec.SoundFormatChanged = false;
	g_audioFrames = g_spec.SoundBufSize;
	if (g_render) take_picture();
}

// a frame in which the game did not take the controllers' state is a lag frame
ECL_EXPORT int InputWasRead(void) { return g_inputRead ? 1 : 0; }
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


// for the package's generator (run-native --describe): not called by Chimera
ECL_EXPORT const char *DebugDescribeSystems(void) { return describe_systems(); }
ECL_EXPORT const char *DescribeDips(void) { return ""; }

// The drive of a machine that takes discs: lit on a frame a sector was read,
// with the project's discs, the one the selector is on and the one inside
// (-1 with the lid up).
ECL_EXPORT int32_t GetDriveCount(void) { return g_discs.empty() ? 0 : 1; }
ECL_EXPORT const char *GetDriveName(int32_t i) { return i == 0 && !g_discs.empty() ? "CD" : ""; }
ECL_EXPORT int32_t GetDriveLight(int32_t i) { return i == 0 && g_driveRead; }
ECL_EXPORT int32_t GetDriveMediaCount(int32_t i) { return i == 0 ? int32_t(g_discs.size()) : 0; }
ECL_EXPORT const char *GetDriveMediaName(int32_t i, int32_t n) { return i == 0 && n >= 0 && size_t(n) < g_discNames.size() ? g_discNames[n].c_str() : ""; }
ECL_EXPORT int32_t GetDriveMediaSelected(int32_t i) { return i == 0 ? g_discSelected : -1; }
ECL_EXPORT int32_t GetDriveMediaInserted(int32_t i) { return i == 0 ? g_discInserted : -1; }

// Export Save Data: each save memory as the file Mednafen would write
ECL_EXPORT int32_t GetSaveDataFileCount(void)
{
	g_saveFiles.clear();
	for (auto const &m : g_saves)
	{
		save_file f;
		f.name = g_machine + "." + m.ext;
		f.bytes.assign(m.bytes, m.bytes + m.size);
		if (m.words)
			for (size_t i = 0; i + 1 < f.bytes.size(); i += 2) std::swap(f.bytes[i], f.bytes[i + 1]);
		g_saveFiles.push_back(std::move(f));
	}
	return int32_t(g_saveFiles.size());
}
ECL_EXPORT const char *GetSaveDataFileName(int32_t i) { return i >= 0 && size_t(i) < g_saveFiles.size() ? g_saveFiles[i].name.c_str() : ""; }
ECL_EXPORT int64_t GetSaveDataFileSize(int32_t i) { return i >= 0 && size_t(i) < g_saveFiles.size() ? int64_t(g_saveFiles[i].bytes.size()) : 0; }
ECL_EXPORT const uint8_t *GetSaveDataFileBuffer(int32_t i) { return i >= 0 && size_t(i) < g_saveFiles.size() ? g_saveFiles[i].bytes.data() : nullptr; }

ECL_EXPORT int GetMemoryDomainCount(void)
{
	int n = 0;
	while (domain_at(n)) n++;
	return n;
}
ECL_EXPORT const char *GetMemoryDomainName(int i) { return domain_at(i) ? domain_at(i)->name.c_str() : ""; }
ECL_EXPORT uint8_t *GetMemoryDomainPtr(int i) { return domain_at(i) ? domain_at(i)->bytes : nullptr; }
ECL_EXPORT int64_t GetMemoryDomainSize(int i) { return domain_at(i) ? domain_at(i)->size : 0; }
ECL_EXPORT int GetMemoryDomainWritable(int i) { return domain_at(i) != nullptr; }

// The Saturn's memory as its processors address it (see memory_area). The bus
// is mostly nothing: its ranges say where the RAM is.
ECL_EXPORT int32_t GetBusCount(void) { return has_bus() ? 1 : 0; }
ECL_EXPORT const char *GetBusName(int32_t i) { return i == 0 && has_bus() ? "System Bus" : ""; }
ECL_EXPORT int64_t GetBusSize(int32_t i) { return i == 0 && has_bus() ? 0x08000000 : 0; }
ECL_EXPORT int32_t GetBusWritable(int32_t i) { return i == 0 && has_bus(); }
ECL_EXPORT int32_t PeekBus(int32_t bus, int32_t addr)
{
	const uint8_t *at = bus == 0 ? bus_byte(int64_t(uint32_t(addr))) : nullptr;
	return at ? *at : 0;
}
ECL_EXPORT void PokeBus(int32_t bus, int32_t addr, int32_t value)
{
	uint8_t *at = bus == 0 ? bus_byte(int64_t(uint32_t(addr))) : nullptr;
	if (at) *at = uint8_t(value);
}
ECL_EXPORT const uint8_t *ReadBus(int32_t bus, int64_t addr, int32_t len)
{
	// an answer to a tool is in no savestate
	ECL_INVISIBLE static uint8_t buffer[0x10000];
	if (bus != 0 || len < 0 || len > int32_t(sizeof buffer)) return nullptr;
	for (int32_t i = 0; i < len; i++)
	{
		const uint8_t *at = bus_byte(addr + i);
		buffer[i] = at ? *at : 0;
	}
	return buffer;
}
ECL_EXPORT const int64_t *GetBusRanges(int32_t bus)
{
	ECL_INVISIBLE static int64_t ranges[2 * 16];
	if (bus != 0 || !has_bus()) return nullptr;
	size_t n = 0;
	for (auto const &m : g_memory)
		if (m.words && n + 4 <= sizeof ranges / sizeof ranges[0])
		{
			ranges[n++] = m.address;
			ranges[n++] = m.size;
		}
	ranges[n] = ranges[n + 1] = 0;
	return ranges;
}

} // extern "C"
