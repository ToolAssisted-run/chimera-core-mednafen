// chimera-core-mednafen: CHD disc images.
//
// Mednafen reads a disc from a cue sheet and its track files, and has no
// reader for CHD, the compressed image MAME defined and most collections now
// use. This file adds one without a second idea of what a disc is: a CHD of a
// CD holds the same tracks a cue sheet lists, so the CHD is shown to
// Mednafen's own cue reader (CDAccess_Image) as the cue sheet and the track
// files it stands for. The cue sheet is written here from the CHD's track
// records, and each "track file" is a view of that track's sectors in the
// CHD, decompressed by libchdr as they are read. Everything else - the table
// of contents, the gaps between tracks, the subchannel, the lead-out - is
// Mednafen's own code, so a CHD made from a cue sheet reads exactly as the
// cue sheet does. The test script checks that: the same game from both gives
// the same run.
//
// What is not read: a CHD's own subchannel data (very few have any; the
// subchannel is made by Mednafen, as for a cue sheet), and GD-ROM images.
#include <mednafen/mednafen.h>
#include <mednafen/MemoryStream.h>
#include <mednafen/Stream.h>
#include <mednafen/VirtualFS.h>
#include <mednafen/cdrom/CDAccess.h>
#include <mednafen/cdrom/CDAccess_Image.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include <libchdr/cdrom.h>
#include <libchdr/chd.h>

#include "chd-disc.h"

/* A text a person reads is a key of languages/en.json, each of its
 * arguments after a TEXT_ARG (chimera docs/translations.md). TEXT_ARG is a
 * string of its own so the byte after it is never read as more of its hex. */
#define TEXT_ARG "\x1f"

using namespace Mednafen;

namespace
{

// One track as the CHD records it
struct chd_track
{
	int number = 0;
	std::string type;             // "MODE1_RAW", "AUDIO", ...
	uint32_t frames = 0;          // sectors of the track that are in the CHD
	uint32_t pregap = 0;          // sectors of gap before the track
	bool pregapStored = false;    // the gap's sectors are among "frames"
	uint32_t postgap = 0;
	uint64_t firstFrame = 0;      // where the track begins in the CHD
	// what a cue sheet calls this kind of track, and the bytes of a sector
	// its file holds
	const char *cueType = "";
	uint32_t sectorBytes = 0;
	bool audio = false;
};

// The CHD, and the last block of it that was decompressed. Sectors are read
// in order, eight to a block, so one block kept is nearly every read served.
struct chd_image
{
	chd_file *file = nullptr;
	uint32_t hunkBytes = 0, unitBytes = 0;
	std::vector<uint8_t> hunk;
	int64_t hunkHeld = -1;
	std::vector<chd_track> tracks;

	~chd_image()
	{
		if (file) chd_close(file);
	}

	const uint8_t *frame(uint64_t number)
	{
		uint32_t const perHunk = hunkBytes / unitBytes;
		int64_t const want = int64_t(number / perHunk);
		if (want != hunkHeld)
		{
			chd_error const err = chd_read(file, uint32_t(want), hunk.data());
			if (err != CHDERR_NONE)
			{
				hunkHeld = -1;
				throw MDFN_Error(0, "error.chd_sector" TEXT_ARG "%llu" TEXT_ARG "%s", (unsigned long long)number, chd_error_string(err));
			}
			hunkHeld = want;
		}
		return &hunk[(number % perHunk) * unitBytes];
	}
};

// A track of the CHD as the file a cue sheet would name for it
class track_stream final : public Stream
{
public:
	track_stream(chd_image *image, const chd_track *track) : image(image), track(track) { }

	uint64 attributes(void) override { return ATTRIBUTE_READABLE | ATTRIBUTE_SEEKABLE; }

	uint64 read(void *data, uint64 count, bool error_on_eos = true) override
	{
		uint8_t *out = static_cast<uint8_t *>(data);
		uint64 done = 0;
		while (done < count && position < size())
		{
			uint64 const sector = position / track->sectorBytes, within = position % track->sectorBytes;
			uint64 const take = std::min<uint64>(count - done, track->sectorBytes - within);
			const uint8_t *from = image->frame(track->firstFrame + sector);
			if (track->audio)
			{
				// a CHD holds audio samples high byte first, a cue sheet's
				// file low byte first: each pair of bytes changes places
				for (uint64 i = 0; i < take; i++) out[done + i] = from[(within + i) ^ 1];
			}
			else
				memcpy(out + done, from + within, take);
			done += take;
			position += take;
		}
		if (done < count && error_on_eos) throw MDFN_Error(0, "error.chd_past_end");
		return done;
	}

	void write(const void *, uint64) override { throw MDFN_Error(EINVAL, "error.chd_read_only"); }
	void truncate(uint64) override { throw MDFN_Error(EINVAL, "error.chd_read_only"); }
	void flush(void) override { }
	void close(void) override { }

