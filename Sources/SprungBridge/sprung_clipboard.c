// Clipboard redirection (MS-RDPECLIP) over FreeRDP's cliprdr channel. The bridge only moves
// format lists and data blobs; formats and conversions live in Swift.
//
// Server messages arrive on the channel's message thread. The API functions may be called from
// any thread: they only queue PDUs, which the session's event loop sends.
#include "sprung_internal.h"

#include <stdlib.h>

#include <freerdp/client/cliprdr.h>
#include <winpr/wlog.h>

static SprungSession *session_of(CliprdrClientContext *cliprdr) {
    return cliprdr ? cliprdr->custom : NULL;
}

static UINT send_client_capabilities(CliprdrClientContext *cliprdr) {
    // No file streaming yet (M5): long format names only.
    CLIPRDR_GENERAL_CAPABILITY_SET general = {
        .capabilitySetType = CB_CAPSTYPE_GENERAL,
        .capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN,
        .version = CB_CAPS_VERSION_2,
        .generalFlags = CB_USE_LONG_FORMAT_NAMES,
    };
    const CLIPRDR_CAPABILITIES capabilities = {
        .common = { .msgType = CB_CLIP_CAPS },
        .cCapabilitiesSets = 1,
        .capabilitySets = (CLIPRDR_CAPABILITY_SET *)&general,
    };
    return cliprdr->ClientCapabilities(cliprdr, &capabilities);
}

static UINT on_monitor_ready(CliprdrClientContext *cliprdr, const CLIPRDR_MONITOR_READY *ready) {
    (void)ready;
    SprungSession *session = session_of(cliprdr);
    const UINT rc = send_client_capabilities(cliprdr);
    if (rc != CHANNEL_RC_OK)
        return rc;
    // The client must answer with its format list; Swift announces the local clipboard.
    if (session->callbacks.clipboardReady)
        session->callbacks.clipboardReady(session->callbacks.userData);
    return CHANNEL_RC_OK;
}

static UINT on_server_capabilities(CliprdrClientContext *cliprdr, const CLIPRDR_CAPABILITIES *capabilities) {
    (void)cliprdr;
    (void)capabilities;
    return CHANNEL_RC_OK;
}

static UINT on_server_format_list(CliprdrClientContext *cliprdr, const CLIPRDR_FORMAT_LIST *list) {
    SprungSession *session = session_of(cliprdr);
    const CLIPRDR_FORMAT_LIST_RESPONSE response = {
        .common = { .msgType = CB_FORMAT_LIST_RESPONSE, .msgFlags = CB_RESPONSE_OK },
    };
    const UINT rc = cliprdr->ClientFormatListResponse(cliprdr, &response);

    if (session->callbacks.clipboardRemoteFormats) {
        SprungClipboardFormat *formats = calloc(list->numFormats ? list->numFormats : 1, sizeof(*formats));
        if (!formats)
            return CHANNEL_RC_NO_MEMORY;
        for (UINT32 i = 0; i < list->numFormats; i++) {
            formats[i].id = list->formats[i].formatId;
            formats[i].name = list->formats[i].formatName;
        }
        session->callbacks.clipboardRemoteFormats(session->callbacks.userData, formats, list->numFormats);
        free(formats);
    }
    return rc;
}

static UINT on_server_format_list_response(CliprdrClientContext *cliprdr,
                                           const CLIPRDR_FORMAT_LIST_RESPONSE *response) {
    SprungSession *session = session_of(cliprdr);
    const bool accepted = (response->common.msgFlags & CB_RESPONSE_OK) != 0;
    if (!accepted)
        WLog_WARN(SPRUNG_TAG, "server rejected the clipboard format list");
    if (session->callbacks.clipboardAnnounced)
        session->callbacks.clipboardAnnounced(session->callbacks.userData, accepted);
    return CHANNEL_RC_OK;
}

static UINT on_server_format_data_request(CliprdrClientContext *cliprdr,
                                          const CLIPRDR_FORMAT_DATA_REQUEST *request) {
    SprungSession *session = session_of(cliprdr);
    if (session->callbacks.clipboardDataRequested) {
        session->callbacks.clipboardDataRequested(session->callbacks.userData, request->requestedFormatId);
        return CHANNEL_RC_OK;
    }
    const CLIPRDR_FORMAT_DATA_RESPONSE failure = {
        .common = { .msgType = CB_FORMAT_DATA_RESPONSE, .msgFlags = CB_RESPONSE_FAIL },
    };
    return cliprdr->ClientFormatDataResponse(cliprdr, &failure);
}

static UINT on_server_format_data_response(CliprdrClientContext *cliprdr,
                                           const CLIPRDR_FORMAT_DATA_RESPONSE *response) {
    SprungSession *session = session_of(cliprdr);
    const bool ok = (response->common.msgFlags & CB_RESPONSE_FAIL) == 0 && response->requestedFormatData;
    if (session->callbacks.clipboardDataReceived)
        session->callbacks.clipboardDataReceived(session->callbacks.userData, ok ? response->requestedFormatData : NULL,
                                                 ok ? response->common.dataLen : 0);
    return CHANNEL_RC_OK;
}

