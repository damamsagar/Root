create or replace PACKAGE BODY      xxfah_acct_hooks_pkg AS
/*===========================================================================+
| PACKAGE NAME                                                               |
|     xxfah_post_acct_hooks_pkg                                              |
|                                                                            |
| DESCRIPTION                                                                |
|     For extension of the accounting engine for FAH Custom Subledger Sources|
|     for updating the stage,status & gl totals on XXFAH_TRANSACTION_CNTRL.  |
|     Triggered by business event oracle.apps.xla.accounting.postaccounting  |
|     when Create Accounting job is run.                                     |
|                                                                            |
| HISTORY                                                                    |
| Name              | Date          | Version   | Description                |
| Leila van Diggele | 30-Jan-2017   |   1.0     | 0026815 - Oracle EBS GL Project|
| Vidya Sagar	    | 09-MAR-2022   |   1.1     | CEN_651 - IFRS17 Segment Validation within Pre-accounting Package (PAAS)
+===========================================================================*/
FUNCTION preaccounting(
                ControlId IN xxfah_transaction_cntrl.control_id%TYPE 
                ,TransactionID IN xxfah_transaction_cntrl.TRANSACTION_NUMBER%TYPE			

             )
  RETURN VARCHAR2  IS
  l_end_date              DATE;
  l_application_id        NUMBER;
  l_ledger_id             NUMBER;
  l_process_category      VARCHAR2(25);
  l_request_id            NUMBER;
  l_valid_application     NUMBER;
  l_segment2              xxfah_passthrough_lines.new_segment2%TYPE;
  l_segment3              xxfah_passthrough_lines.new_segment3%TYPE;
  l_segment4              xxfah_passthrough_lines.new_segment4%TYPE;
  l_segment5              xxfah_passthrough_lines.new_segment5%TYPE;
  l_segment7              xxfah_passthrough_lines.new_segment7%TYPE;
  l_new_centre            xxfah_passthrough_lines.new_centre%TYPE;
  l_new_accnt             xxfah_passthrough_lines.new_accnt%TYPE;
  l_new_fund              xxfah_passthrough_lines.new_fund%TYPE;
  l_fnd_user_id           NUMBER  := 115;
  l_login_id              NUMBER  := 115;
  l_pre_accounting_flag   VARCHAR2(1);
  l_mapping_required      VARCHAR2(1);
  l_buss_unit             xxfah_milly_key_layouts.buss_unit%TYPE;
  l_out_status            VARCHAR2(1);
  l_out_error             VARCHAR2(2000);
  l_segment1              xxfah_passthrough_lines.new_segment1%TYPE;
  l_segment6              xxfah_passthrough_lines.new_segment6%TYPE;
  l_recvat_str            VARCHAR2(20)               := 'RECOVERABLE VAT';
  l_update_flag           BOOLEAN := FALSE;
  l_not_required          EXCEPTION;



  CURSOR cur_events(
                 cur_ControlId       NUMBER
                ,cur_TransactionID     NUMBER
                ) IS
     SELECT 
            xph.layout
		   ,xic.INTERFACE_SUB_TYPE xic_layout -- CEN_651 
           ,xph.transaction_number
           ,xtc.control_id
           ,xph.entity
           ,xph.source_name
           ,xpl.corp
           ,xpl.accnt
           ,xpl.centre
           ,xpl.fund
           ,xpl.opsfund
           ,xpl.line_number
           ,xpl.segment1
           ,xpl.segment2
           ,xpl.segment3
           ,xpl.segment4
           ,xpl.segment5
           ,xpl.segment6
           ,xpl.segment7
           ,xpl.segment8
           ,xpl.segment9
           ,xpl.KEY
           ,xph.currency_code
           ,xpl.scheme
           ,xpl.member
           ,xpl.dr_cr_ind
     FROM  
           xxfah_passthrough_headers xph
           ,xxfah_passthrough_lines xpl
           ,xxfah_transaction_cntrl xtc
		   ,xxcus_interface_cntrl xic     -- CEN_651 : appended this table to get layout from the source details
     WHERE  xtc.STATUS in ('SUCCESS','INVALID')
     AND    xtc.STAGE IN ('LOAD','PREACCOUNTING')
     AND    xtc.control_id = cur_ControlId
	 AND    xic.control_id = xtc.control_id  -- -- CEN_651 : Join Condition
     AND    xph.transaction_number = xpl.transaction_number
     AND    xph.transaction_number = xtc.transaction_number;

