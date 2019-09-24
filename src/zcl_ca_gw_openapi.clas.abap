CLASS zcl_ca_gw_openapi DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.

    INTERFACES zif_ca_gw_openapi .

    METHODS constructor
      IMPORTING
        !iv_service  TYPE /iwfnd/med_mdl_service_grp_id
        !iv_version  TYPE /iwbep/v4_med_service_version DEFAULT '0001'
        !iv_base_url TYPE string OPTIONAL .
    CLASS-METHODS generate_openapi_json_v2
      IMPORTING
        !iv_external_service TYPE /iwfnd/med_mdl_service_grp_id
        !iv_version          TYPE /iwfnd/med_mdl_version DEFAULT '0001'
        !iv_base_url         TYPE string OPTIONAL
      EXPORTING
        !ev_metadata         TYPE xstring
        !ev_metadata_string  TYPE string .

    CLASS-METHODS launch_bsp
      IMPORTING
        !iv_external_service TYPE /iwfnd/med_mdl_service_grp_id
        !iv_version          TYPE /iwfnd/med_mdl_version DEFAULT '0001'
        !iv_json             TYPE xfeld OPTIONAL .
    CLASS-METHODS factory
      IMPORTING
        !iv_service       TYPE /iwfnd/med_mdl_service_grp_id
        !iv_version       TYPE /iwbep/v4_med_service_version DEFAULT '0001'
        !iv_base_url      TYPE string OPTIONAL
      RETURNING
        VALUE(ri_openapi) TYPE REF TO zif_ca_gw_openapi .
  PROTECTED SECTION.
  PRIVATE SECTION.

    DATA mi_metadata_handler TYPE REF TO zif_gw_openapi_metadata .
ENDCLASS.



CLASS zcl_ca_gw_openapi IMPLEMENTATION.


  METHOD constructor.

*   Check that at least a service and version is available, else exception
    IF iv_service IS INITIAL OR iv_version IS INITIAL.

    ENDIF.

    me->mi_metadata_handler = zcl_gw_openapi_metadata_v2=>factory(
                                iv_external_service = iv_service
                                iv_version          = iv_version
                                iv_base_url         = iv_base_url ).

  ENDMETHOD.


  METHOD factory.

*   Return new instance of OpenAPI interface
    ri_openapi ?= NEW zcl_ca_gw_openapi(
      iv_service    = iv_service
      iv_version    = iv_version
      iv_base_url   = iv_base_url ).

  ENDMETHOD.


  METHOD generate_openapi_json_v2.
    DATA: lt_parameters     TYPE abap_trans_parmbind_tab,
          lv_version        TYPE string,
          lv_service        TYPE string,
          lv_path(255)      TYPE c,
          lv_openapi_string TYPE string.

*   Read service details
    SELECT SINGLE h~srv_identifier, h~namespace, h~service_name, h~service_version,  t~description
      FROM /iwfnd/i_med_srh AS h
      LEFT OUTER JOIN /iwfnd/i_med_srt AS t ON  h~srv_identifier = t~srv_identifier
                                            AND h~is_active      = t~is_active
                                            AND t~language       = @sy-langu
      INTO @DATA(ls_service)
      WHERE service_name = @iv_external_service
      AND service_version = @iv_version.

*   Read SICF details
    DATA(lo_icf_access) = /iwfnd/cl_icf_access=>get_icf_access( ).
    DATA(lt_icfdocu) = lo_icf_access->get_icf_docu_for_gw_libs_wo_at( ).

    LOOP AT lt_icfdocu INTO DATA(ls_icfdocu).

*     Get main odata node
      DATA(lv_icf_lib_guid) = lo_icf_access->get_node_guid_wo_at(
                                iv_icf_parent_guid = ls_icfdocu-icfparguid
                                iv_icf_node_name   = CONV icfaltnme( ls_icfdocu-icf_name ) ).

    ENDLOOP.