// Files over the clipboard come in M5; we never announce them, but answer politely.
static UINT on_server_file_contents_request(CliprdrClientContext *cliprdr,
                                            const CLIPRDR_FILE_CONTENTS_REQUEST *request) {
    const CLIPRDR_FILE_CONTENTS_RESPONSE failure = {
        .common = { .msgType = CB_FILECONTENTS_RESPONSE, .msgFlags = CB_RESPONSE_FAIL },
        .streamId = request->streamId,
    };
    return cliprdr->ClientFileContentsResponse(cliprdr, &failure);
}

static UINT on_server_lock(CliprdrClientContext *cliprdr, const CLIPRDR_LOCK_CLIPBOARD_DATA *lock) {
    (void)cliprdr;
    (void)lock;
    return CHANNEL_RC_OK;
}

static UINT on_server_unlock(CliprdrClientContext *cliprdr, const CLIPRDR_UNLOCK_CLIPBOARD_DATA *unlock) {
    (void)cliprdr;
    (void)unlock;
    return CHANNEL_RC_OK;
}

void sprung_clipboard_channel_connected(SprungSession *session, CliprdrClientContext *cliprdr) {
    cliprdr->custom = session;
    cliprdr->MonitorReady = on_monitor_ready;
    cliprdr->ServerCapabilities = on_server_capabilities;
    cliprdr->ServerFormatList = on_server_format_list;
    cliprdr->ServerFormatListResponse = on_server_format_list_response;
    cliprdr->ServerFormatDataRequest = on_server_format_data_request;
    cliprdr->ServerFormatDataResponse = on_server_format_data_response;
    cliprdr->ServerFileContentsRequest = on_server_file_contents_request;
    cliprdr->ServerLockClipboardData = on_server_lock;
    cliprdr->ServerUnlockClipboardData = on_server_unlock;
    pthread_mutex_lock(&session->clipboardLock);
    session->cliprdr = cliprdr;
    pthread_mutex_unlock(&session->clipboardLock);
}

void sprung_clipboard_channel_disconnected(SprungSession *session) {
    pthread_mutex_lock(&session->clipboardLock);
    session->cliprdr = NULL;
    pthread_mutex_unlock(&session->clipboardLock);
}

// MARK: - API

static CliprdrClientContext *clipboard_begin(SprungSession *session) {
    if (!session)
        return NULL;
    pthread_mutex_lock(&session->clipboardLock);
    if (session->cliprdr)
        return session->cliprdr;
    pthread_mutex_unlock(&session->clipboardLock);
    return NULL;
}

static void clipboard_end(SprungSession *session) {
    pthread_mutex_unlock(&session->clipboardLock);
}

bool sprung_session_clipboard_announce(SprungSession *session, const SprungClipboardFormat *formats, size_t count) {
    CliprdrClientContext *cliprdr = clipboard_begin(session);
    if (!cliprdr)
        return false;
    CLIPRDR_FORMAT *list = calloc(count ? count : 1, sizeof(*list));
    UINT rc = CHANNEL_RC_NO_MEMORY;
    if (list) {
        for (size_t i = 0; i < count; i++) {
            list[i].formatId = formats[i].id;
            list[i].formatName = (char *)formats[i].name; // copied when the PDU is built
        }
        const CLIPRDR_FORMAT_LIST formatList = {
            .common = { .msgType = CB_FORMAT_LIST },
            .numFormats = (UINT32)count,
            .formats = list,
        };
        rc = cliprdr->ClientFormatList(cliprdr, &formatList);
        free(list);
    }
    clipboard_end(session);
    return rc == CHANNEL_RC_OK;
}

bool sprung_session_clipboard_request(SprungSession *session, uint32_t formatId) {
    CliprdrClientContext *cliprdr = clipboard_begin(session);
    if (!cliprdr)
        return false;
    const CLIPRDR_FORMAT_DATA_REQUEST request = {
        .common = { .msgType = CB_FORMAT_DATA_REQUEST },
        .requestedFormatId = formatId,
    };
    const UINT rc = cliprdr->ClientFormatDataRequest(cliprdr, &request);
    clipboard_end(session);
    return rc == CHANNEL_RC_OK;
}

bool sprung_session_clipboard_respond(SprungSession *session, bool ok, const uint8_t *data, size_t size) {
    if (size > UINT32_MAX || (size > 0 && !data))
        ok = false;
    CliprdrClientContext *cliprdr = clipboard_begin(session);
    if (!cliprdr)
        return false;
    const CLIPRDR_FORMAT_DATA_RESPONSE response = {
        .common = {
            .msgType = CB_FORMAT_DATA_RESPONSE,
            .msgFlags = ok ? CB_RESPONSE_OK : CB_RESPONSE_FAIL,
            .dataLen = ok ? (UINT32)size : 0,
        },
        .requestedFormatData = ok ? data : NULL,
    };
    const UINT rc = cliprdr->ClientFormatDataResponse(cliprdr, &response);
    clipboard_end(session);
    return rc == CHANNEL_RC_OK;
}
