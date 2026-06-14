/* HarfBuzz stub header — replace with real HarfBuzz for production.
 * This file declares only the HarfBuzz symbols used by src/11/harfbuzz.zig.
 * Drop real HarfBuzz headers + library here to enable full shaping. */
#pragma once
#include <stdint.h>

typedef struct hb_blob_t hb_blob_t;
typedef struct hb_face_t hb_face_t;
typedef struct hb_font_t hb_font_t;
typedef struct hb_buffer_t hb_buffer_t;
typedef uint32_t hb_codepoint_t;
typedef int32_t hb_position_t;
typedef uint32_t hb_mask_t;
typedef uint32_t hb_tag_t;
typedef uint32_t hb_script_t;
typedef const char* hb_language_t;

typedef enum {
    HB_MEMORY_MODE_READONLY = 1,
} hb_memory_mode_t;

typedef enum {
    HB_DIRECTION_LTR = 4,
    HB_DIRECTION_RTL = 5,
} hb_direction_t;

#define HB_SCRIPT_INVALID 0
#define HB_SCRIPT_LATIN   0x4C61746E
#define HB_SCRIPT_ARABIC  0x41726162
#define HB_SCRIPT_HEBREW  0x48656272

typedef struct {
    hb_codepoint_t codepoint;  /* glyph id after shaping */
    hb_mask_t      mask;
    uint32_t       cluster;
    uint16_t       component;
    uint16_t       lig_id;
    uint32_t       var1;
} hb_glyph_info_t;

typedef struct {
    hb_position_t x_advance;
    hb_position_t y_advance;
    hb_position_t x_offset;
    hb_position_t y_offset;
} hb_glyph_position_t;

typedef void (*hb_destroy_func_t)(void *user_data);

hb_blob_t* hb_blob_create(const char *data, unsigned int length,
    hb_memory_mode_t mode, void *user_data, hb_destroy_func_t destroy);
void hb_blob_destroy(hb_blob_t *blob);

hb_face_t* hb_face_create(hb_blob_t *blob, unsigned int index);
void hb_face_destroy(hb_face_t *face);

hb_font_t* hb_font_create(hb_face_t *face);
void hb_font_set_scale(hb_font_t *font, int x_scale, int y_scale);
void hb_font_destroy(hb_font_t *font);

hb_buffer_t* hb_buffer_create(void);
void hb_buffer_add_utf8(hb_buffer_t *buffer, const char *text, int text_length,
    unsigned int item_offset, int item_length);
void hb_buffer_set_direction(hb_buffer_t *buffer, hb_direction_t direction);
void hb_buffer_set_script(hb_buffer_t *buffer, hb_script_t script);
void hb_buffer_set_language(hb_buffer_t *buffer, hb_language_t language);
void hb_buffer_guess_segment_properties(hb_buffer_t *buffer);
void hb_shape(hb_font_t *font, hb_buffer_t *buffer,
    const void *features, unsigned int num_features);
unsigned int hb_buffer_get_length(hb_buffer_t *buffer);
hb_glyph_info_t* hb_buffer_get_glyph_infos(hb_buffer_t *buffer, unsigned int *length);
hb_glyph_position_t* hb_buffer_get_glyph_positions(hb_buffer_t *buffer, unsigned int *length);
void hb_buffer_destroy(hb_buffer_t *buffer);
hb_language_t hb_language_from_string(const char *str, int len);
hb_script_t hb_script_from_string(const char *str, int len);
