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
+============================================================================================================*/

WITH attr_details AS (
   SELECT 
        headers.application_id       fah_appl_id,
        headers.event_id             fah_event_id,
        headers.transaction_number   fah_trx_num,
        lines.line_number,
        replace(lines.CHAR3,'|',' ') attribute1, --defect 178
        lines.LONG_CHAR1 attribute2,
        lines.LONG_CHAR2 attribute3,
        lines.LONG_CHAR3 attribute4,
        lines.CHAR4|| lines.CHAR5 "ATTRIBUTE5",
        lines.CHAR6||lines.CHAR7 "ATTRIBUTE6",
        lines.CHAR8||lines.CHAR9 "ATTRIBUTE7",
        lines.CHAR10||lines.CHAR11 "ATTRIBUTE8",
        lines.CHAR12||lines.CHAR13 "ATTRIBUTE9",
        lines.CHAR14||lines.CHAR15 "ATTRIBUTE10",
        lines.CHAR16||lines.CHAR17 "ATTRIBUTE11",
        lines.CHAR18 || lines.CHAR19 "ATTRIBUTE12",
        lines.CHAR20 || lines.CHAR21 "ATTRIBUTE13",
        lines.CHAR22 || lines.CHAR23 "ATTRIBUTE14",
        lines.CHAR24 || lines.CHAR25 "ATTRIBUTE15",
        lines.CHAR26 || lines.CHAR27 "ATTRIBUTE16",
        lines.CHAR28 || lines.CHAR29 "ATTRIBUTE17",
        lines.CHAR31 || lines.CHAR31 "ATTRIBUTE18",
        lines.CHAR32 || lines.CHAR33 "ATTRIBUTE19",
        lines.CHAR34 || lines.CHAR35 "ATTRIBUTE20",
        lines.CHAR36                 "ATTRIBUTE21" ,
        lines.CHAR37                 "ATTRIBUTE22",
        lines.CHAR38                 "ATTRIBUTE23",
        lines.CHAR39                 "ATTRIBUTE24",
        lines.CHAR40                 "ATTRIBUTE25",
        lines.CHAR41                 "ATTRIBUTE26",
        lines.CHAR42                 "ATTRIBUTE27",
        lines.CHAR43                 "ATTRIBUTE28",
        lines.LONG_CHAR4                    fahkey,
        headers.CHAR10 source_name,
		lines.date1  acc_date                           -- #INC0038148 - selecting DATE1 to return the expected Accounting Date as per Inbound interface for MCS
    FROM
        --adxx_xla_h_fahom_corp   headers,
       -- adxx_xla_l_fahom_corp   lines
	   xla_transaction_headers headers,
	   xla_transaction_lines lines,
	   XLA_SUBLEDGERS_TL xst
    WHERE
        headers.application_id = lines.application_id
		 AND headers.event_id = lines.event_id
		 AND lines.application_id = xst.application_id
		AND xst.application_name  LIKE 'FAH%'
		and xst.language='US'	
),
xx_dril_delimit AS (
    SELECT
        attribute7  delimiter,
        attribute11 drilldown
    FROM
        fnd_lookup_values flv_be
    WHERE
            flv_be.lookup_type = 'XXGL_EXTRACT_FILE_INFO'
        AND flv_be.lookup_code = :program_code
		and flv_be.ENABLED_FLAG = 'Y'
		AND ROWNUM = 1                                                  --tuning, added ROWNUM to ensure only 1 record
),
XXGL_lkp as (
          SELECT
              flv.attribute1   program_code,
              flv.attribute2   ledger_name,
              flv.attribute3   balancing_entity,
              flv.attribute4   budget_center,
              flv.attribute5   accounts,
              gl.ledger_id
          FROM
              fnd_lookup_values   flv,
              gl_ledgers          gl
          WHERE
              flv.lookup_type = 'XXGL_EXTRACT_CRITERIA'
              AND flv.attribute1 = :program_code
			  --AND flv.attribute1 LIKE 'ACCURATE_LINE%'
			  AND NVL(flv.attribute2,NVL(:ledger_name,'x'))      = NVL(:ledger_name     ,NVL(flv.attribute2,'x'))
			  AND NVL(flv.attribute3,NVL(:balancing_entity,'x')) = NVL(:balancing_entity,NVL(flv.attribute3,'x'))
			  AND NVL(flv.attribute4,NVL(:budget_center,'x'))    = NVL(:budget_center   ,NVL(flv.attribute4,'x'))
			  AND NVL(flv.attribute5,NVL(:accounts,'x'))         = NVL(:accounts        ,NVL(flv.attribute5,'x'))
			  AND NVL(flv.attribute5,NVL(:from_accounts,1)) BETWEEN NVL(:from_accounts      ,NVL(flv.attribute5,1))
			                                                    AND NVL(:to_accounts        ,NVL(flv.attribute5,1))
			  AND nvl(flv.enabled_flag, 'N') = 'Y'
              AND gl.name(+) = flv.attribute2
              AND trunc(sysdate) BETWEEN trunc(nvl(flv.start_date_active, sysdate)) 
			                         AND trunc(nvl(flv.end_date_active, sysdate))
      ),
-- DevOnly_start      
-- xx_fdate_dev as ( select sysdate from_PROCESSSTART from dual),
-- xx_tdate_dev as ( select sysdate to_processstart from dual),
-- DevOnly_end
xx_fdate as (
SELECT * FROM (
          SELECT
              ROWNUM from_rownum,
              d.PROCESSSTART from_PROCESSSTART
          FROM
              (
                  SELECT
                      erh.PROCESSSTART
                  FROM
                      ess_request_history    erh,
                      ess_request_property   erp
                  WHERE
                      erh.requestid = erp.requestid
                      AND erh.definition LIKE '%OML_INT_GL_LINES_P_EXT'
                          AND erp.name LIKE 'submit.argument1'
                              AND erp.value LIKE :program_code
                                  AND erh.executable_status = 'SUCCEEDED'
					UNION
					SELECT
						to_date(tag, 'MM-DD-YYYY HH24:MI:SS') PROCESSSTART
					FROM
						fnd_lookup_values flv_be
					WHERE
						flv_be.lookup_type = 'XXGL_EXTRACT_FILE_INFO'
					AND flv_be.lookup_code = :program_code
				
                  ORDER BY
                      PROCESSSTART DESC	 
                  
              ) d
          FETCH FIRST 2 ROWS ONLY
      ) fdate1
 WHERE 1 = 1
 and fdate1.from_rownum = 2),
