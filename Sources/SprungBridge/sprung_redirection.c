// Device redirection settings: drives, printers, audio playback and microphone. FreeRDP loads the
// matching channels (rdpdr, rdpsnd, audin) from these settings in freerdp_client_load_addins.
#include "sprung_internal.h"

#include <freerdp/client/cmdline.h>

static bool apply_audio(rdpSettings *settings, SprungAudioMode mode) {
    // Remote: INFO_REMOTECONSOLEAUDIO, the server keeps the sound; off: INFO_NOAUDIOPLAYBACK only.
    return freerdp_settings_set_bool(settings, FreeRDP_AudioPlayback, mode == SprungAudioLocal) &&
           freerdp_settings_set_bool(settings, FreeRDP_RemoteConsoleAudio, mode == SprungAudioRemote);
}

static bool apply_drives(rdpSettings *settings, const SprungDrive *drives, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (!drives[i].name || !drives[i].path)
            return false;
        // Missing folders are skipped (with a FreeRDP warning), not fatal.
        const char *const params[] = { "drive", drives[i].name, drives[i].path };
        if (!freerdp_client_add_device_channel(settings, ARRAYSIZE(params), params))
            return false;
    }
    return true;
}

bool sprung_redirection_apply(rdpSettings *settings, const SprungSessionConfig *config) {
    if (!apply_audio(settings, config->audio) || !apply_drives(settings, config->drives, config->driveCount))
        return false;
    // The printer channel enumerates the Mac's CUPS printers when it loads.
    return freerdp_settings_set_bool(settings, FreeRDP_RedirectPrinters, config->printers) &&
           freerdp_settings_set_bool(settings, FreeRDP_AudioCapture, config->microphone);
}