*   Get OData service URL
    TRY.
        CASE lv_icf_lib_guid.
          WHEN /iwfnd/cl_icf_access=>gcs_icf_node_ids-lib_02.
            DATA(lv_md_url) = /iwfnd/cl_med_utils=>get_meta_data_doc_url_local(
                                  iv_external_service_doc_name = ls_service-service_name
                                  iv_namespace                 = ls_service-namespace
                                  iv_icf_root_node_guid        = lv_icf_lib_guid ).

          WHEN /iwfnd/cl_icf_access=>gcs_icf_node_ids-lib_10.
            lv_md_url = /iwfnd/cl_med_utils=>get_meta_data_doc_url_local(
                            iv_external_service_doc_name = ls_service-service_name
                            iv_namespace                 = ls_service-namespace
                            iv_version                   = ls_service-service_version
                            iv_icf_root_node_guid        = lv_icf_lib_guid ).
        ENDCASE.

      CATCH /iwfnd/cx_med_mdl_access.
    ENDTRY.

*   Remove everything but path from URL
    REPLACE '/?$format=xml' IN lv_md_url WITH ''.
    DATA(lv_md_url_full) = lv_md_url.
    IF lv_md_url IS NOT INITIAL.
      DATA(lv_leng) = strlen( lv_md_url ).
      IF lv_leng > 7 AND lv_md_url(7) = 'http://'.
        SEARCH lv_md_url FOR '/sap/opu/'.
        IF sy-subrc = 0.
          lv_md_url = lv_md_url+sy-fdpos.
        ENDIF.
      ENDIF.
    ENDIF.

*   Set service
    lv_service = ls_service-namespace && ls_service-service_name.

*   Get base URL details
    IF iv_base_url IS NOT INITIAL.
      DATA(lv_base_url) = iv_base_url && lv_md_url.
    ELSE.
      lv_base_url = lv_md_url_full.
    ENDIF.

    SPLIT lv_base_url AT '://' INTO DATA(lv_scheme) DATA(lv_url_without_scheme).
    SPLIT lv_url_without_scheme AT '/' INTO DATA(lv_host) lv_path.

    DATA(lv_length) = strlen( lv_path ) - 1.
    IF lv_path+lv_length(1) = '/'.
      lv_path+lv_length(1) = ''.
    ENDIF.

*   Initialize NetWeaver Gateway transaction handler
    DATA(lo_transaction_handler) = /iwfnd/cl_transaction_handler=>get_transaction_handler( ).

    lo_transaction_handler->set_service_name( iv_name = ls_service-service_name ).
    lo_transaction_handler->set_service_version( iv_version = ls_service-service_version ).
    lo_transaction_handler->set_service_namespace( iv_namespace = ls_service-namespace ).

*   Initialize metadata access
    lo_transaction_handler->set_metadata_access_info(
        iv_load_last_modified_only = abap_true
        iv_is_busi_data_request    = abap_true
        iv_do_cache_handshake      = abap_true ).

*   Load metadata document
    DATA(li_service_factory) = /iwfnd/cl_sodata_svc_factory=>get_svc_factory( ).
    DATA(li_service) = li_service_factory->create_service( iv_name = lv_service ).
    DATA(li_edm) = li_service->get_entity_data_model( ).
    DATA(li_metadata) = li_edm->get_service_metadata( ).

    li_metadata->get_metadata(
      IMPORTING
        ev_metadata = DATA(lv_xml) ).

*   Convert OData V2 to V4 metadata document
    CALL TRANSFORMATION zgw_odatav2_to_v4
      SOURCE XML lv_xml
      RESULT XML DATA(lv_v4).

*   Set transformation parameters
    lv_version = ls_service-service_version.
    SHIFT lv_version LEFT DELETING LEADING '0'.
    lv_version = 'V' && lv_version.

    lt_parameters = VALUE #( ( name = 'openapi-version' value = '3.0.0' )
                             ( name = 'odata-version' value = '2.0' )
                             ( name = 'scheme' value = lv_scheme )
                             ( name = 'host' value = lv_host )
                             ( name = 'basePath' value = '/' && lv_path )
                             ( name = 'info-version' value = lv_version )
                             ( name = 'info-title' value = ls_service-service_name )
                             ( name = 'info-description' value = ls_service-description )
                             ( name = 'references' value = 'YES' )
                             ( name = 'diagram' value = 'YES' ) ).