	void seek(int64 offset, int whence = SEEK_SET) override
	{
		int64 const base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? int64(position) : int64(size());
		if (base + offset < 0) throw MDFN_Error(EINVAL, "error.chd_before_start");
		position = uint64(base + offset);
	}
	uint64 tell(void) override { return position; }
	uint64 size(void) override { return uint64(track->frames) * track->sectorBytes; }

private:
	chd_image *image;
	const chd_track *track;
	uint64 position = 0;
};

// The two kinds of file Mednafen's cue reader asks for: the cue sheet, and
// the tracks by the names the cue sheet gives them
class chd_files final : public VirtualFS
{
public:
	explicit chd_files(chd_image *image) : VirtualFS('/', "/"), image(image) { }

	static std::string track_name(int number)
	{
		char name[32];
		snprintf(name, sizeof name, "track%02d.bin", number);
		return name;
	}

	std::string cue;

	Stream *open(const std::string &path, const uint32 mode, const int = false, const bool throw_on_noent = true, const CanaryType = CanaryType::open) override
	{
		if (mode == MODE_READ)
		{
			if (path == "disc.cue")
			{
				std::unique_ptr<MemoryStream> text(new MemoryStream(cue.size(), true));
				memcpy(text->map(), cue.data(), cue.size());
				return text.release();
			}
			for (auto const &track : image->tracks)
				if (path == track_name(track.number)) return new track_stream(image, &track);
		}
		// anything else is not there: the cue reader looks for a file of
		// subchannel patches beside the cue sheet, and goes on without it
		if (throw_on_noent) throw MDFN_Error(ENOENT, "error.chd_no_file" TEXT_ARG "%s", path.c_str());
		return nullptr;
	}

	int mkdir(const std::string &, const bool = false, const bool = true) override { throw MDFN_Error(EINVAL, "error.chd_read_only"); }
	bool unlink(const std::string &, const bool = false, const CanaryType = CanaryType::unlink) override { throw MDFN_Error(EINVAL, "error.chd_read_only"); }
	void rename(const std::string &, const std::string &, const CanaryType = CanaryType::rename) override { throw MDFN_Error(EINVAL, "error.chd_read_only"); }
	bool finfo(const std::string &path, FileInfo *, const bool throw_on_noent = true) override
	{
		if (throw_on_noent) throw MDFN_Error(ENOENT, "error.chd_no_file" TEXT_ARG "%s", path.c_str());
		return false;
	}
	void readdirentries(const std::string &, std::function<bool(const std::string &)>) override { }
	std::string get_human_path(const std::string &path) override { return path; }

private:
	chd_image *image;
};

std::string msf(uint32_t sectors)
{
	char text[16];
	snprintf(text, sizeof text, "%02u:%02u:%02u", sectors / 75 / 60, sectors / 75 % 60, sectors % 75);
	return text;
}

// the cue sheet the CHD stands for: a file a track, as redump's are
std::string cue_of(chd_image const &image)
{
	std::string cue;
	for (auto const &t : image.tracks)
	{
		char line[96];
		snprintf(line, sizeof line, "FILE \"%s\" BINARY\n  TRACK %02d %s\n", chd_files::track_name(t.number).c_str(), t.number, t.cueType);
		cue += line;
		if (t.pregap && t.pregapStored)
			// the gap's sectors are in the file, before the track's own
			cue += "    INDEX 00 00:00:00\n    INDEX 01 " + msf(t.pregap) + "\n";
		else
		{
			if (t.pregap) cue += "    PREGAP " + msf(t.pregap) + "\n";
			cue += "    INDEX 01 00:00:00\n";
		}
		if (t.postgap) cue += "    POSTGAP " + msf(t.postgap) + "\n";
	}
	return cue;
}

// A disc that is a CHD: Mednafen's cue reader over the files above. It owns
// the CHD, which the track files read from for as long as the disc is open.
class chd_disc final : public CDAccess
{
public:
	explicit chd_disc(std::unique_ptr<chd_image> opened) : image(std::move(opened)), files(image.get())
	{
		files.cue = cue_of(*image);
		reader.reset(new CDAccess_Image(&files, "disc.cue", false));
	}
	~chd_disc() override { reader.reset(); }

	void Read_Raw_Sector(uint8 *buf, int32 lba) override { reader->Read_Raw_Sector(buf, lba); }
	bool Fast_Read_Raw_PW_TSRE(uint8 *pwbuf, int32 lba) const noexcept override { return reader->Fast_Read_Raw_PW_TSRE(pwbuf, lba); }
	void Read_TOC(CDUtility::TOC *toc) override { reader->Read_TOC(toc); }

private:
	std::unique_ptr<chd_image> image;
	chd_files files;
	std::unique_ptr<CDAccess_Image> reader;
};

} // namespace