xx_tdate as (
SELECT * FROM (
          SELECT
              ROWNUM to_rownum,
              d.PROCESSSTART to_processstart
          FROM
              (
                  SELECT
                      erh.PROCESSSTART
                  FROM
                      ess_request_history    erh,
                      ess_request_property   erp
                  WHERE
                      erh.requestid = erp.requestid
                      AND erh.definition LIKE '%OML_INT_GL_LINES_P_EXT'
                          AND erp.name LIKE 'submit.argument1'
                              AND erp.value LIKE :program_code
                                  AND erh.executable_status = 'SUCCEEDED'
                  ORDER BY
                      erh.PROCESSSTART DESC
              ) d
          FETCH FIRST 2 ROWS ONLY
      ) tdate1
WHERE 1 = 1
and tdate1.to_rownum = 1),										  
xx_cycle_count as (
  SELECT
	  'C'
	  || attribute7
		 || ( to_number(attribute14) + (
		  SELECT
			  nvl(COUNT(*), 0)
		  FROM
			  fusion.ess_request_history   erh,
			  ess_request_property         erp
		  WHERE
			  1 = 1
			  AND erh.definition LIKE '%OML%INT%GL%LINES%C%EXT%'
			
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
),
XX_gcc as 
(
 SELECT gcc1.* 
   FROM gl_code_combinations  gcc1,
        xxgl_lkp  xxgl_lkp1
	WHERE 1 = 1
	AND gcc1.segment1 = nvl(nvl(:balancing_entity,xxgl_lkp1.balancing_entity), gcc1.segment1)
    AND gcc1.segment2 = nvl(nvl(:budget_center   ,xxgl_lkp1.budget_center)   , gcc1.segment2)
    AND gcc1.segment3 = nvl(nvl(:accounts        ,xxgl_lkp1.accounts)        , gcc1.segment3)
	-- CEN-2746_start
	-- Return all if program code does not contain paramater for ACCURATE LINE outbounds
	AND (NVL(xxgl_lkp1.program_code,'x') NOT LIKE 'ACCURATE_%LINE%'
	     OR 
		 -- Accurate specific logic 
		 (xxgl_lkp1.program_code LIKE 'ACCURATE_%LINE%'
	      AND EXISTS (SELECT 1 
		                   FROM fnd_lookup_values flv
					      WHERE 1=1		
					      	AND flv.enabled_flag = 'Y'
			  			    -- effective dates not captured consistently correct as expected
							AND TRUNC(SYSDATE) BETWEEN NVL(flv.start_date_active, TRUNC(SYSDATE)) AND NVL(flv.end_date_active,TRUNC(SYSDATE))
							-- Only return balance sheet accounts for all ACCURATE LINE outbounds
			     	        AND ((flv.lookup_type = 'ACCOUNT TYPE'
                                  AND flv.lookup_code = gcc1.account_type
						          AND flv.meaning IN ('Asset','Liability','Owners'' equity')) 
						     -- Always return gcc for setup specified here irrespective of the balancesheet restriction above
						     OR (flv.lookup_type = 'XXGL_EXTRACT_CRITERIA'
					              -- program_code (we setup and reused the lookup config to specificy same set of criteria for inclusion)
					             AND flv.attribute1 = 'ACCURATE_INCOME_STMNT'
					             -- combination of all 3 entries, of which Ledger, BE must match main (xxgl_lkp1) lookup 
                                 AND flv.attribute2 = xxgl_lkp1.ledger_name
                                 AND flv.attribute3 = xxgl_lkp1.balancing_entity
                                 -- Below not always configured in main (xxgl_lkp1) lookup, there account to map back to gcc
                                 AND flv.attribute5 = gcc1.segment3 --xxgl_lkp1.accounts   
                                 )
                                 )
                      )))
	-- CEN-2746_end
 ),	
xx_gjb as (
select *
from ( select  a.*, rownum rnum
		 from ( SELECT gjb1.je_batch_id gjb2_je_batch_id,
		               gjb1.status      gjb2_status,
					   gjb1.name        gjb2_name,
		               gjh1.*
		          FROM gl_je_batches gjb1,
				       (SELECT gjh.* ,fd.*,td.*
				          FROM gl_je_headers gjh,
					           xx_fdate fd,
	                           xx_tdate td
					     WHERE 1 = 1
					       AND gjh.status = 'P'
                           AND gjh.posted_date >= NVL(to_date(:manual_date, 'DD-MON-YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=AMERICAN'), fd.from_PROCESSSTART)
                           AND gjh.posted_date < NVL( to_date(:manual_date_to, 'DD-MON-YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=AMERICAN'),td.to_PROCESSSTART)
                           AND gjh.je_header_id = NVL(:p_header_id,gjh.je_header_id )
					       AND gjh.period_name = NVL(:p_period_name ,gjh.period_name)
					       and gjh.je_batch_id = NVL(:p_je_batch_id ,gjh.je_batch_id )
				       ) gjh1
		         WHERE 1 = 1				   
				   and gjb1.name = NVL(:p_batch_name ,gjb1.name )
				   -- RPtest_start
                   -- AND gjb1.name in
                   --  ('Accurate SEGMENT3 Test Spreadsheet A 3033393 8702653 N',
                   --   'Accurate SEGMENT3 Test Spreadsheet A 3033394 8702665 N',
                   --   'Accurate SEGMENT3 Test Spreadsheet A 3033396 8702667 N',
                   --   'FAH OM Event Sources A 8662234000001 8662235 N')                    	   
				   -- RPtest_end					   
				   AND gjb1.je_batch_id = gjh1.je_batch_id
		      ORDER BY gjb1.je_batch_id ) a)
where rnum >= NVL(:p_from_batch# ,1)
AND rnum <= NVL(:p_to_batch#,1000000)
),
xx_gjh as (
SELECT gjb2.*,xdd.*,xcc.*
  from xx_gjb gjb2,
	   xx_dril_delimit xdd,
	   xx_cycle_count xcc,
	   (SELECT distinct ledger_id from xxgl_lkp )xlkp
   where 1 = 1
   AND xlkp.ledger_id = gjb2.ledger_id
   --
   
UNION 
SELECT gjb2.*,xdd.*,xcc.*
  from xx_gjb gjb2,
	   xx_dril_delimit xdd,
	   xx_cycle_count xcc
   where 1 = 1
     AND 1 =  (SELECT 1 from  fnd_lookup_values flv
              WHERE flv.lookup_type = 'XXGL_EXTRACT_CRITERIA' 
                AND flv.attribute1 = :program_code
				AND nvl(flv.enabled_flag, 'N') = 'Y'
                AND trunc(sysdate) BETWEEN trunc(nvl(flv.start_date_active, sysdate)) 
			                           AND trunc(nvl(flv.end_date_active, sysdate))
				AND flv.attribute2 IS NULL
				AND ROWNUM = 1)
) ,
fah AS ( 
SELECT 
 gir.je_header_id           C131, --FAH_JE_HEADER_ID,
    gir.je_line_num            C132, --fah_je_line_num,
    xal.accounting_date        C33, --fah_accounting_date,
       nvl(xal.accounted_dr, 0) C34,  --fah_accounted_dr,
		nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
	replace(replace(replace(translate(xal.description,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~','') C142,--fah_line_desc,
    attr_details.attribute1    C50,--fah_att_1,
    attr_details.attribute2    C51  ,--fah_att_2,
    attr_details.attribute3    C52 ,--fah_att_3,
    attr_details.attribute4    C53  ,--fah_att_4,
    attr_details.attribute5    C54  ,--fah_att_5,
    attr_details.attribute6    C55  ,--fah_att_6,
    attr_details.attribute7    C56  ,--fah_att_7,
    attr_details.attribute8    C57  ,--fah_att_8,
    attr_details.attribute9    C58  ,--fah_att_9,
    attr_details.attribute10   C59  ,--fah_att_10,
    attr_details.attribute11   C60  ,--fah_att_11,
    attr_details.attribute12   C61  ,--fah_att_12,
    attr_details.attribute13   C62 ,--fah_att_13,
    attr_details.attribute14   C63 ,--fah_att_14,
    attr_details.attribute15   C64  ,--fah_att_15,
    attr_details.attribute16   C65  ,--fah_att_16,
    attr_details.attribute17   C66  ,--fah_att_17,
    attr_details.attribute18   C67  ,--fah_att_18,
    attr_details.attribute19   C68  ,--fah_att_19,
    attr_details.attribute20   C69  ,--fah_att_20,
    attr_details.attribute21   C93 ,--fah_att_21,
    attr_details.attribute22   C94, --fah_att_22,
    attr_details.attribute23   C133 ,--fah_att_23,
    attr_details.attribute24   C134 ,--fah_att_24,
    attr_details.attribute25   C135 ,--fah_att_25,
    xal.sr56                   C136,--fah_att_26,
    xal.sr59                   C137 ,--fah_att_27,
    xal.sr60                   C138,--fah_att_28,
    attr_details.source_name   C70,--fah_source,
    attr_details.fahkey        C71,--fah_key,
    NULL C72,--supplier_name,
    NULL C73,--supplier_number,
    NULL C74,--payables_invoice_number,
    NULL C75,--asset_number,
    NULL C76,--purchase_order_number,
    NULL C77,--requisition_number,
    NULL C78,--invoice_line_description --defect 177 
          --XAL.DESCRIPTION INVOICE_LINE_DESCRIPTION ,
    NULL C79,--customer_number,
    NULL C80,--customer_name,
    NULL C81,--receivables_invoice_number,
    NULL C82,--receipt_number,
    NULL C83,--check_number,
	xal.sr56  C90,--fah_category
	NULL   C144, --acc_code 
	ROWNUM C84,	
	attr_details.acc_date                    -- #INC0038148 - returning the ACC_DATE for MCS
	-- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end	
  /*  ROWNUM C84,
    NULL   C144,    --acc_code 
   xal.sr56  C90--fah_category,	*/
FROM
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    xx_gjh              gjh,
    gl_je_sources              gjs,
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
    AND attr_details.fah_appl_id= xte.application_id
    AND attr_details.fah_event_id = xe.event_id
    AND attr_details.fah_trx_num= xte.source_id_char_1
    AND attr_details.line_number = xal.SR60
    AND xal.accounting_class_code<>'INTRA'	
UNION
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date   C33, --fah_accounting_date,
    nvl(xal.accounted_dr, 0) C34,  --fah_accounted_dr,
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
    xal.description       fah_line_desc,
    xal.attribute1        fah_att_1,
    xal.attribute2        fah_att_2,
    xal.attribute3        fah_att_3,
    xal.attribute4        fah_att_4,
    xal.attribute5        fah_att_5,
    xal.attribute6        fah_att_6,
    xal.attribute7        fah_att_7,
    xal.attribute8        fah_att_8,
    xal.attribute9        fah_att_9,
    xal.attribute10       fah_att_10,
    xal.attribute11       fah_att_11,
    xal.attribute12       fah_att_12,
    xal.attribute13       fah_att_13,
    xal.attribute14       fah_att_14,
    xal.attribute15       fah_att_15,
    NULL fah_att_16,
    NULL fah_att_17,
    NULL fah_att_18,
    NULL fah_att_19,
    NULL fah_att_20,
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
    'INTRACOMPANY' fah_source,
    NULL fah_key,
    NULL supplier_name,
    NULL supplier_number,
    NULL payables_invoice_number,
    NULL asset_number,
    NULL purchase_order_number,
    NULL requisition_number,
    NULL invoice_line_description,
			--XAL.DESCRIPTION INVOICE_LINE_DESCRIPTION ,
    NULL customer_number,
    NULL customer_name,
    NULL receivables_invoice_number,
    NULL receipt_number,
    NULL check_number,
	xal.sr56  C90,--fah_category
	xal.accounting_class_code   C144, --acc_code 
	ROWNUM C84,
	NULL acc_date                           -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end	
	/*ROWNUM,
    xal.sr56              fah_category,
	xal.accounting_class_code acc_code*/
FROM
    gl_import_references     gir,
    xla_ae_lines             xal,
    xx_gjh            gjh,
    gl_je_sources            gjs
WHERE
    xal.gl_sl_link_id = gir.gl_sl_link_id
    AND xal.gl_sl_link_table = gir.gl_sl_link_table
    AND gjs.user_je_source_name LIKE 'FAH%'
	AND xal.accounting_class_code = 'INTRA'
    AND gjh.je_header_id = gir.je_header_id
    AND gjh.je_source = gjs.je_source_name
UNION
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date-- ACCOUNTING_DATE
    nvl(xal.accounted_dr, 0) C34,  --fah_accounted_dr,
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
NULL,
null -- LINE_ATTRIBUTE_1
,
NULL -- LINE_ATTRIBUTE_2       
,
to_char(acr.cash_receipt_id) fah_att_3, -- LINE_ATTRIBUTE_3        
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
NULL fah_att_21,
NULL fah_att_22,
NULL fah_att_23,
NULL fah_att_24,
NULL fah_att_25,
NULL fah_att_26,
NULL fah_att_27,
NULL fah_att_28,
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
replace(replace(replace(xal.description, CHR(09), ''), CHR(10), ''), CHR(13), '') invoice_line_description -- INVOICE_LINE_DESCRIPTION        
,
to_char(hzp.party_number) customer_number -- CUSTOMER_NUMBER        
,
hzp.party_name  customer_name-- CUSTOMER_NAME        
,
NULL --GetArTranNumber(xal.ae_header_id, xal.ae_line_num, acr.cash_receipt_id)  -- RECEIVABLES_INVOICE_NUMBER        
,
acr.receipt_number receipt_number -- RECEIPT_NUMBER        
,
NULL -- CHECK_NUMBER        
,
xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                    -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
	-- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end	
/*ROWNUM,
xal.sr56 fah_category,
NULL acc_code*/
FROM
    gl_je_lines                gll,
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    ar_cash_receipts_all       acr,
    hz_cust_accounts           hca,
    hz_parties                 hzp,
    fnd_lookup_values          lv,
    xx_gjh              gjh,
    gl_je_sources              gjs
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
                                                                                    AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active
                                                                                    (+), sysdate)) AND trunc(nvl(lv.end_date_active
                                                                                    (+), sysdate))
                                                                                        AND xal.party_id = hca.cust_account_id (+
                                                                                        )
                                                                                            AND hca.party_id = hzp.party_id (+)
UNION
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
    nvl(xal.accounted_dr, 0) C34,  --fah_accounted_dr,
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
    NULL,
    NULL -- LINE_ATTRIBUTE_1
    ,
    to_char(rct.customer_trx_id) fah_att_2 -- LINE_ATTRIBUTE_2
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
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
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
    replace(replace(replace(xal.description, CHR(09), ''), CHR(10), ''), CHR(13), '') invoice_line_description-- INVOICE_LINE_DESCRIPTION
    ,
    to_char(hp.party_number) customer_number-- CUSTOMER_NUMBER
    ,
    hp.party_name customer_name -- CUSTOMER_NAME
    ,
    to_char(rct.trx_number) receivables_invoice_number -- RECEIVABLES_INVOICE_NUMBER
    ,
    NULL -- RECEIPT_NUMBER
    ,
    NULL -- CHECK_NUMBER
    ,
	xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                          -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
	-- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end	 
 /* ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code */
FROM
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    ra_customer_trx_all        rct,
    hz_parties                 hp,
    hz_cust_accounts           hca,
    fnd_lookup_values          lv,
    xx_gjh              gjh,
    gl_je_sources              gjs
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
                                                                                AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active
                                                                                (+), sysdate)) AND trunc(nvl(lv.end_date_active(+
                                                                                ), sysdate))
                                                                                    AND hp.party_id = hca.party_id
UNION 
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num  C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
    nvl(xal.accounted_dr, 0) C34,  --fah_accounted_dr,
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
    NULL,
    to_char(aaa.adjustment_id) fah_att_1-- line_attribute_1
    ,
    to_char(rct.customer_trx_id) fah_att_2 -- LINE_ATTRIBUTE_2
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
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
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
    replace(replace(replace(xal.description, CHR(09), ''), CHR(10), ''), CHR(13), '') invoice_line_description -- INVOICE_LINE_DESCRIPTION
    ,
    to_char(hp.party_number) customer_number -- CUSTOMER_NUMBER
    ,
    hp.party_name customer_name -- CUSTOMER_NAME
    ,
    to_char(rct.trx_number)  receivables_invoice_number-- RECEIVABLES_INVOICE_NUMBER
    ,
    NULL -- RECEIPT_NUMBER
    ,
    NULL -- CHECK_NUMBER
    ,
	xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                         -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
   	-- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end	
    /* ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code */
FROM
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    ra_customer_trx_all        rct,
    hz_parties                 hp,
    ar_adjustments_all         aaa,
    hz_cust_accounts           hca,
    fnd_lookup_values          lv,
    xx_gjh              gjh,
    gl_je_sources              gjs
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
                                                                                        AND trunc(sysdate) BETWEEN trunc(nvl(lv.start_date_active
                                                                                        (+), sysdate)) AND trunc(nvl(lv.end_date_active
                                                                                        (+), sysdate))
                                                                                            AND hp.party_id = hca.party_id
UNION 
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
    /*decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr, 0), nvl(xdl.unrounded_accounted_dr, 0)
    )), '999999999999999999999999999999.99')))*/ 
	 decode(xal.ae_header_id,NULL,nvl(gjl.accounted_dr, 0),decode(xdl.ae_header_id,NULL,nvl(xal.accounted_dr, 0),nvl(xdl.unrounded_accounted_dr, 0))) C34,--fah_accounted_dr -- ACCOUNTED_DR
   /* decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr
    , 0), nvl(xdl.unrounded_accounted_cr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)
    )), '999999999999999999999999999999.99'))) */
	decode(xal.ae_header_id,NULL,nvl(gjl.accounted_cr, 0),decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0))) C35, --fah_accounted_cr,
    decode(TRIM(to_char((decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id
    , NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)))), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr,
    0), nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL
    , nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)))), '999999999999999999999999999999.99'))) C36,--fah_net_movement, -- NET_MOVEMENT
    NULL,
    to_char(ail.product_table) fah_att_1 -- LINE_ATTRIBUTE_1
    ,
    to_char(ail.reference_key1)  fah_att_2-- LINE_ATTRIBUTE_2
    ,
    to_char(ail.reference_key2) fah_att_3-- LINE_ATTRIBUTE_3
    ,
    to_char(aid.po_distribution_id) fah_att_4 -- LINE_ATTRIBUTE_4
    ,
    to_char(aid.charge_applicable_to_dist_id) fah_att_5-- LINE_ATTRIBUTE_5
    ,
    NULL -- LINE_ATTRIBUTE_6
    ,
    NULL -- LINE_ATTRIBUTE_7
    ,
    to_char(aia.invoice_id) fah_att_8-- LINE_ATTRIBUTE_8
    ,
    to_char(aid.invoice_distribution_id)  fah_att_9-- LINE_ATTRIBUTE_9
    ,
    to_char(ail.line_number) fah_att_10-- LINE_ATRIBUTE_10
    ,
    aid.reversal_flag fah_att_11-- LINE_ATTRIBUTE_11
    ,
    lt.meaning fah_att_12-- LINE_ATTRIBUTE_12
    ,
    NULL -- LINE_ATTRIBUTE_13
    ,
    nvl(dt.meaning, aid.line_type_lookup_code) fah_att_14-- LINE_ATTRIBUTE_14
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
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
    aia.source  fah_source-- FAH_SOURCE
    ,
    NULL -- FAH_KEY
    ,
    asa.vendor_name supplier_name-- SUPPLIER_NAME
    ,
    asa.segment1 supplier_number-- SUPPLIER_NUMBER
    ,
    replace(replace(replace(aia.invoice_num, CHR(09), ''), CHR(10), ''), CHR(13), '') payables_invoice_number-- PAYABLES_INVOICE_NUMBER
    ,
    NULL -- ASSET_NUMBER
    ,
    NULL -- PURCHASE_ORDER_NUMBER
    ,
    NULL -- REQUISITION_NUMBER
    ,
    replace(replace(replace(nvl(aid.description, xal.description), CHR(9), ''), CHR(10), ''), CHR(13), '') invoice_line_description-- INVOICE_LINE_DESCRIPTION
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
	xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                           -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,decode(xal.ae_header_id,NULL,gjl.entered_dr,decode(xdl.ae_header_id,NULL,xal.entered_dr,xdl.unrounded_entered_dr)) entered_dr,
	decode(xal.ae_header_id,NULL,gjl.entered_cr,decode(xdl.ae_header_id, NULL,xal.entered_cr,xdl.unrounded_entered_dr)) entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end		
	/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
