*&---------------------------------------------------------------------*
*& Include          ZCA_GW_OPENAPI_CLASS
*&---------------------------------------------------------------------*

CLASS lcl_screen_handler DEFINITION CREATE PRIVATE.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_v2_service_s,
             service_name    TYPE /iwfnd/med_mdl_service_grp_id,
             service_version TYPE /iwfnd/med_mdl_version,
             created_by      TYPE cruser,
             created_at      TYPE timestamp,
             created_date    TYPE d,
             created_time    TYPE t,
             changed_by      TYPE chuser,
             changed_at      TYPE timestamp,
             changed_date    TYPE d,
             changed_time    TYPE t,
             description     TYPE /iwfnd/med_mdl_srg_description,
             devclass        TYPE devclass,
           END OF ty_v2_service_s.

    CLASS-METHODS handle_pbo.
    CLASS-METHODS handle_pai IMPORTING iv_ok_code TYPE syucomm.
  PRIVATE SECTION.
    CLASS-METHODS get_v2_data.
    CLASS-METHODS display_alv.
    CLASS-METHODS columns_alv_v2
      CHANGING
        co_columns TYPE REF TO cl_salv_columns_table.

    CLASS-METHODS handle_link_click
                FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row
                column.

    CLASS-DATA: gt_v2_data TYPE TABLE OF ty_v2_service_s.

ENDCLASS.


CLASS lcl_screen_handler IMPLEMENTATION.

  METHOD handle_pbo.

  ENDMETHOD.

  METHOD handle_pai.

    CASE iv_ok_code.
      WHEN 'CRET' OR 'ONLI'.
        get_v2_data( ).

        display_alv( ).

      WHEN OTHERS.

    ENDCASE.

  ENDMETHOD.

  METHOD get_v2_data.

*   Read service details
    SELECT h~service_name,
           h~service_version,
           h~created_by,
           h~created_timestmp AS created_at,
           h~changed_by,
           h~changed_timestmp AS changed_at,
           t~description,
           p~devclass
      FROM /iwfnd/i_med_srh AS h
      LEFT OUTER JOIN /iwfnd/i_med_srt AS t ON  h~srv_identifier = t~srv_identifier
                                            AND h~is_active      = t~is_active
                                            AND t~language       = @sy-langu
      INNER JOIN tadir AS p ON p~obj_name = h~srv_identifier
      WHERE h~service_name IN @s_name2
        AND h~service_version IN @s_vers2
        AND h~is_active = 'A'
        AND p~pgmid     = 'R3TR'
        AND p~object    = 'IWSG'
      INTO CORRESPONDING FIELDS OF TABLE @gt_v2_data.

    LOOP AT gt_v2_data ASSIGNING FIELD-SYMBOL(<data>).
      CONVERT TIME STAMP <data>-created_at TIME ZONE sy-zonlo INTO DATE <data>-created_date TIME <data>-created_time.
      CONVERT TIME STAMP <data>-changed_at TIME ZONE sy-zonlo INTO DATE <data>-changed_date TIME <data>-changed_time.
    ENDLOOP.

  ENDMETHOD.
  METHOD display_alv.
    TRY.
        cl_salv_table=>factory(
        IMPORTING
          r_salv_table   = DATA(lo_alv)
        CHANGING
          t_table        = gt_v2_data ).

*   Enable all standard ALV functions
        lo_alv->get_functions( )->set_all( abap_true ).

*   Update field catalog
        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( ).

        " Set Zebra Pattern
        lo_alv->get_display_settings( )->set_striped_pattern( 'X' ).

        " Set attributes for the columns
        columns_alv_v2( CHANGING co_columns = lo_columns ).

*   Enable events
        DATA(lo_events) = lo_alv->get_event( ).
        SET HANDLER handle_link_click FOR lo_events.

*   Display ALV
        lo_alv->display( ).
      CATCH cx_salv_msg.

    ENDTRY.

  ENDMETHOD.
  METHOD handle_link_click.

    READ TABLE gt_v2_data INTO DATA(ls_v2_data) INDEX row.
    zcl_ca_gw_openapi=>launch_bsp(
        iv_external_service = ls_v2_data-service_name
        iv_version          = ls_v2_data-service_version
        iv_json             = p_json ).


  ENDMETHOD.


  METHOD columns_alv_v2.

    TRY.
        DATA(lo_column) = CAST cl_salv_column_table( co_columns->get_column( columnname = 'SERVICE_NAME' ) ).
        lo_column->set_cell_type( if_salv_c_cell_type=>hotspot ).

        lo_column ?= co_columns->get_column( columnname = 'CREATED_AT' ).
        lo_column->set_technical( ).

        lo_column ?= co_columns->get_column( columnname = 'CREATED_DATE' ).
        lo_column->set_short_text( 'Created Dt' ).
        lo_column->set_medium_text( 'Created Date' ).
        lo_column->set_long_text( 'Created Date' ).

        lo_column ?= co_columns->get_column( columnname = 'CREATED_TIME' ).
        lo_column->set_short_text( 'Created Tm' ).
        lo_column->set_medium_text( 'Created Time' ).
        lo_column->set_long_text( 'Created Time' ).

        lo_column ?= co_columns->get_column( columnname = 'CHANGED_AT' ).
        lo_column->set_technical( ).

        lo_column ?= co_columns->get_column( columnname = 'CHANGED_DATE' ).
        lo_column->set_short_text( 'Changed Dt' ).
        lo_column->set_medium_text( 'Changed Date' ).
        lo_column->set_long_text( 'Changed Date' ).

        lo_column ?= co_columns->get_column( columnname = 'CHANGED_TIME' ).
        lo_column->set_short_text( 'Changed Tm' ).
        lo_column->set_medium_text( 'Changed Time' ).
        lo_column->set_long_text( 'Changed Time' ).
      CATCH cx_root.
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
