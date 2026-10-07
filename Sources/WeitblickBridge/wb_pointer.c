// Server cursor shapes, handed to the app as BGRA32 images with ids.
#include "wb_internal.h"

#include <stdlib.h>

#include <freerdp/gdi/gdi.h>
#include <freerdp/graphics.h>

typedef struct {
    rdpPointer pointer; // must stay first
    uint64_t id;
} WBPointer;

static BOOL on_pointer_new(rdpContext *context, rdpPointer *pointer) {
    WBSession *session = wb_session_from_context(context);
    WBPointer *sp = (WBPointer *)pointer;
    sp->id = atomic_fetch_add(&session->nextPointerId, 1) + 1;

    const size_t size = (size_t)pointer->width * pointer->height * 4;
    if (size == 0 || !session->callbacks.pointerNew)
        return TRUE;
    uint8_t *pixels = calloc(1, size);
    if (!pixels)
        return FALSE;
    const BOOL ok = freerdp_image_copy_from_pointer_data(
        pixels, PIXEL_FORMAT_BGRA32, 0, 0, 0, pointer->width, pointer->height,
        pointer->xorMaskData, pointer->lengthXorMask, pointer->andMaskData, pointer->lengthAndMask,
        pointer->xorBpp, &context->gdi->palette);
    if (ok)
        session->callbacks.pointerNew(session->callbacks.userData, sp->id, pixels, pointer->width,
                                      pointer->height, pointer->xPos, pointer->yPos);
    free(pixels);
    return ok;
}

static void on_pointer_free(rdpContext *context, rdpPointer *pointer) {
    WBSession *session = wb_session_from_context(context);
    const uint64_t id = ((WBPointer *)pointer)->id;
    if (id && session->callbacks.pointerFree)
        session->callbacks.pointerFree(session->callbacks.userData, id);
}

static BOOL on_pointer_set(rdpContext *context, rdpPointer *pointer) {
    WBSession *session = wb_session_from_context(context);
    if (session->callbacks.pointerSet)
        session->callbacks.pointerSet(session->callbacks.userData, ((WBPointer *)pointer)->id);
    return TRUE;
}

static BOOL on_pointer_set_null(rdpContext *context) {
    WBSession *session = wb_session_from_context(context);
    if (session->callbacks.pointerSetNull)
        session->callbacks.pointerSetNull(session->callbacks.userData);
    return TRUE;
}

static BOOL on_pointer_set_default(rdpContext *context) {
    WBSession *session = wb_session_from_context(context);
    if (session->callbacks.pointerSetDefault)
        session->callbacks.pointerSetDefault(session->callbacks.userData);
    return TRUE;
}

static BOOL on_pointer_set_position(rdpContext *context, UINT32 x, UINT32 y) {
    WBSession *session = wb_session_from_context(context);
    if (session->callbacks.pointerPosition)
        session->callbacks.pointerPosition(session->callbacks.userData, x, y);
    return TRUE;
}

void wb_pointer_register(rdpContext *context) {
    rdpPointer pointer = { 0 };
    pointer.size = sizeof(WBPointer);
    pointer.New = on_pointer_new;
    pointer.Free = on_pointer_free;
    pointer.Set = on_pointer_set;
    pointer.SetNull = on_pointer_set_null;
    pointer.SetDefault = on_pointer_set_default;
    pointer.SetPosition = on_pointer_set_position;
    graphics_register_pointer(context->graphics, &pointer);
}