FROM
    gl_je_lines                    gjl,
    xx_gjh                  gjh,
    gl_je_sources                  gjs,
    gl_import_references           gir,
    xla_ae_lines                   xal,
    xla_ae_headers                 xah,
    xla_transaction_entities       xte,
    xla_distribution_links         xdl,
    ap_invoice_distributions_all   aid,
    ap_invoice_lines_all           ail,
    ap_invoices_all                aia,
    fnd_lookup_values              lt,
    fnd_lookup_values              dt,
    poz_suppliers_v                asa
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
                                                                                AND xdl.source_distribution_id_num_1 = aid.invoice_distribution_id
                                                                                (+)
                                                                                    AND aid.invoice_id = ail.invoice_id (+)
                                                                                        AND aid.invoice_line_number = ail.line_number
                                                                                        (+)
                                                                                            AND xte.source_id_int_1 = aia.invoice_id
                                                                                            (+)
                                                                                                AND ail.line_type_lookup_code = lt
                                                                                                .lookup_code (+)
                                                                                                    AND lt.lookup_type (+) = 'INVOICE LINE TYPE'
                                                                                                        AND lt.enabled_flag (+) =
                                                                                                        'Y'
                                                                                                            AND trunc(sysdate) BETWEEN
                                                                                                            trunc(nvl(lt.start_date_active
                                                                                                            (+), sysdate)) AND trunc
                                                                                                            (nvl(lt.end_date_active
                                                                                                            (+), sysdate))
                                                                                                                AND aid.line_type_lookup_code
                                                                                                                = dt.lookup_code (
                                                                                                                +)
                                                                                                                    AND dt.lookup_type
                                                                                                                    (+) = 'INVOICE DISTRIBUTION TYPE'
                                                                                                                        AND dt.enabled_flag
                                                                                                                        (+) = 'Y'
                                                                                                                            AND trunc
                                                                                                                            (sysdate
                                                                                                                            ) BETWEEN
                                                                                                                            trunc
                                                                                                                            (nvl(
                                                                                                                            dt.start_date_active
                                                                                                                            (+), sysdate
                                                                                                                            )) AND
                                                                                                                            trunc
                                                                                                                            (nvl(
                                                                                                                            dt.end_date_active
                                                                                                                            (+), sysdate
                                                                                                                            ))
                                                                                                                                AND
                                                                                                                                aia
                                                                                                                                .
                                                                                                                                vendor_id
                                                                                                                                =
                                                                                                                                asa
                                                                                                                                .
                                                                                                                                vendor_id
                                                                                                                                (
                                                                                                                                +
                                                                                                                                )
