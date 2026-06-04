package fixed_point_pkg;

    // ============================================================
    // Main dimensions
    // ============================================================

    parameter int NT = 4;
    parameter int NR = 4;

    // ============================================================
    // Fixed-point formats
    // ============================================================
    // Qm.n notation here means:
    // total signed width = m + n
    // fractional bits = n
    //
    // H, y      : Q4.12  -> 16 bits
    // G, b, W   : Q8.12  -> 20 bits
    // ACC       : Q12.16 -> 28 bits
    // x         : Q6.16  -> 22 bits
    // x_out     : Q4.12  -> 16 bits
    // ============================================================

    parameter int H_W      = 16;
    parameter int H_FRAC   = 12;

    parameter int Y_W      = 16;
    parameter int Y_FRAC   = 12;

    parameter int GBW_W    = 20;
    parameter int GBW_FRAC = 12;

    parameter int ACC_W    = 28;
    parameter int ACC_FRAC = 16;

    parameter int X_W      = 22;
    parameter int X_FRAC   = 16;

    parameter int XOUT_W   = 16;
    parameter int XOUT_FRAC = 12;

    // ============================================================
    // Complex fixed-point structs
    // ============================================================

    typedef struct packed {
        logic signed [H_W-1:0] re;
        logic signed [H_W-1:0] im;
    } complex_h_t;

    typedef struct packed {
        logic signed [Y_W-1:0] re;
        logic signed [Y_W-1:0] im;
    } complex_y_t;

    typedef struct packed {
        logic signed [GBW_W-1:0] re;
        logic signed [GBW_W-1:0] im;
    } complex_gbw_t;

    typedef struct packed {
        logic signed [ACC_W-1:0] re;
        logic signed [ACC_W-1:0] im;
    } complex_acc_t;

    typedef struct packed {
        logic signed [X_W-1:0] re;
        logic signed [X_W-1:0] im;
    } complex_x_t;

    typedef struct packed {
        logic signed [XOUT_W-1:0] re;
        logic signed [XOUT_W-1:0] im;
    } complex_xout_t;

    // ============================================================
    // Mode encoding
    // ============================================================

    typedef enum logic [1:0] {
        MODE_GS4  = 2'd0,
        MODE_GS8  = 2'd1,
        MODE_GS16 = 2'd2
    } gs_mode_t;

endpackage