*   Convert metadata document to openapi
    CALL TRANSFORMATION zgw_odatav4_to_openapi
      SOURCE XML lv_v4
      RESULT XML DATA(lv_openapi)
      PARAMETERS (lt_parameters).

*   Convert binary data to string
    DATA(lo_conv) = cl_abap_conv_in_ce=>create(
                        encoding    = 'UTF-8'
                        input       = lv_openapi ).

    lo_conv->read(
      IMPORTING
        data = lv_openapi_string ).

*   Add basic authentication to OpenAPI JSON
    "REPLACE ALL OCCURRENCES OF '"components":{' IN lv_openapi_string
    "WITH '"components":{"securitySchemes":{"BasicAuth":{"type":"http","scheme":"basic"}},'.

*   Convert OpenAPI JSON to binary format
    CLEAR lv_openapi.
    CALL FUNCTION 'SCMS_STRING_TO_XSTRING'
      EXPORTING
        text   = lv_openapi_string
      IMPORTING
        buffer = lv_openapi
      EXCEPTIONS
        failed = 1
        OTHERS = 2.
    IF sy-subrc <> 0.
* Implement suitable error handling here
    ENDIF.

*   Set exporting parameters
    ev_metadata = lv_openapi.
    ev_metadata_string = lv_openapi_string.

  ENDMETHOD.

  METHOD launch_bsp.
    DATA: lv_url                  TYPE string,
          lv_url_1                TYPE agr_url2,
          lv_appl                 TYPE string,
          lv_page                 TYPE string,
          lt_params               TYPE tihttpnvp,
          lv_answer               TYPE string,
          lv_valueout             TYPE string,
          lv_is_syst_client_valid TYPE abap_bool VALUE abap_false.

    WHILE lv_is_syst_client_valid = abap_false.

      CLEAR: lv_answer, lv_valueout.

      CALL FUNCTION 'POPUP_TO_GET_VALUE'
        EXPORTING
          fieldname           = 'MANDT'
          tabname             = 'T000'
          titel               = 'Enter System Client'
          valuein             = sy-mandt
        IMPORTING
          answer              = lv_answer
          valueout            = lv_valueout
        EXCEPTIONS
          fieldname_not_found = 1
          OTHERS              = 2.

      IF sy-subrc <> 0.
        MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
      ENDIF.

      IF lv_answer = 'C'.
        RETURN.
      ENDIF.

      SELECT SINGLE @abap_true
      FROM t000
      WHERE mandt = @lv_valueout
      INTO @lv_is_syst_client_valid.

      IF lv_is_syst_client_valid = abap_false.
        MESSAGE `Client does not exist. Let's try again?!` TYPE 'I' DISPLAY LIKE 'I'.
      ENDIF.

    ENDWHILE.

*   Set parameters for BSP application
    lt_params = VALUE #( ( name = 'service' value = iv_external_service )
                         ( name = 'version' value = iv_version )
                         ( name = 'sap-client' value = lv_valueout )
                         ( name = 'sap-language' value = sy-langu ) ).

*   Set page
    IF iv_json = abap_false.
      lv_page = 'index.html'.
    ELSE.
      lv_page = 'openapi.json'.
    ENDIF.

*   Generate URL for BSP application
    cl_http_ext_webapp=>create_url_for_bsp_application(
      EXPORTING
        bsp_application      = 'ZCA_GW_OPENAPI'
        bsp_start_page       = lv_page
        bsp_start_parameters = lt_params
      IMPORTING
        abs_url              = lv_url ).

*   Launch BSP application
    lv_url_1 = lv_url.

    CALL FUNCTION 'CALL_BROWSER'
      EXPORTING
        url                    = lv_url_1
*       BROWSER_TYPE           =
*       CONTEXTSTRING          =
      EXCEPTIONS
        frontend_not_supported = 1
        frontend_error         = 2
        prog_not_found         = 3
        no_batch               = 4
        unspecified_error      = 5
        OTHERS                 = 6.

  ENDMETHOD.


  METHOD zif_ca_gw_openapi~get_json.

*   Get JSON data
    me->mi_metadata_handler->get_json(
      IMPORTING
        ev_json        = ev_json
        ev_json_string = ev_json_string ).

  ENDMETHOD.
ENDCLASS.