UNION 
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date  C33, --fah_accounting_date--ACCOUNTING_DATE
    /*  decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr, 0), nvl(xdl.unrounded_accounted_dr, 0)
    )), '999999999999999999999999999999.99'))) fah_accounted_dr,*/
	decode(xal.ae_header_id,NULL,nvl(gjl.accounted_dr, 0),decode(xdl.ae_header_id,NULL,nvl(xal.accounted_dr, 0),nvl(xdl.unrounded_accounted_dr, 0))) C34,  --fah_accounted_dr,
   /* decode(TRIM(to_char(decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr
    , 0), nvl(xdl.unrounded_accounted_cr, 0))), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(decode(xal.ae_header_id
    , NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)
    )), '999999999999999999999999999999.99'))) fah_accounted_cr,*/
	decode(xal.ae_header_id,NULL,nvl(gjl.accounted_cr, 0),decode(xdl.ae_header_id, NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0))) C35, --fah_accounted_cr,
    decode(TRIM(to_char((decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr
    , 0), nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id
    , NULL, nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)))), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((decode(xal.ae_header_id, NULL, nvl(gjl.accounted_dr, 0), decode(xdl.ae_header_id, NULL, nvl(xal.accounted_dr,
    0), nvl(xdl.unrounded_accounted_dr, 0))) - decode(xal.ae_header_id, NULL, nvl(gjl.accounted_cr, 0), decode(xdl.ae_header_id, NULL
    , nvl(xal.accounted_cr, 0), nvl(xdl.unrounded_accounted_cr, 0)))), '999999999999999999999999999999.99'))) C36,--fah_net_movement
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
    to_char(aia.invoice_id) fah_att_8-- LINE_ATTRIBUTE_8
    ,
    to_char(aid.invoice_distribution_id) fah_att_9 -- LINE_ATTRIBUTE_9
    ,
    to_char(ail.line_number) fah_att_10-- LINE_ATTRIBUTE_10
    ,
    NULL --aid.reversal_flag                                                                -- LINE_ATTRIBUTE_11
    ,
    NULL --lt.meaning                                                                       -- LINE_ATTRIBUTE_12
    ,
    to_char(aca.check_date, 'DD-MON-YYYY') fah_att_13-- LINE_ATTRIBUTE_13
    ,
    nvl(dt.meaning, aid.line_type_lookup_code) fah_att_14-- LINE_ATTRIBUTE_14
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
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
    aia.source -- FAH_SOURCE
    ,
    NULL -- FAH_KEY
    ,
    aps.vendor_name supplier_name-- SUPPLIER_NAME
    ,
    aps.segment1 supplier_number-- SUPPLIER_NUMBER
    ,
    to_char(replace(replace(replace(aia.invoice_num, CHR(09), ''), CHR(10), ''), CHR(13), '')) payables_invoice_number -- PAYABLES_INVOICE_NUMBER
    ,
    NULL -- ASSET_NUMBER
    ,
    NULL -- PURCHASE_ORDER_NUMBER
    ,
    NULL -- REQUISITION_NUMBER
    ,
    replace(replace(replace(nvl(xal.description, xah.description), CHR(09), ''), CHR(10), ''), CHR(13), '') invoice_line_description -- INVOICE_LINE_DESCRIPTION
    ,
    NULL -- CUSTOMER_NUMBER
    ,
    NULL -- CUSTOMER_NAME
    ,
    NULL -- RECEIVABLES_INVOICE_NUMBER
    ,
    NULL -- RECEIPT_NUMBER
    ,
    to_char(aca.check_number) check_number-- CHECK_NUMBER
    ,
	xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date               -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,decode(xal.ae_header_id,NULL,nvl(gjl.entered_dr, 0),decode(xdl.ae_header_id,NULL,nvl(xal.entered_dr, 0),nvl(xdl.unrounded_entered_dr, 0))) entered_dr,
	decode(xal.ae_header_id,NULL,nvl(gjl.entered_cr, 0),decode(xdl.ae_header_id, NULL, nvl(xal.entered_cr, 0), nvl(xdl.unrounded_entered_dr, 0))) entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end		
    /*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
FROM
    gl_je_lines                    gjl,
    xx_gjh                  gjh,
    gl_import_references           gir,
    xla_ae_lines                   xal,
    xla_ae_headers                 xah,
    xla_transaction_entities       xte,
    xla_distribution_links         xdl,
    ap_checks_all                  aca,
    ap_payment_hist_dists          phd,
    ap_invoice_distributions_all   aid,
    ap_invoices_all                aia,
    ap_invoice_lines_all           ail,
    fnd_lookup_values              lt,
    fnd_lookup_values              dt,
    poz_suppliers_v                aps,
    gl_je_sources                  gjs
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
                                                                                AND xdl.source_distribution_id_num_1 = phd.payment_hist_dist_id
                                                                                (+)
                                                                                    AND phd.invoice_distribution_id = aid.invoice_distribution_id
                                                                                    (+)
                                                                                        AND aid.invoice_id = aia.invoice_id (+)
                                                                                            AND aid.invoice_id = ail.invoice_id (
                                                                                            +)
                                                                                                AND aid.invoice_line_number = ail
                                                                                                .line_number (+)
                                                                                                    AND ail.line_type_lookup_code
                                                                                                    = lt.lookup_code (+)
                                                                                                        AND lt.lookup_type (+) = 'INVOICE LINE TYPE'
                                                                                                            AND lt.enabled_flag (
                                                                                                            +) = 'Y'
                                                                                                                AND trunc(sysdate
                                                                                                                ) BETWEEN trunc(nvl
                                                                                                                (lt.start_date_active
                                                                                                                (+), sysdate)) AND
                                                                                                                trunc(nvl(lt.end_date_active
                                                                                                                (+), sysdate))
                                                                                                                    AND aid.line_type_lookup_code
                                                                                                                    = dt.lookup_code
                                                                                                                    (+)
                                                                                                                        AND dt.lookup_type
                                                                                                                        (+) = 'INVOICE DISTRIBUTION TYPE'
                                                                                                                            AND dt
                                                                                                                            .enabled_flag
                                                                                                                            (+) =
                                                                                                                            'Y'
                                                                                                                                AND
                                                                                                                                trunc
                                                                                                                                (
                                                                                                                                sysdate
                                                                                                                                )
                                                                                                                                BETWEEN
                                                                                                                                trunc
                                                                                                                                (
                                                                                                                                nvl
                                                                                                                                (
                                                                                                                                dt
                                                                                                                                .
                                                                                                                                start_date_active
                                                                                                                                (
                                                                                                                                +
                                                                                                                                )
                                                                                                                                ,
                                                                                                                                sysdate
                                                                                                                                )
                                                                                                                                )
                                                                                                                                AND
                                                                                                                                trunc
                                                                                                                                (
                                                                                                                                nvl
                                                                                                                                (
                                                                                                                                dt
                                                                                                                                .
                                                                                                                                end_date_active
                                                                                                                                (
                                                                                                                                +
                                                                                                                                )
                                                                                                                                ,
                                                                                                                                sysdate
                                                                                                                                )
                                                                                                                                )
                                                                                                                                    AND
                                                                                                                                    xal
                                                                                                                                    .
                                                                                                                                    party_id
                                                                                                                                    =
                                                                                                                                    aps
                                                                                                                                    .
                                                                                                                                    vendor_id
                                                                                                                                    (
                                                                                                                                    +
                                                                                                                                    )
UNION
SELECT
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,  
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
   nvl(xal.accounted_dr, 0) C34, --fah_accounted_dr-- ACCOUNTED_DR
   nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
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
    to_char(faa.asset_id) fah_att_8-- LINE_ATTRIBUTE_8
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
    to_char(faa.tag_number) fah_att_14-- LINE_ATTRIBUTE_14
    ,
    to_char(faa.serial_number) fah_att_15 -- LINE_ATTRIBUTE_15
    ,
    to_char(fdd.book_type_code) fah_att_16-- LINE_ATTRIBUTE_16
    ,
    NULL -- LINE_ATTRIBUTE_17
    ,
    fac.segment1
    || '.'
       || fac.segment2  fah_att_18-- LINE_ATTRIBUTE_18
       ,
    NULL -- LINE_ATTRIBUTE_19
    ,
    NULL -- GetFaAssignedTo(faa.asset_id, fdd.book_type_code) -- LINE_ATTRIBUTE_20
    ,
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
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
    to_char(faa.asset_number) asset_number -- ASSET_NUMBER
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
	xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end		
    /*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
FROM
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    fa_deprn_detail            fdd,
    fa_additions_b             faa,
    fa_categories_b            fac,
    xx_gjh              gjh,
    gl_je_sources              gjs
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
    gir.je_header_id C131, --FAH_JE_HEADER_ID,
    gir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
    nvl(xal.accounted_dr, 0) C34,--fah_accounted_dr -- ACCOUNTED_DR
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
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
    to_char(faa.asset_id) fah_att_8-- LINE_ATTRIBUTE_8
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
    to_char(faa.tag_number) fah_att_14-- LINE_ATTRIBUTE_14
    ,
    to_char(faa.serial_number) fah_att_15-- LINE_ATTRIBUTE_15
    ,
    to_char(fth.book_type_code) fah_att_16-- LINE_ATTRIBUTE_16
    ,
    NULL -- LINE_ATTRIBUTE_17
    ,
    fac.segment1
    || '.'
       || fac.segment2 fah_att_18-- LINE_ATTRIBUTE_18
       ,
    NULL -- LINE_ATTRIBUTE_19
    ,
    NULL --GetFaAssignedTo(faa.asset_id, fth.book_type_code) -- LINE_ATTRIBUTE_20
    ,
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
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
    to_char(faa.asset_number) asset_number -- ASSET_NUMBER
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
    xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                  -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end		
/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
FROM
    gl_import_references       gir,
    xla_ae_lines               xal,
    xla_ae_headers             xah,
    xla_events                 xe,
    xla_transaction_entities   xte,
    fa_transaction_headers     fth,
    fa_additions_b             faa,
    fa_categories_b            fac,
    xx_gjh              gjh,
    gl_je_sources              gjs
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
    glir.je_header_id C131, --FAH_JE_HEADER_ID,
    glir.je_line_num C132, --fah_je_line_num,
    xal.accounting_date C33, --fah_accounting_date --ACCOUNTING_DATE
    nvl(xal.accounted_dr, 0) C34,--fah_accounted_dr-- ACCOUNTED_DR
    nvl(xal.accounted_cr, 0) C35, --fah_accounted_cr,
    decode(TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
    , TRIM(to_char((nvl(xal.accounted_dr, 0) - nvl(xal.accounted_cr, 0)), '999999999999999999999999999999.99'))) C36--fah_net_movement
    ,
    NULL,
    to_char(pha.po_header_id) fah_att_1-- LINE_ATTRIBUTE_1
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
    NULL fah_att_21,
    NULL fah_att_22,
    NULL fah_att_23,
    NULL fah_att_24,
    NULL fah_att_25,
    NULL fah_att_26,
    NULL fah_att_27,
    NULL fah_att_28,
    NULL -- FAH_SOURCE
    ,
    NULL -- FAH_KEY
    ,
    ass.vendor_name supplier_name-- SUPPLIER_NAME
    ,
    ass.segment1 supplier_number-- SUPPLIER_NUMBER
    ,
    NULL -- PAYABLES_INVOICE_NUMBER
    ,
    NULL -- ASSET_NUMBER
    ,
    pha.segment1 purchase_order_number-- PURCHASE_ORDER_NUMBER
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
    xal.sr56  C90,--fah_category
NULL   C144, --acc_code 
ROWNUM C84,
NULL acc_date                -- #INC0038148 - added NULL column to match the columns returned across all UNIONs
    -- CEN-71_start
    ,xal.entered_dr,
	xal.entered_cr,
	xal.currency_code,
	xal.currency_conversion_date,
	xal.currency_conversion_rate,
	xal.currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
    null filler1,
    null filler2,
    null filler3,
    null filler4,
    null filler5,
    null filler6
	-- CEN-71_end		
/*ROWNUM,
    xal.sr56 fah_category,
	NULL acc_code*/
