/* receiver_profile.h — sender-facing geometry derived from the receiver panel. */

#ifndef TB_RECEIVER_PROFILE_H
#define TB_RECEIVER_PROFILE_H

#include <stdint.h>

struct tb_receiver_profile {
    uint32_t panel_w;
    uint32_t panel_h;
    uint32_t mode_w;
    uint32_t mode_h;
    uint32_t capture_w;
    uint32_t capture_h;
    int hi_dpi;
};

/* Build the DISPLAY_PROFILE dimensions from the receiver's logical desktop
 * mode and its native panel pixels. A Retina panel is advertised as HiDPI
 * only when its backing dimensions are at least 2x the logical mode. */
int tb_receiver_profile_from_dimensions(uint32_t logical_w,
                                        uint32_t logical_h,
                                        uint32_t panel_w,
                                        uint32_t panel_h,
                                        struct tb_receiver_profile *out);

#endif