BEGIN

  --fnd_file.put_line(fnd_file.LOG,'Start of xxfah_acct_hooks_pkg.preaccounting');  OC_Comment

  -- Get Parameters
 /* l_application_id := p_event.getvalueforparameter('APPLICATION_ID');            OC_Comment
  l_ledger_id := p_event.getvalueforparameter('LEDGER_ID');
  l_process_category := p_event.getvalueforparameter('PROCESS_CATEGORY');
  l_end_date := p_event.getvalueforparameter('END_DATE');
  l_request_id := p_event.getvalueforparameter('REQUEST_ID');


  fnd_file.put_line(fnd_file.LOG,'l_request_id = '|| l_request_id);
  fnd_file.put_line(fnd_file.LOG,'l_application_id = '|| l_application_id);
  fnd_file.put_line(fnd_file.LOG,'l_ledger_id = '|| l_ledger_id);
  fnd_file.put_line(fnd_file.LOG,'l_process_category = '|| l_process_category);*/

  -- Check whether its a custom subledger application
 /* SELECT COUNT(1)                OC_Comment
  INTO   l_valid_application
  FROM   xla_subledgers
  WHERE  application_id = l_application_id
  AND    application_type_code = 'C';

  IF l_valid_application = 0 THEN
     fnd_file.put_line
        (fnd_file.LOG
        ,' Not a custom subledger application. Hence preaccounting hook will not process any events. ');
     RAISE l_not_required;
  END IF;

  -- Added the below IF condition as per Defect 681
  --IF l_process_category IN('CONVERSION', 'CONVERSION CL') THEN
  IF l_process_category IN('FUS_CONV_CORP', 'FUS_CONV_EBCL', 'FUS_CONV_NGN') THEN
     fnd_file.put_line
        (fnd_file.LOG
        ,' Conversion. Hence preaccounting hook will not process any events. ');
     RAISE l_not_required;
  END IF;*/



  FOR rec_events IN cur_events(ControlId,       
                TransactionID) LOOP

