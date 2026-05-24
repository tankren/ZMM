*&---------------------------------------------------------------------*
*& Report ZMM_MMPV_MASS_01R
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zmm_mmpv_mass_01r.

************************************************************************
* Function: Update Periods (multiple version)                          *
*                                                                      *
* Author..: REN Chenlong (home.lab)                                    *
* Date....: June 3rd 2025                                              *
*                                                                      *
************************************************************************

* Local types
TYPES: BEGIN OF ty_output,
         status     TYPE icon_d,
         bukrs      TYPE bukrs,
         month(2)   TYPE n,
         year(4)    TYPE n,
         status_txt TYPE string,
       END OF ty_output.

TYPES: BEGIN OF ty_itab,
         bukrs TYPE bukrs,
       END OF ty_itab.

* ALV相关定义
TYPE-POOLS: slis, icon.
DATA: gt_fieldcat TYPE slis_t_fieldcat_alv,
      gs_fieldcat TYPE slis_fieldcat_alv,
      gs_layout   TYPE slis_layout_alv,
      gt_events   TYPE slis_t_event,
      gs_event    TYPE slis_alv_event.

* 数据定义
DATA: gt_itab   TYPE STANDARD TABLE OF ty_itab,
      gs_itab   TYPE ty_itab.

DATA: gt_output TYPE STANDARD TABLE OF ty_output,
      gs_output TYPE ty_output.

DATA: gs_marv TYPE marv.

DATA: z_act_month_1st LIKE sy-datum.
DATA: z_old_month_1st LIKE sy-datum.
DATA: z_month(2) TYPE n.
DATA: z_year(4)  TYPE n.
DATA: z_datum    LIKE rm03q-datum.
DATA: counter TYPE i.
DATA: retc LIKE sy-subrc.
DATA: lfd_nr TYPE p.
DATA: lv_month TYPE numc2.
DATA: lv_year  TYPE numc4.

* 参数定义
SELECT-OPTIONS: s_bukrs FOR bukrs DEFAULT '0001' TO 'ZZZZ'.
SELECTION-SCREEN ULINE /1(30).
PARAMETERS: p_test  AS CHECKBOX.
PARAMETERS: p_result AS CHECKBOX DEFAULT 'X'.

*----------------------------------------------------------------------*
* AT SELECTION-SCREEN
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF p_test = 'X' AND ( sy-binpt = 'X' OR sy-batch = 'X' OR sy-ucomm = 'SJOB' ).
    MESSAGE 'Test Run is not allowed in background job' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  PERFORM main_process.

*----------------------------------------------------------------------*
* FORM main_process
*----------------------------------------------------------------------*
FORM main_process.
  CLEAR gt_output[].

  z_act_month_1st = sy-datum.
  z_act_month_1st+6(2) = '01'.

  SELECT bukrs
         FROM t001 INTO TABLE gt_itab
         WHERE bukrs IN s_bukrs.

  LOOP AT gt_itab INTO gs_itab.
    AUTHORITY-CHECK OBJECT 'F_BKPF_BUK'
      ID 'ACTVT' FIELD '02'
      ID 'BUKRS' FIELD gs_itab-bukrs.
    IF sy-subrc <> 0.
      PERFORM add_output_record USING:
        icon_red_light
        gs_itab-bukrs
        0
        0
        'No authorization'.
      CONTINUE.
    ENDIF.

    SELECT SINGLE * FROM marv INTO gs_marv
           WHERE bukrs = gs_itab-bukrs.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    z_old_month_1st(4)   = gs_marv-lfgja.
    z_old_month_1st+4(2) = gs_marv-lfmon.
    z_old_month_1st+6(2) = '01'.
    z_month = z_old_month_1st+4(2).
    z_year  = z_old_month_1st(4).

    "当前年月则不做任何更新
    IF z_month = sy-datum+4(2) AND z_year = sy-datum(4).
      PERFORM add_output_record USING:
               icon_red_light
               gs_itab-bukrs
               z_month
               z_year
               'No need to update'.
      CONTINUE.
    ENDIF.

    WHILE z_old_month_1st < z_act_month_1st.
      lv_month = z_old_month_1st+4(2).
      lv_year  = z_old_month_1st(4).
      lv_month = lv_month + 1.
      IF lv_month > 12.
        lv_month = lv_month - 12.
        lv_year  = lv_year + 1.
      ENDIF.
      z_old_month_1st(4)   = lv_year.
      z_old_month_1st+4(2) = lv_month.
      z_old_month_1st+6(2) = '01'.
      z_month = lv_month.
      z_year  = lv_year.

      "更新记录 - 初始状态为黄灯
      PERFORM add_output_record USING:
               icon_yellow_light
               gs_itab-bukrs
               z_month
               z_year
               'Not processed'.

      IF p_test <> 'X'.
        CLEAR z_datum.
        z_datum(4)   = z_year.
        z_datum+4(2) = z_month.
        z_datum+6(2) = '01.'.

        SUBMIT rmmmperi
                WITH i_bbukr = gs_itab-bukrs
                WITH i_datum = z_datum
                WITH i_vbukr = gs_itab-bukrs
                WITH i_xcomp = 'X'
                WITH i_xinco = ' '
                WITH i_xmove = ' '
                WITH i_xnegq = 'X'
                WITH i_xnegv = 'X'
                EXPORTING LIST TO MEMORY
                AND RETURN.

        retc = sy-subrc.

        "更新状态
        IF retc = 0.
          PERFORM update_status USING:
                   gs_itab-bukrs
                   z_month
                   z_year
                   icon_green_light
                   'Successful'.
        ELSE.
          PERFORM update_status USING:
                   gs_itab-bukrs
                   z_month
                   z_year
                   icon_red_light
                   'Error occurred'.
        ENDIF.

        IF p_result = 'X'.
          PERFORM display_protocol.
        ENDIF.
      ENDIF.
    ENDWHILE.
  ENDLOOP.

  "显示ALV
  PERFORM build_field_catalog.
  PERFORM display_alv_report.
