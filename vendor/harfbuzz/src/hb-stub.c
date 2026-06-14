/* HarfBuzz stub implementation — replace with real HarfBuzz for production.
 * These no-op implementations let the project compile and link without the
 * real HarfBuzz library. The stub shaper returns one glyph per input byte
 * (identity mapping) so ASCII text renders correctly in tests. */
#include "hb.h"
#include <stdlib.h>
#include <string.h>

/* Opaque type implementations (minimal) */
struct hb_blob_t  { const char *data; unsigned int length; };
struct hb_face_t  { int dummy; };
struct hb_font_t  { int x_scale; int y_scale; };

#define MAX_GLYPHS 4096
struct hb_buffer_t {
    const char *text;
    int text_len;
    unsigned int glyph_count;
    hb_glyph_info_t     infos[MAX_GLYPHS];
    hb_glyph_position_t positions[MAX_GLYPHS];
};

hb_blob_t* hb_blob_create(const char *data, unsigned int length,
    hb_memory_mode_t mode, void *user_data, hb_destroy_func_t destroy) {
    (void)mode; (void)user_data; (void)destroy;
    hb_blob_t *b = (hb_blob_t*)malloc(sizeof(hb_blob_t));
    if (!b) return NULL;
    b->data = data; b->length = length;
    return b;
}
void hb_blob_destroy(hb_blob_t *blob) { free(blob); }

hb_face_t* hb_face_create(hb_blob_t *blob, unsigned int index) {
    (void)blob; (void)index;
    hb_face_t *f = (hb_face_t*)malloc(sizeof(hb_face_t));
    if (!f) return NULL; f->dummy = 0; return f;
}
void hb_face_destroy(hb_face_t *face) { free(face); }

hb_font_t* hb_font_create(hb_face_t *face) {
    (void)face;
    hb_font_t *f = (hb_font_t*)malloc(sizeof(hb_font_t));
    if (!f) return NULL; f->x_scale = 0; f->y_scale = 0; return f;
}
void hb_font_set_scale(hb_font_t *font, int x_scale, int y_scale) {
    font->x_scale = x_scale; font->y_scale = y_scale;
}
void hb_font_destroy(hb_font_t *font) { free(font); }

hb_buffer_t* hb_buffer_create(void) {
    hb_buffer_t *b = (hb_buffer_t*)calloc(1, sizeof(hb_buffer_t));
    return b;
}
void hb_buffer_add_utf8(hb_buffer_t *buffer, const char *text, int text_length,
    unsigned int item_offset, int item_length) {
    (void)item_offset; (void)item_length;
    buffer->text = text;
    buffer->text_len = text_length < 0 ? (int)strlen(text) : text_length;
}
void hb_buffer_set_direction(hb_buffer_t *buf, hb_direction_t dir) { (void)buf; (void)dir; }
void hb_buffer_set_script(hb_buffer_t *buf, hb_script_t s) { (void)buf; (void)s; }
void hb_buffer_set_language(hb_buffer_t *buf, hb_language_t l) { (void)buf; (void)l; }
void hb_buffer_guess_segment_properties(hb_buffer_t *buf) { (void)buf; }

void hb_shape(hb_font_t *font, hb_buffer_t *buf,
    const void *features, unsigned int num_features) {
    (void)features; (void)num_features;
    /* Stub: output one glyph per input byte with identity mapping.
     * Real HarfBuzz would produce shaped glyphs with cluster boundaries. */
    int len = buf->text_len < 0 ? 0 : buf->text_len;
    if (len > MAX_GLYPHS) len = MAX_GLYPHS;
    buf->glyph_count = (unsigned int)len;
    for (int i = 0; i < len; i++) {
        buf->infos[i].codepoint = (unsigned char)buf->text[i]; /* identity */
        buf->infos[i].cluster   = (unsigned int)i;
        buf->infos[i].mask      = 0;
        buf->infos[i].component = 0;
        buf->infos[i].lig_id    = 0;
        buf->infos[i].var1      = 0;
        /* x_advance in 26.6 fixed-point; scale / 64 gives pixel advance */
        buf->positions[i].x_advance = font->x_scale > 0 ? font->x_scale / 64 : 512; /* ~8px at 64/64 */
        buf->positions[i].y_advance = 0;
        buf->positions[i].x_offset  = 0;
        buf->positions[i].y_offset  = 0;
    }
}
unsigned int hb_buffer_get_length(hb_buffer_t *buf) { return buf->glyph_count; }
hb_glyph_info_t* hb_buffer_get_glyph_infos(hb_buffer_t *buf, unsigned int *len) {
    if (len) *len = buf->glyph_count; return buf->infos;
}
hb_glyph_position_t* hb_buffer_get_glyph_positions(hb_buffer_t *buf, unsigned int *len) {
    if (len) *len = buf->glyph_count; return buf->positions;
}
void hb_buffer_destroy(hb_buffer_t *buf) { free(buf); }
hb_language_t hb_language_from_string(const char *str, int len) { (void)str; (void)len; return NULL; }
hb_script_t hb_script_from_string(const char *str, int len) { (void)str; (void)len; return 0; }