FROM
    --gl_je_batches              gjb,
    xx_gjh              gjh,
    gl_je_lines                gll,
    xx_gcc       gcc,
    gl_import_references       glir,
    gl_ledgers                 gl,
    xla_ae_lines               xal,
    xla_ae_headers             xlh,
    xla_events                 xle,
    xla_transaction_entities   xlte,
    xla_distribution_links     xldl,
    rcv_transactions           rt,
    rcv_shipment_lines         rsl,
    rcv_shipment_headers       rsh,
    poz_suppliers_v            ass,
    po_distributions_all       pda,
    po_headers_all             pha,
    po_lines_all               pla,
    gl_je_sources              gjs
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
                                                                                                        AND xlte.source_id_int_1 =
                                                                                                        rt.transaction_id
                                                                                                            AND rt.shipment_header_id
                                                                                                            = rsh.shipment_header_id
                                                                                                                AND rt.shipment_line_id
                                                                                                                = rsl.shipment_line_id
                                                                                                                    AND rt.po_header_id
                                                                                                                    = pha.po_header_id
                                                                                                                        AND rt.po_line_id
                                                                                                                        = pla.po_line_id
                                                                                                                            AND rt
                                                                                                                            .po_distribution_id
                                                                                                                            = pda
                                                                                                                            .po_distribution_id
                                                                                                                                AND
                                                                                                                                pha
                                                                                                                                .
                                                                                                                                vendor_id
                                                                                                                                =
                                                                                                                                ass
                                                                                                                                .
                                                                                                                                vendor_id
                                                                                                                                    AND
                                                                                                                                    gjh
                                                                                                                                    .
                                                                                                                                    je_source
                                                                                                                                    =
                                                                                                                                    'Cost Management'
) /*SELECT * FROM FAH WHERE C131 = 2264860 and C132 = 236*/ ,
MAIN_EXTRACT AS(
SELECT DISTINCT 
      1 C127 ,--"KEY" C127,
      gjh.cycle_count C86,--cycle_count,
      1 C141,--"ROW_TYPE" C141,
      gjh.ledger_id C1,
      (
          SELECT
              name
          FROM
              gl_ledgers gl
          WHERE
              gl.ledger_id = gjh.ledger_id
      )  C2,-- ledger_name,
      gcc.segment1 C3,
      decode(gcc.segment1, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 1, gcc.segment1)) C4--segment1_desc
      ,
      gcc.segment2 C5,
      decode(gcc.segment2, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 2, gcc.segment2)) C6--segment2_desc
      ,
      gcc.segment3 C7,
      decode(gcc.segment3, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 3, gcc.segment3)) C8--segment3_desc
      ,
      gcc.segment4 C9,
      decode(gcc.segment4, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 4, gcc.segment4)) C10--segment4_desc
      ,
      gcc.segment5 C11,
      decode(gcc.segment5, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 5, gcc.segment5)) C12--segment5_desc
      ,
      gcc.segment6 C13,
      decode(gcc.segment6, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 6, gcc.segment6)) C14--segment6_desc
      ,
      gcc.segment7 C15,
      decode(gcc.segment7, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 7, gcc.segment7)) C16--segment7_desc
      ,
      gcc.segment8 C17,
      decode(gcc.segment8, NULL, NULL, gl_flexfields_pkg.get_description_sql(gcc.chart_of_accounts_id, 8, gcc.segment8)) C18--segment8_desc
      ,
      gcc.segment9 C19,
	  
      (
          SELECT
              ffvt.description
          FROM
              fnd_flex_value_sets   ffvs,
              fnd_flex_values       ffv,
              fnd_flex_values_tl    ffvt
          WHERE
              ffvs.flex_value_set_id = ffv.flex_value_set_id
              AND ffv.flex_value_id = ffvt.flex_value_id
                  AND ffvs.flex_value_set_name = 'OM_EBC_SPARE2'
                      AND ffv.flex_value = gcc.segment9
      ) C20,--"SEGMENT9_DESC" ,
     gcc.segment10 C21,
      (
          SELECT
              ffvt.description
          FROM
              fnd_flex_value_sets   ffvs,
              fnd_flex_values       ffv,
              fnd_flex_values_tl    ffvt
          WHERE
              ffvs.flex_value_set_id = ffv.flex_value_set_id
              AND ffv.flex_value_id = ffvt.flex_value_id
                  AND ffvs.flex_value_set_name = 'OM_EBC_SPARE3'
                      AND ffv.flex_value = gcc.segment10
      ) C22,--"SEGMENT10_DESC" ,
      gjl.code_combination_id C23,
      gjh.currency_code C24,
      gjl.period_name C25,
      gps.period_num C26,
      to_char(to_date(to_char(substr(gps.period_name, - 2)), 'RR'), 'RRRR') C128, --period_month,
      gps.period_year C27,
      gcc.account_type C28,
      gjl.je_line_num C29,
     (
          CASE
              WHEN gjs.user_je_source_name LIKE 'FAH%' THEN
                  replace(replace(replace(translate(fah.C142,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~','')
              ELSE
                   replace(replace(replace(translate(gjl.description,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~','')
				  
          END
      ) C30 ,--line_description,
      gjl.last_update_date C31,
      to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS.FF') C92,--extract_date,
      --to_date(to_char(gjl.effective_date, 'YYYY-MM-DD'), 'YYYY-MM-DD') C105 ,--effective_date,                   -- #INC0038148 - original commented out
	  decode(fah.C90,'MCS',nvl(to_date(to_char(fah.acc_date, 'YYYY-MM-DD'), 'YYYY-MM-DD'), to_date(to_char(gjl.effective_date, 'YYYY-MM-DD'), 'YYYY-MM-DD')), to_date(to_char(gjl.effective_date, 'YYYY-MM-DD'), 'YYYY-MM-DD') ) C105,  -- #INC0038148 - display different Accouting Dates for MCS, else default
     NVL(NVL(fah.C34,gjl.accounted_dr),0) C106 , --accounted_dr,
	 NVL(NVL(fah.C35,gjl.accounted_cr),0) C87,--accounted_cr,
     decode(TRIM(to_char((nvl(gjl.accounted_dr, 0) - nvl(gjl.accounted_cr, 0)), '999999999999999999999999999999.99')), '.00', '0.00'
      , TRIM(to_char((nvl(gjl.accounted_dr, 0) - nvl(gjl.accounted_cr, 0)), '999999999999999999999999999999.99'))) C129 ,--net_amount,
      decode(TRIM(to_char(nvl(gjl.stat_amount, 0), '999999999999999999999999999999.99')), '.00', '0.00', TRIM(to_char(nvl(gjl.stat_amount
      , 0), '999999999999999999999999999999.99'))) C88,--stat_amount,
      --gjb.name batch_name,
	  gjh.gjb2_name C38, --batch_name C38
      --gjb.status,
	  gjh.gjb2_status C39,
      gjh.je_header_id C40,
      gjh.date_created C41,
      gjh.created_by C42,
      gjh.creation_date C43,
      gjh.posted_date C44,
      gjh.name C45,
      gjs.user_je_source_name C46,
      gjc.user_je_category_name C47,
      substr(gjc.user_je_category_name, 1, 3) C91,--category_substr,	 
	  -- CEN-3083_start
	  -- Not sure what the intend was with multiple variations of replace, will keep it as is becuase of the former but new columns will only substitute \t\n\r and delimeter
	  -- replace(replace(replace(translate(gjh.description,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~','') C48 ,--description,	  
	  replace(replace(replace(replace(translate(gjh.description,chr(10) || chr(13) || chr(09), ' '),'|',''),',',''),'~',''),DELIMITER,' ') C48 ,--description,
      gjh.external_reference C49,
      gjh.je_source C130,
      -- gjl.reference_1 C107,
	  gjl.reference_1 C107,
	  gjl.reference_2 C108,
      gjl.reference_3 C109,
      gjl.reference_4 C110,
      gjl.reference_5 C111,
      gjl.reference_6 C122,
      gjl.reference_7 C123,
      gjl.reference_8 C124,
      gjl.reference_9 C125,
      gjl.reference_10 C126,
      gjl.attribute1 C95,
      gjl.attribute2 C96,
      gjl.attribute3  C97,
      gjl.attribute4 C98,
      gjl.attribute5 C99,
      gjl.attribute6 C100,
      gjl.attribute7 C101,
      gjl.attribute8 C102,
      gjl.attribute9 C103,
      gjl.attribute10 C104,
      gjl.attribute11 C112,
      gjl.attribute12 C113,
      gjl.attribute13 C114,
      gjl.attribute14 C115,
      gjl.attribute15 C116,
      gjl.attribute16 C117,
      gjl.attribute17 C118,
      gjl.attribute18 C119,
      gjl.attribute19 C120,
      gjl.attribute20 C121,
	  -- CEN-CEN-3083_end
      fah.*,
      gjh.delimiter delimiter,
      gjh.drilldown  C85 ,
      TO_CHAR(FROM_TZ(CAST(gjh.from_PROCESSSTART AS TIMESTAMP), 'GMT') at time zone 'CET', 'DD-MM-YYYY HH24:MI:SS') C139,-- "From date",
      TO_CHAR(FROM_TZ(CAST(gjh.to_PROCESSSTART AS TIMESTAMP), 'GMT') at time zone 'CET', 'DD-MM-YYYY HH24:MI:SS') C140,--"To Date",
   --Row_number() over (partition by fah.fah_je_line_num order by fah.fah_je_header_id)   C143--sl_count
    Row_number() over (partition by fah.C132 order by fah.C131)   C143, --sl_count,
	-- CEN-71_start
	NVL(NVL(fah.entered_dr,gjl.entered_dr),0) gl_entered_dr,
	NVL(NVL(fah.entered_cr,gjl.entered_cr),0) gl_entered_cr,	
	gl.currency_code gl_currency_code, --#accounted_currency_code
	-- #GL_CURRENCY_CONVERSION_DATE 
	-- TO_CHAR(NVL(fah.currency_conversion_date,gjl.currency_conversion_date),'YYYY-MM-DD') gl_currency_conversion_date,
	DECODE(gl.currency_code, 	       
	       gjh.currency_code, gjl.currency_conversion_date, 
	       -- GL_ACCOUNTED_CURRENCY_CODE is different ENTERED_CURRENCY_CODE), then drill back to subledger to retrieve 
	       fah.currency_conversion_date) gl_currency_conversion_date,
	-- #GL_CURRENCY_CONVERSION_RATE 	
	-- NVL(fah.currency_conversion_rate,gjl.currency_conversion_rate) gl_currency_conversion_rate, 
	DECODE(gl.currency_code, 	       
	       gjh.currency_code, gjl.currency_conversion_rate, 
	       -- GL_ACCOUNTED_CURRENCY_CODE is different ENTERED_CURRENCY_CODE), then drill back to subledger to retrieve 
	       fah.currency_conversion_rate) gl_currency_conversion_rate,
	-- #GL_CURRENCY_CONVERSION_TYPE        
	-- NVL(fah.currency_conversion_type,gjl.currency_conversion_type) gl_currency_conversion_type,
    DECODE(gl.currency_code, 	       
	       gjh.currency_code, gjl.currency_conversion_type, 
	       -- GL_ACCOUNTED_CURRENCY_CODE is different ENTERED_CURRENCY_CODE), then drill back to subledger to retrieve 
	       fah.currency_conversion_type) gl_currency_conversion_type,
	-- Adding fillers here,so next guy knows where to put and naming remains as expected
	-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
	-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
    null gl_filler1,
    null gl_filler2,
    null gl_filler3,
    null gl_filler4,
    null gl_filler5,
    null gl_filler6
	-- CEN-71_end	
  FROM
      xx_gjh          gjh,
      gl_je_lines            gjl,
      --gl_je_batches          gjb,
      xx_gcc   gcc,
      gl_je_sources          gjs,
      gl_je_categories       gjc,
      gl_period_statuses     gps,
      fah,
      gl_ledgers             gl
  WHERE 1 = 1
    AND gjh.je_header_id           =  gjl.je_header_id
    --AND gjh.je_batch_id            =  gjb.je_batch_id
    AND gl.ledger_id = gjh.ledger_id
   -- AND gjh.je_header_id           =  fah.fah_je_header_id (+)
   AND gjh.je_header_id           =  fah.C131 (+)
    AND gjl.je_line_num            =  fah.C132 (+)
    AND gjl.code_combination_id    =  gcc.code_combination_id
    AND gjh.je_source              =  gjs.je_source_name
    AND gjs.user_je_source_name    <> 'CONVERSION'
    AND gjh.je_category            =  gjc.je_category_name
    AND gps.closing_status         =  decode(:p_open_period, 'Y', 'O', 'N', 'C',gps.closing_status)
    AND gps.closing_status        IN  ('C','O' )
    AND gps.application_id         =  101
    AND gjh.ledger_id              =  gps.ledger_id
    AND gjh.period_name            =  gps.period_name
    AND gps.adjustment_period_flag =  decode(:p_include_adjustment, 'N', 'N', gps.adjustment_period_flag)
    AND 1 = (CASE               
             WHEN :program_code = 'MCS_LINE'
              AND fah.C70 IS NOT NULL
			  AND fah.C136 IN ( 'DISB', 'MCS' ) 
             THEN 1
			 WHEN :program_code = 'MCS_LINE'
              AND fah.C136 IN ( 'DISB', 'MCS' ) 
             THEN 1
             WHEN :program_code = 'ADMIN_LINE'
			  AND fah.C136 IN ( 'DISB', 'MCS', 'ADMIN' )
             THEN 1
             WHEN :program_code = 'ADMIN_LINE' 
			  AND gjs.user_je_source_name = 'Spreadsheet'
              AND gl.name IN ( 'OM - RSA Ledger', 'OM - NAM Ledger' ) 
             THEN 1
             WHEN :program_code = 'RMM_COMM_LINE'
			  AND fah.C136 = 'RMM COMM' 
             THEN 1
             WHEN :program_code NOT IN ( 'MCS_LINE', 'ADMIN_LINE', 'RMM_COMM_LINE' ) 
              THEN 1
             WHEN FAH.C70 IS NOT NULL 
			   AND FAH.C144='INTRA' 
             THEN 1
             ELSE 0
             END
)),
T_RECORD AS(
SELECT 
C3 TC3, COUNT(C3) Count_TC3 , TO_CHAR(SUM(NVL(C106,0)),'fm9999999999999990.00') SUM_TC106 , 
TO_CHAR(SUM(NVL(C87,0)),'fm9999999999999990.00')SUM_TC87

-- What about the entered amounts, since accounted are summed here?
-- CEN-71_end
FROM MAIN_ExTRACT
WHERE 1 = 1
and C40 IS NOT NULL
GROUP BY C3
HAVING COUNT(C3)>1)
--------------------Final query ( with the details  ----------------------------------------------
SELECT 
1 Key, 3 pos,
CASE 
WHEN C85 = 'Yes' or  substr(C46,1,3) = 'FAH'
THEN
'D'||DELIMITER||C1||DELIMITER||C2||DELIMITER||C3||DELIMITER||C4||DELIMITER||
C5||DELIMITER||C6||DELIMITER||C7||DELIMITER||C8||DELIMITER||C9||DELIMITER||
C10||DELIMITER||C11||DELIMITER||C12||DELIMITER||C13||DELIMITER||C14||
DELIMITER||C15||DELIMITER||C16||DELIMITER||C17||DELIMITER||C18||DELIMITER||C19||
DELIMITER||C20||DELIMITER||C21||DELIMITER||C22||DELIMITER||C23||DELIMITER||C24||
DELIMITER||C25||DELIMITER||C26||DELIMITER||C27||DELIMITER||C27||DELIMITER||C28||
DELIMITER||C29||DELIMITER||C30||DELIMITER||TO_CHAR(C31,'YYYY-MM-DD')||DELIMITER||
C92||DELIMITER||
DECODE(C90,'MCS', TO_CHAR(C105,'YYYY-MM-DD'), TO_CHAR(NVL(C33, C105),'YYYY-MM-DD') )||DELIMITER||  -- #INC0038148 - display different Accouting Dates for MCS, else default
TO_CHAR(DECODE(C34,NULL,NVL(C106,0),C34),'fm99999999999999990.00')||DELIMITER||
TO_CHAR(DECODE(C35,NULL,NVL(C87,0),C35),'fm99999999999999990.00')||
DELIMITER||TO_CHAR(DECODE(C36,NULL,NVL(C129,0),C36),'fm99999999999999990.00')||
DELIMITER||TO_CHAR(NVL(C88,0),'fm99999999999999990.00')||
DELIMITER||C38||DELIMITER||C39||DELIMITER||C40||DELIMITER||TO_CHAR(C41,'YYYY-MM-DD')||
DELIMITER||C42||DELIMITER||TO_CHAR(C43,'YYYY-MM-DD')||DELIMITER||TO_CHAR(C44,'YYYY-MM-DD')||
DELIMITER||C45||DELIMITER||C46||DELIMITER||C47||DELIMITER||C48||DELIMITER||C49||DELIMITER||
NVL(C93,C107)||DELIMITER||NVL(C94,C108)||DELIMITER||NVL(C133,C109)||DELIMITER||
NVL(C134,C110)||DELIMITER||NVL(C135, C111)||DELIMITER||NVL(C136,C122)||DELIMITER||
NVL(C137,C123)||DELIMITER||NVL(C138, C124)||DELIMITER||C125||DELIMITER||C126||DELIMITER||
NVL(C50,C95 )||DELIMITER||NVL(C51,C96 )||DELIMITER||NVL(C52,C97 )||DELIMITER||NVL(C53,C98 )||
DELIMITER||NVL(C54,C99 )||DELIMITER||NVL(C55,C100)||DELIMITER||NVL(C56,C101)||DELIMITER||
NVL(C57,C102)||DELIMITER||NVL(C58,C103)||DELIMITER||NVL(C59,C104)||DELIMITER||
NVL(C60,C112)||DELIMITER||NVL(C61,C113)||DELIMITER||NVL(C62,C114)||DELIMITER||
NVL(C63,C115)||DELIMITER||NVL(C64,C116)||DELIMITER||NVL(C65,C117)||DELIMITER||
NVL(C66,C118)||DELIMITER||NVL(C67,C119)||DELIMITER||NVL(C68,C120)||DELIMITER||
NVL(C69,C121)||DELIMITER||C70||DELIMITER||C71||DELIMITER||C72||DELIMITER||C73||
DELIMITER||C74||DELIMITER||C75||DELIMITER||C76||DELIMITER||C77||DELIMITER||C78||
DELIMITER||C79||DELIMITER||C80||DELIMITER||C81||DELIMITER||C143||DELIMITER||C82||DELIMITER||C83
-- CEN-71_start
/*
||DELIMITER||
gl_entered_dr||DELIMITER||
gl_entered_cr||DELIMITER||
gl_currency_code||DELIMITER||
gl_currency_conversion_date||DELIMITER||
gl_currency_conversion_rate||DELIMITER||
gl_currency_conversion_type||DELIMITER||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
gl_filler1||DELIMITER||
gl_filler2||DELIMITER||
gl_filler3||DELIMITER||
gl_filler4||DELIMITER||
gl_filler5||DELIMITER||
gl_filler6
*/
-- CEN-71_end
------------------------------------------------------------------------------------------------------
WHEN C85 != 'Yes' AND  substr(C46,1,3) != 'FAH'
THEN
'D'||DELIMITER||C1||DELIMITER||C2||DELIMITER||C3||DELIMITER||C4||DELIMITER||
C5||DELIMITER||C6||DELIMITER||C7||DELIMITER||C8||DELIMITER||C9||DELIMITER||
C10||DELIMITER||C11||DELIMITER||C12||DELIMITER||C13||DELIMITER||C14||DELIMITER||
C15||DELIMITER||C16||DELIMITER||C17||DELIMITER||C18||DELIMITER||C19||DELIMITER||
C20||DELIMITER||C21||DELIMITER||C22||DELIMITER||C23||DELIMITER||C24||DELIMITER||
C25||DELIMITER||C26||DELIMITER||C27||DELIMITER||C27||DELIMITER||C28||DELIMITER||
C29||DELIMITER||C30||DELIMITER||TO_CHAR(C31,'YYYY-MM-DD')||DELIMITER||C92||
DELIMITER||DECODE(C90,'MCS', TO_CHAR(C105,'YYYY-MM-DD'), TO_CHAR(NVL(C33, C105),'YYYY-MM-DD') )||DELIMITER||  -- #INC0038148 - display different Accouting Dates for MCS, else default
TO_CHAR(NVL(C106,0),'fm99999999999999990.00')||  
DELIMITER||TO_CHAR(NVL(C87,0),'fm99999999999999990.00')||
DELIMITER||TO_CHAR(NVL(C129,0),'fm99999999999999990.00')||DELIMITER||
TO_CHAR(NVL(C88,0),'fm99999999999999990.00')||DELIMITER||C38||DELIMITER||C39||DELIMITER||C40||
DELIMITER||TO_CHAR(C41,'YYYY-MM-DD')||DELIMITER||C42||DELIMITER||TO_CHAR(C43,'YYYY-MM-DD')|
|DELIMITER||TO_CHAR(C44,'YYYY-MM-DD')||DELIMITER||C45||DELIMITER||C46||DELIMITER||C47||
DELIMITER||C48||DELIMITER||C49||DELIMITER||C107||DELIMITER||C108||DELIMITER||C109||DELIMITER||
C110||DELIMITER||C111||DELIMITER||C122||DELIMITER||C123||DELIMITER||C124||DELIMITER||C125||
DELIMITER||C126||DELIMITER||C95||DELIMITER||C96||DELIMITER||C97||DELIMITER||C98||DELIMITER||
C99||DELIMITER||C100||DELIMITER||C101||DELIMITER||C102||DELIMITER||C103||DELIMITER||C104||DELIMITER||
C112||DELIMITER||C113||DELIMITER||C114||DELIMITER||C115||DELIMITER||C116||DELIMITER||C117||
DELIMITER||C118||DELIMITER||C119||DELIMITER||C120||DELIMITER||C121||DELIMITER||C70||DELIMITER||
C71||DELIMITER||C72||DELIMITER||C73||DELIMITER||C74||DELIMITER||C75||DELIMITER||C76||DELIMITER||
C77||DELIMITER||C78||DELIMITER||C79||DELIMITER||C80||DELIMITER||C81||DELIMITER||''||DELIMITER||C82||DELIMITER||C83
-- CEN-71_start
/*
||DELIMITER||
gl_entered_dr||DELIMITER||
gl_entered_cr||DELIMITER||
gl_currency_code||DELIMITER||
gl_currency_conversion_date||DELIMITER||
gl_currency_conversion_rate||DELIMITER||
gl_currency_conversion_type||DELIMITER||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
gl_filler1||DELIMITER||
gl_filler2||DELIMITER||
gl_filler3||DELIMITER||
gl_filler4||DELIMITER||
gl_filler5||DELIMITER||
gl_filler6
*/
-- CEN-71_end	
END trxn
FROM MAIN_ExTRACT
WHERE 1 = 1
and C40 IS NOT NULL
UNION
SELECT 1 Key,  1 record_postion, C86 trxn
FROM MAIN_ExTRACT
WHERE ROWNUM < 2
UNION 
SELECT 
1 Key, 2 record_postion,'H'||DELIMITER||'LEDGER_ID'||DELIMITER||'LEDGER_NAME'||DELIMITER||'SEGMENT1'||DELIMITER||
'SEGMENT1_DESCRIPTION'||DELIMITER||'SEGMENT2'||DELIMITER||'SEGMENT2_DESCRIPTION'||DELIMITER||
'SEGMENT3'||DELIMITER||'SEGMENT3_DESCRIPTION'||DELIMITER||'SEGMENT4'||DELIMITER||
'SEGMENT4_DESCRIPTION'||DELIMITER||'SEGMENT5'||DELIMITER||'SEGMENT5_DESCRIPTION'||
DELIMITER||'SEGMENT6'||DELIMITER||'SEGMENT6_DESCRIPTION'||DELIMITER||'SEGMENT7'||
DELIMITER||'SEGMENT7_DESCRIPTION'||DELIMITER||'SEGMENT8'||DELIMITER||'SEGMENT8_DESCRIPTION'||
DELIMITER||'SEGMENT9'||DELIMITER||'SEGMENT9_DESCRIPTION'||DELIMITER||'SEGMENT10'||DELIMITER||
'SEGMENT10_DESCRIPTION'||DELIMITER||'CODE_COMBINATION_ID'||DELIMITER||'CURRENCY_CODE'||
DELIMITER||'PERIOD_NAME'||DELIMITER||'PERIOD_NUMBER'||DELIMITER||'PERIOD_YEAR'||DELIMITER||
'YEAR'||DELIMITER||'ACCOUNT_TYPE'||DELIMITER||'LINE_NUMBER'||DELIMITER||'LINE_DESCRIPTION'||
DELIMITER||'LINE_LAST_UPDATE_DATE'||DELIMITER||'EXTRACT_DATE'||DELIMITER||'EFFECTIVE_DATE'||
DELIMITER||'ACCOUNTED_DR'||DELIMITER||'ACCOUNTED_CR'||DELIMITER||'NET_MOVEMENT'||DELIMITER||
'LINE_STAT_AMOUNT'||DELIMITER||'BATCH_NAME'||DELIMITER||'BATCH_STATUS'||DELIMITER||'HEADER_ID'||
DELIMITER||'HEADER_DATE_CREATED'||DELIMITER||'HEADER_CREATED_BY'||DELIMITER||'HEADER_CREATION_DATE'||
DELIMITER||'HEADER_POSTED_DATE'||DELIMITER||'HEADER_NAME'||DELIMITER||'SOURCE_NAME'||DELIMITER||
'CATEGORY_NAME'||DELIMITER||'HEADER_DESCRIPTION'||DELIMITER||'HEADER_EXTERNAL_REFERENCE'||
DELIMITER||'LINE_REFERENCE_1'||DELIMITER||'LINE_REFERENCE_2'||DELIMITER||'LINE_REFERENCE_3'||
DELIMITER||'LINE_REFERENCE_4'||DELIMITER||'LINE_REFERENCE_5'||DELIMITER||'LINE_REFERENCE_6'||
DELIMITER||'LINE_REFERENCE_7'||DELIMITER||'LINE_REFERENCE_8'||DELIMITER||'LINE_REFERENCE_9'||
DELIMITER||'LINE_REFERENCE_10'||DELIMITER||'LINE_ATTRIBUTE_1'||DELIMITER||'LINE_ATTRIBUTE_2'||
DELIMITER||'LINE_ATTRIBUTE_3'||DELIMITER||'LINE_ATTRIBUTE_4'||DELIMITER||'LINE_ATTRIBUTE_5'||
DELIMITER||'LINE_ATTRIBUTE_6'||DELIMITER||'LINE_ATTRIBUTE_7'||DELIMITER||'LINE_ATTRIBUTE_8'||
DELIMITER||'LINE_ATTRIBUTE_9'||DELIMITER||'LINE_ATTRIBUTE_10'||DELIMITER||'LINE_ATTRIBUTE_11'||
DELIMITER||'LINE_ATTRIBUTE_12'||DELIMITER||'LINE_ATTRIBUTE_13'||DELIMITER||'LINE_ATTRIBUTE_14'||
DELIMITER||'LINE_ATTRIBUTE_15'||DELIMITER||'LINE_ATTRIBUTE_16'||DELIMITER||'LINE_ATTRIBUTE_17'||
DELIMITER||'LINE_ATTRIBUTE_18'||DELIMITER||'LINE_ATTRIBUTE_19'||DELIMITER||'LINE_ATTRIBUTE_20'||
DELIMITER||'FAH_SOURCE'||DELIMITER||'FAH_KEY'||DELIMITER||'SUPPLIER_NAME'||DELIMITER||'SUPPLIER_NUMBER'||
DELIMITER||'PAYABLES_INVOICE_NUMBER'||DELIMITER||'ASSET_NUMBER'||DELIMITER||'PURCHASE_ORDER_NUMBER'||

DELIMITER||'REQUISITION_NUMBER'||DELIMITER||'INVOICE_LINE_DESCRIPTION'||DELIMITER||'CUSTOMER_NUMBER'||
DELIMITER||'CUSTOMER_NAME'||DELIMITER||'RECEIVABLES_INVOICE_NUMBER'||DELIMITER||'SUBLEDGER_ROW_COUNT'||
-- CEN-71_start
/*
-- DELIMITER||'RECEIPT_NUMBER'||DELIMITER||'CHECK_NUMBER'	trxn
DELIMITER||'RECEIPT_NUMBER'||DELIMITER||'CHECK_NUMBER'||DELIMITER||
'GL_ENTERED_DR'||DELIMITER||
'GL_ENTERED_CR'||DELIMITER||	
'GL_ACCOUNTED_CURRENCY_CODE'||DELIMITER||
'GL_CURRENCY_CONVERSION_DATE'||DELIMITER||
'GL_CURRENCY_CONVERSION_RATE'||DELIMITER||
'GL_CURRENCY_CONVERSION_TYPE'||DELIMITER||
-- Adding fillers here,so next guy knows where to put and naming remains as expected
-- below would probably follow same logic as above (with whatever this filler name will be at the time of implementation)
-- eg. NVL(fah.filler1,gjl.filler1) gl_filler1, 
'FILLER1'||DELIMITER||
'FILLER2'||DELIMITER||
'FILLER3'||DELIMITER||
'FILLER4'||DELIMITER||
'FILLER5'||DELIMITER||
'FILLER6' TRXN
*/
 DELIMITER||'RECEIPT_NUMBER'||DELIMITER||'CHECK_NUMBER'	trxn
-- CEN-71_end	
FROM xx_dril_delimit  
UNION
SELECT 
1 Key, 4 record_postion,'T'|| DELIMITER||TC3||DELIMITER||Count_TC3||DELIMITER||SUM_TC106||DELIMITER||SUM_TC87||
DELIMITER||TO_CHAR(FROM_TZ(CAST(sysdate AS TIMESTAMP), 'GMT') at time zone 'CET' , 'DD-MON-YYYY HH24:MI:SS', 'NLS_DATE_LANGUAGE=AMERICAN') trxn
-- What about the entered amounts, since accounted are returned here?
-- CEN-71_end
FROM T_RECORD, xx_dril_delimit
ORDER BY 1 ASC