ENDFORM.

*----------------------------------------------------------------------*
* FORM add_output_record
*----------------------------------------------------------------------*
FORM add_output_record USING p_status p_bukrs p_month p_year p_status_txt.
  gs_output-status     = p_status.
  gs_output-bukrs      = p_bukrs.
  gs_output-month      = p_month.
  gs_output-year       = p_year.
  gs_output-status_txt = p_status_txt.
  APPEND gs_output TO gt_output.
ENDFORM.

*----------------------------------------------------------------------*
* FORM update_status
*----------------------------------------------------------------------*
FORM update_status USING p_bukrs p_month p_year p_status p_status_txt.
  READ TABLE gt_output INTO gs_output WITH KEY bukrs = p_bukrs month = p_month year = p_year.
  IF sy-subrc = 0.
    gs_output-status     = p_status.
    gs_output-status_txt = p_status_txt.
    MODIFY gt_output FROM gs_output INDEX sy-tabix.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* FORM display_protocol
*----------------------------------------------------------------------*
FORM display_protocol.
  DATA: lt_list TYPE TABLE OF abaplist.
  CALL FUNCTION 'LIST_FROM_MEMORY'
    TABLES
      listobject = lt_list.
  "可以将协议内容添加到输出表中
ENDFORM.

*----------------------------------------------------------------------*
* FORM build_field_catalog
*----------------------------------------------------------------------*
FORM build_field_catalog.
  CLEAR gt_fieldcat[].

  "状态灯栏位(放在最前面)
  PERFORM add_field_catalog USING:
    'STATUS'     'Status'        ' '      ' '       'ICON'    '4'    ' '   'CENTER'.

  "其他栏位
  PERFORM add_field_catalog USING:
    'BUKRS'      'Company Code'  'T001'   'BUKRS'   'CHAR'    '10'   ' '   'LEFT',
    'MONTH'      'Month'         ' '      ' '       'NUMC'    '2'    ' '   'LEFT',
    'YEAR'       'Year'          ' '      ' '       'NUMC'    '4'    ' '   'LEFT',
    'STATUS_TXT' 'Status Text'   ' '      ' '       'CHAR'    '40'   ' '   'LEFT'.
ENDFORM.

*----------------------------------------------------------------------*
* FORM add_field_catalog
*----------------------------------------------------------------------*
FORM add_field_catalog USING p_fieldname p_seltext p_tabname p_field p_datatype p_outputlen p_key p_just.
  CLEAR gs_fieldcat.
  gs_fieldcat-fieldname   = p_fieldname.
  gs_fieldcat-seltext_m   = p_seltext.
  gs_fieldcat-tabname     = p_tabname.
  gs_fieldcat-ref_fieldname = p_field.
  gs_fieldcat-datatype    = p_datatype.
  gs_fieldcat-outputlen   = p_outputlen.
  gs_fieldcat-key         = p_key.
  gs_fieldcat-just        = p_just.
  APPEND gs_fieldcat TO gt_fieldcat.
ENDFORM.

*----------------------------------------------------------------------*
* FORM display_alv_report
*----------------------------------------------------------------------*
FORM display_alv_report.
  gs_layout-colwidth_optimize = 'X'.
  gs_layout-zebra = 'X'.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program = sy-repid
      is_layout          = gs_layout
      it_fieldcat        = gt_fieldcat
    TABLES
      t_outtab           = gt_output
    EXCEPTIONS
      program_error      = 1
      OTHERS             = 2.
  IF sy-subrc <> 0.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
  ENDIF.
ENDFORM.
