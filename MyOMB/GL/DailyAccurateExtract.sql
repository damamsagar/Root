/*============================================================================================================+
| Report Name        : Old Mutual - GL - Journal Lines Extract Child Report
| Report DM Name     : Old Mutual - GL - Journal Lines Extract Child DM
| Report Location    : Shared Folders/Custom/Integration/Extracts/Journal Lines Extract Job Set
| Report DM Location : Shared Folders/Custom/Integration/Extracts/Journal Lines Extract Job Set
| Report Parameters  : program_code
|                      manual_date
|                      manual_date_to
|                      p_period_name
|                      p_batch_name
|                      p_from_batch#
|                      p_to_batch#
|                      p_je_batch_id
|                      balancing_entity
|                      accounts
|                      from_accounts
|                      to_accounts
|                      budget_center
|                      ledger_name
|                      p_header_id
|                      p_open_period
|                      p_include_adjustment
+-------------------------------------------------------------------------------------------------------------+
| Description: GL journal lines outbound extracts - GL Journal Lines Extract (Child)
+-------------------------------------------------------------------------------------------------------------+
| History:
| Author          | Date       | Version | Description
+-----------------------------------------------------------------------------+
|                 |            | 1.0     | Initial creation
| Christo Classen | 22-02-2023 | 1.1     | INC0038148/CEN-1661 GL - Outbound extract (MCS) Multiple Accounting Dates
| Rowan Philander | 22-08-2023 | 1.2     | BSR1626102 - CEN-71: Multi currency recon: Outbound Extract Enhancement Request
|                                                     - CEN-2746: Accurate Outbounds - Balance Sheet Accounts 
|                                                     - CEN-3083: Outbounds Misalignment: Columns Shifting due to Pipe Delimiter causing misalignment
|
+============================================================================================================*/WITH attr_details AS (
    SELECT
        headers.application_id         fah_appl_id,
        headers.event_id               fah_event_id,
        headers.transaction_number     fah_trx_num,
        lines.line_number,
        replace(lines.char3, '|', ' ') attribute1, --defect 178
        lines.long_char1               attribute2,
        lines.long_char2               attribute3,
        lines.long_char3               attribute4,
        lines.char4 || lines.char5     "ATTRIBUTE5",
        lines.char6 || lines.char7     "ATTRIBUTE6",
        lines.char8 || lines.char9     "ATTRIBUTE7",
        lines.char10 || lines.char11   "ATTRIBUTE8",
        lines.char12 || lines.char13   "ATTRIBUTE9",
        lines.char14 || lines.char15   "ATTRIBUTE10",
        lines.char16 || lines.char17   "ATTRIBUTE11",
        lines.char18 || lines.char19   "ATTRIBUTE12",
        lines.char20 || lines.char21   "ATTRIBUTE13",
        lines.char22 || lines.char23   "ATTRIBUTE14",
        lines.char24 || lines.char25   "ATTRIBUTE15",
        lines.char26 || lines.char27   "ATTRIBUTE16",
        lines.char28 || lines.char29   "ATTRIBUTE17",
        lines.char31 || lines.char31   "ATTRIBUTE18",
        lines.char32 || lines.char33   "ATTRIBUTE19",
        lines.char34 || lines.char35   "ATTRIBUTE20",
        lines.char36                   "ATTRIBUTE21",
        lines.char37                   "ATTRIBUTE22",
        lines.char38                   "ATTRIBUTE23",
        lines.char39                   "ATTRIBUTE24",
        lines.char40                   "ATTRIBUTE25",
        lines.char41                   "ATTRIBUTE26",
        lines.char42                   "ATTRIBUTE27",
        lines.char43                   "ATTRIBUTE28",
        lines.long_char4               fahkey,
        headers.char10                 source_name,
        lines.date1                    acc_date                           -- #INC0038148 - selecting DATE1 to return the expected Accounting Date as per Inbound interface for MCS
    FROM
        --adxx_xla_h_fahom_corp   headers,
       -- adxx_xla_l_fahom_corp   lines
        xla_transaction_headers headers,
        xla_transaction_lines   lines,
        xla_subledgers_tl       xst
    WHERE
            headers.application_id = lines.application_id
        AND headers.event_id = lines.event_id
        AND lines.application_id = xst.application_id
        AND xst.application_name LIKE 'FAH%'
        AND xst.language = 'US'
), xx_dril_delimit AS (
    SELECT
        attribute7  delimiter,
        attribute11 drilldown
    FROM
        fnd_lookup_values flv_be
    WHERE
            flv_be.lookup_type = 'XXGL_EXTRACT_FILE_INFO'
        AND flv_be.lookup_code = :program_code
        AND flv_be.enabled_flag = 'Y'
        AND ROWNUM = 1                                                  --tuning, added ROWNUM to ensure only 1 record
), xxgl_lkp AS (
    SELECT
        flv.attribute1 program_code,
        flv.attribute2 ledger_name,
        flv.attribute3 balancing_entity,
        flv.attribute4 budget_center,
        flv.attribute5 accounts,
        gl.ledger_id
    FROM
        fnd_lookup_values flv,
        gl_ledgers        gl
    WHERE
            flv.lookup_type = 'XXGL_EXTRACT_CRITERIA'
        AND flv.attribute1 = :program_code
			  --AND flv.attribute1 LIKE 'ACCURATE_LINE%'
        AND nvl(flv.attribute2,
                nvl(:ledger_name, 'x')) = nvl(:ledger_name,
                                              nvl(flv.attribute2, 'x'))
        AND nvl(flv.attribute3,
                nvl(:balancing_entity, 'x')) = nvl(:balancing_entity,
                                                   nvl(flv.attribute3, 'x'))
        AND nvl(flv.attribute4,
                nvl(:budget_center, 'x')) = nvl(:budget_center,
                                                nvl(flv.attribute4, 'x'))
        AND nvl(flv.attribute5,
                nvl(:accounts, 'x')) = nvl(:accounts,
                                           nvl(flv.attribute5, 'x'))
        AND nvl(flv.attribute5,
                nvl(:from_accounts, 1)) BETWEEN nvl(:from_accounts,
                                                    nvl(flv.attribute5, 1)) AND nvl(:to_accounts,
                                                                                    nvl(flv.attribute5, 1))
        AND nvl(flv.enabled_flag, 'N') = 'Y'
        AND gl.name (+) = flv.attribute2
        AND trunc(sysdate) BETWEEN trunc(nvl(flv.start_date_active, sysdate)) AND trunc(nvl(flv.end_date_active, sysdate))
), xx_fdate AS (
    SELECT
        sysdate from_processstart
    FROM
        dual
), xx_tdate AS (
    SELECT
        sysdate to_processstart
    FROM
        dual
), xx_fdate_dnu AS (
    SELECT
        *
    FROM
        (
            SELECT
                ROWNUM         from_rownum,
                d.processstart from_processstart
            FROM
                (
                    SELECT
                        erh.processstart
                    FROM
                        ess_request_history  erh,
                        ess_request_property erp
                    WHERE
                            erh.requestid = erp.requestid
                        AND erh.definition LIKE '%OMB_INT_GL_LINES_P_EXT'
                        AND erp.name LIKE 'submit.argument1'
                        AND erp.value LIKE :program_code
                        AND erh.executable_status = 'SUCCEEDED'
                    UNION
                    SELECT
                        TO_DATE(tag, 'MM-DD-YYYY HH24:MI:SS') processstart
                    FROM
                        fnd_lookup_values flv_be
                    WHERE
                            flv_be.lookup_type = 'XXGL_EXTRACT_FILE_INFO'
                        AND flv_be.lookup_code = :program_code
                    ORDER BY
                        processstart DESC
                ) d
            FETCH FIRST 2 ROWS ONLY
        ) fdate1
    WHERE
            1 = 1
        AND fdate1.from_rownum = 2
), xx_from_date_ds AS (
    SELECT
        from_processstart
    FROM
        (
            SELECT
                ROWNUM         from_rownum,
                d.processstart from_processstart
            FROM
                (
                    SELECT
                        erh.processstart
                    FROM
                        ess_request_history  erh,
                        ess_request_property erp
                    WHERE
                            erh.requestid = erp.requestid
                        AND erh.definition LIKE '%OMB_INT_GL_LINES_P_EXT'
                        AND erp.name LIKE 'submit.argument1'
                        AND erp.value LIKE :program_code
                        AND erh.executable_status = 'SUCCEEDED'
                        AND erh.processstart <= sysdate - ( 15 / 86400 )
                    UNION
                    SELECT
                        sysdate - 1000
                    FROM
                        dual
                    ORDER BY
                        processstart DESC
                ) d
            FETCH FIRST 1 ROWS ONLY
        )
), xx_tdate_dnu AS (
    SELECT
        *
    FROM
        (
            SELECT
                ROWNUM         to_rownum,
                d.processstart to_processstart
            FROM
                (
                    SELECT
                        erh.processstart
                    FROM
                        ess_request_history  erh,
                        ess_request_property erp
                    WHERE
                            erh.requestid = erp.requestid
                        AND erh.definition LIKE '%OMB_INT_GL_LINES_P_EXT'
                        AND erp.name LIKE 'submit.argument1'
                        AND erp.value LIKE :program_code
                        AND erh.executable_status = 'SUCCEEDED'
                    ORDER BY
                        erh.processstart DESC
                ) d
            FETCH FIRST 2 ROWS ONLY
        ) tdate1
    WHERE
            1 = 1
        AND tdate1.to_rownum = 1
), xx_cycle_count AS (
    SELECT
        'C'
        || attribute7
        || ( TO_NUMBER(attribute14) + (
            SELECT
                nvl(COUNT(*),
                    0)
            FROM
                fusion.ess_request_history erh,
                ess_request_property       erp
            WHERE
                    1 = 1
                AND erh.definition LIKE '%OMB%INT%GL%LINES%C%EXT%'
                AND erh.executable_status = 'SUCCEEDED'
                AND erh.requestid = erp.requestid
                AND erp.name LIKE 'submit.argument1'
                AND erp.value = flv_be.lookup_code
        ) ) cycle_count
    FROM
        fnd_lookup_values flv_be
    WHERE
            flv_be.lookup_type = 'XXGL_EXTRACT_FILE_INFO'
        AND flv_be.lookup_code = :program_code
        AND flv_be.enabled_flag = 'Y'
), xx_gcc AS (
    SELECT
        gcc1.*
    FROM
        gl_code_combinations gcc1,
        xxgl_lkp             xxgl_lkp1
    WHERE
            1 = 1
        AND gcc1.segment1 = nvl(nvl(:balancing_entity, xxgl_lkp1.balancing_entity),
                                gcc1.segment1)
        AND gcc1.segment2 = nvl(nvl(:budget_center, xxgl_lkp1.budget_center),
                                gcc1.segment2)
        AND gcc1.segment3 = nvl(nvl(:accounts, xxgl_lkp1.accounts),
                                gcc1.segment3)
	-- CEN-2746_start
	-- Return all if program code does not contain paramater for ACCURATE outbounds
	/*AND (xxgl_lkp1.program_code NOT LIKE 'ACCURATE_%LINE%'
	     OR 
		 -- Only return balance sheet accounts for all ACCURATE outbounds 
		 (xxgl_lkp1.program_code LIKE 'ACCURATE_%LINE%'
	      AND EXISTS (SELECT 1 
		                   FROM gl_lookups gll
					      WHERE 1=1					     
					        AND gll.lookup_type = 'ACCOUNT TYPE'
                            AND gll.lookup_code = gcc1.account_type
						    AND gll.meaning IN ('Asset','Liability','Owners'' equity')
						    AND gll.enabled_flag = 'Y'
							-- effective dates not captured properly
                            -- AND TRUNC(SYSDATE) BETWEEN gll.start_date_active AND NVL(gll.end_date_active,TRUNC(SYSDATE))
						  ))) */
	-- CEN-2746_end
), xx_gjb AS (
    SELECT
        *
    FROM
        (
            SELECT
                a.*,
                ROWNUM rnum
            FROM
                (
                    SELECT
                        gjb1.je_batch_id gjb2_je_batch_id,
                        gjb1.status      gjb2_status,
                        gjb1.name        gjb2_name,
                        gjh1.*
                    FROM
                        gl_je_batches gjb1,
                        (
                            SELECT
                                gjh.*,
                                fd.*,
                                td.*
                            FROM
                                gl_je_headers   gjh,
                                xx_from_date_ds fd,
                                xx_tdate        td
                            WHERE
                                    1 = 1
                                AND gjh.status = 'P'
                                AND gjh.posted_date >= nvl(TO_DATE(:manual_date, 'DD-MON-YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=AMERICAN'
                                ),
                                                           fd.from_processstart)
                                AND gjh.posted_date < nvl(TO_DATE(:manual_date_to, 'DD-MON-YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=AMERICAN'
                                ),
                                                          td.to_processstart)
                                AND gjh.je_header_id = nvl(:p_header_id, gjh.je_header_id)
                                AND gjh.period_name = nvl(:p_period_name, gjh.period_name)
                                AND gjh.je_batch_id = nvl(:p_je_batch_id, gjh.je_batch_id)
                        )             gjh1
                    WHERE
                            1 = 1
                        AND gjb1.name = nvl(:p_batch_name, gjb1.name)
				   -- RPtest_start
                   --AND gjb1.name in ('GL_OUTBOUND_1 FAH OM Corporate Sources A 7157822000001 7157823 N',
				   --				'GL_OUTBOUND_3 FAH OM Corporate Sources A 7157901000001 7157902 N',
				    --				'GL_OUTBOUND_4 FAH OM Corporate Sources A 7158030000001 7158032 N',
					--			'IM_OMIM_GBP_Bonus provision_Apr-23 Spreadsheet A 2506666 6567430 N',
					--			'MM_NMJ_OMIM_ZAR_SA_Expenses_1035 - Apr-23 Spreadsheet A 2507355 6580254 N',
					--			'MM_OMIM_AUD_Bank_Journal_Apr-22 Spreadsheet A 2501714 6553122 N')				   
				    -- RPtest_end					   
                        AND gjb1.je_batch_id = gjh1.je_batch_id
                    ORDER BY
                        gjb1.je_batch_id
                ) a
        )
    WHERE
            rnum >= nvl(:p_from_batch#, 1)
        AND rnum <= nvl(:p_to_batch#, 100000)
), xx_gjh AS (
    SELECT
        gjb2.*,
        xdd.*,
        xcc.*
    FROM
        xx_gjb          gjb2,
        xx_dril_delimit xdd,
        xx_cycle_count  xcc,
        (
            SELECT DISTINCT
                ledger_id
            FROM
                xxgl_lkp
        )               xlkp
    WHERE
            1 = 1
        AND xlkp.ledger_id = gjb2.ledger_id
   --

    UNION
    SELECT
        gjb2.*,
        xdd.*,
        xcc.*
    FROM
        xx_gjb          gjb2,
        xx_dril_delimit xdd,
        xx_cycle_count  xcc
    WHERE
            1 = 1
        AND 1 = (
            SELECT
                1
            FROM
                fnd_lookup_values flv
            WHERE
                    flv.lookup_type = 'XXGL_EXTRACT_CRITERIA'
                AND flv.attribute1 = :program_code
                AND nvl(flv.enabled_flag, 'N') = 'Y'
                AND trunc(sysdate) BETWEEN trunc(nvl(flv.start_date_active, sysdate)) AND trunc(nvl(flv.end_date_active, sysdate))
                AND flv.attribute2 IS NULL
                AND ROWNUM = 1
        )
), fah AS (
    SELECT
        gir.je_header_id                       c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                        c132, --fah_je_line_num,
        xal.accounting_date                    c33, --fah_accounting_date,
        nvl(xal.accounted_dr, 0)               c34,  --fah_accounted_dr,
        nvl(xal.accounted_cr, 0)               c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99'))) c36--fah_net_movement
                            ,
        replace(replace(replace(translate(xal.description,
                                          CHR(10)
                                          || CHR(13)
                                          || CHR(09),
                                          ' '),
                                '|',
                                ''),
                        ',',
                        ''),
                '~',
                '')                            c142,--fah_line_desc,
        attr_details.attribute1                c50,--fah_att_1,
        attr_details.attribute2                c51,--fah_att_2,
        attr_details.attribute3                c52,--fah_att_3,
        attr_details.attribute4                c53,--fah_att_4,
        attr_details.attribute5                c54,--fah_att_5,
        attr_details.attribute6                c55,--fah_att_6,
        attr_details.attribute7                c56,--fah_att_7,
        attr_details.attribute8                c57,--fah_att_8,
        attr_details.attribute9                c58,--fah_att_9,
        attr_details.attribute10               c59,--fah_att_10,
        attr_details.attribute11               c60,--fah_att_11,
        attr_details.attribute12               c61,--fah_att_12,
        attr_details.attribute13               c62,--fah_att_13,
        attr_details.attribute14               c63,--fah_att_14,
        attr_details.attribute15               c64,--fah_att_15,
        attr_details.attribute16               c65,--fah_att_16,
        attr_details.attribute17               c66,--fah_att_17,
        attr_details.attribute18               c67,--fah_att_18,
        attr_details.attribute19               c68,--fah_att_19,
        attr_details.attribute20               c69,--fah_att_20,
        attr_details.attribute21               c93,--fah_att_21,
        attr_details.attribute22               c94, --fah_att_22,
        attr_details.attribute23               c133,--fah_att_23,
        attr_details.attribute24               c134,--fah_att_24,
        attr_details.attribute25               c135,--fah_att_25,
        xal.sr56                               c136,--fah_att_26,
        xal.sr59                               c137,--fah_att_27,
        xal.sr60                               c138,--fah_att_28,
        attr_details.source_name               c70,--fah_source,
        attr_details.fahkey                    c71,--fah_key,
        NULL                                   c72,--supplier_name,
        NULL                                   c73,--supplier_number,
        NULL                                   c74,--payables_invoice_number,
        NULL                                   c75,--asset_number,
        NULL                                   c76,--purchase_order_number,
        NULL                                   c77,--requisition_number,
        NULL                                   c78,--invoice_line_description --defect 177 
          --XAL.DESCRIPTION INVOICE_LINE_DESCRIPTION ,
        NULL                                   c79,--customer_number,
        NULL                                   c80,--customer_name,
        NULL                                   c81,--receivables_invoice_number,
        NULL                                   c82,--receipt_number,
        NULL                                   c83,--check_number,
        xal.sr56                               c90,--fah_category
        NULL                                   c144, --acc_code 
        ROWNUM                                 c84,
        attr_details.acc_date                    -- #INC0038148 - returning the ACC_DATE for MCS
	-- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                   filler1,
        NULL                                   filler2,
        NULL                                   filler3,
        NULL                                   filler4,
        NULL                                   filler5,
        NULL                                   filler6
	-- CEN-71_end	
  /*  ROWNUM C84,
    NULL   C144,    --acc_code 
   xal.sr56  C90--fah_category,	*/
    FROM
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        xx_gjh                   gjh,
        gl_je_sources            gjs,
        attr_details
    WHERE
            gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND gjs.user_je_source_name LIKE 'FAH%'
        AND xal.ae_header_id = xah.ae_header_id
        AND xal.application_id = xah.application_id
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = xal.application_id
        AND attr_details.fah_appl_id = xte.application_id
        AND attr_details.fah_event_id = xe.event_id
        AND attr_details.fah_trx_num = xte.source_id_char_1
        AND attr_details.line_number = xal.sr60
        AND xal.accounting_class_code <> 'INTRA'
    UNION
    SELECT
        gir.je_header_id                       c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                        c132, --fah_je_line_num,
        xal.accounting_date                    c33, --fah_accounting_date,
        nvl(xal.accounted_dr, 0)               c34,  --fah_accounted_dr,
        nvl(xal.accounted_cr, 0)               c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99'))) c36--fah_net_movement
                            ,
        xal.description                        fah_line_desc,
        xal.attribute1                         fah_att_1,
        xal.attribute2                         fah_att_2,
        xal.attribute3                         fah_att_3,
        xal.attribute4                         fah_att_4,
        xal.attribute5                         fah_att_5,
        xal.attribute6                         fah_att_6,
        xal.attribute7                         fah_att_7,
        xal.attribute8                         fah_att_8,
        xal.attribute9                         fah_att_9,
        xal.attribute10                        fah_att_10,
        xal.attribute11                        fah_att_11,
        xal.attribute12                        fah_att_12,
        xal.attribute13                        fah_att_13,
        xal.attribute14                        fah_att_14,
        xal.attribute15                        fah_att_15,
        NULL                                   fah_att_16,
        NULL                                   fah_att_17,
        NULL                                   fah_att_18,
        NULL                                   fah_att_19,
        NULL                                   fah_att_20,
        NULL                                   fah_att_21,
        NULL                                   fah_att_22,
        NULL                                   fah_att_23,
        NULL                                   fah_att_24,
        NULL                                   fah_att_25,
        NULL                                   fah_att_26,
        NULL                                   fah_att_27,
        NULL                                   fah_att_28,
        'INTRACOMPANY'                         fah_source,
        NULL                                   fah_key,
        NULL                                   supplier_name,
        NULL                                   supplier_number,
        NULL                                   payables_invoice_number,
        NULL                                   asset_number,
        NULL                                   purchase_order_number,
        NULL                                   requisition_number,
        NULL                                   invoice_line_description,
			--XAL.DESCRIPTION INVOICE_LINE_DESCRIPTION ,
        NULL                                   customer_number,
        NULL                                   customer_name,
        NULL                                   receivables_invoice_number,
        NULL                                   receipt_number,
        NULL                                   check_number,
        xal.sr56                               c90,--fah_category
        xal.accounting_class_code              c144, --acc_code 
        ROWNUM                                 c84,
        NULL                                   acc_date                           -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                   filler1,
        NULL                                   filler2,
        NULL                                   filler3,
        NULL                                   filler4,
        NULL                                   filler5,
        NULL                                   filler6
	-- CEN-71_end	
	/*ROWNUM,
    xal.sr56              fah_category,
	xal.accounting_class_code acc_code*/
    FROM
        gl_import_references gir,
        xla_ae_lines         xal,
        xx_gjh               gjh,
        gl_je_sources        gjs
    WHERE
            xal.gl_sl_link_id = gir.gl_sl_link_id
        AND xal.gl_sl_link_table = gir.gl_sl_link_table
        AND gjs.user_je_source_name LIKE 'FAH%'
        AND xal.accounting_class_code = 'INTRA'
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
    UNION
    SELECT
        gir.je_header_id                           c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                            c132, --fah_je_line_num,
        xal.accounting_date                        c33, --fah_accounting_date-- ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)                   c34,  --fah_accounted_dr,
        nvl(xal.accounted_cr, 0)                   c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')))     c36--fah_net_movement
                            ,
        NULL,
        NULL -- LINE_ATTRIBUTE_1
        ,
        NULL -- LINE_ATTRIBUTE_2       
        ,
        to_char(acr.cash_receipt_id)               fah_att_3, -- LINE_ATTRIBUTE_3        
        NULL -- LINE_ATTRIBUTE_4        
        ,
        NULL -- LINE_ATTRIBUTE_5        
        ,
        NULL -- LINE_ATTRIBUTE_6        
        ,
        NULL -- LINE_ATTRIBUTE_7        
        ,
        NULL -- LINE_ATTRIBUTE_8        
        ,
        NULL -- LINE_ATTRIBUTE_9        
        ,
        NULL -- LINE_ATTRIBUTE_10        
        ,
        NULL -- LINE_ATTRIBUTE_11        
        ,
        nvl(lv.meaning, xal.accounting_class_code) fah_att_12, -- LINE_ATTRIBUTE_12        
        NULL -- LINE_ATTRIBUTE_13        
        ,
        NULL -- LINE_ATTRIBUTE_14        
        ,
        NULL -- LINE_ATTRIBUTE_15        
        ,
        NULL -- LINE_ATTRIBUTE_16        
        ,
        NULL -- LINE_ATTRIBUTE_17        
        ,
        NULL -- LINE_ATTRIBUTE_18        
        ,
        NULL -- LINE_ATTRIBUTE_19        
        ,
        NULL -- LINE_ATTRIBUTE_20        
        ,
        NULL                                       fah_att_21,
        NULL                                       fah_att_22,
        NULL                                       fah_att_23,
        NULL                                       fah_att_24,
        NULL                                       fah_att_25,
        NULL                                       fah_att_26,
        NULL                                       fah_att_27,
        NULL                                       fah_att_28,
        NULL -- FAH_SOURCE        
        ,
        NULL -- FAH_KEY        
        ,
        NULL -- SUPPLIER_NAME        
        ,
        NULL -- SUPPLIER_NUMBER        
        ,
        NULL -- PAYABLES_INVOICE_NUMBER        
        ,
        NULL -- ASSET_NUMBER        
        ,
        NULL -- PURCHASE_ORDER_NUMBER        
        ,
        NULL -- REQUISITION_NUMBER        
        ,
        replace(replace(replace(xal.description,
                                CHR(09),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                invoice_line_description -- INVOICE_LINE_DESCRIPTION        
                ,
        to_char(hzp.party_number)                  customer_number -- CUSTOMER_NUMBER        
        ,
        hzp.party_name                             customer_name-- CUSTOMER_NAME        
        ,
        NULL --GetArTranNumber(xal.ae_header_id, xal.ae_line_num, acr.cash_receipt_id)  -- RECEIVABLES_INVOICE_NUMBER        
        ,
        acr.receipt_number                         receipt_number -- RECEIPT_NUMBER        
        ,
        NULL -- CHECK_NUMBER        
        ,
        xal.sr56                                   c90,--fah_category
        NULL                                       c144, --acc_code 
        ROWNUM                                     c84,
        NULL                                       acc_date                    -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
	-- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                       filler1,
        NULL                                       filler2,
        NULL                                       filler3,
        NULL                                       filler4,
        NULL                                       filler5,
        NULL                                       filler6
	-- CEN-71_end	
/*ROWNUM,
xal.sr56 fah_category,
NULL acc_code*/
    FROM
        gl_je_lines              gll,
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        ar_cash_receipts_all     acr,
        hz_cust_accounts         hca,
        hz_parties               hzp,
        fnd_lookup_values        lv,
        xx_gjh                   gjh,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND xal.ae_header_id = xah.ae_header_id
        AND xal.application_id = xah.application_id
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = 222
        AND xte.entity_code = 'RECEIPTS'
        AND acr.cash_receipt_id = xte.source_id_int_1
        AND gir.je_header_id = gll.je_header_id
        AND gir.je_line_num = gll.je_line_num
        AND xal.accounting_class_code = lv.lookup_code (+)
        AND lv.lookup_type (+) = 'XLA_ACCOUNTING_CLASS'
        AND lv.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active(+), sysdate)) AND trunc(nvl(lv.end_date_active(+), sysdate))
        AND xal.party_id = hca.cust_account_id (+)
        AND hca.party_id = hzp.party_id (+)
    UNION
    SELECT
        gir.je_header_id                           c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                            c132, --fah_je_line_num,
        xal.accounting_date                        c33, --fah_accounting_date --ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)                   c34,  --fah_accounted_dr,
        nvl(xal.accounted_cr, 0)                   c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')))     c36--fah_net_movement
                            ,
        NULL,
        NULL -- LINE_ATTRIBUTE_1
        ,
        to_char(rct.customer_trx_id)               fah_att_2 -- LINE_ATTRIBUTE_2
        ,
        NULL -- LINE_ATTRIBUTE_3
        ,
        NULL -- LINE_ATTRIBUTE_4
        ,
        NULL -- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        NULL -- LINE_ATTRIBUTE_8
        ,
        NULL -- LINE_ATTRIBUTE_9
        ,
        NULL -- LINE_ATTRIBUTE_10
        ,
        NULL -- LINE_ATTRIBUTE_11
        ,
        nvl(lv.meaning, xal.accounting_class_code) fah_att_12-- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        NULL -- LINE_ATTRIBUTE_14
        ,
        NULL -- LINE_ATTRIBUTE_15
        ,
        NULL -- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        NULL -- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- LINE_ATTRIBUTE_20
        ,
        NULL                                       fah_att_21,
        NULL                                       fah_att_22,
        NULL                                       fah_att_23,
        NULL                                       fah_att_24,
        NULL                                       fah_att_25,
        NULL                                       fah_att_26,
        NULL                                       fah_att_27,
        NULL                                       fah_att_28,
        NULL -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        NULL -- SUPPLIER_NAME
        ,
        NULL -- SUPPLIER_NUMBER
        ,
        NULL -- PAYABLES_INVOICE_NUMBER
        ,
        NULL -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        replace(replace(replace(xal.description,
                                CHR(09),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                invoice_line_description-- INVOICE_LINE_DESCRIPTION
                ,
        to_char(hp.party_number)                   customer_number-- CUSTOMER_NUMBER
        ,
        hp.party_name                              customer_name -- CUSTOMER_NAME
        ,
        to_char(rct.trx_number)                    receivables_invoice_number -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                                   c90,--fah_category
        NULL                                       c144, --acc_code 
        ROWNUM                                     c84,
        NULL                                       acc_date                          -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
	-- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                       filler1,
        NULL                                       filler2,
        NULL                                       filler3,
        NULL                                       filler4,
        NULL                                       filler5,
        NULL                                       filler6
	-- CEN-71_end	 
 /* ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code */
    FROM
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        ra_customer_trx_all      rct,
        hz_parties               hp,
        hz_cust_accounts         hca,
        fnd_lookup_values        lv,
        xx_gjh                   gjh,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND xal.ae_header_id = xah.ae_header_id
        AND xal.application_id = xah.application_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = 222
        AND xte.entity_code = 'TRANSACTIONS'
        AND rct.customer_trx_id = xte.source_id_int_1
        AND rct.bill_to_customer_id = hca.cust_account_id
        AND xal.accounting_class_code = lv.lookup_code (+)
        AND lv.lookup_type (+) = 'XLA_ACCOUNTING_CLASS'
        AND lv.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active(+), sysdate)) AND trunc(nvl(lv.end_date_active(+), sysdate))
        AND hp.party_id = hca.party_id
    UNION
    SELECT
        gir.je_header_id                           c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                            c132, --fah_je_line_num,
        xal.accounting_date                        c33, --fah_accounting_date --ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)                   c34,  --fah_accounted_dr,
        nvl(xal.accounted_cr, 0)                   c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')))     c36--fah_net_movement
                            ,
        NULL,
        to_char(aaa.adjustment_id)                 fah_att_1-- line_attribute_1
        ,
        to_char(rct.customer_trx_id)               fah_att_2 -- LINE_ATTRIBUTE_2
        ,
        NULL -- LINE_ATTRIBUTE_3
        ,
        NULL -- LINE_ATTRIBUTE_4
        ,
        NULL -- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        NULL -- LINE_ATTRIBUTE_8
        ,
        NULL -- LINE_ATTRIBUTE_9
        ,
        NULL -- LINE_ATTRIBUTE_10
        ,
        NULL -- LINE_ATTRIBUTE_11
        ,
        nvl(lv.meaning, xal.accounting_class_code) fah_att_12 -- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        NULL -- LINE_ATTRIBUTE_14
        ,
        NULL -- LINE_ATTRIBUTE_15
        ,
        NULL -- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        NULL -- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- LINE_ATTRIBUTE_20
        ,
        NULL                                       fah_att_21,
        NULL                                       fah_att_22,
        NULL                                       fah_att_23,
        NULL                                       fah_att_24,
        NULL                                       fah_att_25,
        NULL                                       fah_att_26,
        NULL                                       fah_att_27,
        NULL                                       fah_att_28,
        NULL -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        NULL -- SUPPLIER_NAME
        ,
        NULL -- SUPPLIER_NUMBER
        ,
        NULL -- PAYABLES_INVOICE_NUMBER
        ,
        NULL -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        replace(replace(replace(xal.description,
                                CHR(09),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                invoice_line_description -- INVOICE_LINE_DESCRIPTION
                ,
        to_char(hp.party_number)                   customer_number -- CUSTOMER_NUMBER
        ,
        hp.party_name                              customer_name -- CUSTOMER_NAME
        ,
        to_char(rct.trx_number)                    receivables_invoice_number-- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                                   c90,--fah_category
        NULL                                       c144, --acc_code 
        ROWNUM                                     c84,
        NULL                                       acc_date                         -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
   	-- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                       filler1,
        NULL                                       filler2,
        NULL                                       filler3,
        NULL                                       filler4,
        NULL                                       filler5,
        NULL                                       filler6
	-- CEN-71_end	
    /* ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code */
    FROM
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        ra_customer_trx_all      rct,
        hz_parties               hp,
        ar_adjustments_all       aaa,
        hz_cust_accounts         hca,
        fnd_lookup_values        lv,
        xx_gjh                   gjh,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND xal.ae_header_id = xah.ae_header_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND xal.application_id = xah.application_id
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = 222
        AND xte.entity_code = 'ADJUSTMENTS'
        AND aaa.adjustment_id = xte.source_id_int_1
        AND rct.customer_trx_id = aaa.customer_trx_id
        AND hp.party_id = hca.party_id
        AND rct.bill_to_customer_id = hca.cust_account_id
        AND xal.accounting_class_code = lv.lookup_code (+)
        AND lv.lookup_type (+) = 'XLA_ACCOUNTING_CLASS'
        AND lv.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active(+), sysdate)) AND trunc(nvl(lv.end_date_active(+), sysdate))
        AND hp.party_id = hca.party_id
    UNION
    SELECT
        gir.je_header_id                                   c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                                    c132, --fah_je_line_num,
        xal.accounting_date                                c33, --fah_accounting_date --ACCOUNTING_DATE
    /*decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr, 0), nvl(xdl.unrounded_accounted_dr, 0)
    )), '999999999999999999999999999999.99')))*/
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.accounted_dr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.accounted_dr, 0),
                      nvl(xdl.unrounded_accounted_dr, 0))) c34,--fah_accounted_dr -- ACCOUNTED_DR
   /* decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr
    , 0), nvl(xdl.unrounded_accounted_cr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)
    )), '999999999999999999999999999999.99'))) */
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.accounted_cr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.accounted_cr, 0),
                      nvl(xdl.unrounded_accounted_cr, 0))) c35, --fah_accounted_cr,
        decode(TRIM(to_char((decode(xal.ae_header_id,
                                    NULL,
                                    nvl(gjl.accounted_dr, 0),
                                    decode(xdl.ae_header_id,
                                           NULL,
                                           nvl(xal.accounted_dr, 0),
                                           nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id,
                                                                                         NULL,
                                                                                         nvl(gjl.accounted_cr, 0),
                                                                                         decode(xdl.ae_header_id,
                                                                                                NULL,
                                                                                                nvl(xal.accounted_cr, 0),
                                                                                                nvl(xdl.unrounded_accounted_cr, 0))))
                                                                                                ,
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((decode(xal.ae_header_id,
                                    NULL,
                                    nvl(gjl.accounted_dr, 0),
                                    decode(xdl.ae_header_id,
                                           NULL,
                                           nvl(xal.accounted_dr, 0),
                                           nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id,
                                                                                         NULL,
                                                                                         nvl(gjl.accounted_cr, 0),
                                                                                         decode(xdl.ae_header_id,
                                                                                                NULL,
                                                                                                nvl(xal.accounted_cr, 0),
                                                                                                nvl(xdl.unrounded_accounted_cr, 0))))
                                                                                                ,
                            '999999999999999999999999999999.99')))             c36,--fah_net_movement, -- NET_MOVEMENT
        NULL,
        to_char(ail.product_table)                         fah_att_1 -- LINE_ATTRIBUTE_1
        ,
        to_char(ail.reference_key1)                        fah_att_2-- LINE_ATTRIBUTE_2
        ,
        to_char(ail.reference_key2)                        fah_att_3-- LINE_ATTRIBUTE_3
        ,
        to_char(aid.po_distribution_id)                    fah_att_4 -- LINE_ATTRIBUTE_4
        ,
        to_char(aid.charge_applicable_to_dist_id)          fah_att_5-- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        to_char(aia.invoice_id)                            fah_att_8-- LINE_ATTRIBUTE_8
        ,
        to_char(aid.invoice_distribution_id)               fah_att_9-- LINE_ATTRIBUTE_9
        ,
        to_char(ail.line_number)                           fah_att_10-- LINE_ATRIBUTE_10
        ,
        aid.reversal_flag                                  fah_att_11-- LINE_ATTRIBUTE_11
        ,
        lt.meaning                                         fah_att_12-- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        nvl(dt.meaning, aid.line_type_lookup_code)         fah_att_14-- LINE_ATTRIBUTE_14
        ,
        NULL -- LINE_ATTRIBUTE_15
        ,
        NULL -- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        NULL -- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- LINE_ATTRIBUTE_20
        ,
        NULL                                               fah_att_21,
        NULL                                               fah_att_22,
        NULL                                               fah_att_23,
        NULL                                               fah_att_24,
        NULL                                               fah_att_25,
        NULL                                               fah_att_26,
        NULL                                               fah_att_27,
        NULL                                               fah_att_28,
        aia.source                                         fah_source-- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        asa.vendor_name                                    supplier_name-- SUPPLIER_NAME
        ,
        asa.segment1                                       supplier_number-- SUPPLIER_NUMBER
        ,
        replace(replace(replace(aia.invoice_num,
                                CHR(09),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                        payables_invoice_number-- PAYABLES_INVOICE_NUMBER
                ,
        NULL -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        replace(replace(replace(nvl(aid.description, xal.description),
                                CHR(9),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                        invoice_line_description-- INVOICE_LINE_DESCRIPTION
                ,
        NULL -- CUSTOMER_NUMBER
        ,
        NULL -- CUSTOMER_NAME
        ,
        NULL -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                                           c90,--fah_category
        NULL                                               c144, --acc_code 
        ROWNUM                                             c84,
        NULL                                               acc_date                           -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        /*CASE
            WHEN xal.currency_code = 'ZAR' THEN
                decode(xal.ae_header_id,
                       NULL,
                       nvl(gjl.accounted_dr, 0),
                       decode(xdl.ae_header_id,
                              NULL,
                              nvl(xal.accounted_dr, 0),
                              nvl(xdl.unrounded_accounted_dr, 0)))
            ELSE
                coalesce(xdl.unrounded_entered_dr, gjl.entered_dr)
        END  */ -- commented by Vivek
        CASE
            WHEN xal.currency_code = 'ZAR' THEN
                decode(xal.ae_header_id,
                       NULL,
                       nvl(gjl.entered_dr, 0),
                       decode(xdl.ae_header_id,
                              NULL,
                              nvl(xal.entered_dr, 0),
                              nvl(xdl.unrounded_entered_dr, 0)))
            ELSE
                nvl(xdl.unrounded_entered_dr, 0)
        END   		entered_dr,  -- Added by Vivek
        /*CASE
            WHEN xal.currency_code = 'ZAR' THEN
                decode(xal.ae_header_id,
                       NULL,
                       nvl(gjl.accounted_cr, 0),
                       decode(xdl.ae_header_id,
                              NULL,
                              nvl(xal.accounted_cr, 0),
                              nvl(xdl.unrounded_accounted_cr, 0)))
            ELSE
                coalesce(xdl.unrounded_entered_cr, gjl.entered_cr)
        END */   -- commented by Vivek
        CASE
            WHEN xal.currency_code = 'ZAR' THEN
                decode(xal.ae_header_id,
                       NULL,
                       nvl(gjl.entered_cr, 0),
                       decode(xdl.ae_header_id,
                              NULL,
                              nvl(xal.entered_cr, 0),
                              nvl(xdl.unrounded_entered_cr, 0)))
            ELSE
                nvl(xdl.unrounded_entered_cr, 0)
        END 		entered_cr, -- Added by Vivek
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                               filler1,
        NULL                                               filler2,
        NULL                                               filler3,
        NULL                                               filler4,
        NULL                                               filler5,
        NULL                                               filler6
	-- CEN-71_end		
	/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
    FROM
        gl_je_lines                  gjl,
        xx_gjh                       gjh,
        gl_je_sources                gjs,
        gl_import_references         gir,
        xla_ae_lines                 xal,
        xla_ae_headers               xah,
        xla_transaction_entities     xte,
        xla_distribution_links       xdl,
        ap_invoice_distributions_all aid,
        ap_invoice_lines_all         ail,
        ap_invoices_all              aia,
        fnd_lookup_values            lt,
        fnd_lookup_values            dt,
        poz_suppliers_v              asa
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gjh.je_header_id = gjl.je_header_id
        AND gir.je_header_id = gjl.je_header_id
        AND gir.je_line_num = gjl.je_line_num
        AND xal.gl_sl_link_id = gir.gl_sl_link_id
        AND xal.gl_sl_link_table = gir.gl_sl_link_table
        AND xah.ae_header_id = xal.ae_header_id
        AND xah.application_id = xal.application_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_source = gjs.je_source_name
        AND nvl(xah.accounting_entry_status_code, 'F') = 'F'
        AND nvl(xah.gl_transfer_status_code, 'Y') = 'Y'
        AND xte.application_id = 200
        AND xte.entity_code = 'AP_INVOICES'
        AND xte.application_id = xah.application_id
        AND xte.entity_id = xah.entity_id
        AND xdl.ae_header_id (+) = xal.ae_header_id
        AND xdl.ae_line_num (+) = xal.ae_line_num
        AND xdl.source_distribution_type (+) = 'AP_INV_DIST'
        AND xdl.source_distribution_id_num_1 = aid.invoice_distribution_id (+)
        AND aid.invoice_id = ail.invoice_id (+)
        AND aid.invoice_line_number = ail.line_number (+)
        AND xte.source_id_int_1 = aia.invoice_id (+)
        AND ail.line_type_lookup_code = lt.lookup_code (+)
        AND lt.lookup_type (+) = 'INVOICE LINE TYPE'
        AND lt.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(lt.start_date_active(+), sysdate)) AND trunc(nvl(lt.end_date_active(+), sysdate))
        AND aid.line_type_lookup_code = dt.lookup_code (+)
        AND dt.lookup_type (+) = 'INVOICE DISTRIBUTION TYPE'
        AND dt.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(dt.start_date_active(+), sysdate)) AND trunc(nvl(dt.end_date_active(+), sysdate))
        AND aia.vendor_id = asa.vendor_id (+)
    UNION
    SELECT
        gir.je_header_id                                   c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                                    c132, --fah_je_line_num,
        xal.accounting_date                                c33, --fah_accounting_date--ACCOUNTING_DATE
    /*  decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr, 0), nvl(xdl.unrounded_accounted_dr, 0)
    )), '999999999999999999999999999999.99'))) fah_accounted_dr,*/
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.accounted_dr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.accounted_dr, 0),
                      nvl(xdl.unrounded_accounted_dr, 0))) c34,  --fah_accounted_dr,
   /* decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr
    , 0), nvl(xdl.unrounded_accounted_cr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)
    )), '999999999999999999999999999999.99'))) fah_accounted_cr,*/
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.accounted_cr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.accounted_cr, 0),
                      nvl(xdl.unrounded_accounted_cr, 0))) c35, --fah_accounted_cr,
        decode(TRIM(to_char((decode(xal.ae_header_id,
                                    NULL,
                                    nvl(gjl.accounted_dr, 0),
                                    decode(xdl.ae_header_id,
                                           NULL,
                                           nvl(xal.accounted_dr, 0),
                                           nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id,
                                                                                         NULL,
                                                                                         nvl(gjl.accounted_cr, 0),
                                                                                         decode(xdl.ae_header_id,
                                                                                                NULL,
                                                                                                nvl(xal.accounted_cr, 0),
                                                                                                nvl(xdl.unrounded_accounted_cr, 0))))
                                                                                                ,
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((decode(xal.ae_header_id,
                                    NULL,
                                    nvl(gjl.accounted_dr, 0),
                                    decode(xdl.ae_header_id,
                                           NULL,
                                           nvl(xal.accounted_dr, 0),
                                           nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id,
                                                                                         NULL,
                                                                                         nvl(gjl.accounted_cr, 0),
                                                                                         decode(xdl.ae_header_id,
                                                                                                NULL,
                                                                                                nvl(xal.accounted_cr, 0),
                                                                                                nvl(xdl.unrounded_accounted_cr, 0))))
                                                                                                ,
                            '999999999999999999999999999999.99')))             c36,--fah_net_movement
        NULL,
        NULL -- LINE_ATTRIBUTE_1
        ,
        NULL -- LINE_ATTRIBUTE_2
        ,
        NULL -- LINE_ATTRIBUTE_3
        ,
        NULL -- LINE_ATTRIBUTE_4
        ,
        NULL -- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        to_char(aia.invoice_id)                            fah_att_8-- LINE_ATTRIBUTE_8
        ,
        to_char(aid.invoice_distribution_id)               fah_att_9 -- LINE_ATTRIBUTE_9
        ,
        to_char(ail.line_number)                           fah_att_10-- LINE_ATTRIBUTE_10
        ,
        NULL --aid.reversal_flag                                                                -- LINE_ATTRIBUTE_11
        ,
        NULL --lt.meaning                                                                       -- LINE_ATTRIBUTE_12
        ,
        to_char(aca.check_date, 'DD-MON-YYYY')             fah_att_13-- LINE_ATTRIBUTE_13
        ,
        nvl(dt.meaning, aid.line_type_lookup_code)         fah_att_14-- LINE_ATTRIBUTE_14
        ,
        NULL -- LINE_ATTRIBUTE_15
        ,
        NULL -- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        NULL -- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- LINE_ATTRIBUTE_20
        ,
        NULL                                               fah_att_21,
        NULL                                               fah_att_22,
        NULL                                               fah_att_23,
        NULL                                               fah_att_24,
        NULL                                               fah_att_25,
        NULL                                               fah_att_26,
        NULL                                               fah_att_27,
        NULL                                               fah_att_28,
        aia.source -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        aps.vendor_name                                    supplier_name-- SUPPLIER_NAME
        ,
        aps.segment1                                       supplier_number-- SUPPLIER_NUMBER
        ,
        to_char(replace(replace(replace(aia.invoice_num,
                                        CHR(09),
                                        ''),
                                CHR(10),
                                ''),
                        CHR(13),
                        ''))                                               payables_invoice_number -- PAYABLES_INVOICE_NUMBER
                        ,
        NULL -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        replace(replace(replace(nvl(xal.description, xah.description),
                                CHR(09),
                                ''),
                        CHR(10),
                        ''),
                CHR(13),
                '')                                        invoice_line_description -- INVOICE_LINE_DESCRIPTION
                ,
        NULL -- CUSTOMER_NUMBER
        ,
        NULL -- CUSTOMER_NAME
        ,
        NULL -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        to_char(aca.check_number)                          check_number-- CHECK_NUMBER
        ,
        xal.sr56                                           c90,--fah_category
        NULL                                               c144, --acc_code 
        ROWNUM                                             c84,
        NULL                                               acc_date               -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.entered_dr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.entered_dr, 0),
                      nvl(xdl.unrounded_entered_dr, 0)))   entered_dr,
	--decode(xal.ae_header_id,NULL,nvl(gjl.entered_cr, 0),decode(xdl.ae_header_id, NULL, nvl(xal.entered_cr, 0), nvl(xdl.unrounded_entered_dr, 0))) entered_cr, -- commented by Vivek on 20-Jan-2025 to fix amount issue
        decode(xal.ae_header_id,
               NULL,
               nvl(gjl.entered_cr, 0),
               decode(xdl.ae_header_id,
                      NULL,
                      nvl(xal.entered_cr, 0),
                      nvl(xdl.unrounded_entered_cr, 0)))   entered_cr, -- Added by Vivek on 20-Jan-2025 to fix amount issue
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                               filler1,
        NULL                                               filler2,
        NULL                                               filler3,
        NULL                                               filler4,
        NULL                                               filler5,
        NULL                                               filler6
	-- CEN-71_end		
    /*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
    FROM
        gl_je_lines                  gjl,
        xx_gjh                       gjh,
        gl_import_references         gir,
        xla_ae_lines                 xal,
        xla_ae_headers               xah,
        xla_transaction_entities     xte,
        xla_distribution_links       xdl,
        ap_checks_all                aca,
        ap_payment_hist_dists        phd,
        ap_invoice_distributions_all aid,
        ap_invoices_all              aia,
        ap_invoice_lines_all         ail,
        fnd_lookup_values            lt,
        fnd_lookup_values            dt,
        poz_suppliers_v              aps,
        gl_je_sources                gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gjh.je_header_id = gjl.je_header_id
        AND gir.je_header_id = gjl.je_header_id
        AND gir.je_line_num = gjl.je_line_num
        AND xal.gl_sl_link_id = gir.gl_sl_link_id
        AND xal.gl_sl_link_table = gir.gl_sl_link_table
        AND xah.ae_header_id = xal.ae_header_id
        AND xah.application_id = xal.application_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_source = gjs.je_source_name
        AND nvl(xah.accounting_entry_status_code, 'F') = 'F'
        AND nvl(xah.gl_transfer_status_code, 'Y') = 'Y'
        AND xte.application_id = xah.application_id
        AND xte.entity_id = xah.entity_id
        AND xte.source_id_int_1 = aca.check_id
        AND xte.entity_code = 'AP_PAYMENTS'
        AND xdl.ae_header_id (+) = xal.ae_header_id
        AND xdl.ae_line_num (+) = xal.ae_line_num
        AND xdl.source_distribution_type (+) = 'AP_PMT_DIST'
        AND xdl.source_distribution_id_num_1 = phd.payment_hist_dist_id (+)
        AND phd.invoice_distribution_id = aid.invoice_distribution_id (+)
        AND aid.invoice_id = aia.invoice_id (+)
        AND aid.invoice_id = ail.invoice_id (+)
        AND aid.invoice_line_number = ail.line_number (+)    
        AND ail.line_type_lookup_code = lt.lookup_code (+)
        AND lt.lookup_type (+) = 'INVOICE LINE TYPE'
        AND lt.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(lt.start_date_active(+), sysdate)) AND trunc(nvl(lt.end_date_active(+), sysdate))
        AND aid.line_type_lookup_code = dt.lookup_code (+)
        AND dt.lookup_type (+) = 'INVOICE DISTRIBUTION TYPE'
        AND dt.enabled_flag (+) = 'Y'
        AND trunc(sysdate) BETWEEN trunc(nvl(dt.start_date_active(+), sysdate)) AND trunc(nvl(dt.end_date_active(+), sysdate))
        AND xal.party_id = aps.vendor_id (+)
    UNION
    SELECT
        gir.je_header_id                       c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                        c132, --fah_je_line_num,  
        xal.accounting_date                    c33, --fah_accounting_date --ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)               c34, --fah_accounted_dr-- ACCOUNTED_DR
        nvl(xal.accounted_cr, 0)               c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99'))) c36--fah_net_movement
                            ,
        NULL,
        NULL -- LINE_ATTRIBUTE_1
        ,
        NULL -- LINE_ATTRIBUTE_2
        ,
        NULL -- LINE_ATTRIBUTE_3
        ,
        NULL -- LINE_ATTRIBUTE_4
        ,
        NULL -- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        to_char(faa.asset_id)                  fah_att_8-- LINE_ATTRIBUTE_8
        ,
        NULL -- LINE_ATTRIBUTE_9
        ,
        NULL -- LINE_ATTRIBUTE_10
        ,
        NULL -- LINE_ATTRIBUTE_11
        ,
        NULL -- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        to_char(faa.tag_number)                fah_att_14-- LINE_ATTRIBUTE_14
        ,
        to_char(faa.serial_number)             fah_att_15 -- LINE_ATTRIBUTE_15
        ,
        to_char(fdd.book_type_code)            fah_att_16-- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        fac.segment1
        || '.'
        || fac.segment2                        fah_att_18-- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- GetFaAssignedTo(faa.asset_id, fdd.book_type_code) -- LINE_ATTRIBUTE_20
        ,
        NULL                                   fah_att_21,
        NULL                                   fah_att_22,
        NULL                                   fah_att_23,
        NULL                                   fah_att_24,
        NULL                                   fah_att_25,
        NULL                                   fah_att_26,
        NULL                                   fah_att_27,
        NULL                                   fah_att_28,
        NULL -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        NULL -- SUPPLIER_NAME
        ,
        NULL -- SUPPLIER_NUMBER
        ,
        NULL -- PAYABLES_INVOICE_NUMBER
        ,
        to_char(faa.asset_number)              asset_number -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        NULL --faa.description -- INVOICE_LINE_DESCRIPTION
        ,
        NULL -- CUSTOMER_NUMBER
        ,
        NULL -- CUSTOMER_NAME
        ,
        NULL -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                               c90,--fah_category
        NULL                                   c144, --acc_code 
        ROWNUM                                 c84,
        NULL                                   acc_date                -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                   filler1,
        NULL                                   filler2,
        NULL                                   filler3,
        NULL                                   filler4,
        NULL                                   filler5,
        NULL                                   filler6
	-- CEN-71_end		
    /*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
    FROM
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        fa_deprn_detail          fdd,
        fa_additions_b           faa,
        fa_categories_b          fac,
        xx_gjh                   gjh,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND xal.ae_header_id = xah.ae_header_id
        AND xal.application_id = xah.application_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = 140
        AND xte.entity_code = 'DEPRECIATION'
        AND fdd.asset_id = xte.source_id_int_1
        AND fdd.book_type_code = xte.source_id_char_1
        AND fdd.period_counter = xte.source_id_int_2
        AND fdd.deprn_run_id = xte.source_id_int_3
        AND faa.asset_id = fdd.asset_id
        AND faa.asset_category_id = fac.category_id
    UNION
    SELECT
        gir.je_header_id                       c131, --FAH_JE_HEADER_ID,
        gir.je_line_num                        c132, --fah_je_line_num,
        xal.accounting_date                    c33, --fah_accounting_date --ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)               c34,--fah_accounted_dr -- ACCOUNTED_DR
        nvl(xal.accounted_cr, 0)               c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99'))) c36--fah_net_movement
                            ,
        NULL,
        NULL -- LINE_ATTRIBUTE_1
        ,
        NULL -- LINE_ATTRIBUTE_2
        ,
        NULL -- LINE_ATTRIBUTE_3
        ,
        NULL -- LINE_ATTRIBUTE_4
        ,
        NULL -- LINE_ATTRIBUTE_5
        ,
        NULL -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        to_char(faa.asset_id)                  fah_att_8-- LINE_ATTRIBUTE_8
        ,
        NULL -- LINE_ATTRIBUTE_9
        ,
        NULL -- LINE_ATTRIBUTE_10
        ,
        NULL -- LINE_ATTRIBUTE_11
        ,
        NULL -- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        to_char(faa.tag_number)                fah_att_14-- LINE_ATTRIBUTE_14
        ,
        to_char(faa.serial_number)             fah_att_15-- LINE_ATTRIBUTE_15
        ,
        to_char(fth.book_type_code)            fah_att_16-- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        fac.segment1
        || '.'
        || fac.segment2                        fah_att_18-- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL --GetFaAssignedTo(faa.asset_id, fth.book_type_code) -- LINE_ATTRIBUTE_20
        ,
        NULL                                   fah_att_21,
        NULL                                   fah_att_22,
        NULL                                   fah_att_23,
        NULL                                   fah_att_24,
        NULL                                   fah_att_25,
        NULL                                   fah_att_26,
        NULL                                   fah_att_27,
        NULL                                   fah_att_28,
        NULL -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        NULL -- SUPPLIER_NAME
        ,
        NULL -- SUPPLIER_NUMBER
        ,
        NULL -- PAYABLES_INVOICE_NUMBER
        ,
        to_char(faa.asset_number)              asset_number -- ASSET_NUMBER
        ,
        NULL -- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        NULL --faa.description -- INVOICE_LINE_DESCRIPTION
        ,
        NULL -- CUSTOMER_NUMBER
        ,
        NULL -- CUSTOMER_NAME
        ,
        NULL -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                               c90,--fah_category
        NULL                                   c144, --acc_code 
        ROWNUM                                 c84,
        NULL                                   acc_date                  -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                   filler1,
        NULL                                   filler2,
        NULL                                   filler3,
        NULL                                   filler4,
        NULL                                   filler5,
        NULL                                   filler6
	-- CEN-71_end		
/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
    FROM
        gl_import_references     gir,
        xla_ae_lines             xal,
        xla_ae_headers           xah,
        xla_events               xe,
        xla_transaction_entities xte,
        fa_transaction_headers   fth,
        fa_additions_b           faa,
        fa_categories_b          fac,
        xx_gjh                   gjh,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        AND gir.gl_sl_link_id = xal.gl_sl_link_id
        AND gir.gl_sl_link_table = xal.gl_sl_link_table
        AND xal.ae_header_id = xah.ae_header_id
        AND xal.application_id = xah.application_id
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_header_id = gir.je_header_id
        AND gjh.je_source = gjs.je_source_name
        AND xah.application_id = xe.application_id
        AND xah.event_id = xe.event_id
        AND xe.application_id = xte.application_id
        AND xe.entity_id = xte.entity_id
        AND xte.application_id = 140
        AND xte.entity_code = 'TRANSACTIONS'
        AND fth.transaction_header_id = xte.source_id_int_1
        AND fth.book_type_code = xte.source_id_char_1
        AND fth.asset_id = faa.asset_id
        AND faa.asset_category_id = fac.category_id
    UNION
    SELECT
        glir.je_header_id                      c131, --FAH_JE_HEADER_ID,
        glir.je_line_num                       c132, --fah_je_line_num,
        xal.accounting_date                    c33, --fah_accounting_date --ACCOUNTING_DATE
        nvl(xal.accounted_dr, 0)               c34,--fah_accounted_dr-- ACCOUNTED_DR
        nvl(xal.accounted_cr, 0)               c35, --fah_accounted_cr,
        decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)),
                            '999999999999999999999999999999.99'))) c36--fah_net_movement
                            ,
        NULL,
        to_char(pha.po_header_id)              fah_att_1-- LINE_ATTRIBUTE_1
        ,
        NULL --rrsl.reference1 -- LINE_ATTRIBUTE_2
        ,
        NULL --rrsl.reference2 -- LINE_ATTRIBUTE_3
        ,
        NULL --rrsl.reference3 -- LINE_ATTRIBUTE_4
        ,
        NULL --rrsl.reference4 -- LINE_ATTRIBUTE_5
        ,
        NULL --rrsl.accounting_event_id -- LINE_ATTRIBUTE_6
        ,
        NULL -- LINE_ATTRIBUTE_7
        ,
        NULL -- LINE_ATTRIBUTE_8
        ,
        NULL -- LINE_ATTRIBUTE_9
        ,
        NULL -- LINE_ATTRIBUTE_10
        ,
        NULL -- LINE_ATTRIBUTE_11
        ,
        NULL -- LINE_ATTRIBUTE_12
        ,
        NULL -- LINE_ATTRIBUTE_13
        ,
        NULL -- LINE_ATTRIBUTE_14
        ,
        NULL -- LINE_ATTRIBUTE_15
        ,
        NULL -- LINE_ATTRIBUTE_16
        ,
        NULL -- LINE_ATTRIBUTE_17
        ,
        NULL -- LINE_ATTRIBUTE_18
        ,
        NULL -- LINE_ATTRIBUTE_19
        ,
        NULL -- LINE_ATTRIBUTE_20
        ,
        NULL                                   fah_att_21,
        NULL                                   fah_att_22,
        NULL                                   fah_att_23,
        NULL                                   fah_att_24,
        NULL                                   fah_att_25,
        NULL                                   fah_att_26,
        NULL                                   fah_att_27,
        NULL                                   fah_att_28,
        NULL -- FAH_SOURCE
        ,
        NULL -- FAH_KEY
        ,
        ass.vendor_name                        supplier_name-- SUPPLIER_NAME
        ,
        ass.segment1                           supplier_number-- SUPPLIER_NUMBER
        ,
        NULL -- PAYABLES_INVOICE_NUMBER
        ,
        NULL -- ASSET_NUMBER
        ,
        pha.segment1                           purchase_order_number-- PURCHASE_ORDER_NUMBER
        ,
        NULL -- REQUISITION_NUMBER
        ,
        NULL -- INVOICE_LINE_DESCRIPTION
        ,
        NULL -- CUSTOMER_NUMBER
        ,
        NULL -- CUSTOMER_NAME
        ,
        NULL -- RECEIVABLES_INVOICE_NUMBER
        ,
        NULL -- RECEIPT_NUMBER
        ,
        NULL -- CHECK_NUMBER
        ,
        xal.sr56                               c90,--fah_category
        NULL                                   c144, --acc_code 
        ROWNUM                                 c84,
        NULL                                   acc_date                -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
        ,
        xal.entered_dr,
        xal.entered_cr,
        xal.currency_code,
        xal.currency_conversion_date,
        xal.currency_conversion_rate,
        xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        NULL                                   filler1,
        NULL                                   filler2,
        NULL                                   filler3,
        NULL                                   filler4,
        NULL                                   filler5,
        NULL                                   filler6
	-- CEN-71_end		
/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
    FROM
    --gl_je_batches              gjb,
        xx_gjh                   gjh,
        gl_je_lines              gll,
        xx_gcc                   gcc,
        gl_import_references     glir,
        gl_ledgers               gl,
        xla_ae_lines             xal,
        xla_ae_headers           xlh,
        xla_events               xle,
        xla_transaction_entities xlte,
        xla_distribution_links   xldl,
        rcv_transactions         rt,
        rcv_shipment_lines       rsl,
        rcv_shipment_headers     rsh,
        poz_suppliers_v          ass,
        po_distributions_all     pda,
        po_headers_all           pha,
        po_lines_all             pla,
        gl_je_sources            gjs
    WHERE
            1 = 1
        AND gjh.drilldown = 'Yes' -- DRILLDOWN SET TO YES
        --AND gjb.je_batch_id = gjh.je_batch_id
        AND gjh.je_header_id = gll.je_header_id
        AND gjh.period_name = gll.period_name
        AND gcc.code_combination_id = gll.code_combination_id
                        --AND gjb.status = 'P'
        AND gjh.gjb2_status = 'P'
        AND gjs.user_je_source_name NOT LIKE 'FAH%'
        AND gjh.je_source = gjs.je_source_name
        AND gl.ledger_id = gjh.ledger_id
        AND gjh.je_header_id = glir.je_header_id
        AND gll.je_line_num = glir.je_line_num
                                                --AND glir.je_batch_id = gjb.je_batch_id
        AND glir.je_batch_id = gjh.gjb2_je_batch_id
        AND glir.gl_sl_link_table = xal.gl_sl_link_table
        AND glir.gl_sl_link_id = xal.gl_sl_link_id
        AND xal.application_id = xlh.application_id
        AND xal.ae_header_id = xlh.ae_header_id
        AND xlh.application_id = xle.application_id
        AND xlh.event_id = xle.event_id
        AND xle.application_id = xlte.application_id
        AND xle.entity_id = xlte.entity_id
        AND xal.application_id = xldl.application_id
        AND xal.ae_header_id = xldl.ae_header_id
        AND xal.ae_line_num = xldl.ae_line_num
        AND xlte.entity_code = 'RCV_ACCOUNTING_EVENTS'
        AND xlte.application_id = 707
        AND xlte.source_id_int_1 = rt.transaction_id
        AND rt.shipment_header_id = rsh.shipment_header_id
        AND rt.shipment_line_id = rsl.shipment_line_id
        AND rt.po_header_id = pha.po_header_id
        AND rt.po_line_id = pla.po_line_id
        AND rt.po_distribution_id = pda.po_distribution_id
        AND pha.vendor_id = ass.vendor_id
        AND gjh.je_source = 'Cost Management'
) /*SELECT * FROM FAH WHERE C131 = 2264860 and C132 = 236*/, main_extract AS (
    SELECT DISTINCT
        1                                                                                        c127,--"KEY" C127,
        gjh.cycle_count                                                                          c86,--cycle_count,
        1                                                                                        c141,--"ROW_TYPE" C141,
        gjh.ledger_id                                                                            c1,
        (
            SELECT
                name
            FROM
                gl_ledgers gl
            WHERE
                gl.ledger_id = gjh.ledger_id
        )                                                                                        c2,-- ledger_name,
        gcc.segment1                                                                             c3,
        decode(gcc.segment1,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 1, gcc.segment1)) c4--segment1_desc
               ,
        gcc.segment2                                                                             c5,
        decode(gcc.segment2,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 2, gcc.segment2)) c6--segment2_desc
               ,
        gcc.segment3                                                                             c7,
        decode(gcc.segment3,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 3, gcc.segment3)) c8--segment3_desc
               ,
        gcc.segment4                                                                             c9,
        decode(gcc.segment4,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 4, gcc.segment4)) c10--segment4_desc
               ,
        gcc.segment5                                                                             c11,
        decode(gcc.segment5,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 5, gcc.segment5)) c12--segment5_desc
               ,
        gcc.segment6                                                                             c13,
        decode(gcc.segment6,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 6, gcc.segment6)) c14--segment6_desc
               ,
        gcc.segment7                                                                             c15,
        decode(gcc.segment7,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 7, gcc.segment7)) c16--segment7_desc
               ,
        gcc.segment8                                                                             c17,
        decode(gcc.segment8,
               NULL,
               NULL,
               gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 8, gcc.segment8)) c18--segment8_desc
               ,
        gcc.segment9                                                                             c19,
        (
            SELECT
                ffvt.description
            FROM
                fnd_flex_value_sets ffvs,
                fnd_flex_values     ffv,
                fnd_flex_values_tl  ffvt
            WHERE
                    ffvs.flex_value_set_id = ffv.flex_value_set_id
                AND ffv.flex_value_id = ffvt.flex_value_id
                AND ffvs.flex_value_set_name = 'Spare 2 OLYMPUS SA BANK'
                AND ffv.flex_value = gcc.segment9
        )                                                                                        c20,--"SEGMENT9_DESC" ,
        gcc.segment10                                                                            c21,
        (
            SELECT
                ffvt.description
            FROM
                fnd_flex_value_sets ffvs,
                fnd_flex_values     ffv,
                fnd_flex_values_tl  ffvt
            WHERE
                    ffvs.flex_value_set_id = ffv.flex_value_set_id
                AND ffv.flex_value_id = ffvt.flex_value_id
                AND ffvs.flex_value_set_name = 'Spare 3 OLYMPUS SA BANK'
                AND ffv.flex_value = gcc.segment10
        )                                                                                        c22,--"SEGMENT10_DESC" ,
        gjl.code_combination_id                                                                  c23,
        nvl(gjh.currency_code, gjl.currency_code)                                                c24,
        gjl.period_name                                                                          c25,
        gps.period_num                                                                           c26,
        /*
        to_char(TO_DATE(to_char(substr(gps.period_name, - 2)),
        'RR'),
                'RRRR')                                                                          c128, --period_month,
        --Commented as it creates issue for Adjustment period Conversion
        */
        gps.period_year                                                                          c128,
        gps.period_year                                                                          c27,
        gcc.account_type                                                                         c28,
        gjl.je_line_num                                                                          c29,
        (
            CASE
                WHEN gjs.user_je_source_name LIKE 'FAH%' THEN
                    replace(replace(replace(translate(fah.c142,
                                                      CHR(10)
                                                      || CHR(13)
                                                      || CHR(09),
                                                      ' '),
                                            '|',
                                            ''),
                                    ',',
                                    ''),
                            '~',
                            '')
                ELSE
                    replace(replace(replace(translate(gjl.description,
                                                      CHR(10)
                                                      || CHR(13)
                                                      || CHR(09),
                                                      ' '),
                                            '|',
                                            ''),
                                    ',',
                                    ''),
                            '~',
                            '')
            END
        )                                                                                        c30,--line_description,
        gjl.last_update_date                                                                     c31,
        to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS.FF')                                   c92,--extract_date,
      --to_date(to_char(gjl.effective_date, 'YYYY-MM-DD'), 'YYYY-MM-DD') C105 ,--effective_date,                   -- #INC0038148 - original commented out
        decode(fah.c90,
               'MCS',
               nvl(TO_DATE(to_char(fah.acc_date, 'YYYY-MM-DD'),
        'YYYY-MM-DD'),
                   TO_DATE(to_char(gjl.effective_date, 'YYYY-MM-DD'),
                           'YYYY-MM-DD')),
               TO_DATE(to_char(gjl.effective_date, 'YYYY-MM-DD'),
                       'YYYY-MM-DD'))                                                            c105,  -- #INC0038148 - display different Accouting Dates for MCS, else default
        nvl(nvl(fah.c34, gjl.accounted_dr),
            0)                                                                                   c106, --accounted_dr,
        nvl(nvl(fah.c35, gjl.accounted_cr),
            0)                                                                                   c87,--accounted_cr,
        decode(TRIM(to_char((nvl(gjl.accounted_dr, 0) - nvl(gjl.accounted_cr, 0)),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char((nvl(gjl.accounted_dr, 0) - nvl(gjl.accounted_cr, 0)),
                            '999999999999999999999999999999.99')))                                                   c129,--net_amount,
        decode(TRIM(to_char(nvl(gjl.stat_amount, 0),
                            '999999999999999999999999999999.99')),
               '.00',
               '0.00',
               TRIM(to_char(nvl(gjl.stat_amount, 0),
                            '999999999999999999999999999999.99')))                                                   c88,--stat_amount,
      --gjb.name batch_name,
        gjh.gjb2_name                                                                            c38, --batch_name C38
      --gjb.status,
        gjh.gjb2_status                                                                          c39,
        gjh.je_header_id                                                                         c40,
        gjh.date_created                                                                         c41,
        gjh.created_by                                                                           c42,
        gjh.creation_date                                                                        c43,
        gjh.posted_date                                                                          c44,
        gjh.name                                                                                 c45,
        gjs.user_je_source_name                                                                  c46,
        gjc.user_je_category_name                                                                c47,
        substr(gjc.user_je_category_name, 1, 3)                                                  c91,--category_substr,	 
	  -- CEN-CEN-3083_start
	  -- Not sure what the intend was with multiple variations of replace, will keep it as is becuase of the former but new columns will only substitute \t\n\r and delimeter
	  -- replace(replace(replace(translate(gjh.description,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~','') C48 ,--description,	  
        replace(replace(replace(replace(translate(gjh.description,
                                                  CHR(10)
                                                  || CHR(13)
                                                  || CHR(09),
                                                  ' '),
                                        '|',
                                        ''),
                                ',',
                                ''),
                        '~',
                        ''),
                delimiter,
                ' ')                                                                             c48,--description,
        gjh.external_reference                                                                   c49,
        gjh.je_source                                                                            c130,
      -- gjl.reference_1 C107,
        gjl.reference_1                                                                          c107,
        gjl.reference_2                                                                          c108,
        gjl.reference_3                                                                          c109,
        gjl.reference_4                                                                          c110,
        gjl.reference_5                                                                          c111,
        gjl.reference_6                                                                          c122,
        gjl.reference_7                                                                          c123,
        gjl.reference_8                                                                          c124,
        gjl.reference_9                                                                          c125,
        gjl.reference_10                                                                         c126,
        gjl.attribute1                                                                           c95,
        gjl.attribute2                                                                           c96,
        gjl.attribute3                                                                           c97,
        gjl.attribute4                                                                           c98,
        gjl.attribute5                                                                           c99,
        gjl.attribute6                                                                           c100,
        gjl.attribute7                                                                           c101,
        gjl.attribute8                                                                           c102,
        gjl.attribute9                                                                           c103,
        gjl.attribute10                                                                          c104,
        gjl.attribute11                                                                          c112,
        gjl.attribute12                                                                          c113,
        gjl.attribute13                                                                          c114,
        gjl.attribute14                                                                          c115,
        gjl.attribute15                                                                          c116,
        gjl.attribute16                                                                          c117,
        gjl.attribute17                                                                          c118,
        gjl.attribute18                                                                          c119,
        gjl.attribute19                                                                          c120,
        gjl.attribute20                                                                          c121,
	  -- CEN-CEN-3083_end
        fah.*,
        gjh.delimiter                                                                            delimiter,
        gjh.drilldown                                                                            c85,
        to_char(from_tz(CAST(gjh.from_processstart AS TIMESTAMP),
                        'GMT') AT TIME ZONE 'CET',
                'DD-MM-YYYY HH24:MI:SS')                                                         c139,-- "From date",
        to_char(from_tz(CAST(gjh.to_processstart AS TIMESTAMP),
                        'GMT') AT TIME ZONE 'CET',
                'DD-MM-YYYY HH24:MI:SS')                                                         c140,--"To Date",
   --Row_number() over (partition by fah.fah_je_line_num order by fah.fah_je_header_id)   C143--sl_count
        ROW_NUMBER()
        OVER(PARTITION BY fah.c132
             ORDER BY
                 fah.c131
        )                                                                                        c143, --sl_count,
	-- CEN-71_start
        nvl(nvl(fah.entered_dr, gjl.entered_dr),
            0)                                                                                   gl_entered_dr,
        nvl(nvl(fah.entered_cr, gjl.entered_cr),
            0)                                                                                   gl_entered_cr,
        nvl(nvl(fah.entered_dr, gjl.entered_dr),
            0) - nvl(nvl(fah.entered_cr, gjl.entered_cr),
                     0)                                                                                       gl_entered_net_movement
                     ,
        gl.currency_code                                                                         gl_currency_code, --#accounted_currency_code
        to_char(nvl(fah.currency_conversion_date, gjl.currency_conversion_date),
                'YYYY-MM-DD')                                                                    gl_currency_conversion_date,
        nvl(fah.currency_conversion_rate, gjl.currency_conversion_rate)                          gl_currency_conversion_rate,
        nvl(fah.currency_conversion_type, gjl.currency_conversion_type)                          gl_currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
        gcc.segment11                                                                            c200,
        (
            SELECT
                ffvt.description
            FROM
                fnd_flex_value_sets ffvs,
                fnd_flex_values     ffv,
                fnd_flex_values_tl  ffvt
            WHERE
                    ffvs.flex_value_set_id = ffv.flex_value_set_id
                AND ffv.flex_value_id = ffvt.flex_value_id
                AND ffvs.flex_value_set_name = 'Spare 4 OLYMPUS SA BANK'
                AND ffv.flex_value = gcc.segment11
        )                                                                                        c201,--"SEGMENT11_DESC" ,
        gcc.segment12                                                                            c202,
        (
            SELECT
                ffvt.description
            FROM
                fnd_flex_value_sets ffvs,
                fnd_flex_values     ffv,
                fnd_flex_values_tl  ffvt
            WHERE
                    ffvs.flex_value_set_id = ffv.flex_value_set_id
                AND ffv.flex_value_id = ffvt.flex_value_id
                AND ffvs.flex_value_set_name = 'Spare 5 OLYMPUS SA BANK'
                AND ffv.flex_value = gcc.segment12
        )                                                                                        c203,
        (
            SELECT
                parent_pk1_value
            FROM
                fnd_tree_node ftn
            WHERE
                    ftn.tree_code = 'Account OLYMPUS SA BANK BA'
                AND ftn.tree_structure_code = 'GL_ACCT_FLEX'
                AND ftn.pk1_start_value = gcc.segment3
                AND ROWNUM = 1
        )                                                                                        gl_filler5,
        NULL                                                                                     gl_filler6,
        NULL                                                                                     gl_filler7,
        NULL                                                                                     gl_filler8,
        NULL                                                                                     gl_filler9,
        NULL                                                                                     gl_filler10,
        NULL                                                                                     gl_filler11
	-- CEN-71_end	
    FROM
        xx_gjh             gjh,
        gl_je_lines        gjl,
      --gl_je_batches          gjb,
        xx_gcc             gcc,
        gl_je_sources      gjs,
        gl_je_categories   gjc,
        gl_period_statuses gps,
        fah,
        gl_ledgers         gl
    WHERE
            1 = 1
        AND gjh.je_header_id = gjl.je_header_id
    --AND gjh.je_batch_id            =  gjb.je_batch_id
        AND gl.ledger_id = gjh.ledger_id
   -- AND gjh.je_header_id           =  fah.fah_je_header_id (+)
        AND gjh.je_header_id = fah.c131 (+)
        AND gjl.je_line_num = fah.c132 (+)
        AND gjl.code_combination_id = gcc.code_combination_id
        AND gjh.je_source = gjs.je_source_name
        AND gjs.user_je_source_name <> 'CONVERSION'
        AND gjh.je_category = gjc.je_category_name
        AND gps.closing_status = decode(:p_open_period, 'Y', 'O', 'N', 'C',
                                        gps.closing_status)
        AND gps.closing_status IN ( 'C', 'O' )
        AND gps.application_id = 101
        AND gjh.ledger_id = gps.ledger_id
        AND gjh.period_name = gps.period_name
        AND gps.adjustment_period_flag = decode(:p_include_adjustment, 'N', 'N', gps.adjustment_period_flag)
        AND 1 = (
            CASE
                WHEN :program_code = 'MCS_LINE'
                     AND fah.c70 IS NOT NULL
                     AND fah.c136 IN ( 'DISB', 'MCS' ) THEN
                    1
                WHEN :program_code = 'MCS_LINE'
                     AND fah.c136 IN ( 'DISB', 'MCS' ) THEN
                    1
                WHEN :program_code = 'ADMIN_LINE'
                     AND fah.c136 IN ( 'DISB', 'MCS', 'ADMIN' ) THEN
                    1
                WHEN :program_code = 'ADMIN_LINE'
                     AND gjs.user_je_source_name = 'Spreadsheet'
                     AND gl.name IN ( 'OM - RSA Ledger', 'OM - NAM Ledger' ) THEN
                    1
                WHEN :program_code = 'RMM_COMM_LINE'
                     AND fah.c136 = 'RMM COMM' THEN
                    1
                WHEN :program_code NOT IN ( 'MCS_LINE', 'ADMIN_LINE', 'RMM_COMM_LINE' ) THEN
                    1
                WHEN fah.c70 IS NOT NULL
                     AND fah.c144 = 'INTRA' THEN
                    1
                ELSE
                    0
            END
        )
), t_record AS (
    SELECT
        c3                               tc3,
        COUNT(c3)                        count_tc3,
        to_char(SUM(nvl(c106, 0)),
                'fm9999999999999990.00') sum_tc106,
        to_char(SUM(nvl(c87, 0)),
                'fm9999999999999990.00') sum_tc87

-- What about the entered amounts, since accounted are summed here?
-- CEN-71_end
    FROM
        main_extract
    WHERE
            1 = 1
        AND c40 IS NOT NULL
    GROUP BY
        c3
    HAVING
        COUNT(c3) > 1
)
--------------------Final query ( with the details  ----------------------------------------------
SELECT
    1   key,
    3   pos,
    CASE
        WHEN c85 = 'Yes'
             OR substr(c46, 1, 3) = 'FAH' THEN
            'D'
            || delimiter
            || c1
            || delimiter
            || c2
            || delimiter
            || c3
            || delimiter
            || c4
            || delimiter
            || c5
            || delimiter
            || c6
            || delimiter
            || c7
            || delimiter
            || c8
            || delimiter
            || c9
            || delimiter
            || c10
            || delimiter
            || c11
            || delimiter
            || c12
            || delimiter
            || c13
            || delimiter
            || c14
            || delimiter
            || c15
            || delimiter
            || c16
            || delimiter
            || c17
            || delimiter
            || c18
            || delimiter
            || c19
            || delimiter
            || c20
            || delimiter
            || c21
            || delimiter
            || c22
            || delimiter
            || c23
            || delimiter
            || c24
            || delimiter
            || c25
            || delimiter
            || c26
            || delimiter
            || c27
            || delimiter
            || c27
            || delimiter
            || c28
            || delimiter
            || c29
            || delimiter
            || c30
            || delimiter
            || to_char(c31, 'YYYY-MM-DD')
            || delimiter
            || c92
            || delimiter
            || decode(c90,
                      'MCS',
                      to_char(c105, 'YYYY-MM-DD'),
                      to_char(nvl(c33, c105),
                              'YYYY-MM-DD'))
            || delimiter
            ||  -- #INC0038148 - display different Accouting Dates for MCS, else default
             to_char(decode(c34,
                              NULL,
                              nvl(c106, 0),
                              c34),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(decode(c35,
                              NULL,
                              nvl(c87, 0),
                              c35),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(decode(c36,
                              NULL,
                              nvl(c129, 0),
                              c36),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(nvl(c88, 0),
                       'fm99999999999999990.00')
            || delimiter
            || c38
            || delimiter
            || c39
            || delimiter
            || c40
            || delimiter
            || to_char(c41, 'YYYY-MM-DD')
            || delimiter
            || c42
            || delimiter
            || to_char(c43, 'YYYY-MM-DD')
            || delimiter
            || to_char(c44, 'YYYY-MM-DD')
            || delimiter
            || c45
            || delimiter
            || c46
            || delimiter
            || c47
            || delimiter
            || c48
            || delimiter
            || c49
            || delimiter
            || nvl(c93, c107)
            || delimiter
            || nvl(c94, c108)
            || delimiter
            || nvl(c133, c109)
            || delimiter
            || nvl(c134, c110)
            || delimiter
            || nvl(c135, c111)
            || delimiter
            || nvl(c136, c122)
            || delimiter
            || nvl(c137, c123)
            || delimiter
            || nvl(c138, c124)
            || delimiter
            || c125
            || delimiter
            || c126
            || delimiter
            || nvl(c50, c95)
            || delimiter
            || nvl(c51, c96)
            || delimiter
            || nvl(c52, c97)
            || delimiter
            || nvl(c53, c98)
            || delimiter
            || nvl(c54, c99)
            || delimiter
            || nvl(c55, c100)
            || delimiter
            || nvl(c56, c101)
            || delimiter
            || nvl(c57, c102)
            || delimiter
            || nvl(c58, c103)
            || delimiter
            || nvl(c59, c104)
            || delimiter
            || nvl(c60, c112)
            || delimiter
            || nvl(c61, c113)
            || delimiter
            || nvl(c62, c114)
            || delimiter
            || nvl(c63, c115)
            || delimiter
            || nvl(c64, c116)
            || delimiter
            || nvl(c65, c117)
            || delimiter
            || nvl(c66, c118)
            || delimiter
            || nvl(c67, c119)
            || delimiter
            || nvl(c68, c120)
            || delimiter
            || nvl(c69, c121)
            || delimiter
            || c70
            || delimiter
            || c71
            || delimiter
            || c72
            || delimiter
            || c73
            || delimiter
            || c74
            || delimiter
            || c75
            || delimiter
            || c76
            || delimiter
            || c77
            || delimiter
            || c78
            || delimiter
            || c79
            || delimiter
            || c80
            || delimiter
            || c81
            || delimiter
            || c143
            || delimiter
            || c82
            || delimiter
            || c83
-- CEN-71_start
            || delimiter
            || gl_entered_dr
            || delimiter
            || gl_entered_cr
            || delimiter
            || gl_entered_net_movement
            || delimiter
            || gl_currency_code
            || delimiter
            || gl_currency_conversion_date
            || delimiter
            || gl_currency_conversion_rate
            || delimiter
            || gl_currency_conversion_type
            || delimiter
            || c200
            || delimiter
            || c201
            || delimiter
            || c202
            || delimiter
            || c203
            || delimiter
            ||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
             gl_filler5
            || delimiter
            || gl_filler6
            || delimiter
            || gl_filler7
            || delimiter
            || gl_filler8
            || delimiter
            || gl_filler9
            || delimiter
            || gl_filler10
            || delimiter
            || gl_filler11
-- CEN-71_end
------------------------------------------------------------------------------------------------------
        WHEN c85 != 'Yes'
             AND substr(c46, 1, 3) != 'FAH' THEN
            'D'
            || delimiter
            || c1
            || delimiter
            || c2
            || delimiter
            || c3
            || delimiter
            || c4
            || delimiter
            || c5
            || delimiter
            || c6
            || delimiter
            || c7
            || delimiter
            || c8
            || delimiter
            || c9
            || delimiter
            || c10
            || delimiter
            || c11
            || delimiter
            || c12
            || delimiter
            || c13
            || delimiter
            || c14
            || delimiter
            || c15
            || delimiter
            || c16
            || delimiter
            || c17
            || delimiter
            || c18
            || delimiter
            || c19
            || delimiter
            || c20
            || delimiter
            || c21
            || delimiter
            || c22
            || delimiter
            || c23
            || delimiter
            || c24
            || delimiter
            || c25
            || delimiter
            || c26
            || delimiter
            || c27
            || delimiter
            || c27
            || delimiter
            || c28
            || delimiter
            || c29
            || delimiter
            || c30
            || delimiter
            || to_char(c31, 'YYYY-MM-DD')
            || delimiter
            || c92
            || delimiter
            || decode(c90,
                      'MCS',
                      to_char(c105, 'YYYY-MM-DD'),
                      to_char(nvl(c33, c105),
                              'YYYY-MM-DD'))
            || delimiter
            ||  -- #INC0038148 - display different Accouting Dates for MCS, else default
             to_char(nvl(c106, 0),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(nvl(c87, 0),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(nvl(c129, 0),
                       'fm99999999999999990.00')
            || delimiter
            || to_char(nvl(c88, 0),
                       'fm99999999999999990.00')
            || delimiter
            || c38
            || delimiter
            || c39
            || delimiter
            || c40
            || delimiter
            || to_char(c41, 'YYYY-MM-DD')
            || delimiter
            || c42
            || delimiter
            || to_char(c43, 'YYYY-MM-DD')
            || delimiter
            || to_char(c44, 'YYYY-MM-DD')
            || delimiter
            || c45
            || delimiter
            || c46
            || delimiter
            || c47
            || delimiter
            || c48
            || delimiter
            || c49
            || delimiter
            || c107
            || delimiter
            || c108
            || delimiter
            || c109
            || delimiter
            || c110
            || delimiter
            || c111
            || delimiter
            || c122
            || delimiter
            || c123
            || delimiter
            || c124
            || delimiter
            || c125
            || delimiter
            || c126
            || delimiter
            || c95
            || delimiter
            || c96
            || delimiter
            || c97
            || delimiter
            || c98
            || delimiter
            || c99
            || delimiter
            || c100
            || delimiter
            || c101
            || delimiter
            || c102
            || delimiter
            || c103
            || delimiter
            || c104
            || delimiter
            || c112
            || delimiter
            || c113
            || delimiter
            || c114
            || delimiter
            || c115
            || delimiter
            || c116
            || delimiter
            || c117
            || delimiter
            || c118
            || delimiter
            || c119
            || delimiter
            || c120
            || delimiter
            || c121
            || delimiter
            || c70
            || delimiter
            || c71
            || delimiter
            || c72
            || delimiter
            || c73
            || delimiter
            || c74
            || delimiter
            || c75
            || delimiter
            || c76
            || delimiter
            || c77
            || delimiter
            || c78
            || delimiter
            || c79
            || delimiter
            || c80
            || delimiter
            || c81
            || delimiter
            || ''
            || delimiter
            || c82
            || delimiter
            || c83
-- CEN-71_start
            || delimiter
            || gl_entered_dr
            || delimiter
            || gl_entered_cr
            || delimiter
            || gl_entered_net_movement
            || delimiter
            || gl_currency_code
            || delimiter
            || gl_currency_conversion_date
            || delimiter
            || gl_currency_conversion_rate
            || delimiter
            || gl_currency_conversion_type
            || delimiter
            || c200
            || delimiter
            || c201
            || delimiter
            || c202
            || delimiter
            || c203
            || delimiter
            ||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
             gl_filler5
            || delimiter
            || gl_filler6
            || delimiter
            || gl_filler7
            || delimiter
            || gl_filler8
            || delimiter
            || gl_filler9
            || delimiter
            || gl_filler10
            || delimiter
            || gl_filler11
-- CEN-71_end	
    END trxn
FROM
    main_extract
WHERE
        1 = 1
    AND c40 IS NOT NULL
UNION
SELECT
    1   key,
    1   record_postion,
    c86 trxn
FROM
    main_extract
WHERE
    ROWNUM < 2
UNION
SELECT
    1             key,
    2             record_postion,
    'H'
    || delimiter
    || 'LEDGER_ID'
    || delimiter
    || 'LEDGER_NAME'
    || delimiter
    || 'SEGMENT1'
    || delimiter
    || 'SEGMENT1_DESCRIPTION'
    || delimiter
    || 'SEGMENT2'
    || delimiter
    || 'SEGMENT2_DESCRIPTION'
    || delimiter
    || 'SEGMENT3'
    || delimiter
    || 'SEGMENT3_DESCRIPTION'
    || delimiter
    || 'SEGMENT4'
    || delimiter
    || 'SEGMENT4_DESCRIPTION'
    || delimiter
    || 'SEGMENT5'
    || delimiter
    || 'SEGMENT5_DESCRIPTION'
    || delimiter
    || 'SEGMENT6'
    || delimiter
    || 'SEGMENT6_DESCRIPTION'
    || delimiter
    || 'SEGMENT7'
    || delimiter
    || 'SEGMENT7_DESCRIPTION'
    || delimiter
    || 'SEGMENT8'
    || delimiter
    || 'SEGMENT8_DESCRIPTION'
    || delimiter
    || 'SEGMENT9'
    || delimiter
    || 'SEGMENT9_DESCRIPTION'
    || delimiter
    || 'SEGMENT10'
    || delimiter
    || 'SEGMENT10_DESCRIPTION'
    || delimiter
    || 'CODE_COMBINATION_ID'
    || delimiter
    || 'CURRENCY_CODE'
    || delimiter
    || 'PERIOD_NAME'
    || delimiter
    || 'PERIOD_NUMBER'
    || delimiter
    || 'PERIOD_YEAR'
    || delimiter
    || 'YEAR'
    || delimiter
    || 'ACCOUNT_TYPE'
    || delimiter
    || 'LINE_NUMBER'
    || delimiter
    || 'LINE_DESCRIPTION'
    || delimiter
    || 'LINE_LAST_UPDATE_DATE'
    || delimiter
    || 'EXTRACT_DATE'
    || delimiter
    || 'EFFECTIVE_DATE'
    || delimiter
    || 'ACCOUNTED_DR'
    || delimiter
    || 'ACCOUNTED_CR'
    || delimiter
    || 'NET_MOVEMENT'
    || delimiter
    || 'LINE_STAT_AMOUNT'
    || delimiter
    || 'BATCH_NAME'
    || delimiter
    || 'BATCH_STATUS'
    || delimiter
    || 'HEADER_ID'
    || delimiter
    || 'HEADER_DATE_CREATED'
    || delimiter
    || 'HEADER_CREATED_BY'
    || delimiter
    || 'HEADER_CREATION_DATE'
    || delimiter
    || 'HEADER_POSTED_DATE'
    || delimiter
    || 'HEADER_NAME'
    || delimiter
    || 'SOURCE_NAME'
    || delimiter
    || 'CATEGORY_NAME'
    || delimiter
    || 'HEADER_DESCRIPTION'
    || delimiter
    || 'HEADER_EXTERNAL_REFERENCE'
    || delimiter
    || 'LINE_REFERENCE_1'
    || delimiter
    || 'LINE_REFERENCE_2'
    || delimiter
    || 'LINE_REFERENCE_3'
    || delimiter
    || 'LINE_REFERENCE_4'
    || delimiter
    || 'LINE_REFERENCE_5'
    || delimiter
    || 'LINE_REFERENCE_6'
    || delimiter
    || 'LINE_REFERENCE_7'
    || delimiter
    || 'LINE_REFERENCE_8'
    || delimiter
    || 'LINE_REFERENCE_9'
    || delimiter
    || 'LINE_REFERENCE_10'
    || delimiter
    || 'LINE_ATTRIBUTE_1'
    || delimiter
    || 'LINE_ATTRIBUTE_2'
    || delimiter
    || 'LINE_ATTRIBUTE_3'
    || delimiter
    || 'LINE_ATTRIBUTE_4'
    || delimiter
    || 'LINE_ATTRIBUTE_5'
    || delimiter
    || 'LINE_ATTRIBUTE_6'
    || delimiter
    || 'LINE_ATTRIBUTE_7'
    || delimiter
    || 'LINE_ATTRIBUTE_8'
    || delimiter
    || 'LINE_ATTRIBUTE_9'
    || delimiter
    || 'LINE_ATTRIBUTE_10'
    || delimiter
    || 'LINE_ATTRIBUTE_11'
    || delimiter
    || 'LINE_ATTRIBUTE_12'
    || delimiter
    || 'LINE_ATTRIBUTE_13'
    || delimiter
    || 'LINE_ATTRIBUTE_14'
    || delimiter
    || 'LINE_ATTRIBUTE_15'
    || delimiter
    || 'LINE_ATTRIBUTE_16'
    || delimiter
    || 'LINE_ATTRIBUTE_17'
    || delimiter
    || 'LINE_ATTRIBUTE_18'
    || delimiter
    || 'LINE_ATTRIBUTE_19'
    || delimiter
    || 'LINE_ATTRIBUTE_20'
    || delimiter
    || 'FAH_SOURCE'
    || delimiter
    || 'FAH_KEY'
    || delimiter
    || 'SUPPLIER_NAME'
    || delimiter
    || 'SUPPLIER_NUMBER'
    || delimiter
    || 'PAYABLES_INVOICE_NUMBER'
    || delimiter
    || 'ASSET_NUMBER'
    || delimiter
    || 'PURCHASE_ORDER_NUMBER'
    || delimiter
    || 'REQUISITION_NUMBER'
    || delimiter
    || 'INVOICE_LINE_DESCRIPTION'
    || delimiter
    || 'CUSTOMER_NUMBER'
    || delimiter
    || 'CUSTOMER_NAME'
    || delimiter
    || 'RECEIVABLES_INVOICE_NUMBER'
    || delimiter
    || 'SUBLEDGER_ROW_COUNT'
    ||
-- CEN-71_start
-- DELIMITER||'RECEIPT_NUMBER'||DELIMITER||'CHECK_NUMBER'	trxn
     delimiter
    || 'RECEIPT_NUMBER'
    || delimiter
    || 'CHECK_NUMBER'
    || delimiter
    || 'GL_ENTERED_DR'
    || delimiter
    || 'GL_ENTERED_CR'
    || delimiter
    || 'GL_ENTERED_NET_MOVEMENT'
    || delimiter
    || 'GL_ACCOUNTED_CURRENCY_CODE'
    || delimiter
    || 'GL_CURRENCY_CONVERSION_DATE'
    || delimiter
    || 'GL_CURRENCY_CONVERSION_RATE'
    || delimiter
    || 'GL_CURRENCY_CONVERSION_TYPE'
    || delimiter
    || 'SEGMENT11'
    || delimiter
    || 'SEGMENT11_DESCRIPTION'
    || delimiter
    || 'SEGMENT12'
    || delimiter
    || 'SEGMENT12_DESCRIPTION'
    || delimiter
    ||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
     'FILLER5'
    || delimiter
    || 'FILLER6'
    || delimiter
    || 'FILLER7'
    || delimiter
    || 'FILLER8'
    || delimiter
    || 'FILLER9'
    || delimiter
    || 'FILLER10'
    || delimiter
    || 'FILLER11' trxn
-- CEN-71_end	
FROM
    xx_dril_delimit
UNION
SELECT
    1                                 key,
    4                                 record_postion,
    'T'
    || delimiter
    || tc3
    || delimiter
    || count_tc3
    || delimiter
    || sum_tc106
    || delimiter
    || sum_tc87
    || delimiter
    || to_char(from_tz(CAST(sysdate AS TIMESTAMP),
                       'GMT') AT TIME ZONE 'CET',
               'DD-MON-YYYY HH24:MI:SS',
               'NLS_DATE_LANGUAGE=AMERICAN') trxn
-- What about the entered amounts, since accounted are returned here?
-- CEN-71_end
FROM
    t_record,
    xx_dril_delimit
ORDER BY
    1 ASC