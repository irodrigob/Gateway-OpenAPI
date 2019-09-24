*&---------------------------------------------------------------------*
*& Report ZCA_GW_OPENAPI
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zca_gw_openapi.

INCLUDE: zca_gw_openapi_top.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK bl1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS: s_name2 FOR /iwfnd/i_med_srh-service_name,
                s_vers2 FOR /iwfnd/i_med_srh-service_version.
SELECTION-SCREEN END OF BLOCK bl1.

SELECTION-SCREEN BEGIN OF BLOCK bl2 WITH FRAME TITLE TEXT-002.
PARAMETERS: p_ui   TYPE xfeld RADIOBUTTON GROUP rdb2 DEFAULT 'X' USER-COMMAND ent1,
            p_json TYPE xfeld RADIOBUTTON GROUP rdb2.
SELECTION-SCREEN END OF BLOCK bl2.

INCLUDE zca_gw_openapi_class.

*----------------------------------------------------------------------*
* PBO
*----------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
  lcl_screen_handler=>handle_pbo( ).

*----------------------------------------------------------------------*
* PAI
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  lcl_screen_handler=>handle_pai( iv_ok_code = sy-ucomm ).
  CLEAR sy-ucomm.