--     fnd_file.put_line
--        (fnd_file.LOG
--        ,' rec_events.transaction_number: '|| rec_events.transaction_number);

     BEGIN
        l_segment2 := NULL;
        l_segment3 := NULL;
        l_segment4 := NULL;
        l_segment5 := NULL;
        l_segment7 := NULL;
        l_new_centre := NULL;
        l_new_accnt := NULL;
        l_new_fund := NULL;
        l_pre_accounting_flag := NULL;
        l_buss_unit := NULL;
        l_mapping_required := NULL;
        l_out_status := NULL;
        l_out_error := NULL;
        l_segment1 := NULL;
        l_segment6 := NULL;
        l_update_flag := FALSE;
        
		-- CEN_651 : Added the below IF condition to omit the valdation for XXFAH_IFRS17_LAYOUT  
		
		IF rec_events.xic_layout = 'XXFAH_IFRS17_LAYOUT'
		THEN 
		  NULL;
		-- Check if its a Milly layout
        --IF rec_events.layout = 'MIL' THEN  -- CEN_651
		ELSIF rec_events.layout = 'MIL' THEN -- CEN_651
           -- Find business unit
           BEGIN
              SELECT buss_unit
              INTO   l_buss_unit
              FROM   xxfah_milly_key_layouts
              WHERE  corp = rec_events.entity;
           EXCEPTION
              WHEN NO_DATA_FOUND THEN
                 /*fnd_file.put_line                                                OC_Comment
                    (fnd_file.LOG
                    ,    'Entity not found in milli key layouts for event id'
                      || rec_events.event_id
                      || ' transaction number '
                      || rec_events.transaction_number
                      || ' line number '
                      || rec_events.line_number);*/
                 RAISE;
           END;


           IF l_buss_unit = 'GS' THEN

             g_error_msg:='Unexpected error when finding the new segments mapping for segment2(gsmillybudgetcentrevalue)'; --Added by OC_Comment

             l_segment2 :=
                xxfah_get_mapping_output_pkg.gsmillybudgetcentrevalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);

              g_error_msg:='Unexpected error when finding the new segments mapping for segment3(gsmillyaccountvalue)'; --Added by OC_Comment                                     

             l_segment3 :=
                xxfah_get_mapping_output_pkg.gsmillyaccountvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);

             g_error_msg:='Unexpected error when finding the new segments mapping for segment4(gsmillyrelatedpartyvalue)'; --Added by OC_Comment

             l_segment4 :=
                xxfah_get_mapping_output_pkg.gsmillyrelatedpartyvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);

               g_error_msg:='Unexpected error when finding the new segments mapping for segment5(gsmillyproductvalue)'; --Added by OC_Comment  

             l_segment5 :=
                xxfah_get_mapping_output_pkg.gsmillyproductvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);
             g_error_msg:='Unexpected error when finding the new segments mapping for segment7(gsmillytaxfundvalue)'; --Added by OC_Comment

             l_segment7 :=
                xxfah_get_mapping_output_pkg.gsmillytaxfundvalue
                                                   (rec_events.corp
                                                   ,rec_events.member
                                                   ,l_segment5);

           ELSIF l_buss_unit = 'EB' THEN

           g_error_msg:='Unexpected error when finding the new segments mapping for segment3(ebmillyaccountvalue)'; --Added by OC_Comment
             l_segment3 :=
                xxfah_get_mapping_output_pkg.ebmillyaccountvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);

            g_error_msg:='Unexpected error when finding the new segments mapping for segment4(ebrelatedpartyvalue)'; --Added by OC_Comment

             l_segment4 :=
                xxfah_get_mapping_output_pkg.ebrelatedpartyvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,rec_events.centre);

            g_error_msg:='Unexpected error when finding the new segments mapping for segment5(ebproductvalue)'; --Added by OC_Comment
             l_segment5 :=
                xxfah_get_mapping_output_pkg.ebproductvalue
                   (rec_events.corp, rec_events.accnt
                   ,rec_events.centre, rec_events.opsfund
                   ,rec_events.scheme);

            g_error_msg:='Unexpected error when finding the new segments mapping for segment7(ebtaxfundvalue)'; --Added by OC_Comment       

             l_segment7 :=
                xxfah_get_mapping_output_pkg.ebtaxfundvalue
                   (rec_events.corp
                   ,rec_events.centre
                   ,rec_events.member);

           ELSIF l_buss_unit = 'ILSA' THEN


             l_new_centre :=
                xxfah_get_mapping_output_pkg.ilsamillycostcentrevalue
                                      (rec_events.corp
                                      ,rec_events.accnt
                                      ,rec_events.centre
                                      ,rec_events.fund
                                      ,rec_events.transaction_number
                                      ,rec_events.line_number);
             l_new_fund :=
                xxfah_get_mapping_output_pkg.ilsamillyfundvalue
                                      (rec_events.corp
                                      ,rec_events.accnt
                                      ,l_new_centre, rec_events.fund
                                      ,rec_events.transaction_number
                                      ,rec_events.line_number);


            g_error_msg:='Unexpected error when finding the new segments mapping for segment3(ilsamillyaccountvalue)'; --Added by OC_Comment 

             l_segment3 :=
                xxfah_get_mapping_output_pkg.ilsamillyaccountvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,l_new_centre);

             g_error_msg:='Unexpected error when finding the new segments mapping for segment5(ilsamillyproductvalue)'; --Added by OC_Comment                                       
             l_segment5 :=
                xxfah_get_mapping_output_pkg.ilsamillyproductvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,l_new_centre
                                                   ,l_new_fund);

            g_error_msg:='Unexpected error when finding the new segments mapping for segment7(ilsataxfundvalue)'; --Added by OC_Comment

             l_segment7 :=
                xxfah_get_mapping_output_pkg.ilsataxfundvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,l_new_centre
                                                   ,l_new_fund);

           ELSIF l_buss_unit = 'ILNA' THEN



             l_new_accnt :=
                xxfah_get_mapping_output_pkg.ilnamillyaccountvalue
                                      (rec_events.corp
                                      ,rec_events.accnt
                                      ,rec_events.centre
                                      ,rec_events.fund
                                      ,rec_events.transaction_number
                                      ,rec_events.line_number);
             l_new_centre :=
                xxfah_get_mapping_output_pkg.ilnacostcentrevalue
                                      (rec_events.corp, l_new_accnt
                                      ,rec_events.centre
                                      ,rec_events.fund
                                      ,rec_events.transaction_number
                                      ,rec_events.line_number);
             l_new_fund :=
                xxfah_get_mapping_output_pkg.ilnamillyfundvalue
                                      (rec_events.corp, l_new_accnt
                                      ,l_new_centre, rec_events.fund
                                      ,rec_events.transaction_number
                                      ,rec_events.line_number);

           g_error_msg:='Unexpected error when finding the new segments mapping for segment3(ilnaaccountvalue)'; --Added by OC_Comment                           

             l_segment3 :=
                xxfah_get_mapping_output_pkg.ilnaaccountvalue
                                                    (rec_events.corp
                                                    ,l_new_accnt
                                                    ,l_new_centre);

          g_error_msg:='Unexpected error when finding the new segments mapping for segment5(ilnaproductvalue)'; --Added by OC_Comment  

             l_segment5 :=
                xxfah_get_mapping_output_pkg.ilnaproductvalue
                                                   (rec_events.corp
                                                   ,rec_events.accnt
                                                   ,l_new_centre
                                                   ,l_new_fund);

           ELSE
            g_error_msg:='Unexpected error when finding the new segments mapping for segment3(MillyAccountValue)'; --Added by OC_Comment  

             l_segment3 :=
                xxfah_get_mapping_output_pkg.MillyAccountValue
                                                    (rec_events.corp
                                                    ,rec_events.accnt);

           END IF;
 g_error_msg:='Unexpected error when finding the new segments mapping for segment3(validateAccount)'; --Added by OC_Comment

           l_segment3 := xxfah_get_mapping_output_pkg.validateAccount(nvl(l_segment3, rec_events.segment3));

           UPDATE xxfah_passthrough_lines
              SET  new_segment1 = nvl(l_segment1, new_segment1)
                  ,new_segment2 = nvl(l_segment2, new_segment2)
                  ,new_segment3 = nvl(l_segment3, new_segment3)
                  ,new_segment4 = nvl(l_segment4, new_segment4)
                  ,new_segment5 = nvl(l_segment5, new_segment5)
                  ,new_segment6 = nvl(l_segment6, new_segment6)
                  ,new_segment7 = nvl(l_segment7, new_segment7)
                  ,line_last_update_date = SYSDATE
                  ,line_last_updated_by = l_fnd_user_id
                  ,line_last_update_login = l_login_id
            WHERE  transaction_number = rec_events.transaction_number
              AND  line_number = rec_events.line_number;

        ELSIF rec_events.layout = 'NMD' THEN

        g_error_msg:='Unexpected error when finding the new segments mapping for segment3(MDAccountValue)'; --Added by OC_Comment
              l_segment3 :=
                xxfah_get_mapping_output_pkg.MDAccountValue
                                                    (rec_events.segment5);
            g_error_msg:='Unexpected error when finding the new segments mapping for segment3(validateAccount)'; --Added by OC_Comment
           l_segment3 := xxfah_get_mapping_output_pkg.validateAccount(nvl(l_segment3, rec_events.segment5));

           UPDATE xxfah_passthrough_lines
              SET  new_segment3 = nvl(l_segment3, new_segment3)
                  ,line_last_update_date = SYSDATE
                  ,line_last_updated_by = l_fnd_user_id
                  ,line_last_update_login = l_login_id
            WHERE  transaction_number = rec_events.transaction_number
              AND  line_number = rec_events.line_number;

        ELSIF rec_events.layout IN ('O-11', 'ON-11', 'O-8') THEN
           dbms_output.put_line('Inside Oracle Layout'||SYSTIMESTAMP);
           IF rec_events.KEY = l_recvat_str THEN

           g_error_msg:='Unexpected error when finding the new segments mapping for segment1(recvatbalentity)'; --Added by OC_Comment
              l_segment1 :=
                 xxfah_get_mapping_output_pkg.recvatbalentity
                                                (rec_events.currency_code);
      g_error_msg:='Unexpected error when finding the new segments mapping for segment3(recvataccount)'; --Added by OC_Comment
              l_segment3 :=
                 xxfah_get_mapping_output_pkg.recvataccount
                                                    (rec_events.dr_cr_ind);
              l_update_flag := TRUE;

           ELSE

           DBMS_OUTPUT.put_line('Start Oracle file processing1 befroe l_segment1  for line'||rec_events.line_number||'  '||rec_events.transaction_number);
             g_error_msg:='Unexpected error when finding the new segments mapping for segment1(ccidtobalentity)'; --Added by OC_Comment 
              l_segment1 :=
                 xxfah_get_mapping_output_pkg.ccidtobalentity
                                                     (rec_events.KEY
                                                     ,rec_events.segment1);
          DBMS_OUTPUT.put_line('Start Oracle file processing2 After l_segment1'||'value'||l_segment1);
          g_error_msg:='Unexpected error when finding the new segments mapping for segment2(ccidtobudctr)'; --Added by OC_Comment 
              l_segment2 :=
                 xxfah_get_mapping_output_pkg.ccidtobudctr
                                                     (rec_events.KEY
                                                     ,rec_events.layout
                                                     ,rec_events.segment2);

        g_error_msg:='Unexpected error when finding the new segments mapping for segment3(ccidtoacct)'; --Added by OC_Comment                                               

              l_segment3 :=
                 xxfah_get_mapping_output_pkg.ccidtoacct
                                                    (rec_events.KEY
                                                    ,rec_events.layout
                                                    ,rec_events.segment1
                                                    ,rec_events.segment3
                                                    ,rec_events.segment7);

       g_error_msg:='Unexpected error when finding the new segments mapping for segment4(ccidtorp)'; --Added by OC_Comment                                              
              l_segment4 :=
                 xxfah_get_mapping_output_pkg.ccidtorp
                                                    (rec_events.KEY
                                                    ,rec_events.segment1
                                                    ,rec_events.segment3
                                                    ,rec_events.segment4);

      g_error_msg:='Unexpected error when finding the new segments mapping for segment5(ccidtoproduct)'; --Added by OC_Comment                                                 
              l_segment5 :=
                 xxfah_get_mapping_output_pkg.ccidtoproduct
                                                    (rec_events.KEY
                                                    ,rec_events.layout
                                                    ,rec_events.segment1
                                                    ,rec_events.segment3
                                                    ,rec_events.segment5
                                                    ,rec_events.segment7
                                                    ,rec_events.segment9);

     g_error_msg:='Unexpected error when finding the new segments mapping for segment6(ccidtoscheme)'; --Added by OC_Comment                                                 
              l_segment6 :=
                 xxfah_get_mapping_output_pkg.ccidtoscheme
                                                    (rec_events.KEY
                                                    ,rec_events.layout
                                                    ,rec_events.segment6
                                                    ,rec_events.segment8);

        g_error_msg:='Unexpected error when finding the new segments mapping for segment7(ccidtotaxfund)'; --Added by OC_Comment                                        
              l_segment7 :=
                 xxfah_get_mapping_output_pkg.ccidtotaxfund
                                                    (rec_events.KEY
                                                    ,rec_events.layout
                                                    ,rec_events.segment1
                                                    ,rec_events.segment3
                                                    ,rec_events.segment4
                                                    ,rec_events.segment5
                                                    ,rec_events.segment7
                                                    ,rec_events.segment9);

             DBMS_OUTPUT.put_line('Start Oracle file processing2 After l_segment7');
             DBMS_OUTPUT.put_line(l_segment3||'select'||rec_events.segment3);

             g_error_msg:='Unexpected error when finding the new segments mapping for segment3 -Derived account is control account(validateAccount)'; --Added by OC_Comment 
              l_segment3 := xxfah_get_mapping_output_pkg.validateAccount(nvl(l_segment3, rec_events.segment3));

           END IF;
             DBMS_OUTPUT.put_line('Update l_segment3 value again'||l_segment3||'    '||rec_events.segment3);
             g_error_msg:='Unexpected error when finding the new segments mapping for segment3 -Derived account is control account(validateAccount)'; --Added by OC_Comment
           l_segment3 := xxfah_get_mapping_output_pkg.validateAccount(nvl(l_segment3, rec_events.segment3));
            DBMS_OUTPUT.put_line('update xxfah_passthrough_lines table');
           UPDATE xxfah_passthrough_lines
              SET  new_segment1 = nvl(l_segment1, new_segment1)
                  ,new_segment2 = nvl(l_segment2, new_segment2)
                  ,new_segment3 = nvl(l_segment3, new_segment3)
                  ,new_segment4 = nvl(l_segment4, new_segment4)
                  ,new_segment5 = nvl(l_segment5, new_segment5)
                  ,new_segment6 = nvl(l_segment6, new_segment6)
                  ,new_segment7 = nvl(l_segment7, new_segment7)
                  ,line_last_update_date = SYSDATE
                  ,line_last_updated_by = l_fnd_user_id
                  ,line_last_update_login = l_login_id
            WHERE  transaction_number = rec_events.transaction_number
              AND  line_number = rec_events.line_number;

              DBMS_OUTPUT.put_line('sucessfully update xxfah_passthrough_lines table');

        END IF;

     EXCEPTION
        WHEN OTHERS THEN
           /*fnd_file.put_line                                   OC_Comment
                        (fnd_file.LOG
                        ,    'Exception Raised while processing event id '
                          || rec_events.event_id
                          || ' transaction number '
                          || rec_events.transaction_number
                          || ' line number '
                          || rec_events.line_number
                          || ' : '
                          || SQLERRM);*/
             DBMS_OUTPUT.put_line('Insert Into Error Block');
           --Log the error in xxfah_errors table
           xxfah_err_log_pkg.insertxxfaherrors
                (rec_events.control_id, rec_events.transaction_number
                ,'L', rec_events.line_number
               -- ,'Unexpected error when finding the new segments mapping'
               ,g_error_msg
                ,l_request_id, NULL, l_out_status, l_out_error);

           IF l_out_status = 'E' THEN
             /* fnd_file.put_line
                 (fnd_file.LOG
                 ,    'Error occurred while inserting record into xxfah_errors table for event id '
                   || rec_events.event_id
                   || ' transaction number '
                   || rec_events.transaction_number
                   || ' line number '
                   || rec_events.line_number
                   || '. Error Message:-'
                   || l_out_error);*/
				  DBMS_OUTPUT.PUT_LINE('Error occurred while inserting record into xxfah_errors table for event id '
                  || ' transaction number '
                   || rec_events.transaction_number
                   || ' line number '
                   || rec_events.line_number
                   || '. Error Message:-'
                   || l_out_error);

           END IF;

		--Upadte the Status and Stage  in   XXFAH_TRANSACTION_CNTRL table  (Added by OC_Comment)

           UPDATE XXFAH_TRANSACTION_CNTRL
        SET    status            = 'INVALID',
		       stage             = 'PREACCOUNTING',
               last_update_date  = SYSDATE,
               last_updated_by   = l_fnd_user_id, 
               last_update_login = l_login_id 
        WHERE control_id         = ControlId
        AND STATUS = 'SUCCESS';


           Return 'ERROR';
     END;

  END LOOP;

  --Upadte the Status and Stage  in   XXFAH_TRANSACTION_CNTRL table   (Added by OC_Comment)
  UPDATE XXFAH_TRANSACTION_CNTRL
        SET    status            = 'SUCCESS',
		       stage             = 'PREACCOUNTING',
               last_update_date  = SYSDATE,
               last_updated_by   = l_fnd_user_id, 
               last_update_login = l_login_id 
        WHERE control_id         = ControlId
        AND STATUS = 'SUCCESS' AND stage <> 'AHCSLOAD';
