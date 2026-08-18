#include "receiver_profile.h"

#include <string.h>

int tb_receiver_profile_from_dimensions(uint32_t logical_w,
                                        uint32_t logical_h,
                                        uint32_t panel_w,
                                        uint32_t panel_h,
                                        struct tb_receiver_profile *out) {
    if (!out || !panel_w || !panel_h) return -1;

    memset(out, 0, sizeof(*out));
    out->panel_w = panel_w;
    out->panel_h = panel_h;
    out->capture_w = panel_w;
    out->capture_h = panel_h;

    const int hi_dpi = logical_w && logical_h &&
        panel_w >= logical_w * 2 && panel_h >= logical_h * 2;
    out->hi_dpi = hi_dpi;
    out->mode_w = hi_dpi ? logical_w : panel_w;
    out->mode_h = hi_dpi ? logical_h : panel_h;
    return 0;
}
