// PDFium's public C API, from Vendor/pdfium (see scripts/fetch-pdfium.sh), plus a save helper
// because FPDF_SaveAsCopy's callback cannot capture Swift state.
#include <stdlib.h>
#include <string.h>
#include "../../Vendor/pdfium/include/fpdfview.h"
#include "../../Vendor/pdfium/include/fpdf_edit.h"
#include "../../Vendor/pdfium/include/fpdf_save.h"
#include "../../Vendor/pdfium/include/fpdf_text.h"
#include "../../Vendor/pdfium/include/fpdf_ppo.h"

typedef struct {
    FPDF_FILEWRITE base;
    unsigned char *bytes;
    size_t size;
    size_t capacity;
} PCBuffer;

static int pc_write_block(FPDF_FILEWRITE *self, const void *data, unsigned long size) {
    PCBuffer *buffer = (PCBuffer *)self;
    if (buffer->size + size > buffer->capacity) {
        size_t capacity = (buffer->capacity + size) * 2;
        unsigned char *grown = realloc(buffer->bytes, capacity);
        if (!grown) return 0;
        buffer->bytes = grown;
        buffer->capacity = capacity;
    }
    memcpy(buffer->bytes + buffer->size, data, size);
    buffer->size += size;
    return 1;
}

/// Saves `document` into a malloc'd buffer the caller frees. Returns 0 on failure.
static inline int PCSaveDocument(FPDF_DOCUMENT document, FPDF_DWORD flags, unsigned char **bytes, size_t *size) {
    PCBuffer buffer = { { 1, pc_write_block }, NULL, 0, 0 };
    if (!FPDF_SaveAsCopy(document, &buffer.base, flags)) { free(buffer.bytes); return 0; }
    *bytes = buffer.bytes;
    *size = buffer.size;
    return 1;
}