commit;
Return 'SUCCESS';





EXCEPTION
  WHEN l_not_required THEN
Return 'SUCCESS';

  WHEN OTHERS THEN
     /*fnd_file.put_line                                                          OC_Comment
               (fnd_file.LOG
               ,    'Exception Raised in xxfah_acct_hooks_pkg.preaccounting'
                 || SQLERRM);
     xla_exceptions_pkg.raise_message
                         (p_location => 'xxfah_acct_hooks_pkg.preaccounting');*/

--Upadte the Status and Stage  in   XXFAH_TRANSACTION_CNTRL table   (Added by OC_Comment)

	 UPDATE XXFAH_TRANSACTION_CNTRL
        SET    status            = 'INVALID',
		       stage             = 'PREACCOUNTING',
               last_update_date  = SYSDATE,
               last_updated_by   = l_fnd_user_id, 
               last_update_login = l_login_id 
        WHERE control_id         = ControlId
        AND STATUS = 'SUCCESS';


     Return 'ERROR';

END preaccounting;


/*FUNCTION postaccounting(                                                         OC_Comment
                        p_subscription_guid in raw
                        ,p_event in out WF_EVENT_T
                        )
RETURN VARCHAR2  IS



  CURSOR cur_transaction_cntrl(
     i_application_id      NUMBER
    ,i_ledger_id           NUMBER
    ,i_conc_request_id   NUMBER) IS
     SELECT xah.accounting_entry_status_code acct_status
           ,xah.gl_transfer_status_code gl_status
           ,xtc.transaction_number
           ,xtc.control_id
           ,xtc.source_name
           ,xtc.entity
           ,xtc.period_name
           ,xtc.load_total_dr
           ,xtc.load_count_dr
           ,xtc.load_total_cr
           ,xtc.load_count_cr
           ,xe.event_id
           ,xph.reversal_flag
     FROM   xla_ae_headers xah
           ,xla_events xe
           ,xxfah_passthrough_headers xph
           ,xxfah_transaction_cntrl xtc
     WHERE  xtc.transaction_number = xph.transaction_number
     AND    xph.application_id = xah.application_id
     AND    xph.event_id = xah.event_id
     AND    xah.ledger_id = i_ledger_id
     AND    xah.application_id = xe.application_id
     AND    xah.event_id = xe.event_id
     AND    xe.application_id = i_application_id
     AND    xe.request_id = i_conc_request_id;


  l_valid_application   NUMBER;
  l_stage               xxfah_transaction_cntrl.stage%TYPE;
  l_status              xxfah_transaction_cntrl.status%TYPE;
  l_out_status          VARCHAR2(1);
  l_out_error           VARCHAR2(2000);
  l_total_gl_dr         xxfah_transaction_cntrl.transfer_gl_total_dr%TYPE;
  l_total_gl_cr         xxfah_transaction_cntrl.transfer_gl_total_cr%TYPE;
  l_application_id      NUMBER;
  l_ledger_id           NUMBER;
  l_request_id          NUMBER;


BEGIN

  fnd_file.put_line(fnd_file.LOG,'Start of xxfah_acct_hooks_pkg.postaccounting');

  -- Get Parameters

  l_application_id := p_event.getvalueforparameter('APPLICATION_ID');
  l_ledger_id := p_event.getvalueforparameter('LEDGER_ID');
  l_request_id := p_event.getvalueforparameter('REQUEST_ID');

  fnd_file.put_line(fnd_file.LOG,'l_request_id = '|| l_request_id);
  fnd_file.put_line(fnd_file.LOG,'l_application_id = '|| l_application_id);
  fnd_file.put_line(fnd_file.LOG,'l_ledger_id = '|| l_ledger_id);

  SELECT COUNT(1)
  INTO   l_valid_application
  FROM   xla_subledgers
  WHERE  application_id = l_application_id AND application_type_code = 'C';

  IF l_valid_application = 0 THEN
     fnd_file.put_line
        (fnd_file.LOG
        ,' Not a custom subledger application. Hence postaccounting hook will not process any events. ');
  ELSE
     FOR rec_transaction_cntrl IN
        cur_transaction_cntrl
           (l_application_id,
            l_ledger_id,
            l_request_id)

     LOOP
        fnd_file.put_line(fnd_file.LOG,'In Loop');
        l_out_status := NULL;
        l_out_error := NULL;
        l_stage := NULL;
        l_status := NULL;
        l_total_gl_dr := 0;
        l_total_gl_cr := 0;


        IF rec_transaction_cntrl.reversal_flag = 'Y' THEN
           IF (    rec_transaction_cntrl.acct_status = 'F'
               AND rec_transaction_cntrl.gl_status = 'Y') THEN
              l_stage := 'REVERSED';
              l_status := 'COMPLETED';

              BEGIN
                 SELECT NVL(SUM(xal.entered_dr), 0)
                       ,NVL(SUM(xal.entered_cr), 0)
                 INTO   l_total_gl_dr
                       ,l_total_gl_cr
                 FROM   xla_ae_headers xah, xla_ae_lines xal
                 WHERE  xal.ae_header_id = xah.ae_header_id
                 AND    xah.event_id = rec_transaction_cntrl.event_id;
              EXCEPTION
                 WHEN OTHERS THEN
                    fnd_file.put_line
                       (fnd_file.LOG
                       ,    'Error occurred while calculating journal lines total for transaction number '
                         || rec_transaction_cntrl.transaction_number
                         || ' Error Message:-'
                         || SQLERRM);
                     Return 'ERROR';
              END;
           ELSE
              l_stage := 'REVERSED';
              l_status := 'INVALID';
           END IF;
        ELSE

           IF (    rec_transaction_cntrl.acct_status = 'I'
               AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'ACCOUNTING';
              l_status := 'INVALID';
           ELSIF(    rec_transaction_cntrl.acct_status = 'D'
                 AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'ACCOUNTING';
              l_status := 'DRAFT';
           ELSIF(    rec_transaction_cntrl.acct_status = 'F'
                 AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'GL';
              l_status := 'INVALID';

           ELSIF(    rec_transaction_cntrl.acct_status = 'F'
                 AND rec_transaction_cntrl.gl_status = 'NT') THEN
              l_stage := 'GL';
              l_status := 'INVALID';

           ELSIF(    rec_transaction_cntrl.acct_status = 'F'
                 AND rec_transaction_cntrl.gl_status = 'Y') THEN
              l_stage := 'GL';
              l_status := 'COMPLETED';


              BEGIN
                 SELECT NVL(SUM(xal.entered_dr), 0)
                       ,NVL(SUM(xal.entered_cr), 0)
                 INTO   l_total_gl_dr
                       ,l_total_gl_cr
                 FROM   xla_ae_headers xah, xla_ae_lines xal
                 WHERE  xal.ae_header_id = xah.ae_header_id
                 AND    xah.event_id = rec_transaction_cntrl.event_id;
              EXCEPTION
                 WHEN OTHERS THEN
                    fnd_file.put_line
                       (fnd_file.LOG
                       ,    'Error occurred while calculating journal lines total for transaction number '
                         || rec_transaction_cntrl.transaction_number
                         || ' Error Message:-'
                         || SQLERRM);
                     Return 'ERROR';
              END;

           ELSIF(    rec_transaction_cntrl.acct_status = 'N'
                 AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'ACCOUNTING';
              l_status := 'INVALID';
           ELSIF(    rec_transaction_cntrl.acct_status = 'R'
                 AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'ACCOUNTING';
              l_status := 'INVALID';
           ELSIF(    rec_transaction_cntrl.acct_status =
                                                     'RELATED_EVENT_ERROR'
                 AND rec_transaction_cntrl.gl_status = 'N') THEN
              l_stage := 'ACCOUNTING';
              l_status := 'INVALID';
           END IF;
        END IF;

        xxfah_transaction_cntrl_pkg.updatexxfahcntrl
           (i_transaction_number => rec_transaction_cntrl.transaction_number
           ,i_control_id => rec_transaction_cntrl.control_id
           ,i_entity => rec_transaction_cntrl.entity
           ,i_source_name => rec_transaction_cntrl.source_name
           ,i_period_name => rec_transaction_cntrl.period_name
           ,i_load_total_dr => rec_transaction_cntrl.load_total_dr
           ,i_load_count_dr => rec_transaction_cntrl.load_count_dr
           ,i_load_total_cr => rec_transaction_cntrl.load_total_cr
           ,i_load_count_cr => rec_transaction_cntrl.load_count_cr
           ,i_transfer_gl_total_dr => l_total_gl_dr
           ,i_transfer_gl_total_cr => l_total_gl_cr, i_stage => l_stage
           ,i_status => l_status, i_job_request_id => l_request_id
           ,o_status => l_out_status, o_error_msg => l_out_error);


        IF l_out_status = 'E' THEN
           fnd_file.put_line
              (fnd_file.LOG
              ,    'Error occurred while updating stage, status and transfer to gl totals in xxfah_transaction_cntrl table for transaction number '
                || rec_transaction_cntrl.transaction_number
                || ' Error Message:-'
                || l_out_error);
           Return 'ERROR';
        END IF;

     END LOOP;
  END IF;

  fnd_file.put_line(fnd_file.LOG,'End of xxfah_acct_hooks_pkg.postaccounting');
  RETURN 'SUCCESS';

EXCEPTION
  WHEN OTHERS THEN
     fnd_file.put_line
              (fnd_file.LOG
              ,    'Exception Raised in xxfah_acct_hooks_pkg.postaccounting'
                || SQLERRM);
     xla_exceptions_pkg.raise_message
                           (p_location => 'xxfah_acct_hooks_pkg.postaccounting');
     Return 'ERROR';
END postaccounting;*/

END xxfah_acct_hooks_pkg;