Mednafen::CDAccess *open_chd_disc(const std::string &path)
{
	std::unique_ptr<chd_image> image(new chd_image);
	chd_error const err = chd_open(path.c_str(), CHD_OPEN_READ, nullptr, &image->file);
	if (err != CHDERR_NONE)
		throw MDFN_Error(0, "error.chd_not_opened" TEXT_ARG "%s" TEXT_ARG "%s", path.c_str(), chd_error_string(err));
	const chd_header *header = chd_get_header(image->file);
	image->hunkBytes = header->hunkbytes;
	image->unitBytes = header->unitbytes;
	// a CD's CHD is made of sectors of 2352 bytes with 96 of subchannel
	if (image->unitBytes != CD_FRAME_SIZE || image->hunkBytes == 0 || image->hunkBytes % image->unitBytes)
		throw MDFN_Error(0, "error.chd_not_cd" TEXT_ARG "%s", path.c_str());
	image->hunk.resize(image->hunkBytes);

	static const struct
	{
		const char *type, *cueType;
		uint32_t sectorBytes;
		bool audio;
	} kinds[] = {
		{ "MODE1_RAW", "MODE1/2352", 2352, false },
		{ "MODE2_RAW", "MODE2/2352", 2352, false },
		{ "MODE1", "MODE1/2048", 2048, false },
		{ "MODE2", "MODE2/2336", 2336, false },
		{ "MODE2_FORM_MIX", "MODE2/2336", 2336, false },
		{ "AUDIO", "AUDIO", 2352, true },
	};
	uint64_t next = 0;
	for (uint32_t index = 0; index < 99; index++)
	{
		char text[256] = "", type[32] = "", subtype[32] = "", pgtype[32] = "", pgsub[32] = "";
		int number = 0, frames = 0, pregap = 0, postgap = 0;
		if (chd_get_metadata(image->file, CDROM_TRACK_METADATA2_TAG, index, text, sizeof text - 1, nullptr, nullptr, nullptr) == CHDERR_NONE)
		{
			if (sscanf(text, CDROM_TRACK_METADATA2_FORMAT, &number, type, subtype, &frames, &pregap, pgtype, pgsub, &postgap) != 8)
				throw MDFN_Error(0, "error.chd_track_unreadable" TEXT_ARG "%s", path.c_str());
		}
		else if (chd_get_metadata(image->file, CDROM_TRACK_METADATA_TAG, index, text, sizeof text - 1, nullptr, nullptr, nullptr) == CHDERR_NONE)
		{
			// the older record, which has no gaps
			if (sscanf(text, CDROM_TRACK_METADATA_FORMAT, &number, type, subtype, &frames) != 4)
				throw MDFN_Error(0, "error.chd_track_unreadable" TEXT_ARG "%s", path.c_str());
		}
		else
			break;
		chd_track track;
		track.number = number;
		track.type = type;
		track.frames = uint32_t(frames);
		track.pregap = uint32_t(pregap);
		track.pregapStored = pgtype[0] == 'V';
		track.postgap = uint32_t(postgap);
		track.firstFrame = next;
		for (auto const &kind : kinds)
			if (track.type == kind.type)
			{
				track.cueType = kind.cueType;
				track.sectorBytes = kind.sectorBytes;
				track.audio = kind.audio;
			}
		if (!track.sectorBytes)
			throw MDFN_Error(0, "error.chd_track_kind" TEXT_ARG "%s" TEXT_ARG "%d" TEXT_ARG "%s", path.c_str(), number, type);
		if (number != int(index) + 1 || frames <= 0 || pregap < 0 || postgap < 0 || (track.pregapStored && pregap > frames))
			throw MDFN_Error(0, "error.chd_track_nonsense" TEXT_ARG "%s", path.c_str());
		// each track begins on a block of four sectors
		next += (uint64_t(frames) + CD_TRACK_PADDING - 1) / CD_TRACK_PADDING * CD_TRACK_PADDING;
		image->tracks.push_back(track);
	}
	if (image->tracks.empty())
	{
		char text[256];
		if (chd_get_metadata(image->file, GDROM_TRACK_METADATA_TAG, 0, text, sizeof text - 1, nullptr, nullptr, nullptr) == CHDERR_NONE
			|| chd_get_metadata(image->file, GDROM_OLD_METADATA_TAG, 0, text, sizeof text - 1, nullptr, nullptr, nullptr) == CHDERR_NONE)
			throw MDFN_Error(0, "error.chd_gdrom" TEXT_ARG "%s", path.c_str());
		throw MDFN_Error(0, "error.chd_no_tracks" TEXT_ARG "%s", path.c_str());
	}
	if (next * image->unitBytes > header->logicalbytes)
		throw MDFN_Error(0, "error.chd_short" TEXT_ARG "%s", path.c_str());
	return new chd_disc(std::move(image));
}
